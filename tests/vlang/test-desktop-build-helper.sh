#!/bin/bash
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/vinix-desktop-helper-test.XXXXXX")"
cleanup() {
	rm -rf "$work"
}
trap cleanup EXIT INT TERM

mkdir -p "$work/home/desktop" "$work/home/vmodules/ui2" \
	"$work/system/desktop" "$work/system/vmodules/ui2" "$work/bin"
printf 'module main\nfn main() {}\n' > "$work/home/desktop/main.v"
printf 'Module { name: "ui2" }\n' > "$work/home/vmodules/ui2/v.mod"
printf 'module main\nfn main() {}\n' > "$work/system/desktop/main.v"
printf 'Module { name: "ui2" }\n' > "$work/system/vmodules/ui2/v.mod"
printf '%s\n' old-generation > "$work/home/.vinix-desktop-dev-version"
printf '%s\n' current-generation > "$work/system/.source-version"

cat > "$work/bin/v" <<'EOF'
#!/bin/sh
if [ "${1:-}" = version ]; then
	echo 'V test'
	exit 0
fi
printf '%s\n' "$*" > "$VINIX_DESKTOP_TEST_V_ARGS"
output=
last=
while [ "$#" -gt 0 ]; do
	if [ "$1" = -o ]; then
		output=$2
		shift
	else
		last=$1
	fi
	shift
done
[ -n "$output" ] || exit 1
printf 'int main(void) { return 0; }\n' > "$output"
if [ -n "${VINIX_DESKTOP_TEST_STAGED_SOURCE:-}" ]; then
	cp "$last/main.v" "$VINIX_DESKTOP_TEST_STAGED_SOURCE"
fi
EOF
cat > "$work/bin/tcc" <<'EOF'
#!/bin/sh
echo 'test TCC must be driven through V' >&2
exit 1
EOF
cat > "$work/bin/python3" <<'EOF'
#!/bin/sh
echo 'guest Python must not be used for host-source staging' >&2
exit 1
EOF
cat > "$work/bin/vinix-host-sync" <<'EOF'
#!/bin/sh
: > "$VINIX_DESKTOP_TEST_SYNCED"
EOF
chmod 755 "$work/bin/v" "$work/bin/tcc" "$work/bin/python3"
chmod 755 "$work/bin/vinix-host-sync"

output="$(
	PATH="$work/bin:/usr/bin:/bin" \
	VINIX_DESKTOP_HOME_DEV="$work/home" \
	VINIX_DESKTOP_SYSTEM_DEV="$work/system" \
	VINIX_DESKTOP_OUTPUT="$work/vinix-desktop" \
	VINIX_DESKTOP_TEST_V_ARGS="$work/v-args" \
		"$repo/build-support/vinix-desktop-build" --no-reload
)"
case "$output" in
	*"editable desktop tree is from another image; using the system source copy"*) ;;
	*) echo "desktop helper did not reject its stale editable tree" >&2; exit 1 ;;
esac
grep -F "$work/system/desktop" "$work/v-args" >/dev/null
grep -F "$work/system/vmodules" "$work/v-args" >/dev/null
[ -x "$work/vinix-desktop" ]

cp "$work/system/.source-version" "$work/home/.vinix-desktop-dev-version"
PATH="$work/bin:/usr/bin:/bin" \
VINIX_DESKTOP_HOME_DEV="$work/home" \
VINIX_DESKTOP_SYSTEM_DEV="$work/system" \
VINIX_DESKTOP_OUTPUT="$work/vinix-desktop" \
VINIX_DESKTOP_TEST_V_ARGS="$work/v-args" \
	"$repo/build-support/vinix-desktop-build" --no-reload >/dev/null
grep -F "$work/home/desktop" "$work/v-args" >/dev/null
grep -F "$work/home/vmodules" "$work/v-args" >/dev/null

# A QEMU host share takes precedence over the image-seeded copies. Staging is
# performed by the macOS source service, so the guest helper must consume the
# materialized trees without invoking Python.
host="$work/host"
mkdir -p "$host/desktop" "$host/.vinix-build/desktop" \
	"$host/.vinix-build/vmodules/ui2" "$host/third_party/ui2"
cat > "$host/desktop/main.v" <<'EOF'
// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main
fn main() {}
EOF
cat > "$host/.vinix-build/desktop/main.v" <<'EOF'
// SPDX-License-Identifier: GPL-2.0-or-later
module main
fn main() {}
EOF
printf 'Module { name: "ui2" }\n' > "$host/.vinix-build/vmodules/ui2/v.mod"
printf 'host service\n' > "$work/host-source-url"
PATH="$work/bin:/usr/bin:/bin" \
VINIX_HOST_SOURCE_URL_FILE="$work/host-source-url" \
VINIX_HOST_MOUNT="$host" \
VINIX_DESKTOP_HOME_DEV="$work/home" \
VINIX_DESKTOP_SYSTEM_DEV="$work/system" \
VINIX_DESKTOP_OUTPUT="$work/vinix-desktop" \
VINIX_DESKTOP_TEST_SYNCED="$work/synced" \
VINIX_DESKTOP_TEST_V_ARGS="$work/v-args" \
VINIX_DESKTOP_TEST_STAGED_SOURCE="$work/staged-main.v" \
	"$repo/build-support/vinix-desktop-build" --no-reload >/dev/null
test -f "$work/synced"
grep -F "$host|$host/third_party" "$work/v-args" >/dev/null
grep -F -- '-cc tcc' "$work/v-args" >/dev/null
grep -F -- '-no-retry-compilation' "$work/v-args" >/dev/null
grep -F -- '-cflags -I/usr/include' "$work/v-args" >/dev/null
grep -F '/desktop' "$work/v-args" >/dev/null
if grep -Fq -- '-d glibc' "$work/v-args"; then
	echo "desktop build selected glibc for its musl/TCC output" >&2
	exit 1
fi
grep -Fqx '// SPDX-License-Identifier: GPL-2.0-or-later' "$work/staged-main.v"
if grep -Fq 'All rights reserved.' "$work/staged-main.v"; then
	echo "desktop build retained the V3-incompatible redundant preamble" >&2
	exit 1
fi

echo "PASS desktop build helper source selection and host staging"
