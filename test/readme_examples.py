"""Replay the README's examples and compare them with what the tool prints.

    readme_examples.py <repo-root> <fixture-dir> [--update]

Driven by test-readme-examples.zsh, which owns building the fixtures and
keeping the environment hermetic. Run it directly against an existing fixture
directory when iterating.

Every example is a fenced block tagged with the fixture it was captured from:

    <!-- fixture: demo-clean -->
    ```text
    $ git smartlog
    ...
    ```

The README is the golden file — there is no second copy of the expected output
to drift. --update rewrites the blocks that no longer reproduce, and leaves the
rest byte-for-byte alone so the diff shows only what actually changed.

Commit hashes and relative timestamps are normalized away before comparing:
fixtures are built fresh, so neither can match a capture taken earlier, and
neither carries meaning the examples are teaching. EVERYTHING else — graph
glyphs, refs, change markers, filenames, stat bars, column alignment, totals,
subjects — is compared exactly.
"""

import difflib
import os
import re
import subprocess
import sys

BLOCK = re.compile(
    r"<!-- fixture: ([\w-]+) -->\n```text\n\$ ([^\n]+)\n(.*?)\n```", re.S)
# Any fenced example, tagged or not — so an untagged one is caught rather than
# silently skipped by the pattern above.
ANY_EXAMPLE = re.compile(r"(?m)^\$ git smart")

NORMALIZE = [
    (re.compile(r"\b[0-9a-f]{10}\b"), "<hash>"),
    (re.compile(r"(Today|Yesterday|Monday|Tuesday|Wednesday|Thursday|Friday|"
                r"Saturday|Sunday) at \d\d:\d\d"), "<time>"),
    (re.compile(r"[A-Z][a-z]{2} \d\d at \d\d:\d\d"), "<time>"),
    (re.compile(r"\d{4}-\d\d-\d\d \d\d:\d\d"), "<time>"),
    (re.compile(r"\d+ (?:second|minute|hour|day|week|month|year)s? ago"), "<time>"),
    (re.compile(r"[ \t]+$", re.M), ""),
]


def normalize(text):
    for pattern, replacement in NORMALIZE:
        text = pattern.sub(replacement, text)
    return text


def run_example(repo, fixtures, fixture, command):
    words = command.split()
    if words[:1] != ["git"] or words[1:2] not in (["smartlog"], ["smartstat"]):
        sys.exit(f"FAIL: don't know how to run '{command}'")
    cwd = os.path.join(fixtures, fixture)
    if not os.path.isdir(cwd):
        sys.exit(f"FAIL: no such fixture '{fixture}' (see dev/make-fixtures.zsh)")
    binary = os.path.join(repo, "git-" + words[1])
    return subprocess.run([binary] + words[2:], cwd=cwd,
                          capture_output=True, text=True).stdout.rstrip("\n")


def main(argv):
    update = "--update" in argv
    positional = [a for a in argv if a != "--update"]
    if len(positional) != 2:
        sys.exit(__doc__.strip().split("\n\n")[1].strip())
    repo, fixtures = positional

    readme_path = os.path.join(repo, "README.md")
    readme = open(readme_path).read()
    blocks = BLOCK.findall(readme)

    tagged, total = len(blocks), len(ANY_EXAMPLE.findall(readme))
    if tagged != total:
        sys.exit(f"FAIL: {total} example blocks in README, {tagged} tagged with a "
                 f"fixture — every example must be replayable, so tag the rest")

    failed, rewritten = 0, []
    for fixture, command, expected in blocks:
        got = run_example(repo, fixtures, fixture, command)
        if update:
            # Leave a block that already reproduces alone. Its committed hashes
            # and timestamps are as valid as this fixture's, and rewriting them
            # would bury the blocks that did change under churn.
            if normalize(got) == normalize(expected):
                print(f"  unchanged  $ {command}   [{fixture}]")
                continue
            rewritten.append((fixture, command, expected, got))
            print(f"  captured   $ {command}   [{fixture}]")
        elif normalize(got) == normalize(expected):
            print(f"  ok      $ {command}   [{fixture}]")
        else:
            failed += 1
            print(f"  FAILED  $ {command}   [{fixture}]")
            for line in difflib.unified_diff(
                    normalize(expected).split("\n"), normalize(got).split("\n"),
                    "README", "actual", lineterm="", n=1):
                print("          " + line)

    if update:
        for fixture, command, expected, got in rewritten:
            head = f"<!-- fixture: {fixture} -->\n```text\n$ {command}\n"
            old, new = f"{head}{expected}\n```", f"{head}{got}\n```"
            if readme.count(old) != 1:
                sys.exit(f"FAIL: '{command}' [{fixture}] is not uniquely identified "
                         f"in the README; cannot rewrite it safely")
            readme = readme.replace(old, new)
        if not rewritten:
            print("\nevery example already reproduces; README.md untouched")
            return 0
        open(readme_path, "w").write(readme)
        print(f"\n{len(rewritten)} of {len(blocks)} examples re-captured into "
              f"README.md — read the diff")
        return 0

    if failed:
        print(f"\n{failed} of {len(blocks)} examples no longer match. Re-capture "
              f"them with --update (the README is the golden file), or fix the "
              f"script.", file=sys.stderr)
        return 1
    print(f"\nall {len(blocks)} README examples reproduce")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
