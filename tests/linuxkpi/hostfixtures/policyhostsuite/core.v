// SPDX-License-Identifier: GPL-2.0-only
// Original independent device encodings, DSC tables and i915 timeout goldens.
@[has_globals]
module policyhostsuite
#include "policyhost_v_contract.h"
struct C.drm_i915_private {}
fn C.MKDEV(u32,u32) u32
fn C.MAJOR(u32) u32
fn C.MINOR(u32) u32
fn C.old_valid_dev(u32) bool
fn C.sysv_valid_dev(u32) bool
fn C.new_encode_dev(u32) u32
fn C.new_decode_dev(u32) u32
fn C.huge_encode_dev(u32) u64
fn C.huge_decode_dev(u64) u32
fn C.old_encode_dev(u32) u16
fn C.old_decode_dev(u16) u32
fn C.sysv_encode_dev(u32) u32
fn C.sysv_major(u32) u32
fn C.sysv_minor(u32) u32
fn C.format_dev_t(&char,u32) &char
fn C.print_dev_t(&char,u32) i32
fn C.intel_lookup_range_min_qp(i32,i32,i32,bool) u8
fn C.intel_lookup_range_max_qp(i32,i32,i32,bool) u8
fn C.vinix_linuxkpi_irq_flags() u64
fn C.vinix_linuxkpi_preempt_count() u32
fn C.i915_fence_context_timeout(&C.drm_i915_private,u64) usize
fn C.i915_fence_timeout(&C.drm_i915_private) usize
fn C.msecs_to_jiffies_timeout(u32) usize
@[c_extern] __global C.MAX_JIFFY_OFFSET usize
struct DeviceGolden { major u32 minor u32 kernel u32 encoded u32 old_valid bool sysv_valid bool text &char }
const devices = [
 DeviceGolden{0,0,0x00000000,0x00000000,true,true,&char(c'0:0')},
 DeviceGolden{0,1,0x00000001,0x00000001,true,true,&char(c'0:1')},
 DeviceGolden{1,3,0x00100003,0x00000103,true,true,&char(c'1:3')},
 DeviceGolden{4,64,0x00400040,0x00000440,true,true,&char(c'4:64')},
 DeviceGolden{226,128,0x0e200080,0x0000e280,true,true,&char(c'226:128')},
 DeviceGolden{255,255,0x0ff000ff,0x0000ffff,true,true,&char(c'255:255')},
 DeviceGolden{256,0,0x10000000,0x00010000,false,true,&char(c'256:0')},
 DeviceGolden{0,256,0x00000100,0x00100000,false,true,&char(c'0:256')},
 DeviceGolden{4095,255,0xfff000ff,0x000fffff,false,true,&char(c'4095:255')},
 DeviceGolden{0,262143,0x0003ffff,0x3ff000ff,false,true,&char(c'0:262143')},
 DeviceGolden{0,262144,0x00040000,0x40000000,false,false,&char(c'0:262144')},
 DeviceGolden{4095,262143,0xfff3ffff,0x3fffffff,false,true,&char(c'4095:262143')},
 DeviceGolden{0,1048575,0x000fffff,0xfff000ff,false,false,&char(c'0:1048575')},
 DeviceGolden{4095,1048575,0xffffffff,0xffffffff,false,false,&char(c'4095:1048575')},
 DeviceGolden{2748,913153,0xabcdef01,0xdefabc01,false,false,&char(c'2748:913153')}]!
