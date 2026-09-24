#!/bin/bash
# Create a VirtualBox VM for a Vinix ISO and start it.
#
# Usage: ./run-iso-virtualbox.sh [options] vinix-amd64.iso|vinix-arm64.iso
#
#   --name=NAME      VM name (default: vinix-<arch>)
#   --memory=MB      guest RAM (default: 4096; the whole image is loaded into it)
#   --cpus=N         virtual CPUs (default: 2)
#   --efi            boot an amd64 VM through EFI instead of BIOS
#   --headless       run without a window
#   --serial=FILE    log the first serial port to FILE
#   --no-start       create the VM but do not start it
#   --arch=ARCH      amd64 or arm64, when the file name does not say
#
# An existing VM with the same name is powered off and replaced, so running
# this again after downloading a newer ISO just works. The settings are the
# ones Vinix needs, applied over VirtualBox's defaults for the guest type:
#
#   amd64  "Other/Unknown (64-bit)", BIOS (or EFI), I/O APIC, PS/2 keyboard and
#          mouse, VMSVGA graphics, the ISO on the IDE controller
#   arm64  "Other/Unknown (ARM 64-bit)", EFI, USB keyboard and tablet on xHCI,
#          VMSVGA graphics, the ISO on the VirtioSCSI controller
#
# VirtualBox runs guests of its host's architecture only: the arm64 image on
# Apple Silicon Macs and other arm64 hosts, the amd64 image everywhere else.
set -euo pipefail

VBOXMANAGE="${VBOXMANAGE:-}"
NAME=''
MEMORY=4096
CPUS=2
FIRMWARE=bios
FRONTEND=gui
SERIAL_LOG=''
START=1
ARCH=''
ISO=''

usage() {
    sed -n '2,/^set -/s/^# \{0,1\}//p' "$0" | sed '$d'
}

for arg in "$@"; do
    case "$arg" in
        --name=*) NAME="${arg#*=}" ;;
        --memory=*) MEMORY="${arg#*=}" ;;
        --cpus=*) CPUS="${arg#*=}" ;;
        --efi) FIRMWARE=efi ;;
        --headless) FRONTEND=headless ;;
        --serial=*) SERIAL_LOG="${arg#*=}" ;;
        --no-start) START=0 ;;
        --arch=*) ARCH="${arg#*=}" ;;
        --help|-h) usage; exit 0 ;;
        -*) echo "ERROR: unknown option: $arg" >&2; exit 1 ;;
        *)
            if [ -n "$ISO" ]; then
                echo "ERROR: only one ISO can be given" >&2
                exit 1
            fi
            ISO="$arg"
            ;;
    esac
done

if [ -z "$ISO" ]; then
    usage >&2
    exit 1
fi
if [ ! -f "$ISO" ]; then
    echo "ERROR: ISO not found: $ISO" >&2
    exit 1
fi
ISO="$(cd "$(dirname "$ISO")" && pwd)/$(basename "$ISO")"

if [ -z "$VBOXMANAGE" ]; then
    for candidate in "$(command -v VBoxManage 2>/dev/null || true)" \
        /Applications/VirtualBox.app/Contents/MacOS/VBoxManage \
        /usr/bin/VBoxManage /usr/local/bin/VBoxManage; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            VBOXMANAGE="$candidate"
            break
        fi
    done
fi
if [ -z "$VBOXMANAGE" ]; then
    echo "ERROR: VBoxManage not found. Install VirtualBox, or set VBOXMANAGE." >&2
    exit 1
fi

if [ -z "$ARCH" ]; then
    case "$(basename "$ISO")" in
        *amd64*|*x86_64*|*x64*) ARCH=amd64 ;;
        *arm64*|*aarch64*) ARCH=arm64 ;;
    esac
fi
if [ -z "$ARCH" ] && command -v xorriso >/dev/null 2>&1; then
    listing="$(xorriso -indev "$ISO" -find /EFI/BOOT -name 'BOOT*.EFI' 2>/dev/null || true)"
    case "$listing" in
        *BOOTX64.EFI*) ARCH=amd64 ;;
        *BOOTAA64.EFI*) ARCH=arm64 ;;
    esac
fi
case "$ARCH" in
    amd64|arm64) ;;
    *)
        echo "ERROR: cannot tell whether $ISO is amd64 or arm64; pass --arch" >&2
        exit 1
        ;;
esac
NAME="${NAME:-vinix-$ARCH}"

vbox() {
    "$VBOXMANAGE" "$@"
}

if vbox showvminfo "$NAME" >/dev/null 2>&1; then
    echo "==> Replacing the existing VM '$NAME'..."
    if vbox showvminfo "$NAME" --machinereadable | grep -q '^VMState="running"'; then
        vbox controlvm "$NAME" poweroff >/dev/null 2>&1 || true
        for _ in $(seq 1 30); do
            vbox showvminfo "$NAME" --machinereadable | grep -q '^VMState="running"' || break
            sleep 1
        done
    fi
    # The session lock outlives the VM process by a moment.
    for _ in $(seq 1 10); do
        vbox unregistervm "$NAME" --delete >/dev/null 2>&1 && break
        sleep 1
    done
fi

echo "==> Creating VirtualBox VM '$NAME' ($ARCH, ${MEMORY} MB, $CPUS CPUs)..."
if [ "$ARCH" = amd64 ]; then
    vbox createvm --name "$NAME" --platform-architecture x86 --ostype Other_64 \
        --register --default >/dev/null
    vbox modifyvm "$NAME" \
        --memory "$MEMORY" --cpus "$CPUS" --ioapic on \
        --firmware "$FIRMWARE" \
        --graphicscontroller vmsvga --vram 64 \
        --keyboard ps2 --mouse ps2 \
        --boot1 dvd --boot2 none --boot3 none --boot4 none
    controller="$(vbox showvminfo "$NAME" --machinereadable |
        sed -n 's/^storagecontrollername0="\(.*\)"$/\1/p')"
    controller="${controller:-IDE}"
else
    vbox createvm --name "$NAME" --platform-architecture arm --ostype Other_arm64 \
        --register --default >/dev/null
    vbox modifyvm "$NAME" \
        --memory "$MEMORY" --cpus "$CPUS" \
        --graphicscontroller vmsvga --vram 64 \
        --usb-xhci on --keyboard usb --mouse usbtablet \
        --boot1 dvd --boot2 none --boot3 none --boot4 none
    controller="$(vbox showvminfo "$NAME" --machinereadable |
        sed -n 's/^storagecontrollername0="\(.*\)"$/\1/p')"
    controller="${controller:-VirtioSCSI}"
fi
vbox storageattach "$NAME" --storagectl "$controller" --port 0 --device 0 \
    --type dvddrive --medium "$ISO"

if [ -n "$SERIAL_LOG" ]; then
    mkdir -p "$(dirname "$SERIAL_LOG")"
    : > "$SERIAL_LOG"
    SERIAL_LOG="$(cd "$(dirname "$SERIAL_LOG")" && pwd)/$(basename "$SERIAL_LOG")"
    vbox modifyvm "$NAME" --uart1 0x3f8 4 --uart-mode1 file "$SERIAL_LOG"
fi

if [ "$START" -eq 0 ]; then
    echo "    created; start it with: $VBOXMANAGE startvm $NAME"
    exit 0
fi
echo "==> Starting '$NAME'..."
vbox startvm "$NAME" --type "$FRONTEND" >/dev/null
echo "    running. Stop it with: $VBOXMANAGE controlvm $NAME poweroff"
