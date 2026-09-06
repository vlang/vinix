# Locate the V compiler, for sourcing by the build scripts.
#
# Sets V to a path that can be handed to `make`. This exists because `v` is
# usually a shell alias pointing into a V checkout, and an alias is invisible
# to make and to any non-interactive shell — so a build that just said `v`
# failed with "make: v: No such file or directory", several lines up from
# whatever error the caller actually reported.
#
#   . "$SCRIPT_DIR/build-support/find-v.sh"
#
# $V is honoured if already set, so a caller can point at a particular build.

find_v() {
    if [ -n "$V" ] && [ -x "$V" ]; then
        return 0
    fi

    if command -v v >/dev/null 2>&1; then
        V="$(command -v v)"
        return 0
    fi

    # The usual checkout layout. `vnew` is the freshly built compiler a V
    # developer runs from a source tree; `v` is the released one.
    for candidate in "$HOME/code/v/vnew" "$HOME/code/v/v" "$HOME/v/v"; do
        if [ -x "$candidate" ]; then
            V="$candidate"
            return 0
        fi
    done

    echo "ERROR: cannot find the V compiler." >&2
    echo "Put it on PATH, or set V to it:" >&2
    echo "    V=/path/to/v $0 $*" >&2
    return 1
}

find_v "$@" || exit 1
export V
