#!/bin/sh
set -eu

# Build a Vinix-local copy of KekVM's VirGL renderer with the Apple OpenGL
# buffer-texture workaround. QEMU loads it through DYLD_LIBRARY_PATH.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
kekvm_dir=${VINIX_KEKVM_DIR:-"$repo_dir/../kekvm"}
prefix="$repo_dir/build/virglrenderer-host"
library="$prefix/lib/libvirglrenderer.1.dylib"
tap_dir="$(brew --repository)/Library/Taps/startergo/homebrew-virglrenderer"
formula="$tap_dir/Formula/virglrenderer.rb"

if [ ! -f "$formula" ] || [ ! -f "$kekvm_dir/scripts/build-virglrenderer.sh" ]; then
    echo 'Vinix VirGL needs KekVM and the startergo/virglrenderer Homebrew tap' >&2
    exit 1
fi

build_id=$(cat "$formula" "$tap_dir"/patches/virglrenderer-*.patch \
    "$kekvm_dir/scripts/build-virglrenderer.sh" \
    "$kekvm_dir"/scripts/patches/virglrenderer-*.patch \
    "$script_dir/macos-buffer-textures.patch" "$0" | shasum -a 256 | cut -d' ' -f1)
if [ -f "$library" ] && [ "$(cat "$prefix/.vinix-build-id" 2>/dev/null)" = "$build_id" ]; then
    exit 0
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/vinix-virglrenderer.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
archive="$work_dir/virglrenderer.tar.gz"
if [ -n "${VINIX_VIRGLRENDERER_SOURCE_ARCHIVE:-}" ]; then
    cp "$VINIX_VIRGLRENDERER_SOURCE_ARCHIVE" "$archive"
else
    upstream_url=$(sed -n 's/.*upstream_url = "\(.*\)"/\1/p' "$formula")
    curl -fLsS "$upstream_url" -o "$archive"
fi
mkdir "$work_dir/src"
tar -xzf "$archive" -C "$work_dir/src" --strip-components=1

# Match the patch order used by KekVM's installed QEMU, then apply Vinix's
# workaround to the resulting renderer source.
for patch_name in $(awk '/patches = \[/{found=1; next} found && /\]/{exit} found' "$formula" | tr -d ' ",'); do
    patch -d "$work_dir/src" -p1 --batch --silent -i "$tap_dir/patches/$patch_name"
done
for kekvm_patch in "$kekvm_dir"/scripts/patches/virglrenderer-*.patch; do
    patch -d "$work_dir/src" -p1 --batch --silent -i "$kekvm_patch"
done
patch -d "$work_dir/src" -p1 --batch --silent -i "$script_dir/macos-buffer-textures.patch"

python3 -m venv "$work_dir/venv"
"$work_dir/venv/bin/pip" install --quiet --disable-pip-version-check meson pyyaml
angle=$(brew --prefix angle)
libepoxy=$(brew --prefix libepoxy)
PATH="$work_dir/venv/bin:$PATH" meson setup "$work_dir/build" "$work_dir/src" \
    --prefix="$prefix" --libdir=lib --buildtype=debugoptimized --wrap-mode=nofallback \
    "-Dc_args=-I$angle/include" "-Dcpp_args=-I$angle/include" \
    "--pkg-config-path=$angle/lib/pkgconfig:$libepoxy/lib/pkgconfig" \
    "-Ddrm-renderers=[]" -Dvenus=true -Drender-server-worker=thread \
    -Dtests=false -Dvideo=false -Dtracing=none
PATH="$work_dir/venv/bin:$PATH" meson compile -C "$work_dir/build"
PATH="$work_dir/venv/bin:$PATH" meson install -C "$work_dir/build" --destdir "$work_dir/stage"

staged="$work_dir/stage$prefix"
install_name_tool -add_rpath "$(brew --prefix)/lib" "$staged/lib/libvirglrenderer.1.dylib"
codesign --force --sign - "$staged/lib/libvirglrenderer.1.dylib"
printf '%s\n' "$build_id" > "$staged/.vinix-build-id"
rm -rf "$prefix"
mkdir -p "$(dirname -- "$prefix")"
mv "$staged" "$prefix"
echo "Vinix VirGL renderer ready: $library"
