#!/bin/bash
# Deploy Vinix to the M1 ESP, verify it landed, and say what to look for.
#
# Installed on the M1 by push-to-m1.sh; edit it in the repo, not in place, or
# the next push overwrites your changes.
#
#   sudo ~/code/kek.sh          boot into the desktop (default)
#   sudo ~/code/kek.sh full     BusyBox shell userland + terminal
#   sudo ~/code/kek.sh diag     minimal initramfs, no terminal, stage bars only
#   sudo ~/code/kek.sh halt N   power off at stage N -- machine turning itself
#                               off means the kernel reached that stage
#   sudo ~/code/kek.sh selftest fault on purpose; the machine MUST reboot.
#                               run this first: it proves the signal works
#   sudo ~/code/kek.sh gpu      normal boot + experimental Apple GPU
#
set -euo pipefail

REPO="$HOME/code/vinix"
[ "$(id -u)" -eq 0 ] && REPO="$(eval echo ~"${SUDO_USER:-$USER}")/code/vinix"
DISK="disk0s4"
ESP="/Volumes/EFI - FEDOR"

case "${1:-desktop}" in
    desktop)
        FLAGS=(--native-resolution --desktop-initramfs)
        MODE="desktop"
        ;;
    diag)
        FLAGS=(--native-resolution --minimal-initramfs --no-early-term)
        MODE="diagnostic"
        ;;
    halt)
        if [ -z "${2:-}" ]; then
            echo "error: 'halt' needs a stage number, e.g. kek.sh halt 0" >&2
            exit 1
        fi
        FLAGS=(--native-resolution --minimal-initramfs --no-early-term "--halt-at=$2")
        MODE="halt at stage $2"
        ;;
    selftest)
        FLAGS=(--native-resolution --minimal-initramfs --no-early-term --halt-at=99 --force-fault)
        MODE="selftest"
        ;;
    full)
        FLAGS=(--native-resolution)
        MODE="shell"
        ;;
    gpu)
        FLAGS=(--apple-gpu --native-resolution)
        MODE="normal + Apple GPU"
        ;;
    -h|--help)
        sed -n '2,7p' "$0"
        exit 0
        ;;
    *)
        echo "error: unknown mode '$1' (use: desktop | full | diag | halt N | selftest | gpu)" >&2
        exit 1
        ;;
esac

# deploy-m1-efi.sh and kernel/bin/vinix are relative paths.
cd "$REPO"

# EFI partitions need root to mount; without it diskutil reports "failed to
# mount ... try the readOnly option", which looks like corruption but is not.
if ! mount | grep -q "on $ESP "; then
    diskutil mount "$DISK"
fi

echo "==> deploying ($MODE)"
./deploy-m1-efi.sh "${FLAGS[@]}" "$ESP"
sync

built="$(shasum -a 256 kernel/bin/vinix | awk '{print $1}')"
landed="$(shasum -a 256 "$ESP/boot/vinix" | awk '{print $1}')"
if [ "$built" != "$landed" ]; then
    echo "ERROR: deployed kernel does not match the build" >&2
    echo "  built:  $built" >&2
    echo "  landed: $landed" >&2
    diskutil unmount "$DISK" || true
    exit 1
fi

diskutil unmount "$DISK"
echo
echo "OK. Reboot: hold power -> startup options -> the Asahi/Linux disk."

case "$MODE" in
selftest)
    cat <<'ST'

The machine must REBOOT. That proves PSCI works and that a silent machine
in the other modes is real information rather than a broken signal.
If it does NOT reboot, PSCI is unavailable and the halt modes mean nothing.
ST
    ;;
halt*)
    cat <<'HALT'

The machine powering itself off means the kernel reached that stage.
Staying on a black screen means it did not.

Black by itself proves nothing: Limine clears the screen before handing
over, so every boot goes black no matter what the kernel does. Powering
off is the only real signal.

Reboot instead of power off means the kernel faulted before that stage.
Start at 0. Stage 0 runs before the kernel touches the display at all,
so it answers "was the kernel entered?" and nothing else.
  0  entered kmain, cmdline readable
  1  the whole-screen fill did not fault
  2  pmm_init done
  4  exception vectors installed
  7  survived the page-table switch
HALT
    ;;
esac

if [ "$MODE" = "diagnostic" ]; then
    cat <<'LEGEND'

Nothing clears the framebuffer in this mode, so the coloured bars stay up.
Count them from the top; the count is the last stage kmain reached:

   1  entered kmain
   2  pmm_init done
   3  V runtime _vinit done
   4  exception vectors installed
   5  device tree parsed        (6 instead = no device tree found)
   7  vmm_init done  <- survived the page-table switch
   8  Apple hardware init done
   9  timer done
  10  scheduler running
  11  12  later kernel init

No bars at all means it dies before the first instruction of kmain.
LEGEND
fi
