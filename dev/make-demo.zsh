#!/usr/bin/env zsh
# Build a throwaway demo git repo for screenshotting git-smartlog / git-smartstat
# (e.g. a README cover image). Re-runnable: wipes and recreates the target each time.
#
#   ./dev/make-demo.zsh [target-dir]        # default: /tmp/git-smartlog-demo
#
# It lays out a small HTTP-client project with:
#   - a public base on origin/master (two compact commits by someone else, one by you)
#   - a 3-commit draft stack on a feature branch
#   - other local branches exercising EVERY signal the -b view renders:
#       hotfix             sibling node at the trunk tip, pushed — so the green
#                          origin/hotfix shows and the local name stays hidden
#       fix/redirect-loop  forks from the OLDEST public commit, so the public
#                          commit between it and the tip elides to a dotted ╷
#       prod               parked exactly on a public commit — labels it (cyan)
#       wip/backoff        points at an interior draft of the stack — labels it
#       refactor/timeouts  forks off a DRAFT of the current stack, so the forest
#                          has a real fork and the side-column layout is drawn
#       spike/http3        forks off a draft of refactor/timeouts, nesting that
#                          layout one level deeper
#   - uncommitted working-tree changes exercising EVERY signal the wdir node renders:
#       A staged-new   ? untracked     M modified    D deleted      R renamed
#       T typechange   S submodule     U unmerged    plus a +x mode flip
#     ... including a wholly-untracked DIRECTORY, which collapses to one
#     "dir/ | N files" entry instead of expanding, the way git status lists it.
#     The submodule is both bumped AND left dirty, so its entry expands into both
#     groups: its own uncommitted changes, then the commits the bump gained.
# To produce the conflict (U) the demo is intentionally left mid-merge. Commit dates
# are anchored to "now" so relative times render nicely; screenshot soon after.
set -euo pipefail

DEMO=${1:-/tmp/git-smartlog-demo}
REMOTE="${DEMO}-remote.git"
SUBREMOTE="${DEMO}-timeutil.git"

rm -rf "$DEMO" "$REMOTE" "$SUBREMOTE"

# ── A submodule origin (several commits, so a pointer BUMP expands to a commit
#    list — newest first, capped at 3 with a "… +N more" tail) ─────────────────
git init -q --bare -b master "$SUBREMOTE"   # HEAD on master so the clone checks out
subwork=$(mktemp -d)
git init -q -b master "$subwork"
(
  cd "$subwork"
  git config user.name "Time Util"; git config user.email "tz@example.com"
  for v in 1.0.0 1.1.0 1.2.0 1.3.0 1.4.0 1.5.0; do
    printf 'package timeutil\n\nconst Version = "%s"\n' "$v" > timeutil.go
    git add .; git -c commit.gpgsign=false commit -q -m "v$v"
  done
  git push -q "$SUBREMOTE" master
)
rm -rf "$subwork"

git init -q --bare "$REMOTE"
git init -q -b master "$DEMO"
cd "$DEMO"

git config user.name  "Jun Zhou"
git config user.email "junz@example.com"      # "you" — your commits show in full
git config commit.gpgsign false
git config advice.detachedHead false
git config protocol.file.allow always         # allow the local file:// submodule

now=$(date +%s)
MIN=60; HOUR=3600; DAY=86400

# commit <epoch> <author-name> <author-email> <message>
commit() {
  GIT_AUTHOR_NAME=$2  GIT_AUTHOR_EMAIL=$3  GIT_AUTHOR_DATE="@$1 +0000" \
  GIT_COMMITTER_NAME=$2 GIT_COMMITTER_EMAIL=$3 GIT_COMMITTER_DATE="@$1 +0000" \
    git commit -q -m "$4"
}

# ── Public base (pushed to origin/master) ──────────────────────────────────────
cat > go.mod <<'EOF'
module github.com/junz/httpx

go 1.22
EOF

cat > README.md <<'EOF'
# httpx

A tiny HTTP client with retries and backoff.
EOF

cat > http_client.go <<'EOF'
package httpx

import "net/http"

// Client is a thin wrapper around net/http.
type Client struct {
	base *http.Client
}

// New returns a Client backed by http.DefaultClient.
func New() *Client {
	return &Client{base: http.DefaultClient}
}

// Get issues a GET request.
func (c *Client) Get(url string) (*http.Response, error) {
	return c.base.Get(url)
}
EOF

