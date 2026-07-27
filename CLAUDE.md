# CLAUDE.md — git-smartlog

## Layout

- `git-smartlog` — the entire tool: one self-contained zsh script with no
  dependencies beyond zsh + git (`gh` opt-in for `-p`). `git-smartstat` is a
  symlink to it; the file is multi-call and dispatches on `$PROG`.
- `completions/` — zsh completions (`_git-smartlog`, `_git-smartstat`).
- `dev/make-demo.zsh` — builds a throwaway demo repo exercising every signal the
  views render; the README's text examples are captures from it. When an
  example needs something the demo can't show, the fix is to teach make-demo.zsh
  to produce it — not to build a second repo beside it. (That is how the
  untracked-directory collapse and the draft-forking branches got there.)
- `dev/make-fixtures.zsh` — builds the repo states the README examples are
  captured from: `demo` (make-demo.zsh's dirty tree) and `demo-clean` (the same
  commits, pristine). Deliberately only two.
- `test/test-readme-examples.zsh` — replays every example in the README and
  diffs it against what the script prints now; `--update` re-captures them all.
  The README is the golden file, so there is no second copy to drift. Hashes
  and relative timestamps are normalized away; everything else is exact.
- `.github/workflows/ci.yml` — parses every script, then runs that test.
- `dev/make-screenshots.zsh` — rebuilds the demo repo and regenerates every PNG in
  `screenshots/` (pty capture → ANSI-to-HTML → headless Chrome). Needs
  Chrome; macOS-oriented.
- `screenshots/` — the PNGs the README embeds. Never edit by hand; always
  regenerate.

## After changing output or adding a flag

- Update the README: flag docs, then re-capture the examples with
  `./test/test-readme-examples.zsh --update` and read the resulting diff — it
  makes the examples true, not correct. Run the test without `--update` to
  confirm they all reproduce; CI does the same on every push.
- Each example block is tagged with the fixture it runs in
  (`<!-- fixture: demo -->` above the fence). A new example needs a tag, and
  the test fails if any block lacks one.
- Re-run `./dev/make-screenshots.zsh` to refresh `screenshots/` — the images must
  always match the current renderer. If the change isn't visible in an
  existing shot, extend `make-demo.zsh` to exercise it and/or add a `shoot`
  line for a new image.
- Update the files in `completions/` to match any option change.
