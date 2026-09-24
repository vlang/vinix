#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
command -v "$v" >/dev/null 2>&1 || {
    echo 'ERROR: V is required.' >&2
    exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/security" "$work/proc"
cp "$root/kernel/security/policy.v" "$root/tests/security-policy/policy_test.v" \
    "$work/security/"

# The policy's sole kernel dependency is the trusted current process. Stage a
# controlled credential source so the production policy can be tested on the
# host without linking the rest of the freestanding kernel.
cat > "$work/proc/proc.v" <<'EOF'
@[has_globals]
module proc

__global test_euid = u32(0)

pub struct Process {
pub:
    euid u32
}

pub struct Thread {
pub:
    process Process
}

pub fn set_test_euid(uid u32) {
    test_euid = uid
}

pub fn current_thread() Thread {
    return Thread{process: Process{euid: test_euid}}
}
EOF

"$v" -new-compiler -gc none -manualfree -enable-globals \
    -path "@vlib|$work|@vmodules" test "$work/security/policy_test.v"
