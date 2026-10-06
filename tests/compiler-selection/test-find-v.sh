#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-find-v-test.XXXXXX")
work=$(CDPATH= cd -- "$work" && pwd)
trap 'rm -rf "$work"' EXIT INT TERM

env_command=$(command -v env)
shell_command=$(command -v sh)
mkdir -p "$work/empty-home" "$work/empty-path"

make_compiler() {
	mkdir -p "$(dirname -- "$1")"
	printf '#!/bin/sh\n[ "$#" -eq 1 ] && [ "$1" = version ] || exit 3\n' >"$1"
	case "${2:-valid}" in
		valid) printf "printf 'V 0.5.2 test\\n'\n" >>"$1" ;;
		vim-error)
			printf "printf 'v: line 49: /missing/.viminfo: No such file or directory\\n' >&2\nexit 1\n" >>"$1"
			;;
		non-v) printf "printf 'Vim 9.1\\n'\n" >>"$1" ;;
		failed-version) printf "printf 'V 0.5.2 test\\n'\nexit 1\n" >>"$1" ;;
		no-version) printf 'exit 0\n' >>"$1" ;;
		nondigit-version) printf "printf 'V test\\n'\n" >>"$1" ;;
		*) echo "unknown compiler fixture: $2" >&2; exit 1 ;;
	esac
	chmod +x "$1"
}

run_selector() {
	# Neither the real HOME nor an installed `v` may affect the result.
	"$env_command" -u V -u VINIX_V_COMPILER HOME="$work/empty-home" \
		PATH="$work/empty-path" "$@" "$shell_command" -c \
		'. "$1"; printf "%s" "$V"' sh "$repo/build-support/find-v.sh"
}

assert_selected() {
	expected=$1
	shift
	if ! selected=$(run_selector "$@" 2>"$work/stderr"); then
		cat "$work/stderr" >&2
		echo "expected to select $expected" >&2
		exit 1
	fi
	test "$selected" = "$expected" || {
		echo "expected $expected, selected $selected" >&2
		exit 1
	}
}

assert_diagnostic() {
	grep -F -q -- "$1" "$work/stderr" || {
		cat "$work/stderr" >&2
		echo "expected diagnostic containing $1" >&2
		exit 1
	}
}

assert_rejected() {
	expected_diagnostic=$1
	shift
	if selected=$(run_selector "$@" 2>"$work/stderr"); then
		echo "expected compiler rejection, selected $selected" >&2
		exit 1
	fi
	assert_diagnostic "$expected_diagnostic"
}

# Explicit settings are authoritative; V takes precedence over VINIX_V_COMPILER.
make_compiler "$work/explicit-v"
make_compiler "$work/secondary-v"
assert_selected "$work/explicit-v" "V=$work/explicit-v" \
	"VINIX_V_COMPILER=$work/secondary-v"
assert_selected "$work/secondary-v" "VINIX_V_COMPILER=$work/secondary-v"

# Passing a checkout selects its `v`, even beside a `vnew`.
mkdir -p "$work/explicit-checkout/cmd/v"
: >"$work/explicit-checkout/cmd/v/v.v"
make_compiler "$work/explicit-checkout/v"
make_compiler "$work/explicit-checkout/vnew"
assert_selected "$work/explicit-checkout/v" \
	"VINIX_V_COMPILER=$work/explicit-checkout"

# An exact executable requested through V remains exact even inside a checkout.
assert_selected "$work/explicit-checkout/v" "V=$work/explicit-checkout/v"

# A vnew request uses the adjacent v, including requests resolved through PATH.
assert_selected "$work/explicit-checkout/v" "V=$work/explicit-checkout/vnew"
assert_diagnostic "$work/explicit-checkout/vnew"
assert_selected "$work/explicit-checkout/v" V=vnew "PATH=$work/explicit-checkout"

# Automatic PATH discovery uses the `v` it finds, not a `vnew` beside it.
mkdir -p "$work/path-checkout/cmd/v"
: >"$work/path-checkout/cmd/v/v.v"
make_compiler "$work/path-checkout/v"
make_compiler "$work/path-checkout/vnew"
assert_selected "$work/path-checkout/v" "PATH=$work/path-checkout"

