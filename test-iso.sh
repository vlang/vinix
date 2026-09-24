#!/bin/bash
# Boot Vinix ISOs the way a user would and check that they reach the desktop.
#
# Usage: ./test-iso.sh [options] ISO...
#
#   --no-qemu          skip the QEMU boots
#   --virtualbox       also boot each image in VirtualBox (the default when
#                      VBoxManage is installed and can run the image's
#                      architecture on this host)
#   --no-virtualbox    skip VirtualBox
#   --timeout=SECONDS  per boot (default: 240, or 900 without acceleration)
#   --out=DIR          serial logs and screenshots (default: a temporary dir)
#
# Each image is booted from a virtual CD with nothing but its own files:
#
#   amd64  QEMU, BIOS, i440fx, no HPET, one CPU (what VirtualBox gives a new VM)
#          QEMU, UEFI, q35, two CPUs
#          VirtualBox, BIOS                          (x86 hosts)
#   arm64  QEMU, UEFI, virt, virtio keyboard and tablet
#          QEMU, UEFI, virt, USB keyboard and tablet on xHCI
#          VirtualBox, EFI                           (arm64 hosts)
#
# A boot passes when the serial port says "Vinix: starting the desktop" (or,
# failing that, the screen does), a screenshot shows the desktop rather than a
# console, and typing and (outside VirtualBox, which cannot script its pointer)
# moving the pointer both change what is on the screen.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_QEMU=1
RUN_VBOX=auto
TIMEOUT=''
OUT=''
ISOS=()

usage() {
    sed -n '2,/^set -/s/^# \{0,1\}//p' "$0" | sed '$d'
}

for arg in "$@"; do
    case "$arg" in
        --no-qemu) RUN_QEMU=0 ;;
        --virtualbox) RUN_VBOX=1 ;;
        --no-virtualbox) RUN_VBOX=0 ;;
        --timeout=*) TIMEOUT="${arg#*=}" ;;
        --out=*) OUT="${arg#*=}" ;;
        --help|-h) usage; exit 0 ;;
        -*) echo "ERROR: unknown option: $arg" >&2; exit 1 ;;
        *) ISOS+=("$arg") ;;
    esac
done
if [ "${#ISOS[@]}" -eq 0 ]; then
    usage >&2
    exit 1
fi
OUT="${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/vinix-iso-test.XXXXXX")}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
CHECK="$SCRIPT_DIR/build-support/check-screenshot.py"

HOST_OS="$(uname -s)"
case "$(uname -m)" in
    x86_64|amd64) HOST_ARCH=amd64 ;;
    arm64|aarch64) HOST_ARCH=arm64 ;;
    *) HOST_ARCH=unknown ;;
esac

MARKER='Vinix: starting the (GPU-enabled )?desktop'
# What the boot test types into the first-run dialog, which has focus.
TEST_TEXT=vinixiso
FAILED=()
PASSED=()

# The VM under test. VM_KIND is qemu or virtualbox.
VM_KIND=''
VM_QMP=''
VM_NAME=''
VBOXMANAGE_BIN=''

iso_arch() {
    case "$(basename "$1")" in
        *amd64*|*x86_64*) echo amd64; return ;;
        *arm64*|*aarch64*) echo arm64; return ;;
    esac
    local listing
    listing="$(xorriso -indev "$1" -find /EFI/BOOT -name 'BOOT*.EFI' 2>/dev/null || true)"
    case "$listing" in
        *BOOTX64.EFI*) echo amd64 ;;
        *BOOTAA64.EFI*) echo arm64 ;;
        *) echo unknown ;;
    esac
}

