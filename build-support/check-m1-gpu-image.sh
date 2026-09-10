#!/bin/bash
# Validate the exact kernel/userspace payload required for a native M1 AGX
# test. This intentionally checks the selected initramfs rather than a host
# staging tree: only the archive copied to the ESP matters on hardware.
set -euo pipefail

DESKTOP=0
KERNEL=""
IMAGE=""
TRIANGLE_SOURCE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --desktop)
            DESKTOP=1
            shift
            ;;
        --kernel)
            if [ "$#" -lt 2 ]; then
                echo "error: --kernel needs a path" >&2
                exit 2
            fi
            KERNEL="$2"
            shift 2
            ;;
        --triangle-source)
            if [ "$#" -lt 2 ]; then
                echo "error: --triangle-source needs a path" >&2
                exit 2
            fi
            TRIANGLE_SOURCE="$2"
            shift 2
            ;;
        --help|-h)
            echo "usage: $0 [--desktop] [--kernel PATH] [--triangle-source PATH] <initramfs.tar>"
            exit 0
            ;;
        --*)
            echo "error: unknown option: $1" >&2
            exit 2
            ;;
        *)
            if [ -n "$IMAGE" ]; then
                echo "error: multiple initramfs paths supplied" >&2
                exit 2
            fi
            IMAGE="$1"
            shift
            ;;
    esac
done

if [ -z "$IMAGE" ] || [ ! -f "$IMAGE" ]; then
    echo "error: M1 GPU initramfs is missing: ${IMAGE:-<none>}" >&2
    exit 1
fi

MANIFEST="$(mktemp "${TMPDIR:-/tmp}/vinix-m1-gpu-manifest.XXXXXX")"
ARCHIVED_SOURCE="$(mktemp "${TMPDIR:-/tmp}/vinix-m1-gpu-source.XXXXXX")"
trap 'rm -f "$MANIFEST" "$ARCHIVED_SOURCE"' EXIT
if ! tar -tf "$IMAGE" | sed 's#^\./##' > "$MANIFEST"; then
    echo "error: cannot read initramfs archive: $IMAGE" >&2
    exit 1
fi

missing=0
require_path() {
    if ! grep -Fqx "$1" "$MANIFEST"; then
        echo "error: M1 GPU image is missing /$1" >&2
        missing=1
    fi
}

# Mesa's DRI loader is intentionally small; libgallium contains the Asahi
# implementation. Check both so a dangling asahi_dri.so link cannot pass.
for path in \
    lib/ld-musl-aarch64.so.1 \
    usr/bin/gl-triangle-agx \
    usr/bin/run-gl-triangle-agx \
    usr/bin/run-m1-agx-smoke \
    usr/lib/dri/asahi_dri.so \
    usr/lib/dri/libdril_dri.so \
    usr/lib/libEGL.so.1 \
    usr/lib/libGLESv2.so.2 \
    usr/lib/libgbm.so.1 \
    usr/lib/libvinix-agx-fault.so \
    usr/share/examples/gl-triangle/egl_triangle.c \
    usr/share/vinix/asahi-x11-egl; do
    require_path "$path"
done

marker="$(tar -xOf "$IMAGE" ./usr/share/vinix/asahi-x11-egl 2>/dev/null || \
    tar -xOf "$IMAGE" usr/share/vinix/asahi-x11-egl 2>/dev/null || true)"
case "$marker" in
    "mesa=25.0.5 "*"drivers="*"asahi"*"platforms="*"surfaceless"*"gbm=enabled"*) ;;
    *)
        echo "error: M1 GPU image has an unexpected Mesa capability marker" >&2
        echo "       found: ${marker:-<missing>}" >&2
        missing=1
        ;;
esac
require_path "usr/lib/libgallium-25.0.5.so"

driver_metadata="$(tar -tvf "$IMAGE" 2>/dev/null | \
    awk '/(^|\/)asahi_dri\.so( ->|$)/ { print; exit }')"
if grep -Fqx "usr/lib/dri/asahi_dri.so" "$MANIFEST"; then
    case "$driver_metadata" in
        l*"asahi_dri.so -> libdril_dri.so") ;;
        -*) ;;
        *)
            echo "error: /usr/lib/dri/asahi_dri.so is neither a regular driver nor the expected libdril link" >&2
            missing=1
            ;;
    esac
fi

if [ -n "$TRIANGLE_SOURCE" ]; then
    if [ ! -f "$TRIANGLE_SOURCE" ]; then
        echo "error: expected M1 triangle source is missing: $TRIANGLE_SOURCE" >&2
        missing=1
    elif grep -Fqx "usr/share/examples/gl-triangle/egl_triangle.c" "$MANIFEST"; then
        if tar -xOf "$IMAGE" ./usr/share/examples/gl-triangle/egl_triangle.c \
            > "$ARCHIVED_SOURCE" 2>/dev/null || \
           tar -xOf "$IMAGE" usr/share/examples/gl-triangle/egl_triangle.c \
            > "$ARCHIVED_SOURCE" 2>/dev/null; then
            if ! cmp -s "$TRIANGLE_SOURCE" "$ARCHIVED_SOURCE"; then
                echo "error: M1 GPU image contains a stale egl_triangle.c; --rebuild would test old code" >&2
                missing=1
            fi
        else
            echo "error: cannot extract egl_triangle.c from M1 GPU image" >&2
            missing=1
        fi
    fi
fi

if [ "$DESKTOP" -eq 1 ]; then
    for path in \
        usr/bin/vinix-desktop-gpu \
        usr/bin/Xorg \
        usr/bin/Xvfb \
        usr/bin/startx \
        usr/bin/run-firefox; do
        require_path "$path"
    done
    if grep -Fqx "usr/bin/firefox-esr" "$MANIFEST" && \
       grep -Fqx "usr/lib/firefox-esr/firefox-esr" "$MANIFEST"; then
        :
    elif grep -Fqx "usr/bin/firefox" "$MANIFEST" && \
         grep -Fqx "usr/lib/firefox/firefox" "$MANIFEST"; then
        :
    else
        echo "error: M1 GPU desktop image has no complete Firefox executable pair" >&2
        missing=1
    fi
fi

if [ -n "$KERNEL" ]; then
    if [ ! -f "$KERNEL" ]; then
        echo "error: M1 GPU kernel is missing: $KERNEL" >&2
        missing=1
    else
        kernel_info="$(file -b "$KERNEL" || true)"
        case "$kernel_info" in
            *"ELF 64-bit"*"ARM aarch64"*|*"ELF 64-bit"*"AArch64"*) ;;
            *)
                echo "error: M1 GPU kernel is not an AArch64 ELF64 image: $kernel_info" >&2
                missing=1
                ;;
        esac
        for text in \
            "agx: G13 topology:" \
            "G13 v12.3" \
            "agx: Apple GPU driver initialized successfully"; do
            if ! LC_ALL=C grep -aF "$text" "$KERNEL" >/dev/null; then
                echo "error: M1 GPU kernel lacks native AGX marker: $text" >&2
                missing=1
            fi
        done
    fi
fi

if [ "$missing" -ne 0 ]; then
    exit 1
fi

kind="shell"
[ "$DESKTOP" -eq 1 ] && kind="desktop + Firefox"
echo "M1 GPU image preflight: PASS ($kind, Mesa 25.0.5 Asahi)"
