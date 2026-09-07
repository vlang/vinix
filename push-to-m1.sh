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

# Desktop and diagnostic M1 deployments boot a separate, small image.  The
# base initramfs can be several GB and is often being rebuilt independently;
# do not make those deployments read (and potentially race) an image they do
# not use.  Keep the default intact for direct push-to-m1.sh callers.
set --
if [ "${VINIX_M1_EXCLUDE_BASE_INITRAMFS:-0}" = "1" ]; then
    set -- --exclude 'build-support/init-aarch64/initramfs.tar'
    echo "skipping unused base initramfs"
fi

# macOS ships OpenRSYNC 2.6.9, which has --progress but not rsync 3's
# --info=progress2.  --progress therefore keeps this usable on both: a large
# desktop initramfs shows a live percentage instead of looking hung, and
# --partial lets the next invocation resume after an interrupted Wi-Fi push.
echo "==> Comparing files; changed files show a live percentage..."
# The build workspaces are host-side intermediates, not boot inputs. The
# kernel and selected initramfs remain included below, while their staging
# trees are deliberately left out of an M1 deployment.
rsync -a --partial --progress --stats \
    --exclude '.claude/' \
    --exclude '.git/' \
    --exclude 'vinix.iso' \
    --exclude 'boot-image/boot.img' \
    --exclude 'boot-image/limine-src-9.3.0/' \
    --exclude 'tools/agx-re/build/' \
    --exclude 'build/' \
    --exclude 'build-aarch64-*/' \
    --exclude 'kernel/obj/' \
    --exclude 'kernel/tmp.*' \
    --exclude '.DS_Store' \
    "$@" \
    ./ "$REMOTE:$DEST/"
echo "rsync exit: $?"

# The one path excluded above that must still arrive.
EFI="boot-image/limine-src-9.3.0/bin/BOOTAA64.EFI"
if [ -f "$EFI" ]; then
    ssh "$REMOTE" "mkdir -p '$DEST/boot-image/limine-src-9.3.0/bin'"
    rsync -a "$EFI" "$REMOTE:$DEST/$EFI"
    echo "pushed patched loader: $EFI"
fi

# kek.sh is the command actually typed on the M1, so it has to travel with the
# tree rather than being copied by hand. Installing it outside the repo keeps
# the short path the user already uses.
if [ -f kek.sh ]; then
    rsync -a kek.sh "$REMOTE:$(dirname "$DEST")/kek.sh"
    ssh "$REMOTE" "chmod +x '$(dirname "$DEST")/kek.sh'"
    echo "installed kek.sh -> $(dirname "$DEST")/kek.sh"
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
