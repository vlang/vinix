# SPDX-License-Identifier: GPL-2.0-or-later
# Sourced by the image scripts: Limine's prebuilt loaders, from one pinned
# release archive checked against its SHA-256 before anything is taken from
# it. The arm64 loader the images boot is built from the same release's
# source with Vinix's base revision patch (scripts/build-limine-aarch64.sh);
# keep the two versions together.
LIMINE_BINARY_VERSION=12.9.3
LIMINE_BINARY_SHA256=9f42fe9ea2e84d71056529969b1d5c24ba9a2287ffcc01bcce58b0ef8aa98b1d

limine_binary_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# limine_binary_dir CACHE_DIR: print the directory holding the release's
# binaries (BOOTX64.EFI, limine-uefi-cd.bin, limine-bios-cd.bin,
# limine-bios.sys, limine.c ...), downloading and checking it first if needed.
limine_binary_dir() {
    local cache="$1" archive dir actual
    dir="$cache/limine-binary-$LIMINE_BINARY_VERSION"
    if [ -f "$dir/.verified" ]; then
        printf '%s\n' "$dir"
        return 0
    fi
    mkdir -p "$cache"
    archive="$cache/limine-binary-$LIMINE_BINARY_VERSION.tar.gz"
    if [ ! -s "$archive" ]; then
        echo "==> Fetching Limine $LIMINE_BINARY_VERSION binaries..." >&2
        curl -fL --retry 3 -o "$archive.tmp" \
            "https://github.com/limine-bootloader/limine/releases/download/v$LIMINE_BINARY_VERSION/limine-binary.tar.gz" >&2 &&
            mv -f "$archive.tmp" "$archive" || {
            rm -f "$archive.tmp"
            echo "ERROR: could not download Limine $LIMINE_BINARY_VERSION" >&2
            return 1
        }
    fi
    actual="$(limine_binary_sha256 "$archive")"
    if [ "$actual" != "$LIMINE_BINARY_SHA256" ]; then
        echo "ERROR: Limine $LIMINE_BINARY_VERSION archive checksum mismatch." >&2
        echo "Expected: $LIMINE_BINARY_SHA256" >&2
        echo "Actual:   $actual" >&2
        rm -f "$archive"
        return 1
    fi
    rm -rf "$dir" "$dir.tmp"
    mkdir -p "$dir.tmp"
    tar xzf "$archive" -C "$dir.tmp"
    mv "$dir.tmp/limine-binary" "$dir"
    rmdir "$dir.tmp"
    : > "$dir/.verified"
    printf '%s\n' "$dir"
}
