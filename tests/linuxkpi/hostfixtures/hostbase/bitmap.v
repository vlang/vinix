// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
@[has_globals]
module hostbase
#include "hostbase_v_contract.h"
fn C.hweight_long(usize) u32
fn C.find_first_bit(&usize,usize) usize
fn C.find_first_zero_bit(&usize,usize) usize
fn C.find_first_and_bit(&usize,&usize,usize) usize
fn C.find_next_bit(&usize,usize,usize) usize
fn C.find_next_zero_bit(&usize,usize,usize) usize
fn C.find_next_and_bit(&usize,&usize,usize,usize) usize
fn C.find_next_or_bit(&usize,&usize,usize,usize) usize
fn C.find_next_andnot_bit(&usize,&usize,usize,usize) usize
fn C.find_nth_bit(&usize,usize,usize) usize
fn C.find_last_bit(&usize,usize) usize
fn C.test_bit(usize,&usize) bool
fn C.test_bit_acquire(usize,&usize) bool
fn C.test_and_set_bit(usize,&usize) bool
fn C.test_and_clear_bit(usize,&usize) bool
fn C.__set_bit(usize,&usize)
fn C.__test_and_change_bit(usize,&usize) bool
fn C.test_and_change_bit(usize,&usize) bool
fn C.bitmap_zero(&usize,u32)
fn C.bitmap_fill(&usize,u32)
fn C.bitmap_empty(&usize,u32) bool
fn C.bitmap_full(&usize,u32) bool
fn C.test_and_set_bit_lock(usize,&usize) bool
fn C.clear_bit_unlock(usize,&usize)
fn C.clear_bit_unlock_is_negative_byte(usize,&usize) bool
fn C.set_bit(usize,&usize)
fn C.clear_bit(usize,&usize)
fn C.hweight8(u32) u32
fn C.hweight16(u32) u32
fn C.hweight32(u32) u32
fn C.vmh_bit_worker(voidptr) voidptr
fn C.BIT(usize) usize
fn scalar_next(bitmap &usize,size usize,start usize,value bool) usize { unsafe {
 for bit:=start;bit<size;bit++ { if (bitmap[bit/64]&C.BIT(bit%64)!=0)==value { return bit } };return size
} }
@[export:'vmh_bitmap_tests']
pub fn bitmap_tests() { unsafe {
 mut bitmap:=[4]usize{};mut other:=[4]usize{};mut both:=[4]usize{};mut either:=[4]usize{};mut except:=[4]usize{}
 for pattern:=u32(0);pattern<12;pattern++ {
  for word:=u32(0);word<4;word++ {
   bitmap[word]=if pattern==0 { usize(0) } else if pattern==1 { ~usize(0) } else { usize(0x8421084210842108)^(usize(0x9e3779b97f4a7c15)*usize(pattern+word)) }
   other[word]=usize(0x1248124812481248)*usize(pattern+word+1);both[word]=bitmap[word]&other[word];either[word]=bitmap[word]|other[word];except[word]=bitmap[word]&~other[word]
   mut weight:=u32(0);for bit:=u32(0);bit<64;bit++ { weight+=u32(bitmap[word]&C.BIT(usize(bit))!=0) };C.assert(C.hweight_long(bitmap[word])==weight)
  }
  for size:=usize(0);size<=256;size++ {
   C.assert(C.find_first_bit(&bitmap[0],size)==scalar_next(&bitmap[0],size,0,true));C.assert(C.find_first_zero_bit(&bitmap[0],size)==scalar_next(&bitmap[0],size,0,false))
   C.assert(C.find_first_and_bit(&bitmap[0],&other[0],size)==scalar_next(&both[0],size,0,true));mut last:=size;mut rank:=usize(0)
   for start:=usize(0);start<=size+1;start++ {
    C.assert(C.find_next_bit(&bitmap[0],size,start)==scalar_next(&bitmap[0],size,start,true));C.assert(C.find_next_zero_bit(&bitmap[0],size,start)==scalar_next(&bitmap[0],size,start,false))
    C.assert(C.find_next_and_bit(&bitmap[0],&other[0],size,start)==scalar_next(&both[0],size,start,true));C.assert(C.find_next_or_bit(&bitmap[0],&other[0],size,start)==scalar_next(&either[0],size,start,true))
    C.assert(C.find_next_andnot_bit(&bitmap[0],&other[0],size,start)==scalar_next(&except[0],size,start,true))
    if start<size && C.test_bit(start,&bitmap[0]) { C.assert(C.find_nth_bit(&bitmap[0],size,rank)==start);rank++;last=start }
   }
   C.assert(C.find_nth_bit(&bitmap[0],size,rank)==size && C.find_last_bit(&bitmap[0],size)==last)
  }
 }
 C.bitmap_zero(&bitmap[0],256)
 for bit:=usize(0);bit<256;bit++ {
  C.assert(!C.test_and_set_bit(bit,&bitmap[0]) && C.test_and_set_bit(bit,&bitmap[0]));C.assert(C.test_bit(bit,&bitmap[0]) && C.test_bit_acquire(bit,&bitmap[0]))
  C.assert(C.test_and_clear_bit(bit,&bitmap[0]) && !C.test_and_clear_bit(bit,&bitmap[0]));C.__set_bit(bit,&bitmap[0])
  C.assert(C.__test_and_change_bit(bit,&bitmap[0]) && !C.test_bit(bit,&bitmap[0]));C.assert(!C.test_and_change_bit(bit,&bitmap[0]) && C.test_and_change_bit(bit,&bitmap[0]))
 }
 C.assert(C.bitmap_empty(&bitmap[0],256));C.assert(!C.test_and_set_bit_lock(65,&bitmap[0]));C.assert(C.test_and_set_bit_lock(65,&bitmap[0]))
 C.clear_bit_unlock(65,&bitmap[0]);C.assert(!C.test_bit(65,&bitmap[0]));C.set_bit(7,&bitmap[0]);C.set_bit(0,&bitmap[0])
 C.assert(C.clear_bit_unlock_is_negative_byte(0,&bitmap[0]) && C.test_bit(7,&bitmap[0]));C.clear_bit(7,&bitmap[0]);C.assert(!C.clear_bit_unlock_is_negative_byte(0,&bitmap[0]))
 C.bitmap_fill(&bitmap[0],65);C.assert(C.bitmap_full(&bitmap[0],65));C.assert(C.hweight8(0xff)==8 && C.hweight16(0xffff)==16 && C.hweight32(~u32(0))==32)
} }
__global shared_bits [2]usize
__global bit_lock_count u32
@[export:'vmh_bit_worker']
pub fn bit_worker(argument voidptr) voidptr { unsafe {
 index:=*(&usize(argument));for i:=u32(0);i<20000;i++ { C.set_bit(index,&shared_bits[0]);for C.test_and_set_bit_lock(65,&shared_bits[0]) { C.vinix_linuxkpi_spin_wait() };bit_lock_count++;C.clear_bit_unlock(65,&shared_bits[0]) };return nil
} }
@[export:'vmh_bit_concurrency_tests']
pub fn bit_concurrency_tests() { unsafe {
 mut indexes:=[usize(0),1,62,63]!;mut threads:=[4]C.pthread_t{}
 for i:=usize(0);i<4;i++ { C.assert(C.pthread_create(&threads[i],nil,C.vmh_bit_worker,&indexes[i])==0) }
 for i:=usize(0);i<4;i++ { C.assert(C.pthread_join(threads[i],nil)==0) };C.assert(bit_lock_count==20000*4 && !C.test_bit(65,&shared_bits[0]))
 for i:=usize(0);i<4;i++ { C.assert(C.test_bit(indexes[i],&shared_bits[0])) }
} }
fn C.put_unaligned_le16(u16,voidptr)
fn C.get_unaligned_le16(voidptr) u16
fn C.put_unaligned_be24(u32,voidptr)
fn C.get_unaligned_be24(voidptr) u32
fn C.put_unaligned_le32(u32,voidptr)
fn C.get_unaligned_le32(voidptr) u32
fn C.put_unaligned_be48(u64,voidptr)
fn C.get_unaligned_be48(voidptr) u64
fn C.put_unaligned_be64(u64,voidptr)
fn C.get_unaligned_be64(voidptr) u64
fn C.be32_to_cpu(u32) u32
fn C.cpu_to_be32(u32) u32
fn C.le64_to_cpu(u64) u64
fn C.cpu_to_le64(u64) u64
@[export:'vmh_byteorder_tests']
pub fn byteorder_tests() { unsafe {
 mut bytes:=[18]u8{};C.memset(&bytes[0],0xa5,sizeof(bytes));C.put_unaligned_le16(u16(0x1234),&bytes[1]);C.assert(bytes[1]==0x34 && bytes[2]==0x12 && C.get_unaligned_le16(&bytes[1])==0x1234)
 C.put_unaligned_be24(u32(0x123456),&bytes[1]);C.assert(bytes[1]==0x12 && bytes[3]==0x56 && C.get_unaligned_be24(&bytes[1])==0x123456)
 C.put_unaligned_le32(u32(0x12345678),&bytes[1]);C.assert(bytes[1]==0x78 && bytes[4]==0x12 && C.get_unaligned_le32(&bytes[1])==0x12345678)
 C.put_unaligned_be48(u64(0x123456789abc),&bytes[1]);C.assert(bytes[1]==0x12 && bytes[6]==0xbc && C.get_unaligned_be48(&bytes[1])==u64(0x123456789abc))
 C.put_unaligned_be64(u64(0x123456789abcdef0),&bytes[1]);C.assert(bytes[1]==0x12 && bytes[8]==0xf0 && C.get_unaligned_be64(&bytes[1])==u64(0x123456789abcdef0))
 C.assert(bytes[0]==0xa5 && bytes[9]==0xa5);C.assert(C.be32_to_cpu(C.cpu_to_be32(u32(0x12345678)))==u32(0x12345678))
 C.assert(C.le64_to_cpu(C.cpu_to_le64(u64(0x123456789abcdef0)))==u64(0x123456789abcdef0))
} }
