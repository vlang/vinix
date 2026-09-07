#!/bin/bash
# Deploy Vinix ARM64 boot files to an already-mounted EFI System Partition.
# Usage: ./deploy-m1-efi.sh [--apple-studio-display] [--desktop-initramfs] /path/to/mounted/esp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ESP_MOUNT=""
ENABLE_APPLE_GPU=0
USE_MINIMAL_INITRAMFS=0
USE_DESKTOP_INITRAMFS=0
USE_NATIVE_RESOLUTION=0
USE_EXTERNAL_DISPLAY=0
CMDLINE_EXTRA=""

for argument in "$@"; do
    case "$argument" in
        --apple-gpu)
            ENABLE_APPLE_GPU=1
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.apple_gpu=1"
            ;;
        --apple-dcp)
            # Experimental display-coprocessor probe. The current simplified
            # IOMFB transport does not create /dev/apple-panel-bl. Separate
            # from the GPU: probing one must not run the other's sequence.
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.apple_dcp=1"
            ;;
        --apple-battery)
            # Explicitly enable the read-only SMC battery client (it is also
            # the safe ARM64 default) behind /dev/battery.
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.apple_battery=1"
            ;;
        --apple-wifi)
            # The BCM4378 probe and /dev/wlan0 are deliberately opt-in because
            # the driver takes over PCIe/DART state left by the bootloader.
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.apple_wifi=1"
            ;;
        --apple-ans)
            # ANS2 storage: discovery, namespace reads and validated GPT views.
            # Read-only on its own -- writing needs --ans-rw to name a target.
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.apple_ans=1"
            ;;
        --ans-rw=*)
            # Authorises writes to exactly one Linux-data GPT partition, by
            # PARTUUID. Nothing else on the disk becomes writable, which is the
            # whole of what makes this safe to boot on a machine that still has
            # macOS on it. There is no default and there must not be one.
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.apple_ans=1 vinix.ans_rw=PARTUUID=${argument#*=}"
            ;;
        --ans-root=*)
            # Boot root from that partition instead of the initramfs, read-only.
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.apple_ans=1 vinix.root=PARTUUID=${argument#*=} vinix.rootfstype=ext2 vinix.rootmode=ro vinix.rootfallback=initramfs"
            ;;
        --all-drivers)
            # Enable every optional Apple subsystem in one switch. Battery is
            # already the safe default but remains explicit in this mode.
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.apple_gpu=1 vinix.apple_dcp=1 vinix.apple_battery=1 vinix.apple_wifi=1"
            ;;
        --native-resolution)
            # Drop the resolution request so Limine keeps whatever mode the
            # firmware already set. Apple Silicon's display is a fixed
            # framebuffer m1n1 programmed; U-Boot's GOP exposes essentially
            # that one mode, and asking for another blanks the panel at the
            # very moment Limine applies it, just before entering the kernel.
            USE_NATIVE_RESOLUTION=1
            ;;
        --apple-studio-display|--external-display)
            # Preserve the GOP scanout selected by iBoot/m1n1 and ask Vinix
            # to choose the largest output if firmware exposes more than one.
            # The native internal-panel DCP probe must stay off: it owns a
            # different connector and can reset the shared display fabric.
            USE_EXTERNAL_DISPLAY=1
            USE_NATIVE_RESOLUTION=1
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.display=external vinix.display_hotplug=1 vinix.display_coldplug=reboot vinix.apple_dcp=0"
            ;;
        --apple-display-hotplug)
            # Monitor both CD321x Type-C controllers. This is useful when
            # testing reconnect independently of GOP selection; it does not
            # enable the first-attach reboot policy.
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.display_hotplug=1"
            ;;
        --force-fault)
            # Self-test of the signal channel: fault on purpose and expect a
            # reboot. If the machine does not reboot, PSCI reset is missing
            # and a quiet machine proves nothing about the kernel.
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.force_fault=1"
            ;;
        --halt-at=*)
            # Power off once boot reaches this stage. On a machine with no
            # console and no usable framebuffer, "did it power off?" is the
            # only observable bit, so this turns each stage into a yes/no test.
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.halt_at=${argument#*=}"
            ;;
        --no-early-term)
            # Skip flanterm entirely. Its init clears the framebuffer, so a
            # hang at or just after it looks identical to a kernel that never
            # ran. Without it the stage bars survive and the bar count is the
            # last stage reached.
            CMDLINE_EXTRA="$CMDLINE_EXTRA vinix.no_early_term=1"
            ;;
        --desktop-initramfs)
            # Boot into the full userland image with desktop-init and
            # vinix-desktop overlaid by build-desktop-aarch64.sh.
            USE_DESKTOP_INITRAMFS=1
            ;;
        --minimal-initramfs)
            # Boot with a few-KB initramfs instead of the 120 MB busybox one.
            # If a hang at Limine's "Loading module" line clears with this, the
            # problem is reading the large module, not the kernel.
            USE_MINIMAL_INITRAMFS=1
            ;;
        --help|-h)
            echo "usage: $0 [--apple-studio-display|--external-display] [--apple-display-hotplug] [--apple-gpu] [--apple-dcp] [--apple-battery] [--apple-wifi] [--apple-ans] [--ans-rw=UUID] [--ans-root=UUID] [--all-drivers] [--minimal-initramfs] [--desktop-initramfs] [--no-early-term] [--halt-at=N] [--native-resolution] [--force-fault] <mounted_esp_path>"
            exit 0
            ;;
        --*)
            echo "error: unknown option: $argument" >&2
            exit 1
            ;;
        *)
            if [ -n "$ESP_MOUNT" ]; then
                echo "error: multiple ESP paths supplied" >&2
                exit 1
            fi
            ESP_MOUNT="$argument"
            ;;
    esac
