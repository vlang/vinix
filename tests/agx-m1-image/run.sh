#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
checker="$repo/build-support/check-m1-gpu-image.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/vinix-m1-image-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
root="$work/root"

mkdir -p "$root/lib" "$root/usr/bin" "$root/usr/lib/dri" \
    "$root/usr/share/examples/gl-triangle" "$root/usr/share/vinix" \
    "$root/usr/lib/firefox-esr"
for path in \
    lib/ld-musl-aarch64.so.1 \
    usr/bin/gl-triangle-agx \
    usr/bin/run-gl-triangle-agx \
    usr/lib/dri/libdril_dri.so \
    usr/lib/libEGL.so.1 \
    usr/lib/libGLESv2.so.2 \
    usr/lib/libgbm.so.1 \
    usr/lib/libvinix-agx-fault.so \
    usr/lib/libgallium-25.0.5.so \
    usr/share/examples/gl-triangle/egl_triangle.c; do
    : > "$root/$path"
done
ln -s libdril_dri.so "$root/usr/lib/dri/asahi_dri.so"
printf '%s\n' \
    'mesa=25.0.5 drivers=asahi,virgl,softpipe platforms=x11,surfaceless gbm=enabled' \
    > "$root/usr/share/vinix/asahi-x11-egl"
tar --format=ustar -cf "$work/gpu.tar" -C "$root" .
"$checker" --triangle-source \
    "$root/usr/share/examples/gl-triangle/egl_triangle.c" "$work/gpu.tar"

for path in usr/bin/vinix-desktop-gpu usr/bin/Xorg usr/bin/Xvfb \
    usr/bin/startx usr/bin/run-firefox usr/bin/firefox-esr \
    usr/lib/firefox-esr/firefox-esr; do
    : > "$root/$path"
done
tar --format=ustar -cf "$work/desktop.tar" -C "$root" .
"$checker" --desktop "$work/desktop.tar"

printf '%s\n' 'stale source' > "$work/expected-triangle.c"
if "$checker" --triangle-source "$work/expected-triangle.c" \
    "$work/gpu.tar" >/dev/null 2>&1; then
    echo "M1 image test: checker accepted stale in-image triangle source" >&2
    exit 1
fi

mv "$root/usr/lib/libgallium-25.0.5.so" "$work/libgallium.saved"
tar --format=ustar -cf "$work/missing.tar" -C "$root" .
if "$checker" "$work/missing.tar" >/dev/null 2>&1; then
    echo "M1 image test: checker accepted an image without libgallium" >&2
    exit 1
fi
mv "$work/libgallium.saved" "$root/usr/lib/libgallium-25.0.5.so"

printf '%s\n' \
    'mesa=25.0.5 drivers=virgl,softpipe platforms=x11,surfaceless gbm=enabled' \
    > "$root/usr/share/vinix/asahi-x11-egl"
tar --format=ustar -cf "$work/wrong-driver.tar" -C "$root" .
if "$checker" "$work/wrong-driver.tar" >/dev/null 2>&1; then
    echo "M1 image test: checker accepted a non-Asahi Mesa marker" >&2
    exit 1
fi

echo "M1 GPU image preflight tests: PASS"
