# black-october-mac-sweep

An agent skill (Claude Code and other agents that read `SKILL.md`) that checks a developer's Mac for the October 2026
"Black October" issues, then walks through fixes **one at a time, with your yes before each**.

It covers:
- the Brotli decoder bug in Node, Bun and Claude Code (CVE-2026-111497);
- the compromised eMudhra intermediates: curl, nscurl, pip, uv, Node, Java, `/etc/ssl/cert.pem` and keychain trust;
- Tailscale TS-2026-013, Chrome 156 and macOS 26.7.1;
- PHP, Ruby, GitLab, Next.js and Storybook;
- keys stored on breached platforms;
- the stale, unsandboxed Chromium that Playwright, Puppeteer and agent-browser keep in their caches;
- what to do when an old AWS IAM access key is used.

## Install
```bash
git clone https://github.com/brad07/black-october-mac-sweep ~/.claude/skills/black-october-mac-sweep
```
Then ask your agent to "check my Mac for Black October".

## How it behaves
- **Phase 1 is read-only.** The agent reports one table: `item | status | evidence`.
- **Phase 2 is one fix per yes.** The agent shows each command first, and re-runs the check afterwards.
- **You run anything that needs `sudo` yourself**, in a real terminal. An agent's shell has no TTY for the password prompt.
- **Secrets, process arguments and file contents stay out of the report.**

## Credit and upstream code
This builds on the community advisory **[dominikmartn/black-october-check](https://github.com/dominikmartn/black-october-check)**,
which is the source for fixed versions and for the eMudhra scripts.

That repo has no licence, so this one **does not copy its scripts**. `scripts/upstream-block.sh` downloads them from a
pinned upstream commit, checks the file's SHA-256, and writes them to a file for the agent to read before anyone runs
them. `UPSTREAM_REF=main` follows newer upstream versions, without the hash check.

## Not verified
Some claims in circulation are repeated here and marked unverified. Examples are the "GPU process presses Cmd+Space"
chain for agent browsers, and whether macOS honours a deny for a certificate that is in no keychain. Check fixed versions
against the vendors before you rely on them; this skill reflects the state on 2026-11-03.

## Licence
MIT for the files in this repo; see `LICENSE`. Upstream content that the scripts download stays under its author's terms.
