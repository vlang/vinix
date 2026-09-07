#!/bin/bash
# Deploy Vinix to the M1 ESP, verify it landed, and say what to look for.
#
# Installed on the M1 by push-to-m1.sh; edit it in the repo, not in place, or
# the next push overwrites your changes.
#
#   sudo ~/code/kek.sh          boot into the desktop with Wi-Fi (default)
#   sudo ~/code/kek.sh full     BusyBox shell userland + terminal
#   sudo ~/code/kek.sh diag     minimal initramfs, no terminal, stage bars only
#   sudo ~/code/kek.sh halt N   power off at stage N -- machine turning itself
#                               off means the kernel reached that stage
#   sudo ~/code/kek.sh selftest fault on purpose; the machine MUST reboot.
#                               run this first: it proves the signal works
#   sudo ~/code/kek.sh gpu      shell userland + experimental Apple GPU; the
#                               boot test then runs the AGX render test
#   sudo ~/code/kek.sh desktop-gpu   desktop + experimental Apple GPU
#   sudo ~/code/kek.sh desktop-wifi  desktop + experimental BCM4378 Wi-Fi
#
# Everything below is off by default in the kernel, so these are the only way
# to exercise it on real hardware. Start narrow: GPU and DCP can hard-reset the
# machine, and with several on at once a reset says nothing about which one
# did it.
#
#   sudo ~/code/kek.sh battery  shell + SMC battery only; read-only, the safe
#                               one to try first. `cat /dev/battery` reports
#                               the charge
#   sudo ~/code/kek.sh dcp      shell + display coprocessor only
#   sudo ~/code/kek.sh storage  shell + the SSD, read-only. Nothing is written:
#                               authorising that needs a partition named by
#                               PARTUUID, which deploy-m1-efi.sh takes as
#                               --ans-rw= and this mode deliberately does not
#   sudo ~/code/kek.sh drivers  shell + battery, DCP, GPU and Wi-Fi together
#   sudo ~/code/kek.sh desktop-drivers   desktop + all four: Settings includes
#                               brightness and Wi-Fi controls
#
set -euo pipefail

# A deploy wrapper may use a non-default remote checkout. Keep the historic
# user-home default for direct invocations, but honour the explicit checkout
# passed by that wrapper even though this script runs under sudo.
REPO="${VINIX_REPO:-}"
if [ -z "$REPO" ]; then
    REPO="$HOME/code/vinix"
    [ "$(id -u)" -eq 0 ] && REPO="$(eval echo ~"${SUDO_USER:-$USER}")/code/vinix"
fi
DISK="disk0s4"
ESP="/Volumes/EFI - FEDOR"

case "${1:-desktop}" in
    desktop)
        FLAGS=(--apple-wifi --native-resolution --desktop-initramfs)
        MODE="desktop + Apple Wi-Fi"
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
        MODE="shell + Apple GPU"
        ;;
    desktop-gpu)
        FLAGS=(--apple-gpu --native-resolution --desktop-initramfs)
        MODE="desktop + Apple GPU"
        ;;
    desktop-wifi)
        FLAGS=(--apple-wifi --native-resolution --desktop-initramfs)
        MODE="desktop + Apple Wi-Fi"
        ;;
    storage)
        FLAGS=(--apple-ans --native-resolution)
        MODE="shell + ANS storage (read-only)"
        ;;
    battery)
        FLAGS=(--apple-battery --native-resolution)
        MODE="shell + SMC battery"
        ;;
    dcp)
        FLAGS=(--apple-dcp --native-resolution)
        MODE="shell + Apple DCP"
        ;;
    drivers)
        FLAGS=(--all-drivers --native-resolution)
        MODE="shell + all Apple drivers"
        ;;
    desktop-drivers)
        FLAGS=(--all-drivers --native-resolution --desktop-initramfs)
        MODE="desktop + all Apple drivers"
        ;;
    -h|--help)
        # The whole leading comment block, however long it grows.
        awk 'NR > 1 { if (/^#/) print; else exit }' "$0"
        exit 0
        ;;
    *)
        echo "error: unknown mode '$1' (use: desktop | full | gpu | desktop-gpu | desktop-wifi | battery | dcp | storage | drivers | desktop-drivers | diag | halt N | selftest)" >&2
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
*Apple\ drivers|*SMC\ battery|*Apple\ DCP|*Apple\ Wi-Fi)
    cat <<'DRV'

These drivers are off in the kernel unless the cmdline asks for them, so the boot
log naming them is the first thing to check:

  apple bring-up: GPU=enabled DCP=enabled    <- the line the kernel prints
  apple-smc: ...                             <- silence here means it probed
                                                and found its device tree node

Then, on the shell:
  cat /dev/battery       the charge, as the desktop's taskbar reads it
  ls /dev/apple-panel-bl the backlight the Settings brightness bar writes
  ls /dev/wlan0          the Wi-Fi control/raw Ethernet device
  wifi-ctl status        chip identity and firmware/radio state

The touchpad needs no flag and comes up in every mode: it rides the SPI
transport the keyboard already uses, and the first /dev/pointer read asks for
native mode. It announces itself once:

  apple-spi-tp: first valid touchpad report received

No such line and a cursor that does not move means the reports never arrived.
Until one does, /dev/pointer falls back to VirtIO, which this machine has none
of, so the cursor simply stays put rather than misbehaving.

A machine that resets instead of booting means one of these faulted. Re-run
with `battery` alone first -- it is read-only and touches no display -- then
`dcp`, `desktop-wifi`, and only then `drivers`. Which one resets it is the answer.
DRV
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
