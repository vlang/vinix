module cpu
import policytransport
pub fn cpuid(leaf u32, subleaf u32) (bool, u32, u32, u32, u32) { return policytransport.cpuid(leaf, subleaf) }
pub fn read_cr4() u64 { return policytransport.read_cr4() }
