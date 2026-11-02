# Phase 1: read-only checks

Change nothing in this phase. Every check below only reads. Collect one table row per item:
`item | status (ok / at risk / unknown) | evidence (command + key output line)`.

"Fixed" versions are **as of 2026-10-23** (agent browsers: 2026-10-31). Before reporting, compare them with
the upstream README (see SKILL.md, step 1) and prefer its numbers if they are newer.

Run every block through `bash <<'EOF' … EOF`. See "Shell traps" in SKILL.md for why.

Several checks scan the user's code folders. Ask the user where they keep code, or discover it; the default is a guess.
An agent's shell does not keep variables between commands, so put this line **inside** every block that uses `$CODE_ROOTS`:
```bash
CODE_ROOTS="$HOME/Developer $HOME/code $HOME/src"
```

## 1. Node.js (CVE-2026-111497, Brotli decoder out-of-bounds write)
Fixed: **26.12.1, 24.22.1, 22.23.4** or later. Source: nodejs.org/en/blog/vulnerability/october-2026-security-releases

Version managers are invisible to an agent's non-interactive shell, so look in their install directories too:
```bash
bash <<'EOF'
echo "PATH: $(command -v node || echo none)"
for n in $(which -a node) /opt/homebrew/bin/node /usr/local/bin/node \
  ~/.nvm/versions/node/*/bin/node ~/.volta/tools/image/node/*/bin/node \
  ~/.local/share/fnm/node-versions/*/installation/bin/node "$HOME/Library/Application Support/fnm/node-versions/"*/installation/bin/node \
  ~/.local/share/mise/installs/node/*/bin/node ~/.asdf/installs/nodejs/*/bin/node; do
  [ -x "$n" ] && echo "$(readlink -f "$n") $("$n" -v)"
done | sort -u
EOF
```
Homebrew's node links Homebrew's shared brotli. Fixed: **brotli 1.2.1**.
```bash
bash <<'EOF'
otool -L "$(brew --prefix)/opt/node/bin/node" 2>/dev/null | grep brotli
brew list --versions brotli
DYLD_PRINT_LIBRARIES=1 "$(brew --prefix)/opt/node/bin/node" -e 0 2>&1 | grep -i brotli   # what actually loads
EOF
```
Long-running processes keep the old library in memory until they restart. Without sudo you see only your own processes; say so.
```bash
lsof -nP 2>/dev/null | grep libbrotlidec | awk '{print $2, $1, $NF}' | sort -u
```
Any path with `brotli/1.2.0` is unpatched.

**Which processes run an old Node.** Report the PID and the binary, never the arguments:
```bash
bash <<'EOF'
for p in $(pgrep -x node); do echo "$p $(lsof -nP -p "$p" 2>/dev/null | awk '$4=="txt"{print $NF; exit}')"; done
EOF
```
Old-Node processes are often MCP servers spawned by *other* agent sessions. To find the owner, look at the parent process
(`ps -o ppid=,tty= -p <pid>`). Report the owner; don't guess.

**Pinned old versions:** `.nvmrc` and `.node-version` files bring a vulnerable Node back on the next `fnm use` or `nvm use`:
```bash
bash <<'EOF'
CODE_ROOTS="$HOME/Developer $HOME/code $HOME/src"   # set to the user's code folders
find $CODE_ROOTS -maxdepth 4 \( -name .nvmrc -o -name .node-version \) -not -path '*/node_modules/*' 2>/dev/null |
  while read -r f; do printf '%s  %s\n' "$(head -1 "$f" | tr -d ' \r')" "$f"; done
EOF
```

## 2. Brotli fix marker (works on any binary or library)
A patched decoder contains the string `FORMAT_BLOCK_SWITCH`. `FORMAT_EXUBERANT_NIBBLE` is the control.
```bash
brotli_fixed() { printf '%s control=%s fix=%s\n' "$1" "$(strings -n 8 "$1" | grep -c FORMAT_EXUBERANT_NIBBLE)" "$(strings -n 8 "$1" | grep -c FORMAT_BLOCK_SWITCH)"; }
```
How to read it:
- control > 0 and fix = 0: unpatched.
- control = 0: the check does not apply to that file.
- The marker is a clue, not proof. If it says unpatched, believe it. If it says patched, still check the version.

Upstream results: node 26.12.1 fix=3, libbrotlidec 1.2.1 fix=1, libbrotlidec 1.2.0 fix=0, bun 1.4.4 fix=3, Claude Code 2.1.308 fix=3.

## 3. Bun, and tools built on Bun
Fixed: **Bun 1.4.4**. Bun bundles its own decoder, reached from `fetch()` on any `Content-Encoding: br` response.
```bash
bash <<'EOF'
for b in $(which -a bun | sort -u); do echo "$b $("$b" --version)"; done
ps -axo pid,user,comm | grep -E '[/ ]bun$'
EOF
```
Tools that embed Bun need their own fixed release. Check each with the marker from check 2.

