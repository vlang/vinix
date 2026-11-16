// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_active_mask_values_names_and_guards() {
 mut seen := [1024]bool{}
 mut checks := 0
 for width in u32(1) .. 65 { for count in 1 .. 17 {
  name := 'llvm.get.active.lane.mask.v${count}i1.i${width}'
  n,w := vector_active_mask_name(name)!; assert n == count && w == width
  id,actual,bits := vector_float_intrinsic_name(name)!; assert id == .active_lane_mask && actual == count && bits == 1 && scalar_intrinsic_arity(id) == 2
  key := vector_active_mask_key(count,width)!; assert key == 42628 + int(width-1)*16+count-1 && !seen[key-42628]; seen[key-42628] = true
  if _ := scalar_intrinsic_name(name) { assert false }
  maximum := constant_mask(width)
  for a in [u64(0),1,maximum/2,maximum-1,maximum]! { for b in [u64(0),1,maximum/2,maximum-1,maximum]! {
   result := active_mask_vector(IntegerValue{value:a | ~maximum},IntegerValue{value:b | ~maximum},count,width)!
   assert result.undef == 0
   for lane in 0 .. count {
    // Independent widened-add oracle: carry from u64 is separately rejected.
    sum := (a & maximum) + u64(lane)
    assert result.lanes[lane] == IntegerValue{value:u64(sum >= (a & maximum) && sum < (b & maximum))}; checks++
   }
   for lane in count .. 16 { assert result.lanes[lane] == IntegerValue{} }
  }}
  for left_poison in [false,true] { for right_poison in [false,true] {
   result := active_mask_vector(IntegerValue{value:0,poison:left_poison},IntegerValue{value:maximum,poison:right_poison},count,width)!
   for lane in 0 .. count { assert result.lanes[lane].poison == (left_poison || right_poison) }
  }}
 }}
 for value in seen { assert value }
 for name in ['llvm.get.active.lane.mask.v0i1.i32','llvm.get.active.lane.mask.v17i1.i32','llvm.get.active.lane.mask.v01i1.i32','llvm.get.active.lane.mask.v2i2.i32','llvm.get.active.lane.mask.v2i1.i0','llvm.get.active.lane.mask.v2i1.i65','llvm.get.active.lane.mask.v2i1.i032','llvm.get.active.lane.mask.v2i1.f32','llvm.get.active.lane.mask.nxv2i1.i32','llvm.get.active.lane.mask.v2i1.i32.spoof','llvm.get.active.lane.mask.v2i1.i','llvm.get.active.lane.mask.v999999999999999i1.i32'] { if _,_ := vector_active_mask_name(name) { assert false,name } }
 for n in [0,17] { if _ := active_mask_vector(IntegerValue{},IntegerValue{},n,32) { assert false } }
 for w in [u32(0),65] { if _ := active_mask_vector(IntegerValue{},IntegerValue{},1,w) { assert false } }
 for tag in [IntegerValue{aggregate:true},IntegerValue{vector:true}] {
  if _ := active_mask_vector(tag,IntegerValue{},1,32) { assert false }
  if _ := active_mask_vector(IntegerValue{},tag,1,32) { assert false }
 }
 assert checks == 217600
 println('AIR-ACTIVE-MASK-UNIT: 1024 overload/key identities, ${checks} widened-add lane checks, poison/normalization/unused-lane and canonical guards PASS')
}
