#!/usr/bin/env zsh
# Build every repository state the README's examples are captured from, so each
# one can be replayed and checked (test/test-readme-examples.zsh does that).
#
#   ./dev/make-fixtures.zsh <dir>       # wipes and recreates <dir>
#
# Each example block in the README is tagged with the fixture it came from, e.g.
#
#     <!-- fixture: demo-clean -->
#     ```text
#     $ git smartlog
#     ...
#
# and the names below are those tags:
#
#   demo           the full demo (make-demo.zsh): dirty tree, every -u signal,
#                  left mid-merge for the U conflict
#   demo-clean     the same commits with a pristine working tree — what the
#                  graph looks like with no uncommitted node
#
# demo-clean is a copy of demo, so both share its commit hashes and every example
# in the README stays consistent with every other. There are only these two on
# purpose: anything the examples need to show is a signal the demo should be
# exercising anyway, so the answer to "the demo can't show X" is to teach
# make-demo.zsh to produce X, not to add a fixture beside it.
set -euo pipefail

OUT=${1:?usage: make-fixtures.zsh <dir>}
REPO=$(cd "$(dirname "$0")/.." && pwd)

rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# ── demo ───────────────────────────────────────────────────────────────────────
"$REPO/dev/make-demo.zsh" "$OUT/demo" >/dev/null

# ── demo-clean: the same repo with nothing uncommitted ─────────────────────────
# reset --hard also clears the demo's in-progress merge; the submodule needs its
# own reset, since the demo bumps its pointer AND dirties its working tree.
cp -R "$OUT/demo" "$OUT/demo-clean"
(
  cd "$OUT/demo-clean"
  git reset --hard -q
  git clean -qfd
  git -c protocol.file.allow=always submodule update --init --force -q
  cd vendor/timeutil && git checkout -q -- . && git clean -qfd
)

printf 'fixtures in %s: demo demo-clean\n' "$OUT"
