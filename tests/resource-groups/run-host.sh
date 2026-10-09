#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/modules/cgcontrol" "$work/modules/kbudget" "$work/modules/klock"
cp "$root/kernel/cgcontrol/control.v" "$root/tests/resource-groups/control_test.v" "$work/modules/cgcontrol/"
cp "$root/kernel/kbudget/budget.v" "$root/tests/resource-groups/budget_test.v" "$work/modules/kbudget/"
cat > "$work/v.mod" <<'EOF'
Module { name: 'resource_group_tests' }
EOF
cat > "$work/modules/klock/klock.v" <<'EOF'
module klock
import sync
pub struct Lock { mut: mutex sync.Mutex }
pub fn (mut l Lock) acquire() { l.mutex.lock() }
pub fn (mut l Lock) release() { l.mutex.unlock() }
EOF
cd "$work"
"${V:-v}" -enable-globals -gc none -path "$work/modules|@vlib" test modules
