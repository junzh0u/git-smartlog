# `-r <rev>` — point the graph somewhere other than HEAD

jj's whole log UI is `jj log -r <revset>`; the graph is a view over a revision
expression, not a report about where you're checked out. The portable one percent
of that: draw the smartlog as if `<rev>` were checked out, so you can read a
colleague's branch, a detached sha, or the stack you're about to switch to
without switching to it.

`--base REV` is the precedent — the tool already accepts "aim the view
elsewhere" as a flag. This is the other end of the same range.

## Scope

Everything downstream is already sha-driven; the change is at the point where
`main` decides what `HEAD` is:

- `head_sha=$(git rev-parse HEAD)` → resolve `-r`'s argument instead, and fail
  the same way `--base` does on a bad rev.
- `ACTIVE_BRANCH` — the `name*` token is "the branch you're on". With `-r` it
  should follow the *requested* rev when that rev is a branch, and be empty when
  it isn't. Don't leave it pointing at the real checkout; it would decorate the
  wrong row.
- The uncommitted node — **suppress it** unless `-r` resolves to real `HEAD`.
  The working copy belongs to the checkout, not to the rev being drawn; hanging
  your dirty tree off someone else's branch would be a lie. `has_changes=0` is
  the whole fix.
- `@` — draw it only where the real working copy is. If real `HEAD` happens to
  be in view (likely under `-b`), it keeps its `@`; otherwise the graph has none,
  which is honest. jj does the same: `@` is the working copy, not the argument.
- The compact-public rule keys off `my_email` and is unaffected.

## Also needed

- `completions/_git-smartlog` — the option, and a rev completion for its
  argument (`__git_revisions` via zsh's own `_git` when available, else nothing).
- README: flag docs plus one example. The `demo` fixture already has branches
  worth aiming at (`fix/redirect-loop` has a two-commit stack forking two
  commits down the trunk, which shows `-r` doing something the default view
  can't). New example blocks need a `<!-- fixture: -->` tag or the test fails.

## Not in scope

A revset *language*. `-r` takes one rev, resolved by `git rev-parse`. Anything
past that is reimplementing jj's parser in zsh, and the value is in the first
rev, not the grammar.
