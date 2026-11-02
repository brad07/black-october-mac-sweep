#!/bin/bash
# Read-only. Lists every browser that agent tooling (Playwright, Puppeteer, agent-browser, MCP browser
# servers) can launch on this Mac, with its Chromium version, plus the Playwright versions that would
# download one. Prints table rows: item | status | evidence.
#
# Usage: agent-browsers.sh [min-chromium-version] [code roots...]
#   min-chromium-version  default 156.0.8078.73, the first build fixing CVE-2026-118306/118331/118344/118348
#                         (2026-10-27). Compare the FULL version: Playwright 1.64.1 ships 156.0.8078.4, which
#                         is "156" and still vulnerable. Check the current stable before trusting the default.
#   code roots            default: ~/Developer ~/code ~/src
# A playwright-core is rated by the Chromium its own browsers.json would download, not by its version number.
MIN=${1:-156.0.8078.73}; shift 2>/dev/null
ROOTS=("$@"); [ ${#ROOTS[@]} -gt 0 ] || ROOTS=("$HOME/Developer" "$HOME/code" "$HOME/src")

pw_chromium() { sed -n '/"name": *"chromium"/,/}/s/.*"browserVersion": *"\([^"]*\)".*/\1/p' "${1%/package.json}/browsers.json" 2>/dev/null | head -1; }
row() { printf '%s | %s | %s\n' "$1" "$2" "$3"; }
status_for() { [ -z "$1" ] && { echo unknown; return; }; [ "$(printf '%s\n%s\n' "$MIN" "$1" | sort -V | head -1)" = "$MIN" ] && echo ok || echo "at risk"; }
app_version() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null; }

echo "item | status | evidence"
v=$(app_version "/Applications/Google Chrome.app"); [ -n "$v" ] && row "Google Chrome" "$(status_for "$v")" "CFBundleShortVersionString $v"

# Playwright cache (macOS default location, plus the Linux-style one some setups use)
for c in "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/ms-playwright"; do
  [ -d "$c" ] || continue
  for d in "$c"/chromium-* "$c"/chromium_headless_shell-* "$c"/chrome-*; do
    [ -d "$d" ] || continue
    a=$(find "$d" -maxdepth 4 -name '*.app' -type d 2>/dev/null | head -1)
    if [ -n "$a" ]; then v=$(app_version "$a")
    else b=$(find "$d" -maxdepth 3 -name chrome-headless-shell -type f 2>/dev/null | head -1)
         v=$([ -n "$b" ] && "$b" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9.]+' | head -1); fi
    row "playwright $(basename "$d")" "$(status_for "$v")" "${d/#$HOME/~} -> ${v:-unreadable}"
  done
done

# Puppeteer cache
if [ -d "$HOME/.cache/puppeteer" ]; then
  find "$HOME/.cache/puppeteer" -maxdepth 4 -name '*.app' -type d 2>/dev/null | while IFS= read -r a; do
    v=$(app_version "$a"); row "puppeteer browser" "$(status_for "$v")" "${a/#$HOME/~} -> ${v:-unreadable}"; done
else row "puppeteer cache" ok "~/.cache/puppeteer absent"; fi

# agent-browser keeps its own Chrome for Testing
find "$HOME/.agent-browser/browsers" -maxdepth 2 -name '*.app' -type d 2>/dev/null | while IFS= read -r a; do
  v=$(app_version "$a"); row "agent-browser Chrome" "$(status_for "$v")" "${a/#$HOME/~} -> ${v:-unreadable}"; done

# chrome-devtools-mcp normally drives the installed Chrome; flag any browser it cached itself
if [ -d "$HOME/.cache/chrome-devtools-mcp" ]; then
  n=$(find "$HOME/.cache/chrome-devtools-mcp" -maxdepth 4 -name '*.app' -type d 2>/dev/null | wc -l | tr -d ' ')
  row "chrome-devtools-mcp cache" "$([ "$n" -eq 0 ] && echo ok || echo unknown)" "$n cached browser app(s); 0 means it uses the installed Chrome"
fi

# Playwright versions that could download an old browser again
find "$HOME/.npm/_npx" -maxdepth 4 -path '*/node_modules/playwright-core/package.json' 2>/dev/null | while IFS= read -r f; do
  v=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$f" | head -1); c=$(pw_chromium "$f")
  row "npx playwright-core $v" "$(status_for "$c")" "${f%/node_modules/*} -> downloads Chromium ${c:-unknown}" | sed "s|$HOME|~|"; done
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || continue
  find "$r" -maxdepth 5 -path '*/node_modules/playwright-core/package.json' -not -path '*/node_modules/*/node_modules/*' 2>/dev/null | while IFS= read -r f; do
    p=${f%/node_modules/*}; v=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$f" | head -1); c=$(pw_chromium "$f")
    row "repo playwright-core $v" "$(status_for "$c")" "${p/#$HOME/~} -> downloads Chromium ${c:-unknown} (installed node_modules; check the lockfile too)"; done
done

# Unsandboxed Chrome (Playwright passes --no-sandbox unless chromiumSandbox: true). Counts only, never arguments.
# Two separate greps: neither one's own command line contains both patterns, so they never count themselves.
n=$(ps -axww -o args= | grep -i 'chrom' | grep -c -- '--no-sandbox')
row "Chrome processes with --no-sandbox" "$([ "$n" -eq 0 ] && echo ok || echo "at risk")" "$n process(es)"

# Running agent browsers (names only, never arguments)
n=$(ps -axo comm= | grep -ciE 'Chrome for Testing|chrome-headless-shell|Chromium')
row "agent browsers running now" info "$n process(es)"

# Accessibility grants: the TCC databases need Full Disk Access, which an agent's terminal usually lacks
if sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" 'select 1' >/dev/null 2>&1; then
  row "Accessibility grants" info "$(sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" "select group_concat(client, ', ') from access where service='kTCCServiceAccessibility' and auth_value=2")"
else
  row "Accessibility grants" unknown "TCC.db: authorization denied. User checks System Settings > Privacy & Security > Accessibility"
fi
