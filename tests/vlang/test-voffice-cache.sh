#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-voffice-cache-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

ui2=$work/ui2
office=$work/office
toolchain=$work/toolchain
sysroot=$work/sysroot
gcclib=$work/gcclib
resource=$work/clang-resource
mkdir -p "$ui2/ui" "$office/cmd/excel" "$office/cmd/word" \
	"$office/assets" "$office/vba" "$toolchain/vlib/net/mbedtls" \
	"$toolchain/vlib/v/checker/tests" "$toolchain/vlib/v/driver" \
	"$toolchain/thirdparty/mbedtls/library" "$resource/include" \
	"$sysroot/usr/include" "$sysroot/usr/lib" "$gcclib/include" "$work/bin"

printf "Module { name: 'ui2', subdirs: ['ui'] }\n" > "$ui2/v.mod"
printf 'module ui\n' > "$ui2/ui/ui.v"
printf "Module { name: 'office' }\n" > "$office/v.mod"
printf '0.0.1\n' > "$office/VERSION"
printf 'logo\n' > "$office/assets/logo.png"
printf 'module main\nimport office.vba\n' > "$office/cmd/excel/main.v"
printf 'module main\nimport office.vba\n' > "$office/cmd/word/main.v"
printf 'module vba\n' > "$office/vba/vba.v"
printf '#flag @VEXEROOT/thirdparty/mbedtls/library/fake.o\n' \
	> "$toolchain/vlib/net/mbedtls/mbedtls.c.v"
printf 'module driver\n' > "$toolchain/vlib/v/driver/driver.v"
printf 'int fake_tls;\n' > "$toolchain/thirdparty/mbedtls/library/fake.c"

for name in crt1.o crti.o crtn.o libc.a libm.a; do
	: > "$sysroot/usr/lib/$name"
done
for name in crtbeginT.o crtend.o libgcc.a libgcc_eh.a; do
	: > "$gcclib/$name"
done
: > "$work/bin/ld.lld"

cat > "$toolchain/v" <<'EOF'
#!/bin/sh
count=0
if [ -f "$VINIX_VOFFICE_V_COUNT" ]; then
	count=$(cat "$VINIX_VOFFICE_V_COUNT")
fi
printf '%s\n' "$((count + 1))" > "$VINIX_VOFFICE_V_COUNT"
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
printf 'int main(void) { return 0; }\n' > "$output"
EOF
chmod 755 "$toolchain/v"

cat > "$work/bin/clang" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --print-resource-dir ]; then
	printf '%s\n' "$VINIX_VOFFICE_RESOURCE_DIR"
	exit 0
fi
count=0
if [ -f "$VINIX_VOFFICE_CC_COUNT" ]; then
	count=$(cat "$VINIX_VOFFICE_CC_COUNT")
fi
printf '%s\n' "$((count + 1))" > "$VINIX_VOFFICE_CC_COUNT"
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
chmod 755 "$work/bin/clang"

cat > "$work/bin/strip" <<'EOF'
#!/bin/sh
chmod 755 "$1"
EOF
chmod 755 "$work/bin/strip"

build() {
	VINIX_VOFFICE_V_COUNT=$work/v-count \
	VINIX_VOFFICE_CC_COUNT=$work/cc-count \
	VINIX_VOFFICE_RESOURCE_DIR=$resource \
		python3 "$repo/desktop/tools/build_voffice.py" \
		--repo "$repo" --office-source "$office" --ui2-source "$ui2" \
		--output "$work/output" --work "$work/build" --v "$toolchain/v" \
		--arch arm64 --clang "$work/bin/clang" --strip "$work/bin/strip" \
		--target aarch64-linux-musl --sysroot "$sysroot" --gcclib "$gcclib" \
		--llvm-bin "$work/bin" --jobs 1
}

build >/dev/null
test "$(cat "$work/v-count")" -eq 2
test "$(cat "$work/cc-count")" -eq 3

# Completed Office binaries live independently from temporary generated C and
# mbedTLS objects, so cleaning a deploy workspace must remain a cache hit.
rm -rf "$work/build"
second=$(build)
test "$(cat "$work/v-count")" -eq 2
test "$(cat "$work/cc-count")" -eq 3
printf '%s\n' "$second" | grep -F 'reusing 2 cached VOffice applications' >/dev/null

# V's test outputs and compiler implementation sources do not affect an app
# until the compiler executable changes, so neither may invalidate this cache.
printf '#!/bin/sh\n' > "$toolchain/vlib/v/checker/tests/generated"
chmod 755 "$toolchain/vlib/v/checker/tests/generated"
printf '// compiler source changed\n' >> "$toolchain/vlib/v/driver/driver.v"
build >/dev/null
test "$(cat "$work/v-count")" -eq 2
test "$(cat "$work/cc-count")" -eq 3

# Test-only source is not part of V's production compilation.
printf 'module main\n' > "$office/cmd/excel/model_test.v"
build >/dev/null
test "$(cat "$work/v-count")" -eq 2
test "$(cat "$work/cc-count")" -eq 3

# An app-local edit rebuilds only that app (plus its temporary TLS objects).
printf '// changed\n' >> "$office/cmd/excel/main.v"
partial=$(build)
test "$(cat "$work/v-count")" -eq 3
test "$(cat "$work/cc-count")" -eq 5
printf '%s\n' "$partial" | grep -F 'built 1 VOffice applications; reused 1 cached' >/dev/null

# A missing artifact is never treated as a cache hit.
rm "$work/output/voffice-writer"
build >/dev/null
test "$(cat "$work/v-count")" -eq 4
test "$(cat "$work/cc-count")" -eq 7

# A shared Office module invalidates both applications.
printf '// shared change\n' >> "$office/vba/vba.v"
build >/dev/null
test "$(cat "$work/v-count")" -eq 6
test "$(cat "$work/cc-count")" -eq 10

echo 'PASS VOffice build cache'
