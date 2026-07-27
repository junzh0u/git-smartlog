#!/usr/bin/env zsh
# Replay every example in the README and check it against what the current
# script actually prints. Exits non-zero, with a diff, on the first mismatch.
#
#   ./test/test-readme-examples.zsh [fixture-dir]
#   ./test/test-readme-examples.zsh --update [fixture-dir]
#
# The README is the golden file: there is no second copy of the expected output
# to drift. Each ```text block is tagged with the fixture it was captured from —
#
#     <!-- fixture: demo-clean -->
#     ```text
#     $ git smartlog
#     ...
#
# — and dev/make-fixtures.zsh builds those repos (see it for what each holds).
# Pass a directory to reuse fixtures instead of rebuilding them, which is worth
# doing while iterating. --update rewrites the README's blocks from what the
# script prints right now — the mechanical half of "re-capture any example the
# change affects". Read the diff before committing it: --update makes the
# examples true, not correct.
#
# Commit hashes and relative timestamps are normalized away before comparing:
# fixtures are built fresh, so neither can match a capture taken earlier, and
# neither carries meaning the examples are teaching. EVERYTHING else — graph
# glyphs, refs, change markers, filenames, stat bars, column alignment, totals,
# subjects — is compared exactly.
#
# Needs: zsh, git, python3.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
UPDATE=0
if [[ ${1:-} == --update ]]; then UPDATE=1; shift; fi
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

REPO=$REPO FIXTURES=$FIXTURES UPDATE=$UPDATE python3 - <<'PY'
import os, re, subprocess, sys, difflib

repo, fixtures = os.environ["REPO"], os.environ["FIXTURES"]
update = os.environ["UPDATE"] == "1"
readme_path = os.path.join(repo, "README.md")
readme = open(readme_path).read()

# <!-- fixture: NAME --> immediately above a ```text block starting with "$ cmd"
blocks = re.findall(
    r"<!-- fixture: ([\w-]+) -->\n```text\n\$ ([^\n]+)\n(.*?)\n```", readme, re.S)

fenced = len(re.findall(r"(?m)^\$ git smart", readme))
if len(blocks) != fenced:
    sys.exit(f"FAIL: {fenced} example blocks in README, {len(blocks)} tagged with a "
             f"fixture — every example must be replayable, so tag the rest")

def normalize(text):
    text = re.sub(r"\b[0-9a-f]{10}\b", "<hash>", text)
    text = re.sub(r"(Today|Yesterday|Monday|Tuesday|Wednesday|Thursday|Friday|"
                  r"Saturday|Sunday) at \d\d:\d\d", "<time>", text)
    text = re.sub(r"[A-Z][a-z]{2} \d\d at \d\d:\d\d", "<time>", text)
    text = re.sub(r"\d{4}-\d\d-\d\d \d\d:\d\d", "<time>", text)
    text = re.sub(r"\d+ (?:second|minute|hour|day|week|month|year)s? ago", "<time>", text)
    return re.sub(r"[ \t]+$", "", text, flags=re.M)

BIN = {"smartlog": os.path.join(repo, "git-smartlog"),
       "smartstat": os.path.join(repo, "git-smartstat")}

failed = 0
rewritten = {}
for fixture, command, expected in blocks:
    words = command.split()
    if words[:1] != ["git"] or words[1:2] not in (["smartlog"], ["smartstat"]):
        sys.exit(f"FAIL: don't know how to run '{command}'")
    cwd = os.path.join(fixtures, fixture)
    if not os.path.isdir(cwd):
        sys.exit(f"FAIL: no such fixture '{fixture}' (see dev/make-fixtures.zsh)")
    got = subprocess.run([BIN[words[1]]] + words[2:], cwd=cwd,
                         capture_output=True, text=True).stdout.rstrip("\n")
    if update:
        rewritten[(fixture, command, expected)] = got
        print(f"  captured  $ {command}   [{fixture}]")
        continue
    if normalize(got) == normalize(expected):
        print(f"  ok      $ {command}   [{fixture}]")
        continue
    failed += 1
    print(f"  FAILED  $ {command}   [{fixture}]")
    for line in difflib.unified_diff(
            normalize(expected).split("\n"), normalize(got).split("\n"),
            "README", "actual", lineterm="", n=1):
        print("          " + line)

if update:
    for (fixture, command, expected), got in rewritten.items():
        old = f"<!-- fixture: {fixture} -->\n```text\n$ {command}\n{expected}\n```"
        new = f"<!-- fixture: {fixture} -->\n```text\n$ {command}\n{got}\n```"
        if readme.count(old) != 1:
            sys.exit(f"FAIL: '{command}' [{fixture}] is not uniquely identified in "
                     f"the README; cannot rewrite it safely")
        readme = readme.replace(old, new)
    open(readme_path, "w").write(readme)
    print(f"\n{len(rewritten)} examples re-captured into README.md — read the diff")
    sys.exit(0)

if failed:
    sys.exit(f"\n{failed} of {len(blocks)} examples no longer match. Re-capture them "
             f"with --update (the README is the golden file), or fix the script.")
print(f"\nall {len(blocks)} README examples reproduce")
PY
