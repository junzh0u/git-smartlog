# plans/

Ideas worth doing, written down before they're done. One file per idea, deleted
when it ships (or when it's decided against — with the reason folded into the
script's comments, which is where a decision belongs once it's made).

These came out of a pass over [Jujutsu](https://github.com/jj-vcs/jj) asking what
else this tool could borrow. Most of that pass has shipped: the `(empty)` subject
label, the hash dimmed past its unique prefix, and the `o` → `◇` → `◆` node ramp
— joining the uncommitted-changes node from earlier. What's left:

| plan | idea | cost |
| --- | --- | --- |
| [rev-flag.md](rev-flag.md) | `-r <rev>`: draw the graph around something other than `HEAD` | new flag, completions, README example |

## Deliberately not borrowed

- **Operation log / `jj undo`.** Needs jj's storage model. Git's reflog is not
  the same object and pretending otherwise would be a different tool.
- **Change IDs.** A real one needs a store that tracks rewrites. The Gerrit
  `Change-Id` trailer is the only git-native stand-in and it only exists if every
  committer opts in, which a script you drop on your `PATH` can't assume.
- **Conflicts as commits (`×`).** Git can't commit a conflict. The `U` marker in
  the uncommitted node is the whole of what git has to say here, and it's there.
- **A working-copy node even when clean.** jj always has one because the working
  copy always *is* a commit. Here it would be a row that says nothing on every
  clean run; the node stays dirty-only, and that's a decision, not a gap.
- **`immutable_heads()` as a freeze.** Shipped in weakened form instead: a
  pushed draft draws `◇`, one step short of `◆`. jj's own rule excludes remote
  bookmarks you track, precisely because rewriting your own pushed branch is
  routine — so a stronger mark would have painted every PR stack as frozen. See
  the comment in `main`.
- **New distinctions encoded as a hash color.** `\e[33m` and `\e[93m` are the
  same yellow in Dracula and most 16-color themes, so the existing draft/public
  hash colors differ by *weight*, not hue — survivable only because `◆`/`o`
  says it too. Anything new goes in the glyph or in text.
