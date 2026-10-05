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
# VINIX_V_COMPILER is the equivalent project-specific setting.  Either may be
# an executable or a V checkout directory, whose `v` is used.
#
# Vinix builds with a checkout's `v` (~/code/v/v here), never with the `vnew`
# a V developer's tree may also hold: those go stale and stop building the
# desktop. A `vnew` named explicitly is swapped for the `v` beside it.

select_v() {
    local candidate="$1"

    if [ -d "$candidate" ]; then
        candidate="${candidate%/}/v"
    fi
    case "$candidate" in
        */vnew)
            if [ -x "${candidate%vnew}v" ]; then
                echo "NOTE: using ${candidate%vnew}v, not $candidate" >&2
                candidate="${candidate%vnew}v"
            fi
            ;;
    esac

    if [ -x "$candidate" ]; then
        V="$candidate"
        return 0
    fi

    echo "ERROR: V compiler is not executable: $candidate" >&2
    return 1
}

find_v() {
    if [ -n "${V:-}" ]; then
        select_v "$V"
        return
    fi

    if [ -n "${VINIX_V_COMPILER:-}" ]; then
        select_v "$VINIX_V_COMPILER"
        return
    fi

    if command -v v >/dev/null 2>&1; then
        V="$(command -v v)"
        return 0
    fi

    # The usual checkout layout. Take the first one that can at least report
    # its version.
    for candidate in "$HOME/code/v/v" "$HOME/v/v"; do
        if [ -x "$candidate" ] && "$candidate" version >/dev/null 2>&1; then
            V="$candidate"
            return 0
        fi
    done

    echo "ERROR: cannot find the V compiler." >&2
    echo "Put it on PATH, or set V/VINIX_V_COMPILER to it:" >&2
    echo "    V=~/code/v/v $0 $*" >&2
    echo "    VINIX_V_COMPILER=~/code/v $0 $*" >&2
    return 1
}

find_v "$@" || exit 1
export V
