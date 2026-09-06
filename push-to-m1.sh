#!/bin/sh
# Push this tree to the M1 and prove what landed.
#
# Deployment is only meaningful if the patched Limine arrives with it: the
# loader carrying the VHE hand-off fix is built into
# boot-image/limine-src-9.3.0/bin, which is inside a directory that is
# otherwise far too large to copy. Excluding the whole tree silently leaves
# the machine on whatever loader it already had, so the build output is
# included explicitly and checked on the far side rather than assumed.
set -eu

REMOTE="${1:-sergey@192.168.0.3}"
DEST="${2:-/Users/sergey/code/vinix}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_SIG="6806a0d248111cd5"

cd "$SCRIPT_DIR"

echo "pushing $(git log --oneline -1) to $REMOTE:$DEST"

rsync -a --stats \
    --exclude '.claude/' \
    --exclude '.git/' \
    --exclude 'vinix.iso' \
    --exclude 'boot-image/boot.img' \
    --exclude 'boot-image/limine-src-9.3.0/' \
    --exclude 'tools/agx-re/build/' \
    --exclude 'kernel/obj/' \
    --exclude 'kernel/tmp.*' \
    --exclude '.DS_Store' \
    ./ "$REMOTE:$DEST/"
echo "rsync exit: $?"

# The one path excluded above that must still arrive.
EFI="boot-image/limine-src-9.3.0/bin/BOOTAA64.EFI"
if [ -f "$EFI" ]; then
    ssh "$REMOTE" "mkdir -p '$DEST/boot-image/limine-src-9.3.0/bin'"
    rsync -a "$EFI" "$REMOTE:$DEST/$EFI"
    echo "pushed patched loader: $EFI"
fi

ssh "$REMOTE" "cd '$DEST' && \
    echo \"remote head:  \$(git log --oneline -1 2>/dev/null || echo unknown)\" && \
    echo \"kernel sha:   \$(shasum -a256 kernel/bin/vinix | cut -c1-16)\" && \
    for f in boot-image/limine-src-9.3.0/bin/BOOTAA64.EFI boot-image/limine-bin/BOOTAA64.EFI; do \
        if [ -f \"\$f\" ]; then \
            if xxd -p \"\$f\" | tr -d '\n' | grep -q '$PATCH_SIG'; then s=PATCHED; else s='UPSTREAM (would black-screen)'; fi; \
            printf '%-50s %s\n' \"\$f\" \"\$s\"; \
        fi; \
    done"

echo
echo "now on the M1:  sudo ~/code/kek.sh selftest"
