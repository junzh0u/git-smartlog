#!/usr/bin/env bash
# Regenerate the README screenshots (cover.png, smartstat.png) end to end:
#
#   ./make-screenshots.sh [demo-dir]      # default: /tmp/git-smartlog-demo
#
# 1. Rebuilds the demo repo with make-demo.sh (commit dates anchor to "now",
#    so relative times render nicely).
# 2. Runs each command on a pty (`script -q`) so git-smartlog sees a TTY and
#    colorizes; GIT_PAGER=cat keeps the pager out of the capture.
# 3. Converts the ANSI capture to HTML (embedded python), styled to match the
#    terminal the originals were shot in: Dracula palette on #282a36, MesloLGS
#    NF, with a green `❯ <command>` prompt line on top.
# 4. Renders the HTML with headless Chrome at device-scale-factor 2 (retina),
#    sizing the window to the content via a measuring pass, and writes the
#    PNGs into screenshots/, overwriting the ones the README embeds.
#
# Needs: zsh, python3, and Chrome/Chromium (override the binary with $CHROME).
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
OUT=$REPO/screenshots
DEMO=${1:-/tmp/git-smartlog-demo}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

CHROME=${CHROME:-}
if [[ -z $CHROME ]]; then
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "$(command -v google-chrome || true)" \
           "$(command -v chromium || true)"; do
    if [[ -n $c && -x $c ]]; then CHROME=$c; break; fi
  done
fi
[[ -n $CHROME ]] || { echo "error: Chrome not found; set \$CHROME" >&2; exit 1; }

"$REPO/make-demo.sh" "$DEMO" >/dev/null
echo "demo repo rebuilt: $DEMO"

# Stub `gh` for the cover shot's -p/--prs tags: the demo repo's remote is a
# local bare repo, so the real gh can't list PRs for it. git-smartlog only
# asks gh for a TSV of headRefName/number/state/isDraft/url — serve canned
# rows covering every tag state (open, draft, merged, closed). Prepended to
# PATH inside the capture; other shots never invoke gh, so the stub is inert
# for them.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'GH'
#!/bin/sh
[ "$1" = pr ] && [ "$2" = list ] || exit 1
printf '%s\t%s\t%s\t%s\t%s\n' \
  feat/retry-backoff 42 OPEN   false https://github.com/junz/httpx/pull/42 \
  fix/redirect-loop  37 OPEN   true  https://github.com/junz/httpx/pull/37 \
  wip/backoff        40 CLOSED false https://github.com/junz/httpx/pull/40 \
  hotfix             35 MERGED false https://github.com/junz/httpx/pull/35
GH
chmod +x "$TMP/bin/gh"

cat > "$TMP/ansi2html.py" <<'PY'
"""Read ANSI terminal output on stdin, print a self-sizing HTML page.

argv[1] is the command line to show on the `❯` prompt above the output.
Maps SGR color codes to the Dracula palette; on load the page stamps its
rendered size into <body data-size="WxH"> so the caller can size Chrome's
window to exactly fit the terminal "card".
"""
import html
import re
import sys

display = sys.argv[1]

P = ["#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6",
     "#8be9fd", "#f8f8f2", "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5",
     "#d6acff", "#ff92df", "#a4ffff", "#ffffff"]
FG, BG, GREEN = "#f8f8f2", "#282a36", "#50fa7b"

raw = sys.stdin.buffer.read().decode("utf-8", "replace")
raw = raw.replace("\r\n", "\n").replace("\r", "\n")
# `script` pty artifacts: the echoed "^D" is erased with backspaces — apply
# them destructively, then drop any strays.
while re.search(r"[^\n\x08]\x08", raw):
    raw = re.sub(r"[^\n\x08]\x08", "", raw)
raw = raw.replace("\x08", "").replace("\x04", "")
raw = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", raw)  # OSC (hyperlinks)

fg, bold, dim = None, False, False
parts = []


def emit(text):
    if not text:
        return
    style = []
    if fg:
        style.append("color:" + fg)
    if bold:
        style.append("font-weight:700")
    if dim:
        style.append("opacity:.55")
    esc = html.escape(text)
    parts.append(
        '<span style="%s">%s</span>' % (";".join(style), esc) if style else esc)


