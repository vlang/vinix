#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-ui2-cache-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

ui2=$work/ui2
mkdir -p "$ui2/ui" "$work/bin"
printf "Module { name: 'ui2', subdirs: ['ui'] }\n" > "$ui2/v.mod"
printf 'module ui\n' > "$ui2/ui/ui.v"
while IFS= read -r name; do
	[ -n "$name" ] || continue
	mkdir -p "$ui2/examples/$name"
	printf 'module main\n' > "$ui2/examples/$name/main.v"
done < "$repo/desktop/ui2_examples.txt"

fake_v=$work/bin/v
cat > "$fake_v" <<'EOF'
#!/bin/sh
count=0
if [ -f "$VINIX_UI2_CACHE_TEST_COUNT" ]; then
	count=$(cat "$VINIX_UI2_CACHE_TEST_COUNT")
fi
count=$((count + 1))
printf '%s\n' "$count" > "$VINIX_UI2_CACHE_TEST_COUNT"
output=
while [ "$#" -gt 0 ]; do
	if [ "$1" = -o ]; then
		shift
		output=$1
		break
	fi
	shift
done
[ -n "$output" ]
printf '#!/bin/sh\nexit 0\n' > "$output"
chmod 755 "$output"
EOF
chmod 755 "$fake_v"

build_one() {
	VINIX_UI2_CACHE_TEST_COUNT=$work/count \
		python3 "$repo/desktop/tools/build_ui2_examples.py" \
		--host --only counter --repo "$repo" --ui2-source "$ui2" \
		--output "$work/output" --work "$work/build" --v "$fake_v"
}

build_one >/dev/null
test "$(cat "$work/count")" -eq 1

second=$(build_one)
test "$(cat "$work/count")" -eq 1
printf '%s\n' "$second" | grep -F 'reusing 1 cached ui2 example applications' >/dev/null

# An unrelated example does not invalidate the requested cached application.
printf '// unrelated change\n' >> "$ui2/examples/accordion/main.v"
build_one >/dev/null
test "$(cat "$work/count")" -eq 1

printf '// changed\n' >> "$ui2/examples/counter/main.v"
build_one >/dev/null
test "$(cat "$work/count")" -eq 2

rm "$work/output/vinix-ui2-counter"
build_one >/dev/null
test "$(cat "$work/count")" -eq 3

printf '\n' >> "$fake_v"
build_one >/dev/null
test "$(cat "$work/count")" -eq 4

echo 'PASS ui2 example build cache'
