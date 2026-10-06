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
# Each candidate must report a V version before a build can use it: another
# program or a broken wrapper named `v` can also be installed on PATH.

select_v() {
    local candidate="$1" version
    local severity="${2:-ERROR}"

    if [ -d "$candidate" ]; then
        candidate="${candidate%/}/v"
    fi
    # Explicit overrides may name a command on PATH as well as a file.
    case "$candidate" in
        */*) ;;
        *) candidate="$(command -v "$candidate" 2>/dev/null)" || {
            echo "$severity: V compiler is not executable: $1" >&2
            return 1
        } ;;
    esac
    case "$candidate" in
        */vnew)
            if [ -x "${candidate%vnew}v" ]; then
                echo "NOTE: using ${candidate%vnew}v, not $candidate" >&2
                candidate="${candidate%vnew}v"
            fi
            ;;
    esac

    if [ ! -x "$candidate" ]; then
        echo "$severity: V compiler is not executable: $candidate" >&2
        return 1
    fi

    if version="$("$candidate" version </dev/null 2>&1)"; then
        case "$version" in
            'V '[0-9]*)
                V="$candidate"
                return 0
                ;;
        esac
    fi

    echo "$severity: not a working V compiler: $candidate (checked with 'version')" >&2
    if [ -n "$version" ]; then
        printf '%s\n' "$version" >&2
    fi
    return 1
}

find_v() {
    local candidate

    if [ -n "${V:-}" ]; then
        select_v "$V"
        return
    fi

    if [ -n "${VINIX_V_COMPILER:-}" ]; then
        select_v "$VINIX_V_COMPILER"
        return
    fi

    if command -v v >/dev/null 2>&1; then
        candidate="$(command -v v)"
        if select_v "$candidate" WARNING; then
            return 0
        fi
    fi

    # The usual checkout layout, also used when PATH's `v` is unusable.
    for candidate in "$HOME/code/v/v" "$HOME/v/v"; do
        if [ -x "$candidate" ] && select_v "$candidate" WARNING; then
            return 0
        fi
    done

    echo "ERROR: cannot find a working V compiler." >&2
    return 1
}

find_v "$@" || {
    echo "Set V/VINIX_V_COMPILER to a V programming language compiler:" >&2
    echo "    V=~/code/v/v $0 $*" >&2
    echo "    VINIX_V_COMPILER=~/code/v $0 $*" >&2
    exit 1
}
export V
