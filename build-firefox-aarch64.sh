#!/bin/bash
# Stage Firefox ESR and its Linux/aarch64 runtime for Vinix.
#
# Firefox's widgets are Gecko/XUL, but its Linux window-system glue is GTK 3.
# We use Alpine's musl build and package GTK as an ordinary userspace library;
# no GTK code or ABI is implemented in the Vinix kernel or native desktop.
set -euo pipefail
set -f

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_FIREFOX_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-firefox}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
# Alpine 3.24 links Firefox against Scudo, whose allocator VM contract is not
# implemented by Vinix yet. 3.22 carries the same Firefox 140 ESR generation
# with the normal musl allocator, so keep the compatibility bundle on it.
ALPINE_BRANCH="${ALPINE_BRANCH:-v3.22}"
ALPINE_ARCH=aarch64
FIREFOX_PACKAGE="${VINIX_FIREFOX_PACKAGE:-firefox-esr}"

BRANCH_KEY="$(printf '%s' "$ALPINE_BRANCH" | tr '/:' '__')"
RESOLVED="$BUILD_DIR/resolved-packages.txt"

mkdir -p "$BUILD_DIR" "$DOWNLOADS"
rm -rf "$STAGING"
mkdir -p "$STAGING"
: > "$RESOLVED"

fetch_index() {
    local repo="$1"
    local index_file="$DOWNLOADS/${BRANCH_KEY}_${repo}_APKINDEX"

    if [ ! -s "$index_file" ]; then
        echo "  fetching $ALPINE_BRANCH/$repo package index" >&2
        curl -fsSL --retry 3 \
            "$ALPINE_MIRROR/$ALPINE_BRANCH/$repo/$ALPINE_ARCH/APKINDEX.tar.gz" \
            | tar xOz APKINDEX > "$index_file.tmp"
        mv "$index_file.tmp" "$index_file"
    fi
}

# Print repo, package, version and dependencies as tab-separated fields.
# APK dependencies may name a package directly or one of its `so:`/`cmd:`
# provides. Prefer an exact package name before consulting provides.
lookup_in_index() {
    local repo="$1" wanted="$2" mode="$3"
    local index_file="$DOWNLOADS/${BRANCH_KEY}_${repo}_APKINDEX"

    awk -v repo="$repo" -v wanted="$wanted" -v mode="$mode" '
        BEGIN { RS=""; FS="\n" }
        {
            package=version=dependencies=provides=""
            for (i=1; i<=NF; i++) {
                if ($i ~ /^P:/) package=substr($i, 3)
                else if ($i ~ /^V:/) version=substr($i, 3)
                else if ($i ~ /^D:/) dependencies=substr($i, 3)
                else if ($i ~ /^p:/) provides=substr($i, 3)
            }

            matched=(mode == "exact" && package == wanted)
            if (mode == "provide") {
                count=split(provides, values, " ")
                for (j=1; j<=count; j++) {
                    value=values[j]
                    sub(/[<>=~].*$/, "", value)
                    if (value == wanted) matched=1
                }
            }

            if (matched) {
                printf "%s\t%s\t%s\t%s\n", repo, package, version, dependencies
                exit
            }
        }
    ' "$index_file"
}

