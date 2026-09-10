#!/bin/sh
# Push this tree to the M1 and prove what landed.
#
# Deployment is only meaningful if the current Limine arrives with it. The
# installed loader lives in boot-image/limine-bin; source build directories
# are excluded and the installed artifact is checked on the far side.
set -eu

REMOTE="${1:-sergey@192.168.0.3}"
DEST="${2:-/Users/sergey/code/vinix}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIMINE_VERSION="12.8.0"

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
if [ "${VINIX_M1_EXCLUDE_DESKTOP_TAR:-0}" = "1" ]; then
    set -- "$@" --exclude 'build-support/init-aarch64/initramfs-desktop.tar'
    echo "skipping uncompressed desktop initramfs (Limine will load its gzip image)"
fi
if [ "${VINIX_M1_EXCLUDE_DESKTOP_GZIP:-0}" = "1" ]; then
    set -- "$@" --exclude 'build-support/init-aarch64/initramfs-desktop.tar.gz'
fi

# QEMU uses these local scratch disks, but an M1 deployment never does. They
# are normally left alone: the remote checkout may also be a QEMU workspace.
# A full data volume is the explicit exception. The caller must opt in, and
# this deliberately matches only the generated disks, interrupted rsync
# temporaries, and the QEMU firmware -- never source or M1 boot inputs.
if [ "${VINIX_M1_PRUNE_QEMU_ARTIFACTS:-0}" = "1" ]; then
    echo "==> Removing remote QEMU-only artifacts..."
    ssh "$REMOTE" "
if [ -d '$DEST/boot-image' ]; then
    find '$DEST/boot-image' -maxdepth 1 -type f \
        \( -name 'boot*.img' -o -name '.boot*.img.*' -o \
           -name 'edk2-aarch64-code-*.fd' \) -print -delete
fi"
    ssh "$REMOTE" "
for artifact_dir in '$DEST'/build-*-probe '$DEST'/build-amd64-*; do
    [ -d \"\$artifact_dir\" ] || continue
    find \"\$artifact_dir\" -maxdepth 1 -type f -name '*.img' -print -delete
done"
fi

# macOS ships OpenRSYNC 2.6.9, which has --progress but not rsync 3's
# --info=progress2.  --progress therefore keeps this usable on both: a large
# desktop initramfs shows a live percentage instead of looking hung, and
# --partial lets the next invocation resume after an interrupted Wi-Fi push.
echo "==> Comparing files; changed files show a live percentage..."
# The build workspaces are host-side intermediates, not boot inputs. The
# kernel and selected initramfs remain included below, while their staging
# trees are deliberately left out of an M1 deployment.  The boot-image disk
# files are QEMU scratch disks, too: boot-desktop.img is a sparse 2 GiB disk
# created by run-desktop-aarch64.sh, and the edk2 file is QEMU firmware.  An
# M1 starts through its existing m1n1/U-Boot chain and deploy-m1-efi.sh only
# needs the separately copied Limine EFI below.  Sending either artifact can
# fill the Mac's data volume before the actual desktop initramfs is reached.
# The amd64 build trees and application-probe disk images are QEMU-only too;
# in particular, partially transferring a multi-GB probe disk can strand an
# M1 with no room for the deployment inputs that it actually needs.
if ! rsync -a --partial --progress --stats \
    --exclude '.claude/' \
    --exclude '.git/' \
    --exclude 'vinix.iso' \
    --exclude 'boot-image/boot*.img' \
    --exclude 'boot-image/edk2-aarch64-code-*.fd' \
    --exclude 'build-*-probe/*.img' \
    --exclude 'build-amd64-*/' \
    --exclude 'boot-image/limine-src-*/' \
    --exclude 'tools/agx-re/build/' \
    --exclude 'build/' \
    --exclude 'build-aarch64-*/' \
    --exclude 'kernel/obj/' \
    --exclude 'kernel/tmp.*' \
    --exclude '.DS_Store' \
    "$@" \
    ./ "$REMOTE:$DEST/"; then
    echo >&2
    echo "ERROR: push to $REMOTE ran out of space or was interrupted." >&2
    echo "Remote free space:" >&2
    ssh "$REMOTE" "df -h '$DEST'" >&2 || true
    cat >&2 <<EOF

M1 pushes now skip QEMU-only boot-image disks and firmware. If a prior push
left partial files, inspect the remote QEMU artifacts before removing them:
    ssh $REMOTE 'find "$DEST/boot-image" -maxdepth 1 -type f \\( -name "boot*.img" -o -name ".boot*.img.*" -o -name "edk2-aarch64-code-*.fd" \\) -print'

They are not used by the M1 deployment. Remove only the listed stale or
partial artifacts, then re-run with VINIX_M1_PRUNE_QEMU_ARTIFACTS=1.
EOF
    exit 1
fi
echo "rsync exit: 0"

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
    for f in boot-image/limine-bin/BOOTAA64.EFI; do \
        if [ -f \"\$f\" ]; then \
            if LC_ALL=C grep -aF 'Limine $LIMINE_VERSION (aarch64, UEFI)' \"\$f\" >/dev/null && ! LC_ALL=C grep -aF 'Base revision %u is no longer supported for aarch64' \"\$f\" >/dev/null; then s='Limine $LIMINE_VERSION (Vinix compatible)'; else s='STALE/UNEXPECTED'; fi; \
            printf '%-50s %s\n' \"\$f\" \"\$s\"; \
        fi; \
    done"

if [ "${VINIX_M1_WRAPPED:-0}" != "1" ]; then
    echo
    echo "now on the M1:  sudo ~/code/kek.sh selftest"
fi
