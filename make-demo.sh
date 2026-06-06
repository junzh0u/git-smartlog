#!/usr/bin/env bash
# Build a throwaway demo git repo for screenshotting git-smartlog (e.g. a README
# cover image). Re-runnable: wipes and recreates the target each time.
#
#   ./make-demo.sh [target-dir]        # default: /tmp/git-smartlog-demo
#
# It lays out a small HTTP-client project with:
#   - a public base on origin/master (one commit by someone else, one by you)
#   - a 3-commit draft stack on a feature branch
#   - uncommitted working-tree changes (so `git-smartlog -u` has a node to draw)
# Commit dates are anchored to "now" so the relative times render nicely; screenshot
# soon after generating. Reads best when run during the day.
set -euo pipefail

DEMO=${1:-/tmp/git-smartlog-demo}
REMOTE="${DEMO}-remote.git"

rm -rf "$DEMO" "$REMOTE"
git init -q --bare "$REMOTE"
git init -q -b master "$DEMO"
cd "$DEMO"

git config user.name  "Jun Zhou"
git config user.email "junz@example.com"      # "you" — your commits show in full
git config commit.gpgsign false
git config advice.detachedHead false

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

# ── Draft stack on a feature branch ────────────────────────────────────────────
git switch -q -c feat/retry-backoff

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
git add http_client.go
commit $((now - 14*MIN)) "Jun Zhou" "junz@example.com" "Wire backoff into the HTTP client"
# Note: the feature branch is intentionally NOT pushed — git-smartlog shows the
# active local branch (feat/retry-backoff*) on its own, matching Sapling.

# ── Uncommitted working-tree changes (for `git-smartlog -u`) ────────────────────
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
# An untracked file too, so the file count includes it.
cat > retry_test.go <<'EOF'
package httpx

import "testing"

func TestRetryable(t *testing.T) {
	if !Retryable(503) {
		t.Fatal("503 should be retryable")
	}
}
EOF

cat <<EOF

Demo repo ready: $DEMO

Screenshot it with:
  cd $DEMO
  sl                 # alias: git-smartlog -u  (shows the uncommitted node)
  git-smartlog       # plain draft stack, no uncommitted node
  git-smartlog -n 3  # also reveals Alice's compact public node
EOF
