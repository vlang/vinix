#!/bin/bash
# Build the amd64 and arm64 Vinix ISOs, boot-test them, and publish them as a
# GitHub release.
#
# Usage: ./deploy-iso.sh [options]
#
#   --tag=TAG          release tag (default: iso-YYYY-MM-DD, then -2, -3, ...)
#   --ref=REF          commit to release (default: HEAD); it must be pushed
#   --arch=LIST        amd64, arm64, or amd64,arm64 (default)
#   --draft            create the release as a draft
#   --prerelease       mark the release as a pre-release
#   --no-test          do not boot-test the images first
#   --no-publish       build (and test) only
#   --yes              publish without asking
#   --repo=OWNER/NAME  GitHub repository (default: the one gh picks for this checkout)
#
# The images are built from a clean checkout of REF in build-release/work/src,
# so uncommitted changes in this tree never end up in a release. What is not
# source -- the Alpine package layers the arm64 desktop is assembled from,
# ui2, the V compiler -- comes from this checkout and the environment, as for
# the regular build scripts; set V to pick a compiler.
#
# Outputs, in build-release/TAG:
#
#   vinix-amd64.iso   boots through BIOS or UEFI, from a CD or a disk
#   vinix-arm64.iso   boots through UEFI
#   SHA256SUMS
#   RELEASE_NOTES.md  what the release page says
#   test/             serial logs and screenshots from test-iso.sh
#
# The asset names do not change between releases, so
# https://github.com/OWNER/NAME/releases/latest/download/vinix-arm64.iso always
# names the newest image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TAG=''
REF=HEAD
ARCHES=amd64,arm64
DRAFT=0
PRERELEASE=0
RUN_TESTS=1
PUBLISH=1
ASSUME_YES=0
REPO=''

usage() {
    sed -n '2,/^set -/s/^# \{0,1\}//p' "$0" | sed '$d'
}

for arg in "$@"; do
    case "$arg" in
        --tag=*) TAG="${arg#*=}" ;;
        --ref=*) REF="${arg#*=}" ;;
        --arch=*) ARCHES="${arg#*=}" ;;
        --draft) DRAFT=1 ;;
        --prerelease) PRERELEASE=1 ;;
        --no-test) RUN_TESTS=0 ;;
        --no-publish) PUBLISH=0 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --repo=*) REPO="${arg#*=}" ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: unknown option: $arg" >&2; exit 1 ;;
    esac
done

BUILD_AMD64=0
BUILD_ARM64=0
IFS=, read -r -a arch_list <<< "$ARCHES"
for arch in "${arch_list[@]}"; do
    case "$arch" in
        amd64|x86_64) BUILD_AMD64=1 ;;
        arm64|aarch64) BUILD_ARM64=1 ;;
        *) echo "ERROR: unknown architecture: $arch" >&2; exit 1 ;;
    esac
done