## 4. Claude Code
Fixed: **2.1.308**. It embeds a Bun build, and 2.1.306 and 2.1.307 had control=3, fix=0.
```bash
bash <<'EOF'
b="$(readlink -f "$(command -v claude)")"; claude --version
strings -n 6 "$b" | grep -m1 -oE 'Bun v1\.[0-9]+\.[0-9]+'
brotli_fixed() { printf '%s control=%s fix=%s\n' "$1" "$(strings -n 8 "$1" | grep -c FORMAT_EXUBERANT_NIBBLE)" "$(strings -n 8 "$1" | grep -c FORMAT_BLOCK_SWITCH)"; }
brotli_fixed "$b"
grep -n '"WebFetch"' ~/.claude/settings.json || echo "no WebFetch deny"
EOF
```

## 5. eMudhra compromised intermediates
Eight eMudhra intermediate CA keys are compromised. Anyone holding them can impersonate any website.
Fixed: **pip 26.2.2**, **uv 0.13.5**, Java per CVE-2026-91403 (OpenJDK and Oracle advisories). Incident page: emudhra.we-have-a-problem.com

First list every Python, virtualenv and JDK, so they can be passed to the probe:
```bash
bash <<'EOF'
for py in $(which -a python3 | awk '!s[$0]++'); do echo "$py $("$py" -V 2>&1) pip $("$py" -m pip --version 2>/dev/null | awk '{print $2}')"; done
command -v uv && uv --version
/usr/libexec/java_home -V 2>&1 | grep -oE '/.*/Contents/Home$'
ls -d "$(brew --prefix)"/opt/openjdk*/libexec/openjdk.jdk/Contents/Home "/Applications/Android Studio.app/Contents/jbr/Contents/Home" 2>/dev/null
EOF
```
Then run the probe. It is read-only, takes about a minute per client, and its extra arguments are venv pythons and JDK homes:
```bash
f=$(bash <skill-dir>/scripts/upstream-block.sh probe) && echo "$f"   # writes the probe; read it before running
# Replace its two placeholders (path/to/venv/bin/python, path/to/other/jdk/Contents/Home) with the user's
# virtualenv pythons and any JDK that java_home does not list, or delete them. Then: bash "$f"
```
How to read it:
- **unknown (control failed):** the client couldn't load the valid incident page, so it was never tested. Report it as unknown, never as safe.
- **TRUSTS:** at least one test host answered.
- **safe:** all 14 hosts were refused with a certificate error.

Expected leftovers, from runs on real Macs:
- **Apple's `/usr/bin/python3`** (pip 21.2.4) trusts all 14, and it gets no fix. The fix is to stop installing packages with it; report it as at risk.
- **Homebrew Python** trusts the chain until `brew upgrade ca-certificates certifi`.
- **python.org's Python** (`/Library/Frameworks/Python.framework/...`) has no CA bundle until its `Install Certificates.command` is run. The plain `python` probe then reports *unknown (control failed)*. That result is correct: report it as unknown, and its pip separately (pip has its own bundle).
- **`/usr/bin/curl` and `nscurl`** trust the chain until F4 steps 2 and 3. They trust it again after every macOS update; see F4 step 4.

## 6. Tailscale
Fixed: **1.104.2** (TS-2026-013). First find out *how* it is installed, because the fix differs:
```bash
bash <<'EOF'
echo "cli: $(readlink -f "$(command -v tailscale)")"; tailscale version | head -1
brew list --versions tailscale 2>/dev/null || echo "not a brew formula"
brew list --cask --versions tailscale tailscale-app 2>/dev/null || echo "not a brew cask"
[ -d /Applications/Tailscale.app ] && { defaults read /Applications/Tailscale.app/Contents/Info CFBundleShortVersionString
  [ -d /Applications/Tailscale.app/Contents/_MASReceipt ] && echo "App Store" || echo "standalone (Sparkle) app"; }
tailscale status --json 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print("daemon:",d.get("Version"),"state:",d.get("BackendState"))'
EOF
```
Compare the **daemon** version as well as the CLI and app versions: after an app update, the old daemon keeps running until the app relaunches.

## 7. Browser and OS
Chrome 156 ships 353 security fixes, 6 of them critical, and **156.0.8078.73** (2026-10-27) adds 52 more, including critical CVE-2026-118306, 118331, 118344 and 118348. Compare the full version, not the major: an early 156 build is still at risk. macOS 26.7.1 fixes CVE-2026-86950.
```bash
defaults read "/Applications/Google Chrome.app/Contents/Info" CFBundleShortVersionString; sw_vers -productVersion; softwareupdate -l
```

