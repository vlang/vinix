// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Two representatives of each class, independent of production classification.
fn vector_fpclass_examples(bits u32) [20]u64 {
 return if bits == 16 { [u64(0x7c01), 0xfcff, 0x7e00, 0xffff, 0xfc00, 0xfc00, 0x8400, 0xfbff, 0x8001, 0x83ff, 0x8000, 0x8000, 0, 0, 1, 0x3ff, 0x400, 0x7bff, 0x7c00, 0x7c00]! } else { [u64(0x7f800001), 0xffbfffff, 0x7fc00000, 0xffffffff, 0xff800000, 0xff800000, 0x80800000, 0xff7fffff, 0x80000001, 0x807fffff, 0x80000000, 0x80000000, 0, 0, 1, 0x7fffff, 0x800000, 0x7f7fffff, 0x7f800000, 0x7f800000]! }
}
fn test_vector_fpclass_values() {
 mut checks := 0
 for bits in [u32(16), 32]! {
  examples := vector_fpclass_examples(bits)
  for count in 1 .. 17 { for mask in 0 .. 1024 { for sample in 0 .. 20 {
   mut source := ScalarVectorValue{}
   for lane in 0 .. count { source.lanes[lane] = IntegerValue{value: examples[(sample + lane) % 20] | ~constant_mask(bits)} }
   before := source; result := fpclass_intrinsic_vector(source, bits, count, u64(mask))!
   for lane in 0 .. count { assert result.lanes[lane] == IntegerValue{value: u64(mask & (1 << (((sample + lane) % 20) / 2)) != 0)}; checks++ }
   assert source == before && result.undef == 0
  } } }
 }
 assert checks == 5570560
 println('AIR-VECTOR-FPCLASS-VALUES: ${checks} exact lane results, all 1024 masks, ten classes/boundaries/signs, both formats and every count 1-16; masking and snapshots PASS')
}
fn test_vector_fpclass_states_names_and_masks() {
 mut checks := 0; mut seen := [32]bool{}
 for bits in [u32(16), 32]! { for count in 1 .. 17 {
  id, n, width := vector_float_intrinsic_name('llvm.is.fpclass.v${count}f${bits}')!; assert id == .is_fpclass && n == count && width == bits
  key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 608 && key < 640 && !seen[key - 608]; seen[key - 608] = true
  for mask in [u64(0), 1, 3, 96, 1023]! { for target in 0 .. count {
   mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}; result := fpclass_intrinsic_vector(source, bits, count, mask)!
   for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }
   assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
   source.undef = u16(1) << u32(target); if _ := fpclass_intrinsic_vector(source, bits, count, mask) { assert false, 'undef dominates poison even for empty/full mask' }; checks++
  } }
 } }; for slot in seen { assert slot }
 for name in ['llvm.is.fpclass.f32', 'llvm.is.fpclass.v0f16', 'llvm.is.fpclass.v01f32', 'llvm.is.fpclass.v17f16', 'llvm.is.fpclass.v99999999999f32', 'llvm.is.fpclass.v2f64', 'llvm.is.fpclass.v2bf16', 'llvm.is.fpclass.v2i32', 'llvm.is.fpclass.v2f016', 'llvm.is.fpclass.v2f32.spoof', 'llvm.is.fpclass.v2f32.i32', 'llvm.is.fpclass.nxv2f32', 'air.is.fpclass.v2f32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
 for mask in [u64(1024), 0xffffffff, 0x100000000]! { if _ := fpclass_intrinsic_vector(ScalarVectorValue{}, 32, 1, mask) { assert false, 'mask' } }
 for count in [0, 17] { if _ := fpclass_intrinsic_vector(ScalarVectorValue{}, 16, count, 0) { assert false, 'count' } }
 for width in [u32(0), 1, 64]! { if _ := fpclass_intrinsic_vector(ScalarVectorValue{}, width, 1, 0) { assert false, 'width' } }
 for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := fpclass_intrinsic_vector(source, 32, 1, 0) { assert false, 'lane tag' } }
 assert checks == 16320
 println('AIR-VECTOR-FPCLASS-STATES: ${checks} poison/undef/freeze lane checks including empty/full masks, 32 overload/cache identities and name/mask/shape/tag guards PASS')
}
