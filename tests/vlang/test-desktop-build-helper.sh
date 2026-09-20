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
while [ "$#" -gt 0 ]; do
	if [ "$1" = -o ]; then
		printf 'int main(void) { return 0; }\n' > "$2"
		exit 0
	fi
	shift
done
exit 1
EOF
cat > "$work/bin/gcc" <<'EOF'
#!/bin/sh
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
chmod 755 "$work/bin/v" "$work/bin/gcc"

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

echo "PASS desktop build helper source-generation selection"