find_package() {
    local request="$1" alternative normalized repo result
    local old_ifs="$IFS"
    IFS='|'
    set -- $request
    IFS="$old_ifs"

    for alternative in "$@"; do
        case "$alternative" in
            ''|'!'*|/*) continue ;;
        esac
        normalized="${alternative%%[\<\>\=\~]*}"

        for repo in main community; do
            result="$(lookup_in_index "$repo" "$normalized" exact)"
            if [ -n "$result" ]; then
                printf '%s\n' "$result"
                return 0
            fi
        done
        for repo in main community; do
            result="$(lookup_in_index "$repo" "$normalized" provide)"
            if [ -n "$result" ]; then
                printf '%s\n' "$result"
                return 0
            fi
        done
    done

    return 1
}

extract_package() {
    local repo="$1" package="$2" version="$3"
    local filename="$package-$version.apk"
    local local_file="$DOWNLOADS/$filename"

    if [ ! -s "$local_file" ]; then
        echo "  downloading $filename"
        curl -fL --retry 3 -o "$local_file" \
            "$ALPINE_MIRROR/$ALPINE_BRANCH/$repo/$ALPINE_ARCH/$filename"
    else
        echo "  using cached $filename"
    fi

    tar xzf "$local_file" -C "$STAGING" 2>/dev/null || true
    rm -f "$STAGING/.PKGINFO" "$STAGING/.INSTALL" "$STAGING/.trigger"* \
        "$STAGING/.SIGN"*
}

echo "=== staging $FIREFOX_PACKAGE for Vinix/$ALPINE_ARCH ==="
fetch_index main
fetch_index community

# Firefox itself does not depend on a font package or the system TLS bundle,
# although a useful browser needs both. The resolver follows the full runtime
# closure, including GTK/X11, media codecs and their shared-library providers.
queue=("$FIREFOX_PACKAGE" ca-certificates font-dejavu)
queue_index=0
while [ "$queue_index" -lt "${#queue[@]}" ]; do
    dependency="${queue[$queue_index]}"
    queue_index=$((queue_index + 1))

    case "$dependency" in
        ''|'!'*|/*) continue ;;
    esac

    package_record="$(find_package "$dependency")" || {
        echo "ERROR: cannot resolve Alpine dependency: $dependency" >&2
        exit 1
    }
    IFS=$'\t' read -r repo package version dependencies <<< "$package_record"
    package_key="$repo/$package-$version"
    if grep -Fqx "$package_key" "$RESOLVED"; then
        continue
    fi

    printf '%s\n' "$package_key" >> "$RESOLVED"
    extract_package "$repo" "$package" "$version"

    if [ -n "$dependencies" ]; then
        # Dependency records are deliberately shell words. Globbing is off,
        # and each word is resolved through the two package indexes above.
        for child in $dependencies; do
            queue+=("$child")
        done
    fi
done

# Absolute library links from an APK would otherwise point into the build host.
# Materialise file links as hard links. This avoids O_NOFOLLOW limitations in
# the current Vinix VFS without putting a second 100+ MiB copy of large shared
# objects into the initramfs; Vinix's ustar unpacker preserves hard links.
find "$STAGING" -type l | while IFS= read -r link; do
    target="$(readlink "$link")"
    case "$target" in
        /*) real="$STAGING$target" ;;
        *)  real="$(dirname "$link")/$target" ;;
    esac
    if [ -f "$real" ]; then
        rm "$link"
        ln "$real" "$link"
    fi
done

mkdir -p "$STAGING/usr/bin" "$STAGING/root" "$STAGING/etc/firefox/policies"
install -m755 "$SCRIPT_DIR/build-support/firefox/run-firefox" \
    "$STAGING/usr/bin/run-firefox"
install -m644 "$SCRIPT_DIR/tests/firefox/smoke.html" \
    "$STAGING/root/firefox-smoke.html"
install -m644 "$SCRIPT_DIR/build-support/firefox/policies.json" \
    "$STAGING/etc/firefox/policies/policies.json"

# Alpine has used both directories over Firefox's lifetime. Install prefs and
# enterprise policy beside whichever application directory this APK contains.
found_app=0
for app_dir in "$STAGING/usr/lib/firefox" "$STAGING/usr/lib/firefox-esr"; do
    if [ -d "$app_dir" ]; then
        found_app=1
        mkdir -p "$app_dir/defaults/pref" "$app_dir/distribution"
        install -m644 "$SCRIPT_DIR/build-support/firefox/vinix.js" \
            "$app_dir/defaults/pref/vinix.js"
        install -m644 "$SCRIPT_DIR/build-support/firefox/policies.json" \
            "$app_dir/distribution/policies.json"
    fi
done

if [ "$found_app" -ne 1 ]; then
    echo "ERROR: the staged package has no Firefox application directory" >&2
    exit 1
fi
if [ ! -x "$STAGING/usr/bin/firefox-esr" ] && [ ! -x "$STAGING/usr/bin/firefox" ]; then
    echo "ERROR: the staged package has no Firefox launcher" >&2
    exit 1
fi

echo
echo "staged packages: $(wc -l < "$RESOLVED" | tr -d ' ')"
echo "staged size: $(du -sh "$STAGING" | cut -f1)"
echo "manifest: $RESOLVED"
echo "launcher: /usr/bin/run-firefox"
