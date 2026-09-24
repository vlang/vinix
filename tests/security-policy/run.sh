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

# The policy's sole kernel dependency is the trusted current process: its
# effective UID and capability sets. Stage a controlled credential source so the
# production policy can be tested on the host without linking the rest of the
# freestanding kernel.
cat > "$work/proc/proc.v" <<'EOF'
@[has_globals]
module proc

__global test_euid = u32(0)
__global test_caps = u64(-1)

pub const cap_sys_admin = 21
pub const cap_sys_boot = 22

pub struct Capabilities {
pub:
    effective u64
}

pub struct Process {
pub:
    euid u32
    caps Capabilities
}

pub struct Thread {
pub:
    process &Process
}

pub fn set_test_euid(uid u32) {
    test_euid = uid
}

pub fn set_test_caps(caps u64) {
    test_caps = caps
}

pub fn current_thread() &Thread {
    return &Thread{process: &Process{euid: test_euid, caps: Capabilities{effective: test_caps}}}
}

pub fn has_capability(process &Process, cap int) bool {
    return process.caps.effective & (u64(1) << cap) != 0
}
EOF

"$v" -new-compiler -gc none -manualfree -enable-globals \
    -path "@vlib|$work|@vmodules" test "$work/security/policy_test.v"
