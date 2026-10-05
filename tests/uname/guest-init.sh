#!/bin/sh
set -eu
export PATH=/usr/bin:/bin
trap 'echo "UNAME FAIL"' EXIT

check() {
    expected=$1
    shift
    actual=$(uname "$@")
    if [ "$actual" != "$expected" ]; then
        printf 'UNAME FAIL: uname %s: expected <%s>, got <%s>\n' "$*" "$expected" "$actual"
        exit 1
    fi
}

kernel=$(/bin/busybox uname -s)
test "$kernel" = Vinix
check "$kernel"
check "$kernel" -s
check "$kernel" --
check "$kernel" -o
check "$kernel" --operating-system
check "$kernel" --operating
check "$kernel" -o --
check "$kernel $kernel" -os
check "$kernel $kernel" -o -s -o
check "$(/bin/busybox uname -m) $kernel" -mo
check "$(/bin/busybox uname -m)" -m
check "$(/bin/busybox uname -r)" -r
all=$(/bin/busybox uname -snrvm)
for field in -p -i; do
    value=$(/bin/busybox uname "$field")
    [ "$value" = unknown ] || all="$all $value"
done
all="$all $kernel"
check "$all" -a
check "$all" -oa
check "$all" -a -o
check "$all" --all
check "$all" --al
check "$all" --all --operating-system
test "$(/bin/uname -o)" = "$kernel"
printf 'UNAME OUTPUT: %s\n' "$(uname -a)"

# A hostname equal to BusyBox's label must not be rewritten by uname -n.
hostname=$(/bin/busybox hostname)
/bin/busybox hostname Linux
check Linux -n
check "Linux $kernel" -no
/bin/busybox hostname "$hostname"

for argument in --invalid -z operand; do
    if uname "$argument" >/dev/null 2>&1; then
        echo "UNAME FAIL: accepted $argument"
        exit 1
    fi
    if uname -a "$argument" >/dev/null 2>&1; then
        echo "UNAME FAIL: accepted -a $argument"
        exit 1
    fi
done
uname --help >/dev/null 2>&1

# Linux-compatible UTS namespaces keep the packaged Linux label.
/bin/busybox unshare -u /bin/sh -c '
    test "$(uname -s)" = Linux &&
    test "$(uname -o)" = "$(/bin/busybox uname -o)" &&
    test "$(uname -a)" = "$(/bin/busybox uname -a)"
'
trap - EXIT
echo 'UNAME PASS'
exec /bin/busybox sleep 60