pos = 0
for m in re.finditer(r"\x1b\[([0-9;?]*)([A-Za-z])", raw):
    emit(raw[pos:m.start()])
    pos = m.end()
    if m.group(2) != "m":
        continue  # strip non-SGR CSI sequences
    params = [int(x) for x in m.group(1).split(";") if x] or [0]
    i = 0
    while i < len(params):
        p = params[i]
        if p == 0:
            fg, bold, dim = None, False, False
        elif p == 1:
            bold = True
        elif p == 2:
            dim = True
        elif p == 22:
            bold = dim = False
        elif p == 39:
            fg = None
        elif 30 <= p <= 37:
            fg = P[p - 30]
        elif 90 <= p <= 97:
            fg = P[p - 90 + 8]
        elif p in (38, 48) and i + 2 < len(params) and params[i + 1] == 5:
            if p == 38:
                n = params[i + 2]
                fg = P[n] if n < 16 else None
            i += 2
        i += 1
emit(raw[pos:])

body = "".join(parts).rstrip("\n")
prompt = '<span style="color:%s">❯ %s</span>\n' % (GREEN, html.escape(display))
print("""<!doctype html><meta charset="utf-8"><style>
body{margin:0}
#term{display:inline-block;margin:0;background:%s;color:%s;
padding:12px 18px 14px 14px;font:16px/1.45 "MesloLGS NF",Menlo,monospace;
-webkit-font-smoothing:antialiased}
</style>
<pre id="term">%s%s</pre>
<script>addEventListener("load",()=>{const r=document.getElementById("term")
.getBoundingClientRect();document.body.setAttribute("data-size",
Math.ceil(r.width)+"x"+Math.ceil(r.height))})</script>""" % (
    BG, FG, prompt, body))
PY

# Headless Chrome produces its output within a couple of seconds but can then
# linger for minutes doing first-run/updater housekeeping instead of exiting,
# so waiting for a clean exit stalls every pass. Run it in the background,
# poll until <check> sees the artifact (plus a short grace for the final
# write), then kill it.
chrome_run() {  # chrome_run <check command...> -- <chrome args...>
  local check=()
  while [[ $1 != -- ]]; do check+=("$1"); shift; done
  shift
  local udd
  udd=$(mktemp -d "$TMP/chrome.XXXXXX")
  "$CHROME" --headless=new --disable-gpu --no-first-run \
      --no-default-browser-check --disable-component-update \
      --disable-background-networking --user-data-dir="$udd" "$@" 2>/dev/null &
  local pid=$! i
  for ((i = 0; i < 150; i++)); do  # up to 30s
    if "${check[@]}" 2>/dev/null; then sleep 0.5; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  "${check[@]}" 2>/dev/null
}

# shoot <output.png> <prompt-line text> <command> [args...]
shoot() {
  local out=$1 display=$2
  shift 2
  local stem=${out%.png}
  echo "==> $out  (❯ $display)"

  # Capture on a pty so the tool colorizes; pin the width so stat paths render
  # the same regardless of the invoking terminal. stdin must come from
  # /dev/null or `script` sits waiting for terminal input.
  (cd "$DEMO" && script -q /dev/null zsh -c \
      "stty cols 100 rows 100 2>/dev/null; unset NO_COLOR
       PATH=$TMP/bin:\$PATH GIT_PAGER=cat $*") \
      < /dev/null > "$TMP/$stem.ansi"

  python3 "$TMP/ansi2html.py" "$display" < "$TMP/$stem.ansi" > "$TMP/$stem.html"

  # Pass 1: load the page just to read back the rendered size of #term.
  chrome_run grep -q data-size "$TMP/$stem.dom" -- \
      --window-size=2400,400 --dump-dom "file://$TMP/$stem.html" \
      > "$TMP/$stem.dom" \
      || { echo "error: could not measure $stem.html" >&2; exit 1; }
  local size
  size=$(sed -n 's/.*data-size="\([0-9]*x[0-9]*\)".*/\1/p' "$TMP/$stem.dom")
  [[ -n $size ]] || { echo "error: could not measure $stem.html" >&2; exit 1; }

  # Pass 2: window == content, so the PNG is exactly the terminal card (at 2x).
  rm -f "$OUT/$out"
  chrome_run test -s "$OUT/$out" -- \
      --hide-scrollbars --force-device-scale-factor=2 \
      --window-size="${size%x*},${size#*x}" \
      --screenshot="$OUT/$out" "file://$TMP/$stem.html" \
      || { echo "error: screenshot failed for $out" >&2; exit 1; }
}

mkdir -p "$OUT"

shoot smartstat.png "git smartstat" "$REPO/git-smartstat"
# Last: -p is sticky (drops a marker in the demo's git dir), so running it
# earlier would make any following smartlog shots tag PRs too.
shoot cover.png     "git-smartlog -n 2 -b -a -p" "$REPO/git-smartlog" -n 2 -b -a -p

echo "screenshots written to $OUT"