step() {
    echo
    echo "==> $*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

need() {
    local command_name
    for command_name in "$@"; do
        command -v "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
    done
}

human_size() {
    python3 -c 'import sys; n = float(sys.argv[1])
for unit in ("bytes", "KiB", "MiB", "GiB"):
    if n < 1024 or unit == "GiB":
        print(f"{n:.0f} {unit}" if unit == "bytes" else f"{n:.1f} {unit}")
        break
    n /= 1024' "$1"
}

file_size() {
    wc -c < "$1" | tr -d ' '
}

# ── What to build ──────────────────────────────────────────────────────────

need git python3 curl clang ld.lld xorriso cc rsync
cd "$SCRIPT_DIR"
COMMIT="$(git rev-parse --verify "$REF^{commit}")" || die "no such commit: $REF"
SHORT="$(git rev-parse --short=10 "$COMMIT")"
if [ "$REF" = HEAD ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "NOTE: this checkout has uncommitted changes; the release is built from $SHORT without them."
fi

if [ "$PUBLISH" -eq 1 ]; then
    need gh
    gh auth status >/dev/null 2>&1 || die "gh is not logged in; run: gh auth login"
    if [ -z "$REPO" ]; then
        REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" || die "cannot tell which GitHub repository this is; pass --repo"
    fi
    # A release is created at a commit GitHub already has. Pushing is left to
    # whoever runs this.
    if ! gh api "repos/$REPO/commits/$COMMIT" --silent >/dev/null 2>&1; then
        die "$SHORT is not on github.com/$REPO yet; push it first"
    fi
fi

release_exists() {
    [ "$PUBLISH" -eq 1 ] && gh release view "$1" --repo "$REPO" >/dev/null 2>&1
}

if [ -z "$TAG" ]; then
    base_tag="iso-$(date +%Y-%m-%d)"
    TAG="$base_tag"
    n=2
    while release_exists "$TAG"; do
        TAG="$base_tag-$n"
        n=$((n + 1))
    done
elif release_exists "$TAG"; then
    die "release $TAG already exists on $REPO"
fi

OUT="$SCRIPT_DIR/build-release/$TAG"
WORK="$SCRIPT_DIR/build-release/work"
CACHE="$SCRIPT_DIR/build-release/cache"
SRC="$WORK/src"
mkdir -p "$OUT" "$WORK" "$CACHE"

. "$SCRIPT_DIR/build-support/find-v.sh"
if [ -n "${VINIX_UI2_SOURCE:-}" ]; then
    UI2_SOURCE="$VINIX_UI2_SOURCE"
elif [ -f "$SCRIPT_DIR/../ui2/v.mod" ]; then
    UI2_SOURCE="$(cd "$SCRIPT_DIR/../ui2" && pwd)"
else
    UI2_SOURCE="$SCRIPT_DIR/third_party/ui2"
fi
[ -f "$UI2_SOURCE/v.mod" ] || die "ui2 not found at $UI2_SOURCE; clone it: git clone https://github.com/vlang/ui2 third_party/ui2"

echo "Release $TAG from $SHORT ($(git log -1 --format=%s "$COMMIT"))"
echo "  V:   $V ($("$V" version 2>/dev/null || echo 'version unknown'))"
echo "  ui2: $UI2_SOURCE"
echo "  out: $OUT"

# ── A clean tree at the release commit ─────────────────────────────────────

step "Checking out $SHORT in $SRC"
if [ -e "$SRC/.git" ]; then
    git -C "$SRC" checkout --quiet --detach --force "$COMMIT"
else
    rm -rf "$SRC"
    git worktree prune
    git worktree add --quiet --detach "$SRC" "$COMMIT"
fi
# The kernel's pinned C dependencies. Start from this checkout's copies, if it
# has them, and let get-deps move them to whatever the release commit pins.
for dependency in freestnd-c-hdrs cc-runtime c/flanterm c/uacpi uacpi-repository \
    lwip-repository c/lwip; do
    if [ -d "$SCRIPT_DIR/kernel/$dependency" ]; then
        mkdir -p "$SRC/kernel/$dependency"
        rsync -a --delete "$SCRIPT_DIR/kernel/$dependency/" "$SRC/kernel/$dependency/"
    fi
done
cp -f "$SCRIPT_DIR"/kernel/c/nanoprintf* "$SRC/kernel/c/" 2>/dev/null || true
(cd "$SRC/kernel" && ./get-deps) > "$WORK/get-deps.log" 2>&1 || {
    tail -20 "$WORK/get-deps.log" >&2
    die "fetching the kernel's dependencies failed"
}

# Release kernels are production builds.
unset PROD
export V

IMAGES=()

# ── amd64 ──────────────────────────────────────────────────────────────────

if [ "$BUILD_AMD64" -eq 1 ]; then
    step "Building the amd64 image"
    rm -f "$OUT/vinix-amd64.iso"
    VINIX_UI2_SOURCE="$UI2_SOURCE" \
    VINIX_AMD64_DESKTOP_BUILD_DIR="$WORK/amd64-desktop" \
    VINIX_AMD64_USERLAND_BUILD_DIR="$CACHE/amd64-userland" \
    VINIX_AMD64_BUILD_DIR="$WORK/amd64-kernel" \
    VINIX_AMD64_DESKTOP_ISO="$OUT/vinix-amd64.iso" \
        "$SRC/build-desktop-amd64.sh"
    [ -f "$OUT/vinix-amd64.iso" ] || die "the amd64 build made no ISO"
    IMAGES+=("$OUT/vinix-amd64.iso")
fi

# ── arm64 ──────────────────────────────────────────────────────────────────

if [ "$BUILD_ARM64" -eq 1 ]; then
    step "Building the arm64 image"
    # The desktop is assembled from package layers built by their own
    # scripts. They hold Alpine's and upstream binaries rather than Vinix
    # source, so this checkout's copies are used as they are.
    layer_missing=0
    check_layer() {
        if [ ! -e "$1" ]; then
            echo "  missing: $1 (build it with $2)" >&2
            layer_missing=1
        fi
    }
    check_layer "$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar" ./build-aarch64.sh
    check_layer "$SCRIPT_DIR/build-aarch64-userland/staging" ./build-aarch64.sh
    check_layer "$SCRIPT_DIR/build-aarch64-x11/staging" ./build-x11-aarch64.sh
    check_layer "$SCRIPT_DIR/build-aarch64-network-tools/staging" ./build-network-tools-aarch64.sh
    check_layer "$SCRIPT_DIR/build-aarch64-python/staging" ./build-python-aarch64.sh
    check_layer "$SCRIPT_DIR/build-aarch64-v/staging" ./build-v-aarch64.sh
    check_layer "$SCRIPT_DIR/build-aarch64-firefox/staging" ./build-firefox-aarch64.sh
    [ "$layer_missing" -eq 0 ] || die "build the missing layers in $SCRIPT_DIR first"

    mkdir -p "$SRC/build-support/init-aarch64"
    ln -sf "$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar" \
        "$SRC/build-support/init-aarch64/initramfs.tar"

    VINIX_AARCH64_BUILD_DIR="$WORK/arm64-kernel" \
        "$SRC/build-aarch64.sh" --no-userland --no-iso

    VINIX_UI2_SOURCE="$UI2_SOURCE" \
    VINIX_AARCH64_USERLAND_BUILD_DIR="$SCRIPT_DIR/build-aarch64-userland" \
    VINIX_AARCH64_APP_CACHE="$CACHE/arm64-desktop-apps" \
    VINIX_PYTHON_STAGING="$SCRIPT_DIR/build-aarch64-python/staging" \
    VINIX_NETWORK_TOOLS_STAGING="$SCRIPT_DIR/build-aarch64-network-tools/staging" \
    VINIX_VLANG_STAGING="$SCRIPT_DIR/build-aarch64-v/staging" \
    VINIX_X11_STAGING="$SCRIPT_DIR/build-aarch64-x11/staging" \
    VINIX_FIREFOX_STAGING="$SCRIPT_DIR/build-aarch64-firefox/staging" \
    VINIX_GPU_SYSROOT="$SCRIPT_DIR/build-aarch64-x11/sysroot" \
    VINIX_DESKTOP_INITRAMFS="$WORK/arm64-initramfs-desktop.tar" \
        "$SRC/build-desktop-aarch64.sh" --compact-initramfs

    rm -f "$OUT/vinix-arm64.iso"
    VINIX_AARCH64_KERNEL="$WORK/arm64-kernel/bin/vinix" \
    VINIX_AARCH64_INITRAMFS="$WORK/arm64-initramfs-desktop.tar" \
    VINIX_AARCH64_ISO="$OUT/vinix-arm64.iso" \
    VINIX_AARCH64_ISO_BUILD_DIR="$WORK/arm64-iso" \
        "$SRC/build-support/build-aarch64-iso.sh"
    IMAGES+=("$OUT/vinix-arm64.iso")
fi

[ "${#IMAGES[@]}" -gt 0 ] || die "nothing was built"
for image in "${IMAGES[@]}"; do
    # GitHub refuses release assets of 2 GiB or more.
    if [ "$(file_size "$image")" -ge 2147483648 ]; then
        die "$(basename "$image") is $(human_size "$(file_size "$image")"), over GitHub's 2 GiB asset limit"
    fi
done

# ── Boot tests ─────────────────────────────────────────────────────────────

TEST_SUMMARY=''
if [ "$RUN_TESTS" -eq 1 ]; then
    step "Boot-testing the images"
    rm -rf "$OUT/test"
    if ! "$SRC/test-iso.sh" --out="$OUT/test" "${IMAGES[@]}" | tee "$OUT/test.log"; then
        die "the boot tests failed; nothing was published (logs in $OUT/test)"
    fi
    TEST_SUMMARY="$(sed -n 's/^  PASS  //p' "$OUT/test.log")"
fi

# ── Checksums and notes ────────────────────────────────────────────────────

step "Writing checksums and release notes"
sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"
    fi
}
(cd "$OUT" && sha256 $(for image in "${IMAGES[@]}"; do basename "$image"; done) > SHA256SUMS)
cat "$OUT/SHA256SUMS"

describe_boot() {
    case "$1" in
        qemu-amd64-bios) echo "QEMU, BIOS (i440fx, no HPET, one CPU: VirtualBox's defaults)" ;;
        qemu-amd64-uefi) echo "QEMU, UEFI (q35)" ;;
        qemu-arm64-virtio) echo "QEMU, UEFI (virt, virtio keyboard and tablet)" ;;
        qemu-arm64-usb) echo "QEMU, UEFI (virt, USB keyboard and tablet)" ;;
        virtualbox-amd64) echo "VirtualBox, BIOS" ;;
        virtualbox-arm64) echo "VirtualBox, EFI" ;;
        *) echo "$1" ;;
    esac
}