// The side-effect callback remains inside each imported native macro. If a
// macro evaluates its argument twice, the original counter assertion catches it.
fn next32(value &u32) u32 { unsafe { result:=*value; (*value)++; return result } }
@[export: 'vmh_kdev_tests']
pub fn kdev_tests() { unsafe {
 for i:=u32(0); i<15; i++ {
  vector:=devices[i]; device:=C.MKDEV(vector.major,vector.minor)
  C.assert(device==vector.kernel)
  C.assert(C.MAJOR(device)==vector.major && C.MINOR(device)==vector.minor)
  C.assert(C.old_valid_dev(device)==vector.old_valid)
  C.assert(C.sysv_valid_dev(device)==vector.sysv_valid)
  C.assert(C.new_encode_dev(device)==vector.encoded)
  C.assert(C.new_decode_dev(vector.encoded)==device)
  C.assert(C.huge_encode_dev(device)==u64(vector.encoded))
  C.assert(C.huge_decode_dev(u64(vector.encoded))==device)
  C.assert(C.huge_decode_dev(u64(0xa5a5a5a500000000)|u64(vector.encoded))==device)
  if vector.old_valid {
   C.assert(C.old_encode_dev(device)==vector.encoded)
   C.assert(C.old_decode_dev(C.old_encode_dev(device))==device)
  }
  if vector.sysv_valid { encoded:=C.sysv_encode_dev(device); C.assert(C.sysv_major(encoded)==vector.major); C.assert(C.sysv_minor(encoded)==vector.minor) }
  mut text:=[24]char{}
  C.assert(usize(C.format_dev_t(&text[0],device))==usize(&text[0]))
  C.assert(C.strcmp(&text[0],vector.text)==0)
  length:=C.strlen(vector.text)
  C.assert(C.print_dev_t(&text[0],device)==i32(length)+1)
  C.assert(C.memcmp(&text[0],vector.text,length)==0)
  C.assert(text[length]==10 && text[length+1]==0)
 }
 disk_bit:=[u8(0),1,2,3,4,5,6,7,20,21,22,23,24,25,26,27,28,29,30,31,8,9,10,11,12,13,14,15,16,17,18,19]!
 for bit:=u32(0); bit<32; bit++ { device:=u32(1)<<bit; encoded:=u32(1)<<disk_bit[bit]; C.assert(C.new_encode_dev(device)==encoded && C.new_decode_dev(encoded)==device); C.assert(C.new_encode_dev(~device)==~encoded && C.new_decode_dev(~encoded)==~device) }
 for encoded:=u32(0); encoded<=0xffff; encoded++ { device:=C.old_decode_dev(u16(encoded)); C.assert(C.old_valid_dev(device)); C.assert(C.old_encode_dev(device)==encoded); C.assert(C.new_encode_dev(device)==encoded) }
 C.assert(C.sysv_encode_dev(C.MKDEV(u32(1),u32(3)))==u32(0x00040003))
 C.assert(C.sysv_encode_dev(C.MKDEV(u32(226),u32(128)))==u32(0x03880080))
 C.assert(C.sysv_encode_dev(C.MKDEV(u32(4095),u32(262143)))==u32(0x3fffffff))
 C.assert(C.sysv_major(u32(0xffffffff))==16383 && C.sysv_minor(u32(0xffffffff))==262143)
 mut major:=u32(7); mut minor:=u32(9); mut device:=C.MKDEV(next32(&major),next32(&minor))
 C.assert(major==8 && minor==10 && device==u32(0x00700009))
 C.assert(C.MAJOR(next32(&device))==7 && device==u32(0x0070000a))
 C.assert(C.MINOR(next32(&device))==10 && device==u32(0x0070000b))
 C.assert(C.new_encode_dev(next32(&device))==u32(0x0000070b) && device==u32(0x0070000c))
} }
struct QpGolden { bpc i32 row i32 column i32 is_420 bool minimum u8 maximum u8 }
struct QpFamily { bpc i32 columns i32 is_420 bool }
const families=[QpFamily{8,37,false},QpFamily{10,49,false},QpFamily{12,61,false},QpFamily{8,17,true},QpFamily{10,23,true},QpFamily{12,29,true}]!
@[export: 'vmh_qp_table_tests']
pub fn qp_table_tests() { unsafe {
 pages:=C.vmh_live_pages; irq:=C.vinix_linuxkpi_irq_flags(); depth:=C.vinix_linuxkpi_preempt_count()
 for i:=u32(0); i<48; i++ {
  golden:=qp_goldens[i]
  C.assert(C.intel_lookup_range_min_qp(golden.bpc,golden.row,golden.column,golden.is_420)==golden.minimum)
  C.assert(C.intel_lookup_range_max_qp(golden.bpc,golden.row,golden.column,golden.is_420)==golden.maximum)
 }
 for i:=u32(0); i<6; i++ {
  for row:=i32(0); row<15; row++ {
   for column:=i32(0); column<families[i].columns; column++ {
    minimum:=C.intel_lookup_range_min_qp(families[i].bpc,row,column,families[i].is_420)
    maximum:=C.intel_lookup_range_max_qp(families[i].bpc,row,column,families[i].is_420)
    C.assert(minimum<=maximum && maximum<=23)
   }
  }
 }
 for bpc:=i32(8); bpc<=12; bpc+=2 {
  last_444_column:=2*(3*bpc-6); last_420_column:=3*bpc-8
  C.assert(C.intel_lookup_range_min_qp(bpc,14,2*(6-6),false)==bpc*2-2)
  C.assert(C.intel_lookup_range_max_qp(bpc,14,last_444_column,false)==4)
  C.assert(C.intel_lookup_range_min_qp(bpc,14,8-8,true)==bpc*2-3)
  C.assert(C.intel_lookup_range_max_qp(bpc,14,last_420_column,true)==if bpc==8 { 4 } else { 5 })
 }
 C.assert(C.vmh_live_pages==pages && C.vinix_linuxkpi_irq_flags()==irq && C.vinix_linuxkpi_preempt_count()==depth)
} }
__global vmp_config_devices u32
__global vmp_config_contexts u32
fn config_device() &C.drm_i915_private { unsafe { vmp_config_devices++; return nil } }
fn config_context(value u64) u64 { unsafe { vmp_config_contexts++; return value } }
@[export: 'vmh_i915_config_tests']
pub fn i915_config_tests() { unsafe {
 contexts:=[u64(0),u64(1),u64(2),u64(0xffffffff),u64(1)<<32,u64(1)<<63,~u64(0)]!
 ticks:=[usize(0),usize(10001),usize(10001),usize(10001),usize(10001),usize(10001),usize(10001)]!
 vmp_config_devices=0; vmp_config_contexts=0
 for i:=u32(0); i<7; i++ { C.assert(C.i915_fence_context_timeout(config_device(),config_context(contexts[i]))==ticks[i]); C.assert(vmp_config_devices==i+1 && vmp_config_contexts==i+1) }
 C.assert(C.i915_fence_timeout(config_device())==10001); C.assert(vmp_config_devices==8)
 milliseconds:=[u32(0),u32(1),u32(999),u32(1000),u32(10000),u32(2147483647),~u32(0)]!
 rounded:=[usize(1),usize(2),usize(1000),usize(1001),usize(10001),usize(2147483648),C.MAX_JIFFY_OFFSET]!
 for i:=u32(0); i<7; i++ { mut runtime_value:=milliseconds[i]; C.assert(C.msecs_to_jiffies_timeout(u32(C.__atomic_load_n(&runtime_value,0)))==rounded[i]) }
 C.assert(C.msecs_to_jiffies_timeout(u32(0))==1)
 C.assert(C.msecs_to_jiffies_timeout(u32(10000))==10001)
 C.assert(C.msecs_to_jiffies_timeout(~u32(0))==C.MAX_JIFFY_OFFSET)
} }

