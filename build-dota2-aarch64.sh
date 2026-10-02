#!/bin/bash
# Stage the translated Linux Dota 2 runtime. Valve's game files stay separate.
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd)
build=${VINIX_DOTA2_BUILD_DIR:-$repo/build/dota2-runtime}
steam_build=${VINIX_STEAM_BUILD_DIR:-$repo/build-aarch64-steam}
qemu_build=${VINIX_DOTA2_QEMU_BUILD_DIR:-$build/qemu}

case "${1:-}" in
    '') ;;
    --help|-h)
        echo "usage: $0"
        echo "Stages the private x86-64 glibc/Vulkan runtime and run-dota2."
        echo "First build Steam's library layer with ./build-steam-aarch64.sh."
        echo "VINIX_DOTA2_BUILD_DIR and VINIX_STEAM_BUILD_DIR override the builds."
        echo "VINIX_DOTA2_QEMU_BUILD_DIR overrides the native translator build cache."
        exit 0
        ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { echo 'unexpected arguments' >&2; exit 2; }

python3 "$repo/build-support/dota2/vulkan-stage.py" \
    --steam-build "$steam_build" --build "$build" \
    --mirror "${DEBIAN_MIRROR:-https://deb.debian.org/debian}" \
    --release "${VINIX_STEAM_DEBIAN_RELEASE:-bookworm}"
python3 "$repo/build-support/dota2/qemu-stage.py" \
    --work "$qemu_build" --staging "$build/staging"
mkdir -p "$build/staging/usr/bin"
install -m755 "$repo/build-support/dota2/run-dota2" "$build/staging/usr/bin/run-dota2"
echo "Dota 2 runtime staged in $build/staging"
echo "The Linux game installation must be supplied separately."