{
    echo "Vinix built from $COMMIT ($(git log -1 --format=%cs "$COMMIT")). Both images boot"
    echo "into the Vinix desktop."
    echo
    echo "| Image | Size | Runs on |"
    echo "|---|---|---|"
    for image in "${IMAGES[@]}"; do
        name="$(basename "$image")"
        size="$(human_size "$(file_size "$image")")"
        case "$name" in
            *amd64*) echo "| [$name](https://github.com/${REPO:-vlang/vinix}/releases/download/$TAG/$name) | $size | x86-64: QEMU, VirtualBox on Intel and AMD hosts, PCs (BIOS or UEFI) |" ;;
            *arm64*) echo "| [$name](https://github.com/${REPO:-vlang/vinix}/releases/download/$TAG/$name) | $size | arm64: QEMU, VirtualBox on Apple Silicon Macs (UEFI) |" ;;
        esac
    done
    echo
    echo "The whole system is loaded into memory, so give the VM **at least 4 GB**."
    echo "Nothing is written to disk: a reboot starts from a clean image."
    echo
    echo "### QEMU"
    echo
    echo '```sh'
    echo '# amd64 (use -accel kvm -cpu host on Linux, -accel hvf on an Intel Mac)'
    echo 'qemu-system-x86_64 -machine q35 -m 4096 -smp 2 -cdrom vinix-amd64.iso'
    echo
    echo '# arm64 (use -accel kvm on an arm64 Linux host)'
    echo 'qemu-system-aarch64 -machine virt -accel hvf -cpu host -m 4096 -smp 4 \'
    echo '    -bios "$(brew --prefix qemu)/share/qemu/edk2-aarch64-code.fd" \'
    echo '    -device virtio-scsi-pci -device scsi-cd,drive=cd \'
    echo '    -drive if=none,id=cd,media=cdrom,file=vinix-arm64.iso \'
    echo '    -device ramfb -device qemu-xhci -device usb-kbd -device usb-tablet'
    echo '```'
    echo
    echo "### VirtualBox"
    echo
    echo "VirtualBox runs guests of its host's architecture: the amd64 image on Intel and"
    echo "AMD machines, the arm64 image on Apple Silicon Macs."
    echo
    echo "Create a VM of type **Other/Unknown (64-bit)** or **Other/Unknown (ARM 64-bit)**,"
    echo "give it **4096 MB** of memory and two CPUs, skip the hard disk, and attach the ISO"
    echo "to its optical drive. Everything else can stay as VirtualBox sets it; the amd64"
    echo "image boots with EFI switched on or off. From a checkout of this repository,"
    echo "\`./run-iso-virtualbox.sh vinix-arm64.iso\` creates and starts such a VM."
    if [ -n "$TEST_SUMMARY" ]; then
        echo
        echo "### Tested before release"
        echo
        echo "Booted from the images above to the desktop, with typing and the pointer checked:"
        echo
        while IFS= read -r boot; do
            [ -n "$boot" ] && echo "- $(describe_boot "$boot")"
        done <<< "$TEST_SUMMARY"
    fi
    echo
    echo "SHA-256 checksums are in \`SHA256SUMS\`."
} > "$OUT/RELEASE_NOTES.md"

