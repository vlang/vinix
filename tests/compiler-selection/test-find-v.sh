#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-find-v-test.XXXXXX")
work=$(CDPATH= cd -- "$work" && pwd)
trap 'rm -rf "$work"' EXIT INT TERM

make_executable() {
	mkdir -p "$(dirname -- "$1")"
	printf '#!/bin/sh\nexit 0\n' >"$1"
	chmod +x "$1"
}

assert_selected() {
	expected=$1
	shift
	selected=$(env -u V -u VINIX_V_COMPILER PATH="$PATH" "$@" sh -c \
		'. "$1"; printf "%s" "$V"' sh "$repo/build-support/find-v.sh")
	test "$selected" = "$expected" || {
		echo "expected $expected, selected $selected" >&2
		exit 1
	}
}

# An explicitly named compiler remains authoritative.
make_executable "$work/explicit-v"
selected=$(V="$work/explicit-v" sh -c \
	'. "$1"; printf "%s" "$V"' sh "$repo/build-support/find-v.sh")
test "$selected" = "$work/explicit-v"

# Passing a checkout selects its development compiler before its bootstrap.
mkdir -p "$work/explicit-checkout/cmd/v"
: >"$work/explicit-checkout/cmd/v/v.v"
make_executable "$work/explicit-checkout/v"
make_executable "$work/explicit-checkout/vnew"
selected=$(VINIX_V_COMPILER="$work/explicit-checkout" sh -c \
	'. "$1"; printf "%s" "$V"' sh "$repo/build-support/find-v.sh")
test "$selected" = "$work/explicit-checkout/vnew"

# The same preference applies when the checkout's bootstrap `v` is on PATH.
mkdir -p "$work/path-checkout/cmd/v"
: >"$work/path-checkout/cmd/v/v.v"
make_executable "$work/path-checkout/v"
make_executable "$work/path-checkout/vnew"
assert_selected "$work/path-checkout/vnew" env PATH="$work/path-checkout:$PATH"

# An installed compiler with no source checkout beside it is used as-is.
make_executable "$work/installed/v"
assert_selected "$work/installed/v" env PATH="$work/installed:$PATH"

echo "V compiler selection tests passed."
