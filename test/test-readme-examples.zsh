#!/usr/bin/env zsh
# Replay every example in the README and check it against what the current
# script actually prints. Exits non-zero, with a diff, on the first mismatch.
#
#   ./test/test-readme-examples.zsh [fixture-dir]
#   ./test/test-readme-examples.zsh --update [fixture-dir]
#
# This half owns the fixtures and the environment; the comparing is done by
# readme_examples.py beside it, which documents how each example is tagged with
# the fixture it came from and what is (and isn't) compared.
#
# Pass a directory to reuse fixtures instead of rebuilding them, which is worth
# doing while iterating. --update re-captures every block from what the tool
# prints right now — the mechanical half of "re-capture any example the change
# affects". Read the diff before committing it: --update makes the examples
# true, not correct.
#
# Needs: zsh, git, python3.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
UPDATE=()
if [[ ${1:-} == --update ]]; then UPDATE=(--update); shift; fi
FIXTURES=${1:-}
KEEP=1
if [[ -z $FIXTURES ]]; then
  FIXTURES=$(mktemp -d "${TMPDIR:-/tmp}/git-smartlog-fixtures.XXXXXX")
  KEEP=0
  "$REPO/dev/make-fixtures.zsh" "$FIXTURES" >/dev/null
fi
trap '(( KEEP )) || rm -rf "$FIXTURES"' EXIT

# Keep the user's (or the runner's) git config out of it, so a stray
# diff.relative or color.ui can't change what the examples render to.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_PAGER=cat

python3 "$REPO/test/readme_examples.py" "$REPO" "$FIXTURES" $UPDATE