cat > version.go <<'EOF'
package httpx

// Version is the module version.
const Version = "0.1.0"
EOF

cat > logging.go <<'EOF'
package httpx

import "log"

// logf writes a debug line when verbose logging is enabled.
func logf(format string, args ...any) {
	log.Printf(format, args...)
}
EOF

cat > legacy.go <<'EOF'
package httpx

// Deprecated: use Client.Get. Retained only for the 0.x series.
func LegacyGet(url string) (string, error) {
	return "", nil
}
EOF

cat > config.json <<'EOF'
{
  "timeout_ms": 3000,
  "max_retries": 3
}
EOF

mkdir -p scripts
cat > scripts/release.sh <<'EOF'
#!/usr/bin/env bash
# Tag and push a release. Committed WITHOUT the executable bit on purpose,
# so `chmod +x` later shows up as a mode change in the demo.
set -euo pipefail
git tag "v$(grep -oE '[0-9.]+' version.go | head -1)"
EOF

# Submodule (for the S signal); pinned at its v1.0.0 base for now — the S
# scenario below bumps it forward, so the pointer change expands to a commit list.
git -c protocol.file.allow=always submodule add -q "$SUBREMOTE" vendor/timeutil
( cd vendor/timeutil && git checkout -q "$(git rev-list --max-parents=0 HEAD)" )

git add .
commit $((now - 5*DAY)) "Alice Ng" "alice@example.com" "Initial project scaffold"
scaffold=$(git rev-parse HEAD)   # fork point for fix/redirect-loop and prod below

# A second public commit by Alice. In the -b view nothing forks here, so it is
# the commit that gets ELIDED between the tip and the scaffold (the dotted ╷).
cat > errors.go <<'EOF'
package httpx

import "errors"

// ErrMaxRetries is returned when every attempt has failed.
var ErrMaxRetries = errors.New("httpx: retry budget exhausted")
EOF
git add errors.go
commit $((now - 4*DAY)) "Alice Ng" "alice@example.com" "Introduce typed errors"

# A dependency bump, by you, becomes the origin/master tip.
cat > go.mod <<'EOF'
module github.com/junz/httpx

go 1.22

require golang.org/x/time v0.5.0
EOF
git add go.mod
commit $((now - 3*DAY)) "Jun Zhou" "junz@example.com" "Bump dependencies"

git remote add origin "$REMOTE"
git push -q origin master
git remote set-head origin master

# ── A hotfix branch (off master) that will later conflict on version.go ─────────
git switch -q -c hotfix
cat > version.go <<'EOF'
package httpx

// Version is the module version.
const Version = "0.1.1"
EOF
git add version.go
commit $((now - 2*DAY)) "Jun Zhou" "junz@example.com" "Patch release 0.1.1"
# Pushed, so in -b its node is identified by the green origin/hotfix remote ref
# and the local name stays hidden (same-name remote at the same commit).
git push -q origin hotfix

# ── Branches only the -b view reveals ───────────────────────────────────────────
# fix/redirect-loop forks from the OLDEST public commit: its fork point joins the
# public column and Alice's "Introduce typed errors" in between elides to ╷.
git switch -q -c fix/redirect-loop "$scaffold"
cat > redirect.go <<'EOF'
package httpx

// MaxRedirects caps how many redirects a single request may follow.
const MaxRedirects = 10
EOF
git add redirect.go
commit $((now - 26*HOUR)) "Jun Zhou" "junz@example.com" "Cap redirect chains at 10 hops"
cat > redirect.go <<'EOF'
package httpx

import "net/http"

// MaxRedirects caps how many redirects a single request may follow.
const MaxRedirects = 10

// checkRedirect aborts a request once MaxRedirects is exceeded.
func checkRedirect(req *http.Request, via []*http.Request) error {
	if len(via) >= MaxRedirects {
		return http.ErrUseLastResponse
	}
	return nil
}
EOF
git add redirect.go
commit $((now - 25*HOUR)) "Jun Zhou" "junz@example.com" "Abort redirect loops via CheckRedirect"

# prod is parked exactly on a public commit — -b labels that commit (cyan)
# instead of drawing a node.
git branch prod "$scaffold"

# ── Draft stack on the feature branch ──────────────────────────────────────────
git switch -q -c feat/retry-backoff master

cat > retry.go <<'EOF'
package httpx

// Policy decides whether and when a request is retried.
type Policy struct {
	MaxAttempts int
}