done

if [ -z "$ESP_MOUNT" ]; then
    echo "usage: $0 [--apple-studio-display|--external-display] [--apple-display-hotplug] [options] <mounted_esp_path>"
    exit 1
fi

if [ ! -d "$ESP_MOUNT" ]; then
    echo "error: ESP mount path does not exist: $ESP_MOUNT"
    exit 1
fi

KERNEL="$SCRIPT_DIR/kernel/bin/vinix"
INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar"
MINIMAL_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs-minimal.tar"
DESKTOP_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs-desktop.tar"
LIMINE_EFI_BUILT="$SCRIPT_DIR/boot-image/limine-src-9.3.0/bin/BOOTAA64.EFI"
LIMINE_EFI_BIN="$SCRIPT_DIR/boot-image/limine-bin/BOOTAA64.EFI"
LIMINE_CONF="$SCRIPT_DIR/build-support/limine.conf"

if [ -f "$LIMINE_EFI_BUILT" ] && { [ ! -f "$LIMINE_EFI_BIN" ] || [ "$LIMINE_EFI_BUILT" -nt "$LIMINE_EFI_BIN" ]; }; then
    LIMINE_EFI="$LIMINE_EFI_BUILT"
else
    LIMINE_EFI="$LIMINE_EFI_BIN"
fi

if [ "$USE_DESKTOP_INITRAMFS" -eq 1 ]; then
    if [ ! -f "$DESKTOP_INITRAMFS" ]; then
        echo "error: desktop initramfs not built: $DESKTOP_INITRAMFS" >&2
        echo "hint: run ./build-desktop-aarch64.sh" >&2
        exit 1
    fi
    INITRAMFS="$DESKTOP_INITRAMFS"
    echo "using desktop initramfs ($(wc -c < "$INITRAMFS" | tr -d ' ') bytes)"
fi
if [ "$USE_MINIMAL_INITRAMFS" -eq 1 ]; then
    if [ ! -f "$MINIMAL_INITRAMFS" ]; then
        echo "error: minimal initramfs not built: $MINIMAL_INITRAMFS" >&2
        exit 1
    fi
    INITRAMFS="$MINIMAL_INITRAMFS"
    echo "using minimal initramfs ($(wc -c < "$INITRAMFS" | tr -d ' ') bytes)"
fi

for f in "$KERNEL" "$INITRAMFS" "$LIMINE_EFI" "$LIMINE_CONF"; do
    if [ ! -f "$f" ]; then
        echo "error: missing required file: $f"
        exit 1
    fi
done

echo "using limine EFI: $LIMINE_EFI"

# The upstream 9.3.0 loader cannot boot this kernel on Apple Silicon: its
# EL2-to-EL1 hand-off leaves FP/SIMD and the physical timer trapping to EL2
# on CPUs that keep VHE on. build-limine-aarch64.sh builds the patched one and
# stamps it with an instruction sequence the upstream binary does not contain.
if ! xxd -p "$LIMINE_EFI" | tr -d '\n' | grep -q "6806a0d248111cd5"; then
    echo "error: $LIMINE_EFI is the upstream Limine build, which black-screens on Apple Silicon" >&2
    echo "hint: run ./build-limine-aarch64.sh first" >&2
    exit 1
fi
echo "limine EFI is the Apple Silicon build (sha256 $(shasum -a 256 "$LIMINE_EFI" | cut -c1-16))"

RUNTIME_CONF="$(mktemp "${TMPDIR:-/tmp}/vinix-limine.XXXXXX")"
trap 'rm -f "$RUNTIME_CONF"' EXIT
CMDLINE_EXTRA="${CMDLINE_EXTRA# }"
if [ -n "$CMDLINE_EXTRA" ]; then
    awk -v extra="$CMDLINE_EXTRA" '
        /^[[:space:]]*cmdline:/ { found = 1; $0 = $0 " " extra }
        { print }
        END { if (!found) print "    cmdline: " extra }
    ' "$LIMINE_CONF" > "$RUNTIME_CONF"
    echo "kernel cmdline additions: $CMDLINE_EXTRA"
else
    cp "$LIMINE_CONF" "$RUNTIME_CONF"
fi

KERNEL_FILE_INFO="$(file -b "$KERNEL" || true)"
if ! echo "$KERNEL_FILE_INFO" | grep -Eiq 'ELF 64-bit'; then
    echo "error: kernel is not an ELF64 image: $KERNEL_FILE_INFO"
    exit 1
