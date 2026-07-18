# CLAUDE.md — git-smartlog

## Layout

- `git-smartlog` — the entire tool: one self-contained zsh script with no
  dependencies beyond zsh + git (`gh` opt-in for `-p`). `git-smartstat` is a
  symlink to it; the file is multi-call and dispatches on `$PROG`.
- `completions/` — zsh completions (`_git-smartlog`, `_git-smartstat`).
- `make-demo.sh` — builds a throwaway demo repo exercising every signal the
  views render; the README's text examples are captures from it.
- `make-screenshots.sh` — rebuilds the demo repo and regenerates every PNG in
  `screenshots/` (pty capture → ANSI-to-HTML → headless Chrome). Needs
  Chrome; macOS-oriented.
- `screenshots/` — the PNGs the README embeds. Never edit by hand; always
  regenerate.

## After changing output or adding a flag

- Update the README: flag docs, and re-capture any text examples the change
  affects (run the commands in the `make-demo.sh` repo, piped so ANSI is
  suppressed).
- Re-run `./make-screenshots.sh` to refresh `screenshots/` — the images must
  always match the current renderer. If the change isn't visible in an
  existing shot, extend `make-demo.sh` to exercise it and/or add a `shoot`
  line for a new image.
- Update the files in `completions/` to match any option change.
