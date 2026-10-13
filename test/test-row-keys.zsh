#!/usr/bin/env zsh
# Check the row tagging behind `git smartlog -i`: the child run fzf reads
# (GIT_SMARTLOG_ROWKEYS) must be the plain render with a key column in front,
# and the keys must name the right nodes. The interactive part is fzf's; what
# can drift silently is the tagging, so that is what this pins down.
#
#   ./test/test-row-keys.zsh [fixture-dir]
#
# For every fixture and view flag combination below:
#   - the rows, key column and color stripped, are exactly the plain render
#   - every key is "wdir" or a full sha that names a commit
#   - the heads file lists exactly the node header rows, each carrying the
#     hash of its own key, and marks exactly one of them @ — the row with
#     the @ glyph
#
# Pass a fixture directory to reuse one (see test-readme-examples.zsh).
# Needs: zsh, git.
set -euo pipefail
setopt extended_glob

REPO=${0:A:h:h}
FIXTURES=${1:-}
KEEP=1
if [[ -z $FIXTURES ]]; then
  FIXTURES=$(mktemp -d "${TMPDIR:-/tmp}/git-smartlog-fixtures.XXXXXX")
  KEEP=0
  "$REPO/dev/make-fixtures.zsh" "$FIXTURES" >/dev/null
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/git-smartlog-rowkeys.XXXXXX")
trap '(( KEEP )) || rm -rf "$FIXTURES"; rm -rf "$WORK"' EXIT

# Same hermetic config as the README test; no COLUMNS, so neither run wraps.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_PAGER=cat
unset COLUMNS NO_COLOR

typeset -i failures=0 checks=0
function fail {
  print -r -- "  FAIL  $1"
  (( ++failures ))
}

function strip_ansi {
  # SGR colors and OSC 8 hyperlinks (-p's PR tags).
  sed -e $'s/\e\\[[0-9;]*m//g' -e $'s/\e\\]8;;[^\e]*\e\\\\//g' -e 's/[[:space:]]*$//'
}

function check {
  local fixture=$1; shift
  local label="[$fixture] git smartlog${*:+ $*}"
  local dir=$FIXTURES/$fixture
  local plain=$WORK/plain tagged=$WORK/tagged heads=$WORK/heads
  (cd $dir && "$REPO/git-smartlog" "$@") | strip_ansi >| $plain
  (cd $dir && GIT_SMARTLOG_ROWKEYS=$heads "$REPO/git-smartlog" "$@") >| $tagged
  (( ++checks ))

  if ! diff -q <(cut -f2- $tagged | strip_ansi) $plain >/dev/null; then
    fail "$label: tagged rows differ from the plain render"
    diff <(cut -f2- $tagged | strip_ansi) $plain | head -10 | sed 's/^/          /'
    return
  fi

  local -a keys=("${(@f)$(cut -f1 $tagged)}")
  local -a rows=("${(@f)$(cut -f2- $tagged | strip_ansi)}")
  local k=
  for k in ${(u)keys}; do
    [[ $k == wdir ]] && continue
    if [[ $k != [0-9a-f](#c40) ]] || ! git -C $dir cat-file -e "$k^{commit}" 2>/dev/null; then
      fail "$label: key '$k' is neither wdir nor a commit"
    fi
  done

  # A header row: graph gutter, a node glyph, two spaces, then a hash or
  # the uncommitted node's label.
  local -a want=() got=()
  local -i i=0
  for ((i = 1; i <= ${#rows}; i++)); do
    [[ ${rows[i]} =~ '^[│╷├╭─╯ ]*[@o◇◆]  ([0-9a-f]{4,}|Uncommitted changes)' ]] && want+=($(( i - 1 )))
  done
  local -a entries=("${(@f)$(<$heads)}")
  got=(${entries%% *})
  [[ ${(j: :)got} == ${(j: :)want} ]] ||
    fail "$label: heads lists rows (${got[1,8]} …), header rows are (${want[1,8]} …)"
  local n= row= key=
  for n in $got; do
    row=${rows[n + 1]} key=${keys[n + 1]}
    if [[ $key == wdir ]]; then
      [[ $row == *"Uncommitted changes"* ]] || fail "$label: wdir header row $n is '$row'"
    else
      [[ $row == *"${key[1,10]}"* ]] || fail "$label: header row $n doesn't show its key ${key[1,10]}"
    fi
  done
  local -a at=(${(M)entries:#* @})
  if (( ${#at} != 1 )); then
    fail "$label: ${#at} rows marked @"
  else
    n=${at[1]%% *}
    [[ ${rows[n + 1]} =~ '^[│╷├╭─╯ ]*@  ' ]] || fail "$label: the row marked @ is '${rows[n + 1]}'"
  fi
}

for fixture in demo demo-clean; do
  check $fixture
  check $fixture -c
  check $fixture -b
  check $fixture -m
  check $fixture -b -c -m
  check $fixture -f
done

if (( failures )); then
  print -r -- "$failures failure(s) across $checks views"
  exit 1
fi
print -r -- "row keys hold across all $checks views"