// DefaultPolicy retries idempotent requests up to three times.
func DefaultPolicy() Policy {
	return Policy{MaxAttempts: 3}
}
EOF
cat > http_client.go <<'EOF'
package httpx

import "net/http"

// Client is a thin wrapper around net/http with a retry policy.
type Client struct {
	base   *http.Client
	policy Policy
}

// New returns a Client with the default retry policy.
func New() *Client {
	return &Client{base: http.DefaultClient, policy: DefaultPolicy()}
}

// Get issues a GET request.
func (c *Client) Get(url string) (*http.Response, error) {
	return c.base.Get(url)
}
EOF
git add retry.go http_client.go
commit $((now - 1*DAY)) "Jun Zhou" "junz@example.com" "Extract retry policy into its own module"

cat > backoff.go <<'EOF'
package httpx

import (
	"math/rand"
	"time"
)

// Backoff returns the delay before attempt n using exponential backoff
// with full jitter.
func Backoff(n int) time.Duration {
	base := time.Duration(1<<n) * 100 * time.Millisecond
	return time.Duration(rand.Int63n(int64(base)))
}
EOF
cat > retry.go <<'EOF'
package httpx

import "time"

// Policy decides whether and when a request is retried.
type Policy struct {
	MaxAttempts int
}

// DefaultPolicy retries idempotent requests up to three times.
func DefaultPolicy() Policy {
	return Policy{MaxAttempts: 3}
}

// Wait sleeps for the backoff delay before attempt n.
func (p Policy) Wait(n int) {
	time.Sleep(Backoff(n))
}
EOF
git add backoff.go retry.go
commit $((now - 3*HOUR)) "Jun Zhou" "junz@example.com" "Add exponential backoff with jitter"
# wip/backoff points at this interior draft — -b labels the draft (cyan) rather
# than drawing a separate node.
git branch wip/backoff

cat > http_client.go <<'EOF'
package httpx

import "net/http"

// Client is a thin wrapper around net/http with a retry policy.
type Client struct {
	base   *http.Client
	policy Policy
}

// New returns a Client with the default retry policy.
func New() *Client {
	return &Client{base: http.DefaultClient, policy: DefaultPolicy()}
}

// Get issues a GET request, retrying on transient failures.
func (c *Client) Get(url string) (resp *http.Response, err error) {
	for n := 0; n < c.policy.MaxAttempts; n++ {
		if n > 0 {
			c.policy.Wait(n)
		}
		resp, err = c.base.Get(url)
		if err == nil && resp.StatusCode < 500 {
			return resp, nil
		}
	}
	return resp, err
}
EOF
# Bump the version on the feature branch so it diverges from hotfix -> merge conflict.
cat > version.go <<'EOF'
package httpx

// Version is the module version.
const Version = "0.2.0-dev"
EOF
git add http_client.go version.go
commit $((now - 14*MIN)) "Jun Zhou" "junz@example.com" "Wire backoff into the HTTP client"
# Note: the feature branch is intentionally NOT pushed — git-smartlog shows the
# active local branch (feat/retry-backoff*) on its own, matching Sapling.

# ── Branches forking off DRAFT commits ─────────────────────────────────────────
# The rest of the branches hang off public commits, so the -b forest would be
# nothing but straight chains — and its fork layout (spine child continues the
# column, every other child opens one a level deeper, closing with a ├─╯ bend)
# would never be drawn. These two exercise it, nested: refactor/timeouts forks
# off a draft of the current stack, and spike/http3 off a draft of THAT branch.
draft_base=$(git rev-parse "feat/retry-backoff~2")   # "Extract retry policy..."
git switch -q -c refactor/timeouts "$draft_base"
cat > timeout.go <<'EOF'
package httpx

import "time"

// DefaultTimeout bounds a single attempt, not the whole retry budget.
const DefaultTimeout = 5 * time.Second
EOF
git add timeout.go
commit $((now - 20*HOUR)) "Jun Zhou" "junz@example.com" "Bound each attempt with a timeout"
timeouts_base=$(git rev-parse HEAD)
cat > timeout.go <<'EOF'
package httpx

import "time"

// DefaultTimeout bounds a single attempt, not the whole retry budget.
const DefaultTimeout = 5 * time.Second

// WithTimeout overrides DefaultTimeout for one client.
func (c *Client) WithTimeout(d time.Duration) *Client {
	c.base.Timeout = d
	return c
}
EOF
git add timeout.go
commit $((now - 19*HOUR)) "Jun Zhou" "junz@example.com" "Let callers override the attempt timeout"

