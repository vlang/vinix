#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/modules/cgcontrol" "$work/modules/kbudget" "$work/modules/klock" "$work/modules/memory" "$work/modules/errno"
cp "$root/kernel/cgcontrol/control.v" "$work/modules/cgcontrol/"
cp "$root/kernel/kbudget/budget.v" "$root/tests/kernel-resources/budget_test.v" "$work/modules/kbudget/"
cat > "$work/v.mod" <<'EOF'
Module { name: 'kernel_resource_budget_tests' }
EOF
cat > "$work/modules/klock/klock.v" <<'EOF'
module klock
import sync
pub struct Lock { mut: mutex sync.Mutex }
pub fn (mut l Lock) acquire() { l.mutex.lock() }
pub fn (mut l Lock) release() { l.mutex.unlock() }
EOF
cp "$root/kernel/memory/table_budget.v" "$root/tests/kernel-resources/table_test.v" "$work/modules/memory/"
cat > "$work/modules/errno/errno.v" <<'EOF'
module errno
pub const enomem = 12
pub fn set(_code u64) {}
EOF
cat > "$work/modules/memory/fixture.v" <<'EOF'
@[has_globals]
module memory
import kbudget
pub const page_size = u64(4096)
pub const higher_half = u64(0)
pub const pte_flags_mask = ~u64(4095)
__global (la57 bool live_pages int)
pub struct Pagemap { pub mut: top_level &u64 = unsafe { nil } kernel_owner kbudget.Owner kernel_charge kbudget.Charge }
pub fn pmm_alloc_fallible(_count u64) voidptr { live_pages++; return unsafe { calloc(usize(page_size), 1) } }
pub fn pmm_free(ptr voidptr, _count u64) { live_pages--; unsafe { C.free(ptr) } }
pub fn user_room(_count u64) bool { return true }
EOF
cd "$work"
"${V:-v}" -enable-globals -gc none -path "$work/modules|@vlib" test modules
