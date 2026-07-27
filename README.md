# git-smartlog

A [Sapling](https://sapling-scm.com/)-inspired `smartlog` for plain Git, in a
single self-contained zsh script. The same file doubles as
[`git-smartstat`](#git-smartstat), a standalone view of uncommitted changes.

It renders the current branch's **draft stack** — the first-parent chain of your
local (unpushed) commits — drawn on top of its nearest **public** (pushed) base,
with relative timestamps, authors, and ref decorations. A dirty working tree
always draws an uncommitted-changes node on top, and three independent flags —
`-c` for per-file change stats under your commits and your working copy, `-b` to
fold your other local branches into the graph as full stacks, `-f` to stop
abbreviating anything — combine freely. See below.

It began as a mimic of Sapling's `sl`, and still owes it the graph layout, the
relative-time format and the color defaults. It has since grown enough of its
own that it no longer tracks `sl`'s output, and isn't trying to. Four things
come from [Jujutsu](https://github.com/jj-vcs/jj) instead: the
uncommitted-changes node, since jj treats the working copy as a commit in its
own right; the `(empty)` label on a commit that changed nothing; hashes that dim
everything past the prefix which uniquely identifies them; and a node glyph that
carries how rewritable the commit is (`o` → `◇` → `◆`) rather than leaving it to
the palette.

The story behind it is in
[this post](https://junz.info/writing/git-smartlog/).

<p align="center">
  <img src="screenshots/cover.png" alt="git-smartlog -b -f -p output" width="600">
</p>

## Example

On a feature branch with a few local commits stacked on `origin/master`, with a
clean working tree:

<!-- fixture: demo-clean -->
```text
$ git smartlog
  @  2f0e95dfc5  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │
  o  6660e2b318  Today at 20:10  junz
  │  Add exponential backoff with jitter
  │
  o  859711ce71  Today at 18:10  junz
  │  (empty) Require golang.org/x/time
  │
  o  0280c2f0a8  Yesterday at 23:10  junz
╭─╯  Extract retry policy into its own module
│
◆  9126f994b8  Thursday at 23:10  junz  origin/master
│  Bump dependencies
~
```

`@` marks `HEAD`; the `o` nodes above the bend (`╭─╯`) are your draft commits,
newest first. Below the bend sits the public base — the nearest pushed commit,
here `origin/master`, drawn `◆` — and `~` marks the truncated history beyond it.
This example and the next assume that clean tree: a dirty one always draws one
more node on top, which is the section after them.

The node glyph is a ramp of how set in stone a commit is: **`o`** a draft that's
still only yours, **`◇`** a draft already pushed to a remote — rewriting it costs
a force-push — and **`◆`** a public commit. `@` outranks all three, wherever the
working copy is. (`◇` needs a branch of yours on a remote to show up; it appears
in the `-b` examples further down, on `origin/hotfix`.)

That ramp is shape rather than color on purpose. Indentation can't carry it — a
`-b` side column is indented too — and neither can the palette: the draft and
public hash colors are `\e[93m` and `\e[33m`, which are the *same yellow* in
Dracula and most 16-color themes, so bold was doing all the work. Shape also
survives `NO_COLOR`, a pipe, and every capture on this page.

A subject prefixed **`(empty)`** is a commit that changed nothing against its
parent — here, a rebase onto `origin/master` found the dependency bump already
applied and left the commit with nothing in it. Without the label an emptied
commit is indistinguishable from one still carrying work; with it, the commit
you want to drop says so. (`-c` gives such a commit no stat body at all, below.)

In a terminal the hash also splits: the shortest prefix that uniquely names the
commit in this repo keeps the hash color and the digits past it go dim, so a row
shows how much of a hash you actually have to type. It's a color effect only —
the text is the same 10 digits either way, which is why these captures don't
show it. The cover image up top does.

The public column stops at that base by design — one row plus `~`. `-f` /
`--full` is the tool's one *don't abbreviate* switch, and it lifts three
shortenings at once. Two show up here: older public history keeps streaming
below the base instead of stopping (lazily, into the pager, like `git log` —
scroll and it keeps going, down to the root commit), and public commits authored
by *someone else*, which render metadata-only by default, get their author and
subject back. The third is the submodule sub-line cap, further down.

<!-- fixture: demo-clean -->
```text
$ git smartlog -f
  @  2f0e95dfc5  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │
  o  6660e2b318  Today at 20:10  junz
  │  Add exponential backoff with jitter
  │
  o  859711ce71  Today at 18:10  junz
  │  (empty) Require golang.org/x/time
  │
  o  0280c2f0a8  Yesterday at 23:10  junz
╭─╯  Extract retry policy into its own module
│
◆  9126f994b8  Thursday at 23:10  junz  origin/master
│  Bump dependencies
│
◆  13dfdace4e  Wednesday at 23:10  alice
│  Introduce typed errors
│
◆  566785cd0c  Tuesday at 23:10  alice
│  Initial project scaffold
~
```

A synthetic **Uncommitted changes** node is drawn on top of `HEAD` whenever the
working tree is dirty — no flag needed. It's one line: compact totals from
`git diff --stat HEAD`, so a dirty tree costs the graph a single row no matter
how much is uncommitted. Loose untracked files are folded into those totals (as
new-file additions) via a throwaway index overlay, so they count without touching
the real index; a **wholly-untracked directory counts as one entry** rather than
every file inside it, just like `git status`. The per-file breakdown is `-c`'s
job — the node is a commit like any other in that respect — and that's the
section right after this one.

The `@` marker moves to the node — that's where the working
copy is — and `HEAD` drops to an `o` (keeping its author and subject):

<!-- fixture: demo -->
```text
$ git smartlog
  @  Uncommitted changes  11 files, +30 -13
  │
  o  2f0e95dfc5  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │
  o  6660e2b318  Today at 20:10  junz
  │  Add exponential backoff with jitter
  │
  o  859711ce71  Today at 18:10  junz
  │  (empty) Require golang.org/x/time
  │
  o  0280c2f0a8  Yesterday at 23:10  junz
╭─╯  Extract retry policy into its own module
│
◆  9126f994b8  Thursday at 23:10  junz  origin/master
│  Bump dependencies
~
```

With `-c` / `--changes`, a per-file stat block attaches to **every commit in the
current stack**, clean or dirty (against each commit's first parent), **and to
the uncommitted node** — the same flag, on the same footing; sitting directly on
the trunk (no stack), it covers **every public commit in view** instead — pair it
with `-f` to walk back through it. Commit bodies close with a dim
`N files, +X -Y` total line; the uncommitted node keeps its total in the header
it already had. An `(empty)` commit gets no body — there is nothing to stat, and
its subject already says so.

Every body is `git diff --stat` bars with each filename prefixed by a one-letter
change marker; both marker and name are color-coded by kind, on top of git's
usual green/red `+`/`-` bars. Lines are **grouped by marker**, in the order below
(sorted by path within each group, matching `git status`):

| marker | meaning | color |
| :-: | --- | --- |
| `A` | added (staged) | green |
| `?` | untracked | dim green |
| `M` | modified | default |
| `D` | deleted | red |
| `R` | renamed | blue |
| `T` | typechange (file↔symlink) | magenta |
| `S` | submodule | cyan |
| `U` | unmerged (conflict) | bold red |

`?` and `U` can only occur in the uncommitted node — a committed diff has
neither. There, too, loose untracked files show up as their own entries and a
wholly-untracked directory collapses to a single `dir/ | N files` line instead of
expanding to every file inside it.

A pure executable-bit flip (`chmod`), which `--stat` renders as `| 0`, gets a
trailing `+x`/`-x` hint. A **submodule** (`S`) expands into sub-lines under its
stat line, in two groups of at most 10 lines each, each closing with a dim
`… +N more` when it overflows (`-f` lifts the cap):

- its own **uncommitted changes** — this same stat block, recomputed inside the
  submodule and indented one level in, keeping its markers, colors and bars (a
  dirty submodule inside it nests again). Without this a merely dirty submodule
  says nothing at all: its recorded sha is unchanged, so git renders it as a bare
  `| 0`. Under a commit body there's no working tree to read, so this group is
  the uncommitted node's alone.
- the commits its pointer **gained or lost**, from `git diff --submodule=log`,
  newest first and dim — `›` for one gained, `‹` for one lost (a rewind); a bump
  git can't summarize (commits not present locally) adds none.

<!-- fixture: demo -->
```text
$ git smartlog -c
  @  Uncommitted changes  11 files, +30 -13
  │  A metrics.go           | 7 +++++++
  │  ? coverage/            | 2 files
  │  ? retry_test.go        | 9 +++++++++
  │  M http_client.go       | 2 +-
  │  M retry.go             | 8 +++++++-
  │  M scripts/release.sh   | 0 +x
  │  D legacy.go            | 6 ------
  │  R logging.go => log.go | 0
  │  T config.json          | 5 +----
  │  S vendor/timeutil      | 2 +-
  │      ? clock.go    | 1 +
  │      M timeutil.go | 2 ++
  │      › v1.11.0
  │      › v1.10.0
  │      › v1.9.0
  │      › v1.8.0
  │      › v1.7.0
  │      › v1.6.0
  │      › v1.5.0
  │      › v1.4.0
  │      › v1.3.0
  │      › v1.2.0
  │      … +1 more
  │  U version.go           | 4 ++++
  │
  o  2f0e95dfc5  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │  M http_client.go | 15 ++++++++++++---
  │  M version.go     |  2 +-
  │  2 files, +13 -4
  │
  o  6660e2b318  Today at 20:10  junz
  │  Add exponential backoff with jitter
  │  A backoff.go | 13 +++++++++++++
  │  M retry.go   |  7 +++++++
  │  2 files, +20 -0
  │
  o  859711ce71  Today at 18:10  junz
  │  (empty) Require golang.org/x/time
  │
  o  0280c2f0a8  Yesterday at 23:10  junz
  │  Extract retry policy into its own module
  │  A retry.go       | 11 +++++++++++
  │  M http_client.go |  9 +++++----
  │  2 files, +16 -4
╭─╯
│
◆  9126f994b8  Thursday at 23:10  junz  origin/master
│  Bump dependencies
~
```

With `-b` / `--branches`, every **other local branch** joins the graph too, each
rendering its **complete stack**. All heads' chains
union into a forest, so a branch **forking from a draft commit** shows as a real
fork, and commits **stacked above `HEAD`** — a branch containing `HEAD` while
you're checked out mid-stack — appear too, with `@` drawn mid-tree. Fork points
join the public column no matter how far down they sit, and commits skipped
between them elide to a dotted `╷` spine. Two rules keep the graph
quiet: a branch merged into the trunk just labels that commit instead of adding
a node (`prod` below), and a branch whose same-name remote ref sits at the same
commit shows only the remote name (`origin/hotfix`). Branch names render
**cyan**, so they stand apart from green remote refs and the yellow active
branch. Everything composes with `-c` and with the `-f` used here, which gives
Alice's public commits their full headers and keeps the trunk streaming past the
base:

<!-- fixture: demo -->
```text
$ git smartlog -b -f
  @  Uncommitted changes  11 files, +30 -13
  │
  o  2eba87d41d  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │
  o  508eb458ca  Today at 20:42  junz  wip/backoff
  │  Add exponential backoff with jitter
  │
  o  1d043187ca  Today at 18:42  junz
  │  (empty) Require golang.org/x/time
  │
  │ o  8c4ace2f8e  Today at 05:42  junz  spike/http3
  │ │  Spike HTTP/3 transport
  │ │
  │ │ o  def5ea265d  Today at 04:42  junz  refactor/timeouts
  │ ├─╯  Let callers override the attempt timeout
  │ │
  │ o  fc76d17f31  Today at 03:42  junz
  ├─╯  Bound each attempt with a timeout
  │
  o  fd1261ffc9  Yesterday at 23:42  junz
╭─╯  Extract retry policy into its own module
│
│ ◇  ad37e81b52  Friday at 23:42  junz  origin/hotfix
├─╯  Patch release 0.1.1
│
◆  4e4eef0507  Thursday at 23:42  junz  origin/master
╷  Bump dependencies
╷
╷ o  9746e604e8  Yesterday at 22:42  junz  fix/redirect-loop
╷ │  Abort redirect loops via CheckRedirect
╷ │
╷ o  da4f68a140  Yesterday at 21:42  junz
╭─╯  Cap redirect chains at 10 hops
│
◆  263b50e712  Tuesday at 23:42  alice  prod
│  Initial project scaffold
~
```

At each fork the spine child (the one on `HEAD`'s path, else the newest subtree)
continues the column and every other child opens a column one level deeper,
newest first, closing with a `├─╯` bend right above the fork. Narrow the public
window back to the default and the elision shows up too:

<!-- fixture: demo -->
```text
$ git smartlog -b
  @  Uncommitted changes  11 files, +30 -13
  │
  o  2eba87d41d  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │
  o  508eb458ca  Today at 20:42  junz  wip/backoff
  │  Add exponential backoff with jitter
  │
  o  1d043187ca  Today at 18:42  junz
  │  (empty) Require golang.org/x/time
  │
  │ o  8c4ace2f8e  Today at 05:42  junz  spike/http3
  │ │  Spike HTTP/3 transport
  │ │
  │ │ o  def5ea265d  Today at 04:42  junz  refactor/timeouts
  │ ├─╯  Let callers override the attempt timeout
  │ │
  │ o  fc76d17f31  Today at 03:42  junz
  ├─╯  Bound each attempt with a timeout
  │
  o  fd1261ffc9  Yesterday at 23:42  junz
╭─╯  Extract retry policy into its own module
│
│ ◇  ad37e81b52  Friday at 23:42  junz  origin/hotfix
├─╯  Patch release 0.1.1
│
◆  4e4eef0507  Thursday at 23:42  junz  origin/master
╷  Bump dependencies
╷
╷ o  9746e604e8  Yesterday at 22:42  junz  fix/redirect-loop
╷ │  Abort redirect loops via CheckRedirect
╷ │
╷ o  da4f68a140  Yesterday at 21:42  junz
╭─╯  Cap redirect chains at 10 hops
│
◆  263b50e712  Tuesday at 23:42  prod
│
~
```

Here `refactor/timeouts` forks off a draft of the current stack and
`spike/http3` off a draft of *that* branch, so the layout nests one level
further. Sibling subtrees render newest-first, and the child on `HEAD`'s path
continues the column. Below `origin/master`, `fix/redirect-loop`'s fork point sits two
commits down the trunk, so the commit between them elides to the dotted `╷`
spine. A dirty working tree draws its uncommitted node directly above `HEAD`,
wherever `HEAD` sits in the tree.

With `-p` / `--prs` (needs the [GitHub CLI](https://cli.github.com/)), every
branch name shown on a commit that has a GitHub PR gets a trailing `#N` tag —
blue for open, dim blue for draft, magenta for merged, red for closed — and,
on a TTY, an OSC 8 hyperlink to the PR. The flag is sticky per repo: once
passed, later runs keep tagging without it until `-P` / `--no-prs` turns it
off. The cover image up top shows the tags in all four states on the `-b`
view.

In a real terminal the output is colorized — draft hashes in bold yellow,
`HEAD`'s line in magenta, remote refs in green, `-b` branch names in cyan, and
every hash dim past its unique prefix. ANSI is suppressed when stdout
isn't a TTY (as in these captures) or when `NO_COLOR` is set — which is why
`(empty)` and the `o`/`◇`/`◆` ramp are text and the hash dimming is not. Nothing
is encoded in the hash color alone; two of the three yellows in a 16-color theme
are the same yellow, so anything that mattered had to go in the glyph.

`◇` is deliberately weaker than jj's immutability line, which *excludes* remote
bookmarks you track, on the grounds that rewriting your own pushed branch is
routine. Painting a whole PR stack as frozen would be worse than saying nothing —
hence the middle glyph rather than `◆`.

## Requirements

- `zsh`
- `git`

That's it. The script sources nothing else, so you can drop it anywhere on your
`PATH` and run it — the uncommitted node included, since its stat block is
computed in-file (see
[git-smartstat](#git-smartstat)). The one opt-in extra is `-p`/`--prs`, which
needs the [GitHub CLI (`gh`)](https://cli.github.com/); everything else works
without it.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/junzh0u/git-smartlog/master/git-smartlog \
  -o ~/.local/bin/git-smartlog
chmod +x ~/.local/bin/git-smartlog
# optional: the same file doubles as `git smartstat` (see below)
ln -s git-smartlog ~/.local/bin/git-smartstat
```

Because the script is named `git-smartlog` and lives on your `PATH`, Git picks it
up as a subcommand — run it as `git smartlog`. A short alias is handy:

```sh
git config --global alias.sl smartlog
```

Zsh completions live in [`completions/`](completions/): put `_git-smartlog` and
`_git-smartstat` in a directory on your `fpath` before `compinit` runs. They
complete the direct commands, and — with zsh's own `_git` — the `git smartlog` /
`git smartstat` subcommand forms too; add the subcommand *names* to `git <TAB>`
with:

```sh
zstyle ':completion:*:*:git:*' user-commands \
    smartlog:'draft stack over its public base' \
    smartstat:'uncommitted working-tree stat block'
```

## Usage

Both commands take `-C <path>`, exactly as git does — run as if started in that
directory, repeats composing — so you can point them at a repo without leaving
the one you're in.

```
usage: git-smartlog [-C <path>] [-c] [-b] [-f] [-p|-P] [--base REV]

Sapling-inspired smartlog using only git: the current branch's draft stack
drawn on top of its nearest public (pushed) base. A dirty working tree always
draws an "Uncommitted changes" node on top of HEAD, carrying its totals.

The three view flags below are independent and combine freely.

  -c, --changes       show per-file changes under every commit in the current
                      stack — or under the public commit in view when HEAD
                      sits on the trunk (pair with -f for history) — and under
                      the uncommitted node, which otherwise shows totals only
  -b, --branches      show every other local branch as its full stack —
                      including forks at draft commits and commits stacked
                      above HEAD
  -f, --full          don't abbreviate: show author + subject on every commit
                      (including other authors' public ones, which otherwise
                      render metadata-only), keep streaming older
                      public history below the base — lazily when paged, like
                      git log — and stop capping a submodule entry's sub-lines
                      at 10 (-b's ╷ elision stays — it keeps distant fork
                      points adjacent, which is the point of that view)
  -p, --prs           tag shown branch names that have a GitHub PR with its
                      "#N" — colored by PR state, hyperlinked on a TTY
                      (needs the gh CLI); sticky — remembered per repo, so
                      later runs tag PRs without the flag
  -P, --no-prs        turn PR tagging off and forget the remembered -p
                      (wins when both are given)
      --base REV      override the public base (default: nearest remote trunk, e.g.
                      origin/HEAD, origin/main, origin/master, upstream/main)
  -C <path>           run as if started in <path>, like git's own -C; repeats
                      compose, each relative to the last
  -h, --help          show this help and exit

Output taller than the terminal is paged ($GIT_PAGER / core.pager / $PAGER /
less; GIT_PAGER=cat disables paging).
```

## git-smartstat

The uncommitted-changes block isn't just an add-on to the graph — it's also useful
on its own. `git-smartlog` is **multi-call**: the same file, invoked under the name
`git-smartstat`, prints *only* that block (the exact body the graph's node draws) as a
standalone command. Symlink it and you get `git smartstat`:

```sh
ln -s git-smartlog ~/.local/bin/git-smartstat
```

```
usage: git-smartstat [-C <path>] [--color WHEN]

Show uncommitted working-tree changes as a compact stat block: a summary line
("2 files, +69 -2") followed by per-file diff bars; loose untracked files are
folded in and wholly-untracked directories collapse to a single entry like git
status. Each name carries a change marker — A added, ? untracked, M modified,
D deleted, R renamed, T typechange, S submodule, U unmerged — colored by kind.
Prints nothing when the working tree is clean. The same block git-smartlog draws
under its uncommitted-changes node with -c.

      --color WHEN    colorize output: auto (default), always, or never
  -C <path>           run as if started in <path>, like git's own -C
  -h, --help          show this help and exit
```

<!-- fixture: demo -->
```text
$ git smartstat
11 files, +30 -13
 A metrics.go           | 7 +++++++
 ? coverage/            | 2 files
 ? retry_test.go        | 9 +++++++++
 M http_client.go       | 2 +-
 M retry.go             | 8 +++++++-
 M scripts/release.sh   | 0 +x
 D legacy.go            | 6 ------
 R logging.go => log.go | 0
 T config.json          | 5 +----
 S vendor/timeutil      | 2 +-
     ? clock.go    | 1 +
     M timeutil.go | 2 ++
     › v1.11.0
     › v1.10.0
     › v1.9.0
     › v1.8.0
     › v1.7.0
     › v1.6.0
     › v1.5.0
     › v1.4.0
     › v1.3.0
     › v1.2.0
     … +1 more
 U version.go           | 4 ++++
```

<p align="center">
  <img src="screenshots/smartstat.png" alt="git smartstat output, color-coded by change kind" width="560">
</p>

A wholly-untracked directory collapses to a single entry — the way `git status`
lists a new directory — with a file count in place of the `+`/`-` graph,
right-justified into the same column as git's per-file line counts. That's the
`coverage/` line above: two files inside, one line out, and it counts as one
entry in the `11 files` total rather than two.

Paths are shown in full up to your terminal width; like `git diff --stat`, they
shorten to a leading `...tail` only when the terminal is too narrow to fit them
(piped output uses git's 80-column default).

It prints nothing when the working tree is clean. Both names share one in-file
function (`uncommitted_stat`), so there's no duplicated logic and `git-smartlog`
stays a single self-contained file — the node needs nothing external. (Standalone,
`git-smartstat` also works in a repo with no commits yet, diffing against the
empty tree so staged and untracked files still show as additions.)

## How it works

- **Public base** — the nearest public ancestor of `HEAD`. Candidate trunks are
  remote-tracking refs only (`origin/HEAD`, `upstream/HEAD`, `origin/main`,
  `origin/master`, `upstream/main`, `upstream/master`); among those, the one whose
  merge-base with `HEAD` is closest to `HEAD` wins. `@{u}` and a local
  `main`/`master` are last-resort fallbacks when no remote trunk exists.
- **Drafts** — first-parent commits in `HEAD ^base`, newest first.
- **Symbols** — `@` where the working copy is, then a ramp: `o` unpushed draft,
  `◇` pushed draft, `◆` public. jj's idea: the node carries the phase, so it
  survives `NO_COLOR`, a pipe, and a `-b` side column's indentation. Shape and
  not color because `\e[93m`/`\e[33m` are one yellow in most themes.
- **Pushed drafts** — a draft reachable from any remote-tracking ref draws `◇`.
  One `git rev-list <draft heads> --not --remotes`
  prints the drafts that *aren't*, so the ones it omits are pushed; the walk
  stops at the remote boundary, so it's bounded by the unpushed set, and it's
  skipped entirely in a repo with no remotes. (`--no-walk` doesn't restrict that
  to the argument set — with `--not` in play git walks regardless.)
- **Hashes** — 10 digits, but only the leading ones matter: a second `%h` at
  `--abbrev=4` in the same `git log` pass asks git for the shortest prefix that
  names exactly one object, and the digits past it render dim. jj's idea — its
  ids show at a glance how much you'd have to type. A repo big enough to collide
  inside 10 digits is shown the wider unique prefix instead of an ambiguous
  hash, the way git widens its own output.
- **`(empty)`** — a commit whose tree equals its first parent's (the empty tree
  for a root commit) gets its subject prefixed `(empty)`, and no `-c` body. jj
  labels these in its log; git doesn't, so an emptied commit looks like any
  other. Decided from tree hashes, not diffs: `%T` rides along with the metadata every
  row already fetches, and the handful of parents outside the window are fetched
  in one batch rather than a `rev-parse` per row. In the `-f` tail, where there
  is no window to batch over, rows are held one behind — in a first-parent walk
  the next record *is* the previous row's parent.
- **Uncommitted changes** — whenever `git status` is non-empty, a synthetic
  node on top of `HEAD` carrying compact totals; the `@` marker moves there.
  Borrowed from jj, where the working copy *is* a commit and needs no synthesis.
  With `-c` it also gets per-file `git diff --stat HEAD` bars. Totals and bars
  alike are computed against a throwaway index overlay that intent-to-adds loose
  untracked files so they're folded in without mutating the repo (a wholly-untracked
  directory instead collapses to one `dir/ | N files` entry, like `git status`).
  Each body filename gets a
  one-letter change marker (`A`/`?`/`M`/`D`/`R`/`T`/`S`/`U`, from `git diff --raw`,
  plus the porcelain status for conflicts) colored by kind (see the marker table
  above), and a `+x`/`-x` hint on executable-bit flips. This block is computed by
  the in-file `uncommitted_stat` function — the same code the
  [`git-smartstat`](#git-smartstat) command runs. Without `-c` that function
  stops at the totals, skipping the marker/sort pass and the per-submodule
  expansion nobody would see.
- **Public window** — one commit: the base, with `~` below it. `-f` streams
  the history below instead.
- **Other branches** — with `-b`/`--branches`, every head's first-parent chain
  is unioned into a forest of draft trees (shared prefixes dedup), each rendered
  above its root's public fork point: the spine child continues the column, side
  subtrees open one column deeper per fork level and close with a `├─╯` bend
  above the fork. Sibling subtrees order by newest commit date and the spine
  prefers `HEAD`'s path — Git has no revision numbers to sort by. Includes
  commits stacked above `HEAD`. Fork points are added
  to the public column no matter how far down they sit, with commits skipped
  between them eliding to a dotted `╷` spine. Branch names render cyan
  so they stand apart from green remote refs. Two branches don't get a node of
  their own: one merged into the trunk (its head *is* the merge-base) labels
  that public commit instead, and one whose same-name remote ref sits at the
  same commit shows only the remote name.
- **PR numbers** — with `-p`/`--prs`, every branch name shown on a commit (the
  active branch, a remote bookmark, or a `-b` local) that has a GitHub PR
  gets a trailing `#N` tag: blue for open, dim blue for draft, magenta for
  merged, red for closed — and, on a color-capable TTY, an OSC 8 hyperlink to
  the PR. One `gh pr list --state all` call maps branches to PRs (a branch with
  several keeps an open one over closed/merged, else the newest); the trunk's
  own branch is skipped so its long-merged PR doesn't tag every graph. The
  call's ~1s API round-trip is cached per repo in the git dir for
  `$GIT_SMARTLOG_PR_TTL` seconds (default 60; `0` forces a refetch), so only
  the first `-p` run in a while pays it. Needs the GitHub CLI (`gh`); a failed
  listing warns and falls back to the stale cache, else renders without tags.
  `-p` is sticky per repo — it drops a marker file in the git dir
  (`smartlog-pr-on`), so later runs tag PRs without the flag; `-P`/`--no-prs`
  removes the marker and turns tagging off (winning when both are given).
  When tagging is on only via the marker, a missing `gh` warns instead of
  erroring, so plain runs keep working on a machine without it.
- **Subjects** — shown in full, never truncated to the terminal width, so a
  long one wraps rather than ending in an ellipsis.
- **Color** — ANSI, automatically suppressed when stdout isn't a TTY or `NO_COLOR`
  is set.
- **Paging** — output taller than the terminal is piped through a pager
  (`$GIT_PAGER`, then git's `core.pager`, then `$PAGER`, then `less` with
  `LESS=FRX` like git). Output that fits, or piped/redirected output, prints
  directly; `GIT_PAGER=cat` disables paging. Colors survive the pager.
- **Infinite scroll** — with `-f`/`--full`, the public column doesn't stop at
  the base: older history keeps streaming below it — lazily when paged, so
  scrolling keeps revealing commits like plain `git log`, down to the root
  commit. Without `-f` the base row and the trailing `~` truncation row are
  unconditional. `-f` is the one *don't abbreviate* switch, so the same flag
  also restores full headers on other authors' public commits and lifts the
  10-line cap on a submodule entry's sub-lines — the only way to see every
  commit a big bump brought in. It deliberately leaves `-b`'s `╷` elision
  alone: this tail streams lazily and only downward, one row per scroll, while
  filling the gaps *between* fork points is eager and unbounded — a branch
  forking 200 commits down the trunk would push every other tree off screen.
  Keeping distant fork points adjacent is the whole point of the `-b` view.

## License

[MIT](LICENSE)
