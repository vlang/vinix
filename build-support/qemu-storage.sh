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

vinix_storage_find_debugfs() {
    local candidate

    if [ -n "${VINIX_DEBUGFS:-}" ]; then
        [ -x "$VINIX_DEBUGFS" ] || return 1
        printf '%s\n' "$VINIX_DEBUGFS"
        return 0
    fi
    for candidate in \
        "$(command -v debugfs 2>/dev/null || true)" \
        /opt/homebrew/opt/e2fsprogs/sbin/debugfs \
        /usr/local/opt/e2fsprogs/sbin/debugfs; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
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
#
# $4, when given, turns the result into a *system* volume rather than a home
# one: the kernel's mount points are created, the image identity is recorded so
# a later run can tell a rebuilt image from the one already installed, and $5,
# when given, replaces the archive's /root with a home carried over from the
# volume being replaced.
vinix_storage_create_ext2() {
    local target="$1"
    local size_mb="$2"
    local seed_archive="${3:-}"
    local image_id="${4:-}"
    local carried_home="${5:-}"
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

    if [ -n "$image_id" ]; then
        if [ -z "$seed_dir" ]; then
            echo "ERROR: a system volume needs a seed archive" >&2
            rm -f "$temp_disk"
            return 1
        fi
        # The kernel overlays these four and refuses a volume that does not
        # provide all of them as plain directories, rather than mounting /dev
        # over whatever an image happens to have put there.
        if ! mkdir -p "$seed_dir/dev" "$seed_dir/proc" "$seed_dir/tmp" \
            "$seed_dir/run" "$seed_dir/root"; then
            rm -rf "$seed_dir"
            rm -f "$temp_disk"
            return 1
        fi
        chmod 1777 "$seed_dir/tmp" 2>/dev/null || true
        if [ -n "$carried_home" ]; then
            rm -rf "${seed_dir:?}/root"
            if ! cp -a "$carried_home" "$seed_dir/root"; then
                echo "ERROR: could not carry the existing home into the new volume" >&2
                rm -rf "$seed_dir"
                rm -f "$temp_disk"
                return 1
            fi
        fi
        printf '%s\n' "$image_id" > "$seed_dir/.vinix-image-id"
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

    # mke2fs -d copies the ownership of the host files it read, so a volume
    # built on a Mac arrives owned by whoever ran the build. Vinix runs as root
    # and enforces Unix permissions; Firefox, for one, refuses to start when it
    # finds that $HOME belongs to somebody else.
    if [ -n "$seed_dir" ]; then
        if ! python3 "$(dirname "${BASH_SOURCE[0]}")/ext2-set-root-owner.py" \
            "$temp_disk"; then
            echo "ERROR: could not give the new volume to root" >&2
            rm -rf "$seed_dir"
            rm -f "$temp_disk"
            return 1
        fi
    fi

    rm -rf "$seed_dir"
    if ! mv -f "$temp_disk" "$target"; then
        rm -f "$temp_disk"
        return 1
    fi
}

# The identity of the image a system volume was installed from. Size and mtime
# are what a rebuild always changes, and reading them costs a stat rather than
# a hash of a gigabyte.
vinix_storage_image_id() {
    local image="$1"
    local mtime

    [ -f "$image" ] || return 1
    if mtime="$(stat -f%m "$image" 2>/dev/null)"; then
        :
    elif mtime="$(stat -c%Y "$image" 2>/dev/null)"; then
        :
    else
        return 1
    fi
    printf '%s-%s\n' "$(vinix_storage_file_size "$image")" "$mtime"
}

# The identity recorded inside an existing system volume, or nothing when it
# has none -- which is also how a home volume and a corrupt one read.
vinix_storage_installed_image_id() {
    local disk="$1"
    local debugfs

    [ -f "$disk" ] || return 1
    debugfs="$(vinix_storage_find_debugfs)" || return 1
    "$debugfs" -R 'cat /.vinix-image-id' "$disk" 2>/dev/null | tr -d '\r' | head -1
}

# Copy a home out of an ext2 volume, so it can be carried into the volume that
# replaces it. $3 is where the home lives on that volume: /root on a system
# volume, and / on the older home-only one, whose root directory is the home.
# Failure here is never fatal on its own -- the caller decides whether to go on
# without the old home or to keep the old volume.
vinix_storage_extract_home() {
    local disk="$1"
    local destination="$2"
    local source="${3:-/root}"
    local debugfs

    debugfs="$(vinix_storage_find_debugfs)" || return 1
    rm -rf "$destination"
    mkdir -p "$destination" || return 1
    "$debugfs" -R "rdump $source $destination" "$disk" >/dev/null 2>&1 || return 1
    # rdump recreates the named directory inside the destination.
    local extracted="$destination/$(basename "$source")"
    if [ "$source" = / ]; then
        extracted="$destination"
    fi
    [ -d "$extracted" ] || return 1
    # ext2's own bookkeeping directory belongs to the volume, not to the home
    # it happens to sit at the top of; carrying it over would put it in the
    # user's home on the new one.
    rm -rf "${extracted:?}/lost+found"
    # An empty result is not a home worth carrying, and would silently replace
    # the image's own /root with nothing.
    [ -n "$(ls -A "$extracted" 2>/dev/null)" ] || return 1
    printf '%s\n' "$extracted"
}
