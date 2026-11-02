# How to undo

- **cert.pem:** `sudo cp -p /etc/ssl/cert.pem.bak-emudhra-2026-10-22 /etc/ssl/cert.pem`
- **Keychain denies:** for each file in `~/emudhra-proof/certs`, run `sudo security remove-trusted-cert -d <file>.crt.pem`. You can also open Keychain Access → System, find the eMudhra certificate, and delete its custom trust setting.
- **Java blocked.certs:** `sudo cp -p <jdk>/lib/security/blocked.certs.bak-emudhra-2026-10-23 <jdk>/lib/security/blocked.certs`
- **WebFetch deny:** remove `"WebFetch"` from `permissions.deny` in `~/.claude/settings.json`.
- **Firewall:** `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off`
- **Removed Node versions:** reinstall with the version manager, e.g. `fnm install <version>`. This brings the vulnerability back.
- **Deleted agent browsers:** the tool downloads its browser again on its next run or `install`.
- **Repo Playwright bumps:** delete the branch, or revert the commit.
- **brotli, Node, ca-certificates, uv, pip, Chrome, macOS, Tailscale:** no undo needed; these are plain upgrades.
