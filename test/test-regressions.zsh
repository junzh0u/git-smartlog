#!/usr/bin/env zsh
# Regression checks for bugs the README examples can't show: each case builds
# its own throwaway repo in the shape that once broke, runs the script, and
# checks the one line that went wrong. The README replay stays the golden file
# for what the views look like; this is for corners no example should carry.
#
#   ./test/test-regressions.zsh
#
# Needs: zsh, git.
set -euo pipefail

REPO=${0:A:h:h}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/git-smartlog-regressions.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Hermetic, like the other suites: no user config, no pager, no color.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_PAGER=cat
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export NO_COLOR=1
unset COLUMNS

typeset -i failures=0 checks=0

function new_repo {
    # cd into a fresh repo named $1 under WORK; $2.. extra `git init` flags.
    local name=$1; shift
    git init -q -b main "$@" $WORK/$name
    cd $WORK/$name
}

function expect {
    # Pass when output $2 contains line $3 (a glob); $1 names the case.
    (( ++checks ))
    if [[ $'\n'$2$'\n' == *$'\n'$~3$'\n'* ]]; then
        print -r -- "  ok      $1"
    else
        print -r -- "  FAIL    $1"
        print -r -- "          expected a line matching: $3"
        print -r -- "$2" | sed 's/^/          /'
        (( ++failures ))
    fi
}

# --base=REV: zparseopts keeps the "=", which used to reach rev-parse.
new_repo base-eq
git commit -q --allow-empty -m one
git update-ref refs/remotes/origin/main HEAD
expect "--base=REV resolves like --base REV" \
    "$("$REPO/git-smartlog" --base=origin/main 2>&1)" '@  * origin/main'

# A conflicted path holding a space: porcelain quotes it, so it used to miss
# the unmerged set and show M.
new_repo conflict-space
print a >| 'a b.txt'
git add . && git commit -qm base
git checkout -qb side && print side >| 'a b.txt' && git commit -qam side
git checkout -q main && print main >| 'a b.txt' && git commit -qam main
git merge -q side >/dev/null 2>&1 || true
expect "smartstat marks a conflicted spaced path U" \
    "$("$REPO/git-smartstat")" ' U a b.txt *'
expect "smartshow marks a conflicted spaced path U" \
    "$("$REPO/git-smartshow" --list)" 'U a b.txt *'

print
if (( failures )); then
    print -r -- "$failures of $checks regression checks failed"
    exit 1
fi
print -r -- "all $checks regression checks pass"