## 8. Agent browsers (Playwright, Puppeteer, agent-browser, MCP browser tools)
Background, claims, and what is verified are in `references/playwright-agent-browsers.md`. Run:
```bash
bash <skill-dir>/scripts/agent-browsers.sh 156.0.8078.73 ~/Developer ~/code ~/src   # min full Chromium version, then code folders
```
It prints table rows directly. It rates each `playwright-core` by the Chromium its own `browsers.json` would download, and it reports any Chrome process running with `--no-sandbox`.

Run it as its own command. If its text sits in the same shell command line as the sandbox check (a heredoc or `-c` string), that command line matches itself and the count goes up by one.

## 9. Servers and dev servers
- **PHP** (CVE-2026-109618 and CVE-2026-109619). Fixed: 8.5.12, 8.4.27, 8.3.36, 8.2.35. Check: `php -v`.
- **Self-managed GitLab** (CVE-2026-110264). Check: `command -v gitlab-ctl`.
- **Ruby** regex fixes. Fixed: 4.0.9, 3.4.12, 3.3.13. Ruby 3.2 and older get no fix.
  ```bash
  bash <<'EOF'
  for r in $(which -a ruby) ~/.rbenv/versions/*/bin/ruby ~/.rubies/*/bin/ruby ~/.local/share/mise/installs/ruby/*/bin/ruby; do [ -x "$r" ] && echo "$r: $("$r" -v)"; done
  EOF
  ```
  macOS's `/usr/bin/ruby` (2.6) is fine on disk as long as no server runs on it.
- **Self-hosted Next.js.** Fixed: next 16.4.1 or 15.5.28, and sharp 0.35.5. Check: `npm ls next sharp` in each project.
- **Storybook dev server** (CVE-2026-114125). Fixed: 8.6.19, 9.1.21, 10.6.2. A 7.x install has no fix, so don't run `storybook dev` there.
  ```bash
  bash <<'EOF'
CODE_ROOTS="$HOME/Developer $HOME/code $HOME/src"   # set to the user's code folders
  find $CODE_ROOTS -maxdepth 6 -path '*/node_modules/storybook/package.json' 2>/dev/null | while read -r f; do echo "$(grep -m1 '"version"' "$f") ${f%/node_modules/*}"; done
  EOF
  ```

## 10. Keys stored on breached platforms
Breached: Railway (Oct 21), OpenCode Console (Oct 17), Fireworks AI (Oct 9), TiDB Cloud, and Treg (Oct 22, where every stored key was reachable).
```bash
command -v railway opencode; ls -d ~/.railway ~/.config/opencode 2>/dev/null
```
A local config folder doesn't show whether keys were stored on the platform. Ask the user and record "unknown" until they answer.

## 11. Long-term cloud keys on disk
A leaked old key is the most common real incident here. Count the keys and name the profiles; never print a value.
```bash
bash <<'EOF'
CODE_ROOTS="$HOME/Developer $HOME/code $HOME/src"   # set to the user's code folders
awk '/^\[/{s=$0} /aws_access_key_id/{v=$0; sub(/.*= */,"",v); print s, "key-type:", substr(v,1,4)}' ~/.aws/credentials 2>/dev/null
find $CODE_ROOTS ~/.config -maxdepth 6 -type f -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null |
  xargs grep -lE 'AKIA[0-9A-Z]{16}' 2>/dev/null | head -20      # paths only
EOF
```
- `AKIA` is a long-term key and `ASIA` is a temporary one.
- A long-term key whose profile is not in `~/.aws/config`, and that nothing has used in months, is the likeliest leak.

If the user reports that a key *was used*, switch to `references/aws-leaked-key.md`.

## 12. Hygiene
```bash
bash <<'EOF'
CODE_ROOTS="$HOME/Developer $HOME/code $HOME/src"   # set to the user's code folders
ps -axo user,pid,comm | awk '$1!="root" && $1!~/^_/' | cut -c1-120 | sort -u | head -40      # other accounts running things
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==1 || $9 ~ /^\*:|^0\.0\.0\.0:|^\[::\]:/ {print $1, $2, $3, $9}' | sort -u
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
echo "npm authToken lines: $(grep -c '_authToken' ~/.npmrc 2>/dev/null || echo 0)"
echo "world-readable env files (excluding examples): $(find $CODE_ROOTS -maxdepth 4 -name '.env*' -perm -o=r -not -name '*.example' -not -path '*/node_modules/*' 2>/dev/null | wc -l)"
EOF
```
`lsof` and `netstat` without sudo don't show other macOS users' sockets. Say so in the report. A process that looks orphaned may be a live bot running under another account.
