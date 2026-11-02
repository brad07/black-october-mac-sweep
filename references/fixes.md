# Phase 2: fixes, one at a time

For every fix:
1. Propose it and show the exact command.
2. Wait for a yes.
3. Run it, or hand it to the user if it needs sudo or a dialog.
4. Re-run the matching check from `checks.md` and show the evidence line.

"Hand to the user" means they run it in a **real terminal tab**. An agent's shell, and Claude Code's `!` prefix, give `sudo` no TTY.

## F1. Node
Fixed: 26.12.1, 24.22.1, 22.23.4. Fix every install found in check 1, not just the one on PATH.
- **Homebrew:** `brew upgrade node`.
- **Version managers:** `fnm install 22.23.4`, then `fnm default 22.23.4` (likewise for nvm, volta, mise or asdf). Then offer to uninstall the old versions. Removing them is what stops a stale `.nvmrc` silently bringing one back. List any `.nvmrc` that pins a removed version, and offer to bump it.
  - fnm's data folder varies, so pass `FNM_DIR` explicitly if `fnm list` shows nothing in the agent's shell. Try `~/.local/share/fnm`, or `~/Library/Application Support/fnm`.
- **`/usr/local/bin/node` from the nodejs.org pkg:**
  1. Download the `.pkg` and `SHASUMS256.txt` to a fresh folder. Never pipe them into anything.
  2. `shasum -a 256 -c` the pkg against `SHASUMS256.txt`.
  3. Check the signature with `pkgutil --check-signature`. It must say "Developer ID Installer: Node.js Foundation" and notarized.
  4. Hand the install to the user: it needs a password.
  5. If gpg is absent, say that the `.sig` was not verified.
- **Restart long-running Node processes.** Before restarting a service, say what it does and who uses it.
  - Old-Node processes spawned by other agent sessions (MCP servers) can be stopped with `kill -TERM`, but only after re-checking their identity just before the kill: the PID's binary (`lsof txt`) and its script.
  - Then tell the user which sessions need `/mcp` to reconnect.
  - For launchd services: `launchctl kickstart -k gui/$(id -u)/<label>`.

## F2. Homebrew brotli
```bash
HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew upgrade brotli
```
Restart every process from check 1's `lsof` list. Verify that node really loads 1.2.1, with
`DYLD_PRINT_LIBRARIES=1 "$(brew --prefix)/opt/node/bin/node" -e 0 2>&1 | grep brotli`. Then offer `brew cleanup brotli`, which removes the 1.2.0 keg.

## F3. Claude Code
Run `claude update` to get 2.1.308 or later, and restart running sessions. Re-run check 4: it must show fix > 0. Remove any WebFetch deny that was added as a stopgap.

## F4. eMudhra
1. **Update the client bundles:**
   - `brew upgrade ca-certificates certifi`.
   - In each Python and virtualenv you install packages with: `path/to/python -m pip install -U pip` (gets pip 26.2.2).
     - **Homebrew's Python is PEP 668 "externally managed":** its pip can't upgrade itself. Use `brew upgrade python@3.x` instead, or report the probe result if it already shows safe.
     - Virtualenvs keep their own old pip, so upgrade each one.
   - uv 0.13.5: run `uv self update` for the standalone installer, or `brew upgrade uv`. Then `uv python upgrade` for uv-managed Pythons.
   - Never install packages with Apple's `/usr/bin/python3`.
2. **Remove the two roots from `/etc/ssl/cert.pem`** using the file from `<skill-dir>/scripts/upstream-block.sh certpem`. Read it, then **hand it to the user:** it needs sudo.
   - Expected output: `ok: removed 2 root(s), 128 -> 126`.
   - The backup goes to `/etc/ssl/cert.pem.bak-emudhra-2026-10-22`. That date is upstream's literal, and step 4 relies on it.
3. **Deny the 16 certificates in Apple's trust settings** using the file from `<skill-dir>/scripts/upstream-block.sh keychain`. Read it, then **hand it to the user:** it needs a password and one dialog.
   - Expected output: `before: N entries, after: N+16` and `Trust Settings imported successfully`.
   - Before handing it over, the agent can dry-run the fingerprint matching without sudo: extract the certificates and count matches.
     **Don't** parse the `BAD=` block with `tr -d 'BAD="'`. `tr` deletes characters, not strings, so it strips the hex letters B, A and D, and every fingerprint stops matching.
4. **After every macOS update,** re-run check 5. The update restores Apple's `cert.pem` (the advisory's run went back to 128 certificates). The keychain denies survive. If `/usr/bin/curl` trusts again:
   1. `sudo mv /etc/ssl/cert.pem.bak-emudhra-2026-10-22 /etc/ssl/cert.pem.bak-emudhra-old`.
   2. Re-run step 2.
5. **Linux (Debian or Ubuntu)**, from the incident page:
   ```bash
   sudo sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf && sudo update-ca-certificates
   ```
6. **Java:**
   - Update each JDK the probe flagged, from its vendor.
   - Until then, and for Java 26 (which gets no fix), append the 16 fingerprints to that JDK's `lib/security/blocked.certs` with upstream's `block_jdk` function. It is in the upstream README (F4 step 6) and needs sudo.
   - Restart every JVM afterwards: Gradle daemons, IDEs and services.

After all of F4, re-run check 5, and also confirm that github.com, google.com, apple.com and registry.npmjs.org still load.

## F5. Tailscale
Fixed: 1.104.2. The fix depends on how check 6 found it installed:
- **Standalone (Sparkle) app from tailscale.com:** `tailscale update` is **not supported** on this edition. The user picks "Check for Updates…" in the menu-bar app, installs, then quits and relaunches the app.
  - Verify the **daemon** version and that `BackendState` is `Running`. Checking only the app version misses an old daemon that is still running.
  - Say first what Tailscale does for them and who loses connectivity while it restarts.
- **App Store:** the user updates it in the App Store.
- **Homebrew `tailscaled` as a system daemon:** `sudo "$(brew --prefix tailscale)/bin/tailscaled" install-system-daemon`, which needs sudo. Swapping the binary and running `kickstart` got the daemon killed for a code-signing mismatch.

## F6. Chrome and macOS
Relaunch Chrome on 156.0.8078.73 or later. Install the macOS update when a restart suits the user, then repeat F4 step 4.

## F7. Rotate keys from check 10
Ask the user which keys were stored on those platforms. Rotate them at the provider, then update every place that consumes them.

## F8. Servers
- **PHP:** update. Until then, set `session.upload_progress.enabled=0` and restart the workers.
- **GitLab:** update to the fixed patch for your branch.
- **Ruby:** update to 4.0.9, 3.4.12 or 3.3.13 (`brew upgrade ruby` or your version manager), then restart Ruby services.
- **Next.js:** next 16.4.1 or 15.5.28, plus sharp 0.35.5, then redeploy.
- **Storybook:** update to the fixed version for your major. On 7.x, which has no fix, don't run `storybook dev`.

## F9. Hygiene
- **Env files:** `chmod 600` on world-readable ones. List their paths first and never print their contents.
- **Firewall:** turn it on for laptops. **Hand this to the user:** `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on`.
- **npm tokens:** remove dead ones, but only after confirming against their registry that they're dead.
- **Dev servers:** bind them to 127.0.0.1.
- **tmux:** don't `brew upgrade tmux` while sessions are running.

## F10. Agent browsers
See `references/playwright-agent-browsers.md`, fixes A–D.

## F11. A long-term AWS key that was used
See `references/aws-leaked-key.md`.
