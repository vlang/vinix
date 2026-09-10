#!/bin/bash
# Shared host-side storage helpers for the AArch64 QEMU launchers.

vinix_storage_file_size() {
    if stat -f%z "$1" >/dev/null 2>&1; then
        stat -f%z "$1"
    else
        stat -c%s "$1"
    fi
}

vinix_storage_is_temporary_path() {
    local candidate="$1"
    local temp_root

    case "$candidate" in
        /tmp/*|/private/tmp/*) return 0 ;;
    esac
    temp_root="${TMPDIR:-}"
    if [ -n "$temp_root" ]; then
        temp_root="${temp_root%/}"
        case "$candidate" in
            "$temp_root"/*) return 0 ;;
        esac
    fi
    return 1
}

vinix_storage_find_mke2fs() {
    local candidate

    if [ -n "${VINIX_MKE2FS:-}" ]; then
        [ -x "$VINIX_MKE2FS" ] || return 1
        printf '%s\n' "$VINIX_MKE2FS"
        return 0
    fi
    for candidate in \
        "$(command -v mke2fs 2>/dev/null || true)" \
        "$(command -v mkfs.ext2 2>/dev/null || true)" \
        /opt/homebrew/opt/e2fsprogs/sbin/mke2fs \
        /usr/local/opt/e2fsprogs/sbin/mke2fs; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# Atomically create an ext2 image, optionally populating it from a tar archive.
# The target is never published when formatting or seed extraction fails.
vinix_storage_create_ext2() {
    local target="$1"
    local size_mb="$2"
    local seed_archive="${3:-}"
    local target_dir temp_disk seed_dir mke2fs persist_bytes
    local -a seed_args

    target_dir="$(dirname "$target")"
    mkdir -p "$target_dir" || return 1
    temp_disk="$(mktemp "$target.tmp.XXXXXX")" || return 1
    seed_dir=""

    if [ -n "$seed_archive" ]; then
        if [ ! -f "$seed_archive" ]; then
            echo "ERROR: persistent root seed is missing: $seed_archive" >&2
            rm -f "$temp_disk"
            return 1
        fi
        seed_dir="$(mktemp -d "${TMPDIR:-/tmp}/vinix-root-seed.XXXXXX")" || {
            rm -f "$temp_disk"
            return 1
        }
        if ! tar -xf "$seed_archive" -C "$seed_dir"; then
            echo "ERROR: persistent root seed is not a readable tar archive: $seed_archive" >&2
            rm -rf "$seed_dir"
            rm -f "$temp_disk"
            return 1
        fi
    fi

    persist_bytes=$((size_mb * 1024 * 1024))
    if command -v truncate >/dev/null 2>&1; then
        if ! truncate -s "$persist_bytes" "$temp_disk"; then
            rm -rf "$seed_dir"
            rm -f "$temp_disk"
            return 1
        fi
    elif command -v mkfile >/dev/null 2>&1; then
        if ! mkfile -n "$persist_bytes" "$temp_disk"; then
            rm -rf "$seed_dir"
            rm -f "$temp_disk"
            return 1
        fi
    else
        if ! dd if=/dev/zero of="$temp_disk" bs=1m count="$size_mb" 2>/dev/null; then
            rm -rf "$seed_dir"
            rm -f "$temp_disk"
            return 1
        fi
    fi

    mke2fs="$(vinix_storage_find_mke2fs)" || {
        echo "ERROR: persistent storage needs mke2fs (install e2fsprogs)." >&2
        rm -rf "$seed_dir"
        rm -f "$temp_disk"
        return 1
    }
    seed_args=()
    if [ -n "$seed_dir" ]; then
        seed_args=(-d "$seed_dir")
    fi
    if ! "$mke2fs" -q -F -t ext2 -b 4096 -I 128 \
        -O filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum \
        "${seed_args[@]}" "$temp_disk"; then
        rm -rf "$seed_dir"
        rm -f "$temp_disk"
        return 1
    fi

    rm -rf "$seed_dir"
    if ! mv -f "$temp_disk" "$target"; then
        rm -f "$temp_disk"
        return 1
    fi
}
