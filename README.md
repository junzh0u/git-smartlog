# git-smartlog

A [Sapling](https://sapling-scm.com/)-style `smartlog` for plain Git, in a single
self-contained zsh script. The same file doubles as
[`git-smartstat`](#git-smartstat), a standalone view of uncommitted changes.

It renders the current branch's **draft stack** — the first-parent chain of your
local (unpushed) commits — drawn on top of its nearest **public** (pushed) base,
with relative timestamps, authors, and ref decorations, closely mirroring the
output of Sapling's `sl`. Four things depart from that mirror: a dirty working
tree always draws an uncommitted-changes node, and three independent flags —
`-c` for per-file change stats under your commits and your working copy, `-b` to
fold your other local branches into the graph as full stacks, `-a` to stop
compacting other people's public commits — combine freely on top. See below.

The story behind it is in
[this post](https://junz.info/writing/git-smartlog/).

<p align="center">
  <img src="screenshots/cover.png" alt="git-smartlog -n 2 -b -a -p output" width="600">
</p>

## Example

On a feature branch with a few local commits stacked on `origin/master`, with a
clean working tree:

<!-- fixture: demo-clean -->
```text
$ git smartlog
  @  e6152ce8e3  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │
  o  6f1c5c322c  Today at 17:34  junz
  │  Add exponential backoff with jitter
  │
  o  4166003ae8  Yesterday at 20:34  junz
╭─╯  Extract retry policy into its own module
│
o  99b3100c38  Thursday at 20:34  junz  origin/master
│  Bump dependencies
~
```

`@` marks `HEAD`; the indented `o` nodes above the bend (`╭─╯`) are your unpushed
draft commits, newest first. Below the bend sits the public base — the nearest
pushed commit, here `origin/master` — and `~` marks the truncated history beyond
it. This example and the next assume that clean tree: a dirty one always draws
one more node on top, which is the section after them.

Widen the public window with `-n`. Public commits authored by *someone else*
render metadata-only (no author, no subject), exactly as Sapling does — see
`a21fc72b55` and `80cf810025` below. Pass `-a` / `--all-authors` to turn that
off and show the author and subject for every commit, including other people's
public ones:

<!-- fixture: demo-clean -->
```text
$ git smartlog -n 4
  @  e6152ce8e3  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │
  o  6f1c5c322c  Today at 17:34  junz
  │  Add exponential backoff with jitter
  │
  o  4166003ae8  Yesterday at 20:34  junz
╭─╯  Extract retry policy into its own module
│
o  99b3100c38  Thursday at 20:34  junz  origin/master
│  Bump dependencies
│
o  71068b2065  Wednesday at 20:34
│
│
o  2438d674fc  Tuesday at 20:34
│
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
copy is — and `HEAD` drops to an `o` (keeping its author and subject). This is a
git-smartlog extension with no Sapling equivalent, so the output no longer mirrors
`sl` (see [Differences](#differences-from-saplings-sl)):

<!-- fixture: demo -->
```text
$ git smartlog -n 2
  @  Uncommitted changes  11 files, +30 -13
  │
  o  8685566e7a  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │
  o  332dae7792  Today at 18:29  junz
  │  Add exponential backoff with jitter
  │
  o  424771e9eb  Yesterday at 21:29  junz
╭─╯  Extract retry policy into its own module
│
o  db25b229b0  Thursday at 21:29  junz  origin/master
│  Bump dependencies
│
o  2aa517301c  Wednesday at 21:29
│
~
```

With `-c` / `--changes`, a per-file stat block attaches to **every commit in the
current stack**, clean or dirty (against each commit's first parent), **and to
the uncommitted node** — the same flag, on the same footing; sitting directly on
the trunk (no stack), it covers **every public commit in view** instead — pair it
with `-n` to review recent history. Commit bodies close with a dim
`N files, +X -Y` total line; the uncommitted node keeps its total in the header
it already had.

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
`… +N more` when it overflows (`-N` lifts the cap):

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
  o  6e3da2593c  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │  M http_client.go | 15 ++++++++++++---
  │  M version.go     |  2 +-
  │  2 files, +13 -4
  │
  o  0c83b006b2  Today at 18:08  junz
  │  Add exponential backoff with jitter
  │  A backoff.go | 13 +++++++++++++
  │  M retry.go   |  7 +++++++
  │  2 files, +20 -0
  │
  o  090efdec03  Yesterday at 21:08  junz
  │  Extract retry policy into its own module
  │  A retry.go       | 11 +++++++++++
  │  M http_client.go |  9 +++++----
  │  2 files, +16 -4
╭─╯
│
o  0fa721bda0  Thursday at 21:08  junz  origin/master
│  Bump dependencies
~
```

With `-b` / `--branches`, every **other local branch** joins the graph too, each
rendering its **complete stack**, exactly as Sapling draws it. All heads' chains
union into a forest, so a branch **forking from a draft commit** shows as a real
fork, and commits **stacked above `HEAD`** — a branch containing `HEAD` while
you're checked out mid-stack — appear too, with `@` drawn mid-tree. Fork points
join the public column no matter how far down they sit, and commits skipped
between them elide to Sapling's dotted `╷` spine. Two rules keep the graph
quiet: a branch merged into the trunk just labels that commit instead of adding
a node (`prod` below), and a branch whose same-name remote ref sits at the same
commit shows only the remote name (`origin/hotfix`). Branch names render
**cyan**, so they stand apart from green remote refs and the yellow active
branch. Everything composes with `-c`, `-n`, and the `-a` used here to give
Alice's public commits their full headers:

<!-- fixture: demo -->
```text
$ git smartlog -n 2 -b -a
  @  Uncommitted changes  11 files, +30 -13
  │
  o  8685566e7a  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │
  o  332dae7792  Today at 18:29  junz  wip/backoff
  │  Add exponential backoff with jitter
  │
  │ o  2cba6cab4d  Today at 03:29  junz  spike/http3
  │ │  Spike HTTP/3 transport
  │ │
  │ │ o  3e17ebb235  Today at 02:29  junz  refactor/timeouts
  │ ├─╯  Let callers override the attempt timeout
  │ │
  │ o  fcb3c6c361  Today at 01:29  junz
  ├─╯  Bound each attempt with a timeout
  │
  o  424771e9eb  Yesterday at 21:29  junz
╭─╯  Extract retry policy into its own module
│
│ o  d0511f97bf  Friday at 21:29  junz  origin/hotfix
├─╯  Patch release 0.1.1
│
o  db25b229b0  Thursday at 21:29  junz  origin/master
│  Bump dependencies
│
o  2aa517301c  Wednesday at 21:29  alice
│  Introduce typed errors
│
│ o  254752406c  Yesterday at 20:29  junz  fix/redirect-loop
│ │  Abort redirect loops via CheckRedirect
│ │
│ o  249db17a80  Yesterday at 19:29  junz
├─╯  Cap redirect chains at 10 hops
│
o  70357b18fd  Tuesday at 21:29  alice  prod
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
  o  8685566e7a  14 minutes ago  junz  feat/retry-backoff*
  │  Wire backoff into the HTTP client
  │
  o  332dae7792  Today at 18:29  junz  wip/backoff
  │  Add exponential backoff with jitter
  │
  │ o  2cba6cab4d  Today at 03:29  junz  spike/http3
  │ │  Spike HTTP/3 transport
  │ │
  │ │ o  3e17ebb235  Today at 02:29  junz  refactor/timeouts
  │ ├─╯  Let callers override the attempt timeout
  │ │
  │ o  fcb3c6c361  Today at 01:29  junz
  ├─╯  Bound each attempt with a timeout
  │
  o  424771e9eb  Yesterday at 21:29  junz
╭─╯  Extract retry policy into its own module
│
│ o  d0511f97bf  Friday at 21:29  junz  origin/hotfix
├─╯  Patch release 0.1.1
│
o  db25b229b0  Thursday at 21:29  junz  origin/master
╷  Bump dependencies
╷
╷ o  254752406c  Yesterday at 20:29  junz  fix/redirect-loop
╷ │  Abort redirect loops via CheckRedirect
╷ │
╷ o  249db17a80  Yesterday at 19:29  junz
╭─╯  Cap redirect chains at 10 hops
│
o  70357b18fd  Tuesday at 21:29  prod
│
~
```

Here `refactor/timeouts` forks off a draft of the current stack and
`spike/http3` off a draft of *that* branch, so the layout nests one level
further — what Sapling's renderdag produces for the same topology, verified
against it. Below `origin/master`, `fix/redirect-loop`'s fork point sits two
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
`HEAD`'s line in magenta, remote refs in green, `-b` branch names in cyan. ANSI is suppressed when stdout
isn't a TTY (as in these captures) or when `NO_COLOR` is set.

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
    smartlog:'sapling-style smartlog' \
    smartstat:'uncommitted working-tree stat block'
```

## Usage

Both commands take `-C <path>`, exactly as git does — run as if started in that
directory, repeats composing — so you can point them at a repo without leaving
the one you're in.

```
usage: git-smartlog [-C <path>] [-c] [-b] [-a] [-p|-P] [-n N] [-N] [--base REV]

Sapling-style smartlog using only git: the current branch's draft stack
drawn on top of its nearest public (pushed) base. A dirty working tree always
draws an "Uncommitted changes" node on top of HEAD, carrying its totals.

The three view flags below are independent and combine freely.

  -c, --changes       show per-file changes under every commit in the current
                      stack — or under every public commit in view when HEAD
                      sits on the trunk (pair with -n) — and under the
                      uncommitted node, which otherwise shows totals only
  -b, --branches      show every other local branch as its full stack, like
                      sapling — including forks at draft commits and commits
                      stacked above HEAD
  -a, --all-authors   show author + subject for every commit, including public
                      commits by other authors (default: those render compact)
  -p, --prs           tag shown branch names that have a GitHub PR with its
                      "#N" — colored by PR state, hyperlinked on a TTY
                      (needs the gh CLI); sticky — remembered per repo, so
                      later runs tag PRs without the flag
  -P, --no-prs        turn PR tagging off and forget the remembered -p
                      (wins when both are given)
  -n, --limit N       public commits to show, including the merge-base (default 1)
  -N, --no-limit      don't truncate: keep streaming older public history
                      below the -n window — lazily when paged, like git log —
                      and stop capping a submodule entry's sub-lines at 10
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
- **Uncommitted changes** — whenever `git status` is non-empty, a synthetic
  node on top of `HEAD` carrying compact totals; the `@` marker moves there.
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
- **Public window** — `-n` commits starting at the base.
- **Other branches** — with `-b`/`--branches`, every other local branch joins the
  graph as a single node (its head commit) above its anchor — the nearest shown
  commit down its chain: a draft of the current stack, another branch's node,
  or its fork point with the trunk — tagged with a dim `(+N)` count of commits
  since that anchor; branch names render
  cyan so they stand apart from green remote refs. Trunk fork points are added
  to the public column, with skipped commits eliding to Sapling's dotted `╷`
  spine. A
  branch merged into the trunk — or pointing at a commit already on screen —
  labels that commit instead of adding a node, and a branch whose same-name
  remote ref sits at the same commit shows only the remote name.
- **Full stacks** — with `-b`/`--branches`, every head's first-parent chain
  is unioned into a forest of draft trees (shared prefixes dedup), each rendered
  above its root's public fork point: the spine child continues the column, side
  subtrees open one column deeper per fork level and close with a `├─╯` bend
  above the fork. Includes commits stacked above `HEAD`.
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
- **Color** — ANSI, automatically suppressed when stdout isn't a TTY or `NO_COLOR`
  is set.
- **Paging** — output taller than the terminal is piped through a pager
  (`$GIT_PAGER`, then git's `core.pager`, then `$PAGER`, then `less` with
  `LESS=FRX` like git). Output that fits, or piped/redirected output, prints
  directly; `GIT_PAGER=cat` disables paging. Colors survive the pager.
- **Infinite scroll** — with `-N`/`--no-limit`, the public column doesn't stop
  at the `-n` window: older history keeps streaming below it — lazily when
  paged, so scrolling keeps revealing commits like plain `git log`, down to
  the root commit. Without `-N` the window and the trailing `~` truncation row
  are unconditional. `-N` reads as *don't truncate* rather than strictly *no
  `-n` limit*, so it also lifts the 10-line cap on a submodule entry's
  sub-lines — the only way to see every commit a big bump brought in.

## Differences from Sapling's `sl`

- **Single stack only.** It renders the current `HEAD`'s first-parent draft chain
  plus its public base. Sapling renders *every* draft branch as its own stack via
  a full DAG renderer; this script deliberately does not, so other local branches
  and draft heads won't appear by default. Output matches `sl` exactly when you're
  working a single branch (the common case).
- **`-b`/`--branches` is the parity mode.** Without it only the current stack
  is drawn, where Sapling always renders every draft branch. With it you get
  full per-branch stacks in the same contiguous-chain layout Sapling's renderdag
  produces (verified against it); branch names are cyan rather than Sapling's
  green `sl.book`, so local branches read differently from remote refs. The
  remaining differences are ordering heuristics: Sapling sorts by its local
  revision numbers, which Git doesn't have, so sibling subtrees order by newest
  commit date and the spine prefers `HEAD`'s path.
- **Long subjects shown in full.** Sapling truncates them to the terminal width
  with an ellipsis.
- **The uncommitted node is an extension, not a mirror.** On a clean tree the
  output tracks Sapling's `sl` closely, but the node has no Sapling
  equivalent — the idea is borrowed from
  [Jujutsu](https://github.com/jj-vcs/jj), which treats the working copy as a
  commit in its own right; Sapling surfaces working-copy changes differently.
  Unlike the flags below it is always on, so any dirty-tree output diverges from
  `sl` by that node.
- **`-c`/`--changes` is an extension too.** It draws a per-file stat body under
  every commit in the current stack (or every public commit in view, when
  sitting on the trunk) and under the uncommitted node. Sapling has no
  equivalent; the default output is unchanged.
- **`-a`/`--all-authors` is an extension.** By default, public commits by other
  authors render metadata-only, exactly as Sapling does. `-a` turns that off and
  shows the author and subject for every commit — handy on shared branches where
  you want to see who did what. Sapling has no equivalent toggle; the default
  output is unchanged.

## License

[MIT](LICENSE)