qemu_firmware() {
    local qemu_bin="$1" name="$2" prefix candidate
    prefix="$(cd "$(dirname "$(command -v "$qemu_bin")")/.." && pwd)"
    shift 2
    for candidate in "$prefix/share/qemu/$name" "$@"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# Send QMP commands, one JSON object per argument, to the VM under test.
qmp() {
    python3 - "$VM_QMP" "$@" <<'PY'
import json, socket, sys
sock = socket.socket(socket.AF_UNIX)
sock.connect(sys.argv[1])
reader = sock.makefile('r')
reader.readline()
def command(request):
    sock.sendall(json.dumps(request).encode() + b'\n')
    while True:
        reply = json.loads(reader.readline())
        if 'return' in reply or 'error' in reply:
            return reply
command({'execute': 'qmp_capabilities'})
for request in sys.argv[2:]:
    reply = command(json.loads(request))
    if 'error' in reply:
        sys.exit(reply['error'].get('desc', 'QMP error'))
PY
}

# Save a screenshot of the VM under test to "$1" plus .ppm or .png.
vm_shoot() {
    rm -f "$1".ppm "$1".png
    if [ "$VM_KIND" = qemu ]; then
        qmp "{\"execute\":\"screendump\",\"arguments\":{\"filename\":\"$1.ppm\"}}"
    else
        "$VBOXMANAGE_BIN" controlvm "$VM_NAME" screenshotpng "$1.png"
    fi
}

vm_image() {
    if [ -f "$1.ppm" ]; then echo "$1.ppm"; else echo "$1.png"; fi
}

vm_type() {
    if [ "$VM_KIND" = qemu ]; then
        local c
        for ((i = 0; i < ${#1}; i++)); do
            c="${1:i:1}"
            qmp "{\"execute\":\"send-key\",\"arguments\":{\"keys\":[{\"type\":\"qcode\",\"data\":\"$c\"}]}}"
            sleep 0.15
        done
    else
        "$VBOXMANAGE_BIN" controlvm "$VM_NAME" keyboardputstring "$1"
    fi
}

# Move the pointer to the top left quarter: an absolute event for a tablet and
# a relative one for a mouse; each device takes the kind it understands.
vm_point() {
    qmp '{"execute":"input-send-event","arguments":{"events":[{"type":"abs","data":{"axis":"x","value":6000}},{"type":"abs","data":{"axis":"y","value":6000}}]}}' \
        2>/dev/null || true
    qmp '{"execute":"input-send-event","arguments":{"events":[{"type":"rel","data":{"axis":"x","value":-150}},{"type":"rel","data":{"axis":"y","value":-120}}]}}' \
        2>/dev/null || true
}

# Wait for the desktop marker, a screenshot that shows the desktop, and a
# screen that answers the keyboard and the pointer. `$1` names the boot, `$2`
# is its serial log, `$3` the PID of the VM (or 0).
check_boot() {
    local name="$1" serial="$2" pid="$3"
    local started=$SECONDS shot="$OUT/$name" verdict=''
    local deadline=$((started + TIMEOUT)) next_shot=$((started + 30)) drawn=0
    # The serial marker says the desktop was started. A VM whose serial port is
    # not logged anywhere never prints it, so a screenshot of the desktop counts
    # as well.
    while [ "$SECONDS" -lt "$deadline" ]; do
        if [ "$pid" != 0 ] && ! kill -0 "$pid" 2>/dev/null; then
            echo "    $name: the VM exited" >&2
            return 1
        fi
        grep -Eaq "$MARKER" "$serial" 2>/dev/null && break
        if [ "$SECONDS" -ge "$next_shot" ]; then
            next_shot=$((SECONDS + 10))
            if vm_shoot "$shot" >/dev/null 2>&1 &&
                verdict="$(python3 "$CHECK" "$(vm_image "$shot")")"; then
                drawn=1
                echo "    $name: no marker on serial, but the screen shows the desktop"
                break
            fi
        fi
        sleep 2
    done
    if [ "$drawn" -eq 0 ]; then
        if ! grep -Eaq "$MARKER" "$serial" 2>/dev/null; then
            echo "    $name: no desktop within ${TIMEOUT}s (${verdict:-no screenshot})" >&2
            vm_shoot "$shot-timeout" >/dev/null 2>&1 || true
            return 1
        fi
        echo "    $name: desktop started after $((SECONDS - started))s"
        while [ "$SECONDS" -lt "$deadline" ]; do
            sleep 10
            vm_shoot "$shot" >/dev/null 2>&1 || continue
            if verdict="$(python3 "$CHECK" "$(vm_image "$shot")")"; then
                drawn=1
                break
            fi
        done
    fi
    if [ "$drawn" -eq 0 ]; then
        echo "    $name: the screen never showed the desktop (${verdict:-no screenshot})" >&2
        return 1
    fi
    echo "    $name: $verdict after $((SECONDS - started))s"

    # Let the first-run dialog settle, then type into it.
    sleep 5
    vm_shoot "$shot-before" >/dev/null
    vm_type "$TEST_TEXT"
    sleep 4
    vm_shoot "$shot-typed" >/dev/null
    if ! verdict="$(python3 "$CHECK" --changed "$(vm_image "$shot-before")" "$(vm_image "$shot-typed")" 120)"; then
        echo "    $name: typing did not reach the desktop ($verdict)" >&2
        return 1
    fi
    echo "    $name: keyboard: $verdict"
    if [ "$VM_KIND" = qemu ]; then
        vm_point
        sleep 4
        vm_shoot "$shot-pointer" >/dev/null
        if ! verdict="$(python3 "$CHECK" --changed "$(vm_image "$shot-typed")" "$(vm_image "$shot-pointer")" 120)"; then
            echo "    $name: the pointer did not move ($verdict)" >&2
            return 1
        fi
        echo "    $name: pointer: $verdict"
    fi
    return 0
}

run_qemu_boot() {
    local name="$1" qemu_bin="$2"
    shift 2
    local dir="$OUT/$name" pid status=0
    rm -rf "$dir"
    mkdir -p "$dir"
    echo "==> $name"
    "$qemu_bin" "$@" \
        -display none -no-reboot \
        -serial "file:$dir/serial.log" \
        -qmp "unix:$dir/qmp.sock,server,nowait" \
        > "$dir/qemu.log" 2>&1 &
    pid=$!
    for _ in $(seq 1 50); do
        [ -S "$dir/qmp.sock" ] && break
        sleep 0.1
    done
    VM_KIND=qemu
    VM_QMP="$dir/qmp.sock"
    check_boot "$name" "$dir/serial.log" "$pid" || status=1
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    if [ "$status" -eq 0 ]; then
        PASSED+=("$name")
    else
        FAILED+=("$name (see $dir)")
    fi
}

qemu_amd64() {
    local iso="$1" qemu_bin="${VINIX_QEMU_X86_64:-qemu-system-x86_64}" accel=() ovmf
    if ! command -v "$qemu_bin" >/dev/null 2>&1; then
        FAILED+=("qemu-amd64 ($qemu_bin not installed)")
        return
    fi
    if [ -w /dev/kvm ]; then
        accel=(-accel kvm -cpu host)
    elif [ "$HOST_OS" = Darwin ] && [ "$HOST_ARCH" = amd64 ]; then
        accel=(-accel hvf -cpu host)
    else
        accel=(-accel tcg -cpu max)
    fi
    run_qemu_boot qemu-amd64-bios "$qemu_bin" "${accel[@]}" \
        -machine pc,hpet=off -m 4096 -smp 1 -vga std -cdrom "$iso"
    if ovmf="$(qemu_firmware "$qemu_bin" edk2-x86_64-code.fd \
        /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.fd \
        /usr/share/qemu/OVMF.fd)"; then
        run_qemu_boot qemu-amd64-uefi "$qemu_bin" "${accel[@]}" \
            -machine q35 -m 4096 -smp 2 -vga std \
            -drive "if=pflash,format=raw,unit=0,readonly=on,file=$ovmf" \
            -cdrom "$iso"
    else
        FAILED+=("qemu-amd64-uefi (no x86_64 UEFI firmware found)")
    fi
}

qemu_arm64() {
    local iso="$1" qemu_bin="${VINIX_QEMU_AARCH64:-qemu-system-aarch64}" accel=() code template
    if ! command -v "$qemu_bin" >/dev/null 2>&1; then
        FAILED+=("qemu-arm64 ($qemu_bin not installed)")
        return
    fi
    if [ "$HOST_OS" = Darwin ] && [ "$HOST_ARCH" = arm64 ]; then
        accel=(-accel hvf -cpu host)
    elif [ "$HOST_ARCH" = arm64 ] && [ -w /dev/kvm ]; then
        accel=(-accel kvm -cpu host)
    else
        accel=(-accel tcg -cpu max)
    fi
    if ! code="$(qemu_firmware "$qemu_bin" edk2-aarch64-code.fd \
        /usr/share/AAVMF/AAVMF_CODE.fd /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
        /usr/share/edk2/aarch64/QEMU_EFI.fd)"; then
        FAILED+=("qemu-arm64 (no aarch64 UEFI firmware found)")
        return
    fi
    template="$(qemu_firmware "$qemu_bin" edk2-arm-vars.fd /usr/share/AAVMF/AAVMF_VARS.fd || true)"
    local input name vars
    for input in virtio usb; do
        name="qemu-arm64-$input"
        vars="$OUT/$name-vars.fd"
        if [ -n "$template" ]; then
            cp "$template" "$vars"
        else
            dd if=/dev/zero of="$vars" bs=1048576 count=64 2>/dev/null
        fi
        local devices=(-device virtio-keyboard-device -device virtio-tablet-device)
        if [ "$input" = usb ]; then
            devices=(-device qemu-xhci,id=xhci -device usb-kbd,bus=xhci.0
                -device usb-tablet,bus=xhci.0)
        fi
        run_qemu_boot "$name" "$qemu_bin" "${accel[@]}" \
            -machine virt -m 4096 -smp 4 \
            -drive "if=pflash,format=raw,readonly=on,file=$code" \
            -drive "if=pflash,format=raw,file=$vars" \
            -device virtio-scsi-pci,id=scsi0 \
            -drive "if=none,id=cd0,media=cdrom,readonly=on,file=$iso" \
            -device scsi-cd,drive=cd0,bus=scsi0.0 \
            -device ramfb "${devices[@]}"
    done
}

find_vboxmanage() {
    local candidate
    for candidate in "${VBOXMANAGE:-}" "$(command -v VBoxManage 2>/dev/null || true)" \
        /Applications/VirtualBox.app/Contents/MacOS/VBoxManage; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

virtualbox_boot() {
    local iso="$1" arch="$2"
    local name="virtualbox-$arch" dir status=0
    dir="$OUT/$name"
    rm -rf "$dir"
    mkdir -p "$dir"
    echo "==> $name"
    VM_KIND=virtualbox
    VM_NAME="vinix-test-$arch"
    if ! VBOXMANAGE="$VBOXMANAGE_BIN" "$SCRIPT_DIR/run-iso-virtualbox.sh" --headless \
        --name="$VM_NAME" --arch="$arch" --serial="$dir/serial.log" "$iso" \
        > "$dir/virtualbox.log" 2>&1; then
        cat "$dir/virtualbox.log" >&2
        FAILED+=("$name (the VM did not start; see $dir)")
        return
    fi
    check_boot "$name" "$dir/serial.log" 0 || status=1
    "$VBOXMANAGE_BIN" controlvm "$VM_NAME" poweroff >/dev/null 2>&1 || true
    for _ in $(seq 1 10); do
        "$VBOXMANAGE_BIN" unregistervm "$VM_NAME" --delete >/dev/null 2>&1 && break
        sleep 1
    done
    if [ "$status" -eq 0 ]; then
        PASSED+=("$name")
    else
        FAILED+=("$name (see $dir)")
    fi
}

for iso in "${ISOS[@]}"; do
    if [ ! -f "$iso" ]; then
        FAILED+=("$iso (not found)")
        continue
    fi
    iso="$(cd "$(dirname "$iso")" && pwd)/$(basename "$iso")"
    arch="$(iso_arch "$iso")"
    echo "==> Testing $(basename "$iso") ($arch)"
    default_timeout=0
    if [ -z "$TIMEOUT" ]; then
        default_timeout=1
        if [ "$arch" = "$HOST_ARCH" ]; then TIMEOUT=240; else TIMEOUT=900; fi
    fi

    if [ "$RUN_QEMU" -eq 1 ]; then
        case "$arch" in
            amd64) qemu_amd64 "$iso" ;;
            arm64) qemu_arm64 "$iso" ;;
            *) FAILED+=("$iso (neither amd64 nor arm64)") ;;
        esac
    fi

    if [ "$RUN_VBOX" != 0 ]; then
        if [ "$arch" != "$HOST_ARCH" ]; then
            if [ "$RUN_VBOX" = 1 ]; then
                echo "    virtualbox-$arch: skipped, VirtualBox cannot run $arch guests on a $HOST_ARCH host"
            fi
        elif VBOXMANAGE_BIN="$(find_vboxmanage)"; then
            virtualbox_boot "$iso" "$arch"
        elif [ "$RUN_VBOX" = 1 ]; then
            FAILED+=("virtualbox-$arch (VBoxManage not found)")
        fi
    fi
    if [ "$default_timeout" -eq 1 ]; then
        TIMEOUT=''
    fi
done

echo
echo "Logs and screenshots: $OUT"
for boot in ${PASSED[@]+"${PASSED[@]}"}; do
    echo "  PASS  $boot"
done
for boot in ${FAILED[@]+"${FAILED[@]}"}; do
    echo "  FAIL  $boot"
done
if [ "${#FAILED[@]}" -ne 0 ] || [ "${#PASSED[@]}" -eq 0 ]; then
    exit 1
fi