# An installed compiler with no source checkout beside it is used as-is.
make_compiler "$work/installed/v"
assert_selected "$work/installed/v" "PATH=$work/installed"
assert_selected "$work/installed/v" V=v "PATH=$work/installed"

# Paths containing spaces and symlinked installations stay usable.
make_compiler "$work/checkout with spaces/v"
assert_selected "$work/checkout with spaces/v" "V=$work/checkout with spaces/"
mkdir -p "$work/symlinked"
ln -s "$work/installed/v" "$work/symlinked/v"
assert_selected "$work/symlinked/v" "PATH=$work/symlinked"

# PATH wins over the standard checkouts; the code/v layout wins over ~/v.
make_compiler "$work/home/code/v/v"
make_compiler "$work/home/v/v"
assert_selected "$work/installed/v" "HOME=$work/home" "PATH=$work/installed"
assert_selected "$work/home/code/v/v" "HOME=$work/home"
assert_selected "$work/explicit-v" "V=$work/explicit-v" \
	"HOME=$work/home" "PATH=$work/installed"
assert_selected "$work/secondary-v" "VINIX_V_COMPILER=$work/secondary-v" \
	"HOME=$work/home" "PATH=$work/installed"

# The reported .viminfo wrapper failure is diagnosed and a checkout is used.
make_compiler "$work/broken-path/v" vim-error
assert_selected "$work/home/code/v/v" "HOME=$work/home" "PATH=$work/broken-path"
assert_diagnostic "$work/broken-path/v"
assert_diagnostic '.viminfo'

# Successful non-V programs and failing V-looking programs are also skipped.
for fixture in non-v failed-version no-version nondigit-version; do
	make_compiler "$work/$fixture/v" "$fixture"
	assert_selected "$work/home/code/v/v" "HOME=$work/home" "PATH=$work/$fixture"
	assert_diagnostic "$work/$fixture/v"
	# An explicit override fails instead of silently using a valid fallback.
	assert_rejected "$work/$fixture/v" "V=$work/$fixture/v" \
		"VINIX_V_COMPILER=$work/secondary-v" "HOME=$work/home" "PATH=$work/installed"
done
assert_rejected '.viminfo' "VINIX_V_COMPILER=$work/broken-path/v" \
	"HOME=$work/home" "PATH=$work/installed"

# A broken first checkout still allows the second standard checkout.
make_compiler "$work/second-home/code/v/v" non-v
make_compiler "$work/second-home/v/v"
assert_selected "$work/second-home/v/v" "HOME=$work/second-home" \
	"PATH=$work/broken-path"
assert_diagnostic "$work/second-home/code/v/v"

# The compiler beside an explicitly selected vnew is validated too.
make_compiler "$work/broken-checkout/v" non-v
make_compiler "$work/broken-checkout/vnew"
assert_rejected "$work/broken-checkout/v" "V=$work/broken-checkout/vnew" \
	"HOME=$work/home"

# Missing and non-executable explicit settings cannot fall back either.
assert_rejected "$work/missing-v" "V=$work/missing-v" "HOME=$work/home"
make_compiler "$work/not-executable-v"
chmod -x "$work/not-executable-v"
assert_rejected "$work/not-executable-v" "VINIX_V_COMPILER=$work/not-executable-v" \
	"HOME=$work/home"

# With no usable candidate, fail early and explain how to select a compiler.
assert_rejected 'cannot find a working V compiler'
assert_diagnostic 'V/VINIX_V_COMPILER'
make_compiler "$work/broken-home/code/v/v" failed-version
make_compiler "$work/broken-home/v/v" non-v
assert_rejected 'cannot find a working V compiler' "HOME=$work/broken-home" \
	"PATH=$work/broken-path"
assert_diagnostic "$work/broken-path/v"
assert_diagnostic "$work/broken-home/code/v/v"
assert_diagnostic "$work/broken-home/v/v"

echo "V compiler selection tests passed."
