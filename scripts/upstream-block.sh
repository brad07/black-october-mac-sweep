#!/bin/bash
# Downloads one script block from the upstream advisory (github.com/dominikmartn/black-october-check) and
# writes it to a file, so the agent can READ it before anyone runs it. Runs nothing it downloads.
#
# The upstream repo has no licence, so this skill does not redistribute its scripts. It fetches them from
# a pinned commit and checks the README's SHA-256, so a changed file is noticed instead of run.
#
# Usage: upstream-block.sh <probe|certpem|keychain> [out-dir]
#   probe     check 5, the read-only 14-host eMudhra trust probe
#   certpem   F4 step 2, removes two roots from /etc/ssl/cert.pem (sudo; the USER runs it in a real terminal)
#   keychain  F4 step 3, denies 16 certificates in Apple's trust settings (sudo + a dialog; the USER runs it)
#   out-dir   default: a new temporary directory
#
# UPSTREAM_REF=main skips the pin and the hash check, for when upstream has moved on. Read the diff first.
#
# Changes this script makes to what it downloads:
#   - wraps the block in a function, because upstream blocks are written to paste into a shell and may `return`
#   - certpem: stops when the backup cannot be made (no TTY, wrong password), instead of carrying on and
#     stopping later at "openssl failed on every certificate". Applied only if the line matches exactly.
set -eu
PIN=9f3ee434e23a6aa139ec1dbeb33fcbcfbe958fa9   # upstream main on 2026-10-30
PIN_SHA256=364d6f9bf3a0cbbf2d33b346e6a59358a4a2ca012c3943dfe997ffc0f08ec96c
REF=${UPSTREAM_REF:-$PIN}

case "${1:-}" in
  probe)    anchor='^### 5[.] eMudhra' ;;
  certpem)  anchor='^2[.] Remove the two affected roots' ;;
  keychain) anchor='^3[.] [*][*]Human at the screen[.][*][*] Deny' ;;
  *) echo "usage: $0 <probe|certpem|keychain> [out-dir]" >&2; exit 2 ;;
esac
out=${2:-$(mktemp -d)}; mkdir -p "$out"
readme="$out/upstream-README-$REF.md"

[ -f "$readme" ] || curl -fsSLo "$readme" "https://raw.githubusercontent.com/dominikmartn/black-october-check/$REF/README.md"
if [ "$REF" = "$PIN" ]; then
  got=$(shasum -a 256 "$readme" | cut -d' ' -f1)
  [ "$got" = "$PIN_SHA256" ] || { echo "STOP: README hash $got does not match the pin; nothing extracted" >&2; exit 1; }
else
  echo "warning: UPSTREAM_REF=$REF, hash not checked. Read the whole block before running it." >&2
fi

# Anchors use [.] and [*], not backslashes: awk -v eats backslash escapes.
# The first ```bash block after the anchor line. List-item blocks are indented; strip that indent.
body=$(awk -v a="$anchor" '
  !found && $0 ~ a { found=1; next }
  found && !inb && /^[[:space:]]*```bash/ { inb=1; match($0, /^[[:space:]]*/); ind=RLENGTH; next }
  inb && /^[[:space:]]*```[[:space:]]*$/ { exit }
  inb { print substr($0, ind+1) }' "$readme")
[ -n "$body" ] || { echo "STOP: no bash block found after the '$1' anchor; upstream changed its layout" >&2; exit 1; }

if [ "$1" = certpem ]; then
  old='[ -f "$B" ] || sudo cp -p /etc/ssl/cert.pem "$B"'
  new='[ -f "$B" ] || sudo cp -p /etc/ssl/cert.pem "$B" || { echo "STOP: could not create the backup (sudo needs a real terminal), nothing changed"; return 1; }'
  if [ "$(printf '%s\n' "$body" | grep -cxF "$old")" -eq 1 ]; then
    body=$(printf '%s\n' "$body" | awk -v o="$old" -v n="$new" '$0 == o { print n; next } { print }')
  else
    echo "warning: backup line not found exactly once; the backup guard was NOT added" >&2
  fi
fi

f="$out/$1.sh"
{ printf '#!/bin/bash\n# Extracted from github.com/dominikmartn/black-october-check@%s (%s block) by upstream-block.sh.\n' "$REF" "$1"
  printf 'main() {\n%s\n}\nmain "$@"\n' "$body"; } > "$f"
bash -n "$f" || { echo "STOP: extracted block does not parse: $f" >&2; exit 1; }
echo "$f"