const qp_goldens = [QpGolden{8, 0, 0, false, 0, 4}, QpGolden{8, 0, 36, false, 0, 0},
    QpGolden{8, 14, 0, false, 14, 15}, QpGolden{8, 14, 36, false, 3, 4},
    QpGolden{8, 3, 2, false, 2, 7}, QpGolden{8, 7, 18, false, 2, 4},
    QpGolden{8, 10, 34, false, 1, 2}, QpGolden{8, 13, 6, false, 7, 11},
    QpGolden{10, 0, 0, false, 0, 8}, QpGolden{10, 0, 48, false, 0, 0},
    QpGolden{10, 14, 0, false, 18, 19}, QpGolden{10, 14, 48, false, 3, 4},
    QpGolden{10, 3, 2, false, 6, 11}, QpGolden{10, 7, 24, false, 5, 7},
    QpGolden{10, 10, 46, false, 1, 2}, QpGolden{10, 13, 6, false, 12, 15},
    QpGolden{12, 0, 0, false, 0, 12}, QpGolden{12, 0, 60, false, 0, 0},
    QpGolden{12, 14, 0, false, 22, 23}, QpGolden{12, 14, 60, false, 3, 4},
    QpGolden{12, 3, 2, false, 10, 15}, QpGolden{12, 7, 30, false, 7, 8},
    QpGolden{12, 10, 58, false, 1, 2}, QpGolden{12, 13, 6, false, 15, 19},
    QpGolden{8, 0, 0, true, 0, 4}, QpGolden{8, 0, 16, true, 0, 0},
    QpGolden{8, 14, 0, true, 13, 14}, QpGolden{8, 14, 16, true, 3, 4},
    QpGolden{8, 3, 2, true, 1, 6}, QpGolden{8, 7, 8, true, 2, 4},
    QpGolden{8, 10, 14, true, 2, 3}, QpGolden{8, 13, 6, true, 7, 9},
    QpGolden{10, 0, 0, true, 0, 8}, QpGolden{10, 0, 22, true, 0, 0},
    QpGolden{10, 14, 0, true, 17, 18}, QpGolden{10, 14, 22, true, 4, 5},
    QpGolden{10, 3, 2, true, 5, 10}, QpGolden{10, 7, 11, true, 5, 7},
    QpGolden{10, 10, 20, true, 2, 3}, QpGolden{10, 13, 6, true, 11, 13},
    QpGolden{12, 0, 0, true, 0, 11}, QpGolden{12, 0, 28, true, 0, 0},
    QpGolden{12, 14, 0, true, 21, 22}, QpGolden{12, 14, 28, true, 4, 5},
    QpGolden{12, 3, 2, true, 9, 13}, QpGolden{12, 7, 14, true, 8, 9},
    QpGolden{12, 10, 26, true, 2, 3}, QpGolden{12, 13, 6, true, 15, 17}]!
