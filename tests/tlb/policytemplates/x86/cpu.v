@[has_globals]
module cpu
__global (pub feature_bits u8 = 3 pub hardware_root u64 pub control u64)
pub fn cpuid(leaf u32, _ u32) (bool, u32, u32, u32, u32) {
 return true, 0, if feature_bits & 2 != 0 && leaf == 7 { u32(1) << 10 } else { u32(0) },
 if feature_bits & 1 != 0 && leaf == 1 { u32(1) << 17 } else { u32(0) }, 0
}
pub fn read_cr3() u64 { return hardware_root }
pub fn write_cr3(value u64) { hardware_root = value }
pub fn read_cr4() u64 { return control }
pub fn write_cr4(value u64) { control = value }
pub fn invlpg(_ u64) {}
