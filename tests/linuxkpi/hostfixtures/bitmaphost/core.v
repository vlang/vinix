// SPDX-License-Identifier: GPL-2.0-or-later
// The original bool-per-bit oracle remains independent of word-mask algorithms.
@[translated]
@[has_globals]
module bitmaphost
#include "bitmaphost_v_contract.h"
fn C.__bitmap_equal(&usize,&usize,u32) bool
fn C.__bitmap_subset(&usize,&usize,u32) bool
fn C.__bitmap_intersects(&usize,&usize,u32) bool
fn C.__bitmap_weight(&usize,u32) u32
fn C.__bitmap_weight_and(&usize,&usize,u32) u32
fn C.bitmap_empty(&usize,u32) bool
fn C.bitmap_full(&usize,u32) bool
fn C.bitmap_weight(&usize,u32) u32
fn C.__bitmap_and(&usize,&usize,&usize,u32) bool
fn C.__bitmap_andnot(&usize,&usize,&usize,u32) bool
fn C.__bitmap_or(&usize,&usize,&usize,u32)
fn C.__bitmap_xor(&usize,&usize,&usize,u32)
fn C.__bitmap_or_equal(&usize,&usize,&usize,u32) bool
fn C.__bitmap_complement(&usize,&usize,u32)
fn C.__bitmap_replace(&usize,&usize,&usize,&usize,u32)
fn C.__bitmap_shift_right(&usize,&usize,u32,u32)
fn C.__bitmap_shift_left(&usize,&usize,u32,u32)
fn C.__bitmap_clear(&usize,u32,u32)
fn C.__bitmap_set(&usize,u32,u32)
fn C.bitmap_to_arr32(&u32,&usize,u32)
fn C.bitmap_from_arr32(&usize,&u32,u32)
fn C.bitmap_zalloc(u32,u32) &usize
fn C.bitmap_alloc(u32,u32) &usize
fn C.bitmap_zalloc_node(u32,u32,i32) &usize
fn C.bitmap_alloc_node(u32,u32,i32) &usize
fn C.bitmap_free(&usize)
fn C.ksize(voidptr) usize
fn C.vinix_linuxkpi_bitmap_runtime_selftest() i32
fn C.malloc(usize) voidptr
fn C.free(voidptr)
const test_bits = 8193
const test_words = 130
const guard = usize(0x5a15a15a15a15a15)
const widths = [u32(0),1,31,32,33,63,64,65,127,128,129,257,4097,8193]!
fn bitmap_test_bit(bitmap &usize,bit u32) bool { unsafe { return (bitmap[bit/64]&(usize(1)<<(bit%64)))!=0 } }
fn bitmap_test_check(bitmap &usize,expected &bool,nbits u32) { unsafe {
 for bit:=u32(0); bit<nbits; bit++ { C.assert(bitmap_test_bit(bitmap,bit)==expected[bit]) }
 words:=usize(nbits/64)+if nbits%64!=0 { usize(1) } else { usize(0) }
 C.assert(bitmap[words]==guard)
} }
fn bitmap_runtime_properties(nbits u32,seed &usize) { unsafe {
 mut a:=[test_words]usize{}; mut b:=[test_words]usize{}; mut mask:=[test_words]usize{}; mut dst:=[test_words]usize{}; mut alias:=[test_words]usize{}
 mut ar:=[test_bits]bool{}; mut br:=[test_bits]bool{}; mut mr:=[test_bits]bool{}; mut expected:=[test_bits]bool{}
 words:=usize(nbits/64)+if nbits%64!=0 { usize(1) } else { usize(0) }
 for word:=usize(0); word<words; word++ {
  *seed^=*seed<<13; *seed^=*seed>>7; *seed^=*seed<<17
  a[word]=*seed; b[word]=*seed*usize(0x9e3779b97f4a7c15); mask[word]=*seed^usize(0xaaaaaaaaaaaaaaaa)
 }
 a[words]=guard; b[words]=guard; mask[words]=guard; dst[words]=guard
 mut equal:=true; mut subset:=true; mut intersects:=false; mut empty:=true; mut full:=true; mut weight:=u32(0); mut weight_and:=u32(0)
 for bit:=u32(0); bit<nbits; bit++ {
  ar[bit]=bitmap_test_bit(&a[0],bit); br[bit]=bitmap_test_bit(&b[0],bit); mr[bit]=bitmap_test_bit(&mask[0],bit)
  equal=equal && ar[bit]==br[bit]; subset=subset && (!ar[bit] || br[bit]); intersects=intersects || (ar[bit]&&br[bit]); empty=empty && !ar[bit]; full=full && ar[bit]
  if ar[bit] { weight++ }; if ar[bit]&&br[bit] { weight_and++ }
 }
 C.assert(C.__bitmap_equal(&a[0],&b[0],nbits)==equal); C.assert(C.__bitmap_subset(&a[0],&b[0],nbits)==subset)
 C.assert(C.__bitmap_intersects(&a[0],&b[0],nbits)==intersects); C.assert(C.__bitmap_weight(&a[0],nbits)==weight)
 C.assert(C.__bitmap_weight_and(&a[0],&b[0],nbits)==weight_and); C.assert(C.bitmap_empty(&a[0],nbits)==empty && C.bitmap_full(&a[0],nbits)==full); C.assert(C.bitmap_weight(&a[0],nbits)==weight)
 for operation:=u32(0); operation<4; operation++ {
  mut any:=false
  for bit:=u32(0); bit<nbits; bit++ {
   if operation==0 { expected[bit]=ar[bit]&&br[bit] }; if operation==1 { expected[bit]=ar[bit]&&!br[bit] }
   if operation==2 { expected[bit]=ar[bit]||br[bit] }; if operation==3 { expected[bit]=ar[bit]!=br[bit] }; any=any || expected[bit]
  }
  for target:=u32(0); target<3; target++ {
   mut lhs:=&a[0]; mut rhs:=&b[0]; mut out:=&dst[0]
   if target!=0 { C.memcpy(&alias[0],if target==1 { &a[0] } else { &b[0] },(words+1)*sizeof(usize)); out=&alias[0]; if target==1 { lhs=&alias[0] } else { rhs=&alias[0] } }
   if operation==0 { C.assert(C.__bitmap_and(out,lhs,rhs,nbits)==any) }; if operation==1 { C.assert(C.__bitmap_andnot(out,lhs,rhs,nbits)==any) }
   if operation==2 { C.__bitmap_or(out,lhs,rhs,nbits) }; if operation==3 { C.__bitmap_xor(out,lhs,rhs,nbits) }
   bitmap_test_check(out,&expected[0],nbits)
   if operation==2 { C.assert(C.__bitmap_or_equal(&a[0],&b[0],out,nbits)) }
   if operation<2 && nbits%64!=0 { for bit:=nbits; usize(bit)<words*64; bit++ { C.assert(!bitmap_test_bit(out,bit)) } }
  }
 }
 for bit:=u32(0); bit<nbits; bit++ { expected[bit]=!ar[bit] }
 C.__bitmap_complement(&dst[0],&a[0],nbits); bitmap_test_check(&dst[0],&expected[0],nbits)
 C.memcpy(&alias[0],&a[0],(words+1)*sizeof(usize)); C.__bitmap_complement(&alias[0],&alias[0],nbits); bitmap_test_check(&alias[0],&expected[0],nbits)
 for bit:=u32(0); bit<nbits; bit++ { expected[bit]=if mr[bit] { br[bit] } else { ar[bit] } }
 for target:=u32(0); target<4; target++ {
  mut old:=&a[0]; mut new:=&b[0]; mut selection:=&mask[0]; mut out:=&dst[0]
  if target!=0 { C.memcpy(&alias[0],if target==1 { &a[0] } else if target==2 { &b[0] } else { &mask[0] },(words+1)*sizeof(usize)); out=&alias[0]; if target==1 { old=&alias[0] }; if target==2 { new=&alias[0] }; if target==3 { selection=&alias[0] } }
  C.__bitmap_replace(out,old,new,selection,nbits); bitmap_test_check(out,&expected[0],nbits)
 }
 shifts:=[u32(0),1,31,32,63,64,65,if nbits!=0 { nbits-1 } else { u32(0) },nbits,nbits+1,~u32(0)]!
 for s:=usize(0); s<shifts.len; s++ { shift:=shifts[s]
  for direction:=u32(0); direction<2; direction++ {
   for bit:=u32(0); bit<nbits; bit++ { expected[bit]=false; if direction==0 && shift<nbits-bit { expected[bit]=ar[bit+shift] }; if direction==1 && bit>=shift { expected[bit]=ar[bit-shift] } }
   C.memcpy(&alias[0],&a[0],(words+1)*sizeof(usize))
   if direction==0 { C.__bitmap_shift_right(&dst[0],&a[0],shift,nbits); C.__bitmap_shift_right(&alias[0],&alias[0],shift,nbits) } else { C.__bitmap_shift_left(&dst[0],&a[0],shift,nbits); C.__bitmap_shift_left(&alias[0],&alias[0],shift,nbits) }
   bitmap_test_check(&dst[0],&expected[0],nbits); bitmap_test_check(&alias[0],&expected[0],nbits)
  }
 }
 starts:=[u32(0),1,31,63,64,nbits]!; lengths:=[u32(0),1,2,63,64,65,nbits]!
 for s:=usize(0); s<starts.len; s++ { start:=starts[s]; if start>nbits { continue }
  for l:=usize(0); l<lengths.len; l++ { mut len:=lengths[l]; if len>nbits-start { len=nbits-start }
   for clear:=u32(0); clear<2; clear++ {
    C.memcpy(&dst[0],&a[0],(words+1)*sizeof(usize)); C.memcpy(&expected[0],&ar[0],usize(nbits)*sizeof(bool))
    for bit:=start; bit<start+len; bit++ { expected[bit]=clear==0 }
    if clear!=0 { C.__bitmap_clear(&dst[0],start,len) } else { C.__bitmap_set(&dst[0],start,len) }; bitmap_test_check(&dst[0],&expected[0],nbits)
    for bit:=nbits; usize(bit)<words*64; bit++ { C.assert(bitmap_test_bit(&dst[0],bit)==bitmap_test_bit(&a[0],bit)) }
   }
  }
 }
 halfwords:=usize(nbits/32)+if nbits%32!=0 { usize(1) } else { usize(0) }
 packed:=&u32(C.malloc((if halfwords!=0 { halfwords } else { usize(1) })*sizeof(u32))); C.assert(packed!=nil)
 C.bitmap_to_arr32(packed,&a[0],nbits)
 for bit:=u32(0); bit<nbits; bit++ { C.assert(((packed[bit/32]&(u32(1)<<(bit%32)))!=0) == ar[bit]) }
 for bit:=nbits; usize(bit)<halfwords*32; bit++ { C.assert((packed[bit/32]&(u32(1)<<(bit%32)))==0) }
 C.bitmap_from_arr32(&dst[0],packed,nbits); bitmap_test_check(&dst[0],&ar[0],nbits)
 for bit:=nbits; usize(bit)<words*64; bit++ { C.assert(!bitmap_test_bit(&dst[0],bit)) }; C.free(packed)
 C.memcpy(&alias[0],&a[0],(words+1)*sizeof(usize)); if nbits%64!=0 { alias[words-1]^=~usize(0)<<(nbits%64) }
 C.assert(C.__bitmap_equal(&a[0],&alias[0],nbits)); C.assert(C.__bitmap_weight(&alias[0],nbits)==weight)
 for word:=usize(0); word<words; word++ { alias[word]=0 }; if nbits%64!=0 { alias[words-1]=~usize(0)<<(nbits%64) }; C.assert(C.bitmap_empty(&alias[0],nbits))
 for word:=usize(0); word<words; word++ { alias[word]=~usize(0) }; if nbits%64!=0 { alias[words-1]>>=64-nbits%64 }; C.assert(C.bitmap_full(&alias[0],nbits))
} }
@[export:'vmh_test_bitmap_runtime']
pub fn test_bitmap_runtime() { unsafe {
 before:=C.vmh_live_pages; mut seed:=usize(0x1234abcddcba4321)
 for round:=u32(0); round<4; round++ { for i:=usize(0); i<widths.len; i++ { bitmap_runtime_properties(widths[i],&seed) } }
 C.assert(C.vmh_live_pages==before)
 C.assert(C.__bitmap_equal(nil,nil,0) && C.__bitmap_subset(nil,nil,0)); C.assert(!C.__bitmap_intersects(nil,nil,0) && C.__bitmap_weight(nil,0)==0)
 C.assert(!C.__bitmap_and(nil,nil,nil,0)); C.assert(!C.__bitmap_andnot(nil,nil,nil,0))
 C.__bitmap_shift_right(nil,nil,~u32(0),0); C.__bitmap_shift_left(nil,nil,~u32(0),0); C.__bitmap_set(nil,~u32(0),0); C.__bitmap_clear(nil,~u32(0),0); C.bitmap_from_arr32(nil,nil,0); C.bitmap_to_arr32(nil,nil,0)
 C.assert(voidptr(C.bitmap_zalloc(0,C.GFP_KERNEL))==voidptr(C.ZERO_SIZE_PTR)); C.bitmap_free(nil); C.bitmap_free(&usize(C.ZERO_SIZE_PTR))
 C.assert(C.bitmap_alloc_node(1,C.GFP_KERNEL,1)==nil); C.assert(C.bitmap_zalloc_node(1,C.GFP_KERNEL,-2)==nil); C.assert(C.bitmap_alloc(1,C.GFP_KERNEL|C.__GFP_DMA32)==nil)
 for round:=u32(0); round<200; round++ { nbits:=widths[round%u32(widths.len)]; bitmap:=C.bitmap_zalloc_node(nbits,C.GFP_KERNEL,if round&1!=0 { i32(0) } else { i32(-1) }); C.assert(bitmap!=nil)
  if nbits!=0 { bytes:=(usize(nbits/64)+if nbits%64!=0 { usize(1) } else { usize(0) })*sizeof(usize); C.assert(C.ksize(bitmap)==bytes); for i:=usize(0); i<bytes; i++ { C.assert((&u8(bitmap))[i]==0) }; C.__bitmap_set(bitmap,0,nbits); C.assert(C.__bitmap_weight(bitmap,nbits)==nbits) }
  C.bitmap_free(bitmap); C.assert(C.vmh_live_pages==before)
 }
 C.vmh_fail_allocation=true; C.assert(C.bitmap_alloc(1,C.GFP_KERNEL)==nil); C.assert(C.bitmap_zalloc(4097,C.GFP_KERNEL)==nil); C.assert(C.bitmap_alloc(~u32(0),C.GFP_KERNEL)==nil); C.assert(C.bitmap_zalloc_node(~u32(0),C.GFP_KERNEL,0)==nil); C.vmh_fail_allocation=false; C.assert(C.vmh_live_pages==before)
 for round:=u32(0); round<200; round++ { C.assert(C.vinix_linuxkpi_bitmap_runtime_selftest()==0); C.assert(C.vmh_live_pages==before) }
} }
