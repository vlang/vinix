#!/bin/bash
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$repo/build-support/qemu-storage.sh"

work="$(mktemp -d "${TMPDIR:-/tmp}/vinix-storage-test.XXXXXX")"
cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

vinix_storage_is_temporary_path "/tmp/vinix-test.img"
vinix_storage_is_temporary_path "/private/tmp/vinix-test.img"
if vinix_storage_is_temporary_path "$repo/boot-image/boot.img"; then
    echo "repository boot image was classified as temporary" >&2
    exit 1
fi

mkdir -p "$work/seed/.wine"
printf '%s\n' office > "$work/seed/.wine/state"
tar -czf "$work/seed.tar.gz" -C "$work/seed" .
cat > "$work/fake-mke2fs" <<'EOF'
#!/bin/sh
seed=
while [ "$#" -gt 0 ]; do
    if [ "$1" = -d ]; then
        seed=$2
        shift 2
        continue
    fi
    shift
done
[ -n "$seed" ]
[ "$(cat "$seed/.wine/state")" = office ]
EOF
chmod +x "$work/fake-mke2fs"

VINIX_MKE2FS="$work/fake-mke2fs"
export VINIX_MKE2FS
vinix_storage_create_ext2 "$work/root.ext2" 8 "$work/seed.tar.gz"
[ -f "$work/root.ext2" ]
[ "$(vinix_storage_file_size "$work/root.ext2")" = 8388608 ]

VINIX_MKE2FS=/usr/bin/false
export VINIX_MKE2FS
if vinix_storage_create_ext2 "$work/broken.ext2" 8 "$work/seed.tar.gz"; then
    echo "failed formatter unexpectedly published a persistent disk" >&2
    exit 1
fi
[ ! -e "$work/broken.ext2" ]

echo "PASS QEMU storage helpers"