if [ "$PUBLISH" -eq 0 ]; then
    step "Done; not publishing (--no-publish)"
    echo "Images and notes are in $OUT"
    exit 0
fi

# ── Publish ────────────────────────────────────────────────────────────────

step "Publishing $TAG to github.com/$REPO"
kind=release
[ "$PRERELEASE" -eq 1 ] && kind=pre-release
[ "$DRAFT" -eq 1 ] && kind="draft $kind"
echo "  $kind $TAG at $SHORT, with:"
for image in "${IMAGES[@]}"; do
    echo "    $(basename "$image") ($(human_size "$(file_size "$image")"))"
done
echo "    SHA256SUMS"
if [ "$ASSUME_YES" -ne 1 ]; then
    if [ ! -t 0 ]; then
        die "not a terminal; pass --yes to publish without asking"
    fi
    read -r -p "Publish? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Not published. Everything is in $OUT"; exit 0 ;;
    esac
fi

create_args=(release create "$TAG" --repo "$REPO" --target "$COMMIT"
    --title "Vinix $TAG" --notes-file "$OUT/RELEASE_NOTES.md")
[ "$DRAFT" -eq 1 ] && create_args+=(--draft)
[ "$PRERELEASE" -eq 1 ] && create_args+=(--prerelease)
gh "${create_args[@]}" "${IMAGES[@]}" "$OUT/SHA256SUMS"

step "Published"
gh release view "$TAG" --repo "$REPO" --json url --jq .url
