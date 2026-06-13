#!/usr/bin/env bash
# Build a throwaway demo git repo for screenshotting git-smartlog / git-smartstat
# (e.g. a README cover image). Re-runnable: wipes and recreates the target each time.
#
#   ./make-demo.sh [target-dir]        # default: /tmp/git-smartlog-demo
#
# It lays out a small HTTP-client project with:
#   - a public base on origin/master (one compact commit by someone else, one by you)
#   - a 3-commit draft stack on a feature branch
#   - uncommitted working-tree changes exercising EVERY signal the -u node renders:
#       A staged-new   ? untracked     M modified    D deleted      R renamed
#       T typechange   S submodule     U unmerged    plus a +x mode flip
# To produce the conflict (U) the demo is intentionally left mid-merge. Commit dates
# are anchored to "now" so relative times render nicely; screenshot soon after.
set -euo pipefail

DEMO=${1:-/tmp/git-smartlog-demo}
REMOTE="${DEMO}-remote.git"
SUBREMOTE="${DEMO}-timeutil.git"

rm -rf "$DEMO" "$REMOTE" "$SUBREMOTE"

# ── A tiny submodule origin (two commits, so we can show a pointer change) ───────
git init -q --bare -b master "$SUBREMOTE"   # HEAD on master so the clone checks out
subwork=$(mktemp -d)
git init -q -b master "$subwork"
(
  cd "$subwork"
  git config user.name "Time Util"; git config user.email "tz@example.com"
  printf 'package timeutil\n\nconst Version = "1.0.0"\n' > timeutil.go
  git add .; git -c commit.gpgsign=false commit -q -m "v1.0.0"
  printf 'package timeutil\n\nconst Version = "1.1.0"\n' > timeutil.go
  git add .; git -c commit.gpgsign=false commit -q -m "v1.1.0"
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

# Submodule (for the S signal); pinned at its v1.1.0 tip for now.
git -c protocol.file.allow=always submodule add -q "$SUBREMOTE" vendor/timeutil

git add .
commit $((now - 5*DAY)) "Alice Ng" "alice@example.com" "Initial project scaffold"

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

# D  deleted (tracked file removed)
git rm -q legacy.go

# R  renamed (tracked file moved)
git mv logging.go log.go

# +x mode flip (status M with a "| 0" stat, surfaced as a +x hint)
chmod +x scripts/release.sh

# T  typechange — a regular file replaced by a symlink
rm config.json
ln -s config.defaults.json config.json

# S  submodule pointer change (check the working copy out one commit back)
( cd vendor/timeutil && git checkout -q HEAD~1 )

cat <<EOF

Demo repo ready: $DEMO   (left mid-merge to show the U conflict signal)

Screenshot it with:
  cd $DEMO
  sl                  # alias: git-smartlog -u  (uncommitted node, every signal)
  git smartstat       # just the uncommitted stat block, standalone
  git-smartlog        # plain draft stack, no uncommitted node
  git-smartlog -n 3   # also reveals Alice's compact public node
EOF
