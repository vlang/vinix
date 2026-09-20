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
cat > "$work/bin/gcc" <<'EOF'
#!/bin/sh
[ -z "${VINIX_DESKTOP_TEST_GCC_ARGS:-}" ] || printf '%s\n' "$*" > "$VINIX_DESKTOP_TEST_GCC_ARGS"
while [ "$#" -gt 0 ]; do
	if [ "$1" = -o ]; then
		printf '#!/bin/sh\nexit 0\n' > "$2"
		chmod 755 "$2"
		exit 0
	fi
	shift
done
exit 1
EOF
cat > "$work/bin/vinix-host-sync" <<'EOF'
#!/bin/sh
: > "$VINIX_DESKTOP_TEST_SYNCED"
EOF
chmod 755 "$work/bin/v" "$work/bin/gcc"
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

# A QEMU host share takes precedence over the image-seeded copies. The helper
# must stage the raw host desktop and ui2 checkout the same way as the host
# image builder before invoking V.
host="$work/host"
mkdir -p "$host/desktop/tools" "$host/third_party/ui2/ui" \
	"$host/third_party/ui2/examples/calculator"
cat > "$host/desktop/main.v" <<'EOF'
// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main
fn main() {}
EOF
cp "$repo/desktop/tools/stage_app.py" "$host/desktop/tools/stage_app.py"
cp "$repo/desktop/tools/stage_ui2.py" "$host/desktop/tools/stage_ui2.py"
cp "$repo/desktop/tools/ui2_headless_bounds.v" \
	"$host/desktop/tools/ui2_headless_bounds.v"
cat > "$host/third_party/ui2/v.mod" <<'EOF'
Module {
    name: 'ui2'
    subdirs: ['ui']
}
EOF
printf 'module ui2\n' > "$host/third_party/ui2/ui/ui.v"
cat > "$host/third_party/ui2/examples/calculator/main.v" <<'EOF'
module main

struct CalculatorModel {}

fn main() {
}
EOF
printf 'int vinix_execinfo_compat;\n' > "$host/desktop/execinfo_compat.c"
printf 'extern int vinix_execinfo_compat;\n' > "$host/desktop/execinfo_compat.h"
printf 'host service\n' > "$work/host-source-url"
PATH="$work/bin:/usr/bin:/bin" \
VINIX_HOST_SOURCE_URL_FILE="$work/host-source-url" \
VINIX_HOST_MOUNT="$host" \
VINIX_DESKTOP_HOME_DEV="$work/home" \
VINIX_DESKTOP_SYSTEM_DEV="$work/system" \
VINIX_DESKTOP_OUTPUT="$work/vinix-desktop" \
VINIX_DESKTOP_TEST_SYNCED="$work/synced" \
VINIX_DESKTOP_TEST_V_ARGS="$work/v-args" \
VINIX_DESKTOP_TEST_GCC_ARGS="$work/gcc-args" \
VINIX_DESKTOP_TEST_STAGED_SOURCE="$work/staged-main.v" \
	"$repo/build-support/vinix-desktop-build" --no-reload >/dev/null
test -f "$work/synced"
grep -F "$host|$host/third_party" "$work/v-args" >/dev/null
grep -F -- '-d glibc' "$work/v-args" >/dev/null
grep -F '/desktop' "$work/v-args" >/dev/null
grep -F "$host/desktop/execinfo_compat.c" "$work/gcc-args" >/dev/null
grep -F -- '-lgcc_eh' "$work/gcc-args" >/dev/null
grep -Fqx '// SPDX-License-Identifier: GPL-2.0-or-later' "$work/staged-main.v"
if grep -Fq 'All rights reserved.' "$work/staged-main.v"; then
	echo "desktop build retained the V3-incompatible redundant preamble" >&2
	exit 1
fi

echo "PASS desktop build helper source selection and host staging"