git switch -q -c spike/http3 "$timeouts_base"
cat > http3.go <<'EOF'
package httpx

// Spike: does the retry policy even make sense over QUIC?
const http3Enabled = false
EOF
git add http3.go
commit $((now - 18*HOUR)) "Jun Zhou" "junz@example.com" "Spike HTTP/3 transport"

git switch -q feat/retry-backoff

# ── Mid-merge conflict (U) — created on a CLEAN tree, before the other edits ─────
# Merging hotfix conflicts on version.go (0.2.0-dev vs 0.1.1) and stops; the repo is
# left mid-merge so version.go shows up unmerged in the uncommitted node.
git merge hotfix >/dev/null 2>&1 || true

# ── The remaining uncommitted signals, layered on the conflicted tree ───────────
# M  modified (tracked content change)
cat > retry.go <<'EOF'
package httpx

import "time"

// Policy decides whether and when a request is retried.
type Policy struct {
	MaxAttempts int
	Base        time.Duration
}

// DefaultPolicy retries idempotent requests up to three times.
func DefaultPolicy() Policy {
	return Policy{MaxAttempts: 3, Base: 100 * time.Millisecond}
}

// Wait sleeps for the backoff delay before attempt n.
func (p Policy) Wait(n int) {
	time.Sleep(Backoff(n))
}

// Retryable reports whether status warrants another attempt.
func Retryable(status int) bool {
	return status == 429 || status >= 500
}
EOF
cat > http_client.go <<'EOF'
package httpx

import "net/http"

// Client is a thin wrapper around net/http with a retry policy.
type Client struct {
	base   *http.Client
	policy Policy
}

// New returns a Client with the default retry policy.
func New() *Client {
	return &Client{base: http.DefaultClient, policy: DefaultPolicy()}
}

// Get issues a GET request, retrying on transient failures.
func (c *Client) Get(url string) (resp *http.Response, err error) {
	for n := 0; n < c.policy.MaxAttempts; n++ {
		if n > 0 {
			c.policy.Wait(n)
		}
		resp, err = c.base.Get(url)
		if err == nil && !Retryable(resp.StatusCode) {
			return resp, nil
		}
	}
	return resp, err
}
EOF

# A  staged new file
cat > metrics.go <<'EOF'
package httpx

// Metrics counts retry attempts and failures.
type Metrics struct {
	Attempts int
	Failures int
}
EOF
git add metrics.go

# ?  untracked file
cat > retry_test.go <<'EOF'
package httpx

import "testing"

func TestRetryable(t *testing.T) {
	if !Retryable(503) {
		t.Fatal("503 should be retryable")
	}
}
EOF

# ?  untracked DIRECTORY — collapses to a single "coverage/ | 2 files" entry
#    rather than expanding to its contents, mirroring git status
mkdir -p coverage
printf 'mode: set\n' > coverage/http_client.out
printf 'mode: set\n' > coverage/retry.out

# D  deleted (tracked file removed)
git rm -q legacy.go

# R  renamed (tracked file moved)
git mv logging.go log.go

# +x mode flip (status M with a "| 0" stat, surfaced as a +x hint)
chmod +x scripts/release.sh

# T  typechange — a regular file replaced by a symlink
rm config.json
ln -s config.defaults.json config.json

# S  submodule: bump the working copy forward to the origin tip, so the entry
#    expands into the gained commits (newest first, capped at 3 + "… +N more"),
#    and leave the submodule's own worktree dirty too, so the entry ALSO expands
#    into its uncommitted changes — the group git's "| 2 +-" can't show
( cd vendor/timeutil && git checkout -q master
  printf '\nfunc Round(ms int64) int64 { return ms }\n' >> timeutil.go   # M
  printf 'package timeutil\n' > clock.go )                               # ?

cat <<EOF

Demo repo ready: $DEMO   (left mid-merge to show the U conflict signal)

Screenshot it with:
  cd $DEMO
  git smartstat       # just the uncommitted stat block, standalone
  git-smartlog        # draft stack + the uncommitted node
  git-smartlog -n 4   # also reveals Alice's compact public nodes
  git-smartlog -a     # ... and un-compacts them
  git-smartlog -c     # a change body under every commit in the stack
  git-smartlog -b     # every other local branch as its full stack, ╷ elision
EOF
