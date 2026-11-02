# Response: an old IAM user or access key was used

Use this when the user reports activity on an IAM user or key they no longer use, whether from a GuardDuty finding, an AWS Health
or abuse email, a GitHub secret-scanning alert, or a surprise bill. It is incident response, not a version sweep, and the contract
still applies: read-only first, ask before every change, and never print a secret.

## 1. Find the key locally (read-only)
```bash
bash <<'EOF'
grep -E '^\[' ~/.aws/config ~/.aws/credentials 2>/dev/null
# which sections hold a long-term (AKIA) or temporary (ASIA) key; prefix only, never the value
awk '/^\[/{s=$0} /aws_access_key_id/{v=$0; sub(/.*= */,"",v); print s, "key-type:", substr(v,1,4)} /aws_session_token/{print s, "has session token"}' ~/.aws/credentials
EOF
```
Then look for the key in project files and **git history**, reporting repo names and commit IDs only:
```bash
bash <<'EOF'
CODE_ROOTS="$HOME/Developer $HOME/code $HOME/src"
find $CODE_ROOTS -maxdepth 6 -type f -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | xargs grep -lE 'AKIA[0-9A-Z]{16}' 2>/dev/null
for g in $(find $CODE_ROOTS -maxdepth 4 -name .git -type d 2>/dev/null); do
  r=${g%/.git}; c=$(git -C "$r" log --all -G 'AKIA[0-9A-Z]{16}' --format=%h 2>/dev/null | head -5 | tr '\n' ' ')
  [ -n "$c" ] && echo "$r: $c"
done
EOF
```
If gitleaks or trufflehog is installed, they're more thorough. Run them with output redacted.

**Do not use the key to identify it** (`aws sts get-caller-identity --profile <p>`) without asking first.
- It's read-only, but it writes a CloudTrail event from the user's IP into the trail they're about to investigate.
- The user may prefer to read the account ID from the alert.

## 2. Contain it (the user acts in the console, or approves each CLI call)
1. **Deactivate the key; don't delete it.** Go to IAM → Users → the user → Security credentials. Deactivating cuts off access straight away and keeps the evidence.
2. Look for persistence, because the attacker may have created their own access:
   - new IAM users, access keys, login profiles or roles;
   - policies attached to anything;
   - trust policies edited to let in an outside account.
3. Look in **every region** for EC2 or GPU instances, Lambda functions, and new key pairs. These are the usual cash-out.

## 3. Investigate
In CloudTrail Event history, filter by **Access key ID** and look back 90 days. Look for:
- `GetCallerIdentity` from unfamiliar IPs (the attacker's first move);
- `CreateUser`, `CreateAccessKey`, `CreateLoginProfile`, `AttachUserPolicy` and `PutUserPolicy`;
- `RunInstances` (in every region), `CreateFunction`, `ImportKeyPair`, and SES or SNS sends.

GuardDuty findings and Cost Explorer (grouped by service and region) confirm the scope.

## 4. Clean up (ask first)
- **Once the user confirms nothing depends on it,** delete the key, and the user if it's unused.
- **Remove the local copy** from `~/.aws/credentials`. Back up the file first, then remove only that section.
- **Rewriting git history** only helps once the key is dead. Rotating the key, which deactivating it already does, is what actually fixes a leak.
- **Prefer IAM Identity Center (SSO) or roles** over long-term keys from now on.