fi
if ! echo "$KERNEL_FILE_INFO" | grep -Eiq '(ARM aarch64|ARM64|AArch64)'; then
    echo "error: kernel is not AArch64: $KERNEL_FILE_INFO"
    echo "hint: rebuild with: make -C kernel ARCH=aarch64 CC=clang"
    exit 1
fi

mkdir -p "$ESP_MOUNT/EFI/BOOT"
mkdir -p "$ESP_MOUNT/boot"
mkdir -p "$ESP_MOUNT/limine"

if [ -f "$ESP_MOUNT/EFI/BOOT/BOOTAA64.EFI" ]; then
    cp "$ESP_MOUNT/EFI/BOOT/BOOTAA64.EFI" "$ESP_MOUNT/EFI/BOOT/BOOTAA64.EFI.bak"
fi

cp "$LIMINE_EFI" "$ESP_MOUNT/EFI/BOOT/BOOTAA64.EFI"
if [ "$USE_NATIVE_RESOLUTION" -eq 1 ]; then
    sed -i '' '/^[[:space:]]*resolution:/d' "$RUNTIME_CONF"
    echo "NATIVE RESOLUTION: no mode switch requested; Limine keeps the firmware's framebuffer"
fi
if [ "$USE_EXTERNAL_DISPLAY" -eq 1 ]; then
    echo "EXTERNAL DISPLAY: preserving firmware scanout; Vinix will select the largest GOP framebuffer"
fi

cp "$RUNTIME_CONF" "$ESP_MOUNT/boot/limine.conf"
cp "$RUNTIME_CONF" "$ESP_MOUNT/limine.conf"
cp "$RUNTIME_CONF" "$ESP_MOUNT/EFI/BOOT/limine.conf"
cp "$RUNTIME_CONF" "$ESP_MOUNT/limine/limine.conf"
# Refuse to start a copy that cannot finish. A half-written initramfs or
# kernel leaves the ESP looking deployed while the machine will not boot.
needed=$(( $(wc -c < "$KERNEL") + $(wc -c < "$INITRAMFS") ))
avail=$(df -k "$ESP_MOUNT" | awk 'NR==2 {print $4 * 1024}')
if [ -n "$avail" ] && [ "$avail" -lt "$needed" ]; then
    echo "error: ESP has ${avail} bytes free, needs ${needed}" >&2
    echo "hint: remove stale files from $ESP_MOUNT/boot" >&2
    exit 1
fi

cp "$KERNEL" "$ESP_MOUNT/boot/vinix"
cp "$INITRAMFS" "$ESP_MOUNT/boot/initramfs.tar"

sync

# Verify what actually landed. cp can fail silently enough that the next
# symptom is an unbootable machine rather than an error here.
verify_copy() {
    src="$1"
    dst="$2"
    if ! cmp -s "$src" "$dst"; then
        echo "error: $dst does not match $src after copy" >&2
        exit 1
    fi
}
verify_copy "$KERNEL" "$ESP_MOUNT/boot/vinix"
verify_copy "$INITRAMFS" "$ESP_MOUNT/boot/initramfs.tar"
verify_copy "$LIMINE_EFI" "$ESP_MOUNT/EFI/BOOT/BOOTAA64.EFI"

echo "Deployed Vinix boot files to: $ESP_MOUNT"

# Limine prints the ELF entry point on the boot screen. Printing it here too
# is the only easy way to confirm which build actually booted.
kernel_sha="$(shasum -a 256 "$KERNEL" | awk '{print $1}')"
# e_entry is the 8-byte little-endian field at offset 24 of the ELF64 header;
# od -tx8 already renders it host-order, so no byte swapping is needed.
kernel_entry="$(od -An -tx8 -j24 -N8 "$KERNEL" | tr -d ' \n')"
# Limine also prints how many protocol requests it found. Counting the request
# magic in the image gives the number to expect, so a stale kernel with a
# different request set is caught at the boot screen too.
kernel_requests="$(xxd -p "$KERNEL" | tr -d '\n' | grep -o '888b4cdf30ddb1c77bf094a183e8820a' | wc -l | tr -d ' ')"
echo "  kernel sha256: $kernel_sha"
echo "  kernel entry:  0x$kernel_entry"
echo "  kernel limine requests: $kernel_requests (Limine's 'Requests count' line)"
echo "  initramfs:     $(wc -c < "$INITRAMFS") bytes"
echo "Compare the entry point against Limine's 'ELF entry point' line at boot."
if [ "$USE_EXTERNAL_DISPLAY" -eq 1 ]; then
    cat <<'EXTERNAL_DISPLAY'

Apple Studio Display handoff is enabled. You can either boot with the display
already connected, or connect it after Vinix starts on the M1 Air panel. A
first post-boot connection causes one warm reboot; leave the cable attached so
iBoot/m1n1 can train the link. Clamshell mode is the most reliable way to make
firmware choose the Studio Display as its single output.

Vinix will print "framebuffer: selected GOP ... (external handoff)" once the
kernel owns the selected surface. Unplug/replug of an already handed-off
output is detected and repainted without another reboot.
EXTERNAL_DISPLAY
fi
