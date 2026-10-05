#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/smp" "$work/x86/cpu" "$work/limine"
cp "$root/kernel/x86/smp/topology.v" "$root/tests/smt-policy/topology_test.v" "$work/smp/"
cat > "$work/x86/cpu/cpu.v" <<'VEOF'
@[has_globals]
module cpu
struct Leaf { leaf u32 level u32 width u32 count u32 kind u32 }
__global (entries []Leaf)
pub fn clear() { entries.clear() }
pub fn add(leaf u32, level u32, width u32, count u32, kind u32) {
 entries << Leaf{leaf, level, width, count, kind}
}
pub fn cpuid(leaf u32, level u32) (bool, u32, u32, u32, u32) {
 for entry in entries {
  if entry.leaf == leaf && entry.level == level {
   return true, entry.width, entry.count, entry.kind << 8, 0
  }
 }
 return false, 0, 0, 0, 0
}
VEOF
cat > "$work/limine/limine.v" <<'VEOF'
@[has_globals]
module limine
pub struct File { pub mut: cmdline charptr }
__global (mock_boot_file File)
pub fn kernel_file() &File { return unsafe { &mock_boot_file } }
pub fn command(value string) { mock_boot_file.cmdline = unsafe { charptr(value.str) } }
VEOF
VMODULES="$work" "${V:-v}" -enable-globals test "$work/smp"
