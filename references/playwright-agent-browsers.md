# Agent browsers: Playwright, Puppeteer, agent-browser, MCP browser tools

## The claim, and what is verified
A widely shared post (late Oct 2026) argues as follows:
1. Your regular Chrome auto-updated to 156, but agent tooling runs its **own cached Chromium**, often stuck on v131–151.
2. The IDE or terminal holding macOS **Accessibility** permission spawns that browser, and the browser inherits the permission.
3. A malicious site the agent visits could then (the post says through the GPU process) press Cmd+Space, open Terminal, and run commands.

What is solid:
- Agent tools really do ship their own Chromium builds, and those lag behind stable.
- On macOS, a child process is attributed to its "responsible" parent app for privacy (TCC) permissions.

What is **not** verified:
- The GPU-process keystroke step. Treat that exploit chain as the post's claim.

Old Chromium visiting untrusted pages is worth fixing whether or not that chain works, because Chrome 156 alone shipped 353 security fixes.

## Two facts that are verified, and make it worse (2026-11-03)
- **The newest stable Playwright still ships a vulnerable Chromium.** Playwright 1.64.1's `browsers.json` pins `chromium 1248` = **156.0.8078.4**. Four critical bugs (CVE-2026-118306, 118331, 118344, 118348) were fixed in **156.0.8078.73** on 2026-10-27. On 2026-11-03 only the `1.65.0-alpha` builds carried a newer Chromium (158). Check again: read `browsers.json` from `npm pack playwright-core@<version>`; don't trust the release notes' major version.
- **Playwright turns the Chromium sandbox off by default.** playwright-core has `if (options.chromiumSandbox !== true) chromeArguments.push("--no-sandbox")`, so a renderer bug runs as the user, not in a contained process. The default exists for Linux containers; on macOS `chromiumSandbox: true` works.

## Where agent browsers live on macOS
| Tool | Location | How to read the version |
|---|---|---|
| Playwright | `~/Library/Caches/ms-playwright/chromium-<rev>`, plus `chromium_headless_shell-<rev>` | the `.app`'s Info.plist; for the headless shell, `chrome-headless-shell --version` |
| Puppeteer | `~/.cache/puppeteer/` | the `.app`'s Info.plist |
| agent-browser | `~/.agent-browser/browsers/chrome-<version>/` | the folder name, or the Info.plist |
| chrome-devtools-mcp | drives the installed Chrome; `~/.cache/chrome-devtools-mcp` normally holds only `latest.json` | the installed Chrome's version |

`<skill-dir>/scripts/agent-browsers.sh` checks all of these, plus every `playwright-core` that could download an old browser again.

## Fixes (ask before each)
**A. Get a patched browser.** First read which Chromium the newest Playwright pins:
```bash
d=$(mktemp -d); (cd "$d" && npm pack playwright-core@latest --silent >/dev/null && tar -xzOf playwright-core-*.tgz package/browsers.json) | grep -A3 '"chromium"'
```
- **If it is at or above the fixed build**, install it: `npx -y playwright@<that version> install chromium chromium-headless-shell`.
- **If it is not** (the case on 2026-11-03), do not install it. Point the tooling at the system's patched Chrome instead: `channel: 'chrome'` in the launch options or `use` config, plus `chromiumSandbox: true`. Or skip to B and leave Playwright without a browser until a fixed release ships. An alpha is the user's call, not a default.

Re-run the check. Each browser must show 156.0.8078.73 or later.

**B. Delete the old browsers.** List the exact directories found, never a glob over the whole cache:
```bash
rm -rf ~/Library/Caches/ms-playwright/chromium-<old-rev> ~/Library/Caches/ms-playwright/chromium_headless_shell-<old-rev> \
       "$HOME/.agent-browser/browsers/chrome-<old-version>"
```
agent-browser downloads a current Chrome on its next run. Check which version it picks.

**C. Bump Playwright in each repo** that pins an old version. This is a repo change, so do it on a branch, and in a separate worktree when
the user's checkout has uncommitted work.
1. Bump the direct dependency (`@playwright/test` or `playwright`) to the newest version whose `browsers.json` you read in A. If even that version's Chromium is below the fix, say so in the PR: the bump removes the much older builds, but on its own it is not the fix. Also set `channel: 'chrome'` and `chromiumSandbox: true` in the repo's Playwright config.
2. Update the **lockfile only**: `pnpm install --lockfile-only --ignore-scripts`, or `npm install --package-lock-only --ignore-scripts`.
   - Use the repo's own pinned package manager (`engines.pnpm` or `packageManager`), e.g. `npx -y pnpm@<pinned> …`, so the lockfile format doesn't churn.
   - If `engines.node` pins an exact version you no longer have (because you removed it as vulnerable), let the resolver pretend: `--config.node-version=<pinned>`.
3. Grep the lockfile for every `playwright@` and `playwright-core@` entry. A transitive dependency can pin an old version exactly
   (for example a dev tool that depends on an old `playwright` at an exact version). Lift just that one with a scoped override:
   `"pnpm": { "overrides": { "<parent>>playwright": "<version>" } }`, or npm's `overrides`.
4. Show the user the diff stat and every resolution that changed besides Playwright.
5. Commit, push and open a PR only after a yes. Never push to someone else's upstream: a local branch is the fix for a third-party clone.

**Do not** run `playwright install` on an old branch to fix the "Executable doesn't exist" error after step B. It downloads the
vulnerable browser again. Upgrade the repo's Playwright instead.

**D. Accessibility.** An agent usually can't read the TCC database (that needs Full Disk Access), so hand this to the user:
System Settings → Privacy & Security → Accessibility. Their call is whether a terminal or IDE that runs agents needs it.

## Related, but not the same risk
Server-side headless Chromium, such as `@sparticuz/chromium` in AWS Lambda, is not an Accessibility risk on the laptop. If it renders URLs or HTML that users supply, an old build is an RCE-in-Lambda surface. Flag it, and leave it out of the laptop fixes.
