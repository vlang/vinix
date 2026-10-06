// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native integer builtin oracle: exhaustive narrow/mixed operands,
// full-width boundaries, destination truncation, native constants and lvalues.
@[translated]
module overflowfixture

#include <linux/overflow.h>
#include "vinix/integer_policy.h"
@[typedef]
struct C.vop_i128 {}
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.vinix_overflow_fixture_left() i16
fn C.vinix_overflow_fixture_right() u64
fn C.vinix_overflow_fixture_result() &i8
fn C.vinix_overflow_fixture_pointer() voidptr
fn C.preemptible() i32
fn C.ZERO_OR_NULL_PTR(voidptr) i32
@[c: 'check_add_overflow']
fn C.vop_effect_add(i16, u64, &i8) bool
@[c: 'check_sub_overflow']
fn C.vop_effect_sub(i16, u64, &i8) bool
@[c: 'check_mul_overflow']
fn C.vop_effect_mul(i16, u64, &i8) bool

@[c_extern]
__global (
 C.VOP_MAX_I8 u64
 C.VOP_MAX_U8 u64
 C.VOP_MAX_I16 u64
 C.VOP_MAX_U16 u64
 C.VOP_MAX_I32 u64
 C.VOP_MAX_U32 u64
 C.VOP_MAX_I64 u64
 C.VOP_MAX_U64 u64
 C.VOP_MAX_I128 u128
 C.VOP_MAX_U128 u128
 C.VOP_POLICY_INT u32
 C.VOP_ZERO_CONST_I32 u32
 C.VOP_ZERO_CONST_PTR u32
)

// Native global initializers require genuine integer constant expressions.
@[cinit]
__global (
 vop_max_i8 u64 = C.VOP_MAX_I8
 vop_max_u8 u64 = C.VOP_MAX_U8
 vop_max_i16 u64 = C.VOP_MAX_I16
 vop_max_u16 u64 = C.VOP_MAX_U16
 vop_max_i32 u64 = C.VOP_MAX_I32
 vop_max_u32 u64 = C.VOP_MAX_U32
 vop_max_i64 u64 = C.VOP_MAX_I64
 vop_max_u64 u64 = C.VOP_MAX_U64
 vop_max_i128 u128 = C.VOP_MAX_I128
 vop_max_u128 u128 = C.VOP_MAX_U128
 vop_policy_int u32 = C.VOP_POLICY_INT
 vop_zero_const_i32 u32 = C.VOP_ZERO_CONST_I32
 vop_zero_const_ptr u32 = C.VOP_ZERO_CONST_PTR
 vop_left_calls u32
 vop_right_calls u32
 vop_result_calls u32
 vop_pointer_calls u32
 vop_result i8
 vop_preempt u32
 vop_irq_flags usize = 512
 vop_preempt_calls u32
 vop_irq_calls u32
)

@[export: 'vinix_overflow_fixture_left']
pub fn left_argument() i16 { unsafe { vop_left_calls++; return -32768 } }
@[export: 'vinix_overflow_fixture_right']
pub fn right_argument() u64 { unsafe { vop_right_calls++; return 0xffffffffffffffff } }
@[export: 'vinix_overflow_fixture_result']
pub fn result_argument() &i8 { unsafe { vop_result_calls++; return &vop_result } }
@[export: 'vinix_overflow_fixture_pointer']
pub fn pointer_argument() voidptr { unsafe { vop_pointer_calls++; return voidptr(16) } }
@[export: 'vinix_linuxkpi_preempt_count']
pub fn preempt_count() u32 { unsafe { vop_preempt_calls++; return vop_preempt } }
@[export: 'vinix_linuxkpi_irq_flags']
pub fn irq_flags() usize { unsafe { vop_irq_calls++; return vop_irq_flags } }

fn native_signed(bits u128) C.vop_i128 {
 mut value := C.vop_i128{}
 unsafe { C.memcpy(&value, &bits, 16) }
 return value
}
fn signed_bits(value C.vop_i128) u128 {
 mut bits := u128(0)
 unsafe { C.memcpy(&bits, &value, 16) }
 return bits
}
fn mix(digest &u64, overflow bool, bits u128) {
 unsafe {
  *digest = (*digest ^ u64(overflow)) * u64(1099511628211)
  *digest = (*digest ^ u64(bits)) * u64(1099511628211)
  *digest = (*digest ^ u64(bits >> 64)) * u64(1099511628211)
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_i8_u8_u8(i8, u8, &u8) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_i8_u8_u8(i8, u8, &u8) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_i8_u8_u8(i8, u8, &u8) bool
fn calculate_i8_u8_u8(operation u32, a i8, b u8, result &u8) bool {
 return match operation {
  0 { C.vop_add_i8_u8_u8(a, b, result) }
  1 { C.vop_sub_i8_u8_u8(a, b, result) }
  2 { C.vop_mul_i8_u8_u8(a, b, result) }
  else { false }
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_i8_u8_i8(i8, u8, &i8) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_i8_u8_i8(i8, u8, &i8) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_i8_u8_i8(i8, u8, &i8) bool
fn calculate_i8_u8_i8(operation u32, a i8, b u8, result &i8) bool {
 return match operation {
  0 { C.vop_add_i8_u8_i8(a, b, result) }
  1 { C.vop_sub_i8_u8_i8(a, b, result) }
  2 { C.vop_mul_i8_u8_i8(a, b, result) }
  else { false }
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_i8_u8_i16(i8, u8, &i16) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_i8_u8_i16(i8, u8, &i16) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_i8_u8_i16(i8, u8, &i16) bool
fn calculate_i8_u8_i16(operation u32, a i8, b u8, result &i16) bool {
 return match operation {
  0 { C.vop_add_i8_u8_i16(a, b, result) }
  1 { C.vop_sub_i8_u8_i16(a, b, result) }
  2 { C.vop_mul_i8_u8_i16(a, b, result) }
  else { false }
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_i16_u64_i32(i16, u64, &i32) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_i16_u64_i32(i16, u64, &i32) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_i16_u64_i32(i16, u64, &i32) bool
fn calculate_i16_u64_i32(operation u32, a i16, b u64, result &i32) bool {
 return match operation {
  0 { C.vop_add_i16_u64_i32(a, b, result) }
  1 { C.vop_sub_i16_u64_i32(a, b, result) }
  2 { C.vop_mul_i16_u64_i32(a, b, result) }
  else { false }
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_i16_u64_u64(i16, u64, &u64) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_i16_u64_u64(i16, u64, &u64) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_i16_u64_u64(i16, u64, &u64) bool
fn calculate_i16_u64_u64(operation u32, a i16, b u64, result &u64) bool {
 return match operation {
  0 { C.vop_add_i16_u64_u64(a, b, result) }
  1 { C.vop_sub_i16_u64_u64(a, b, result) }
  2 { C.vop_mul_i16_u64_u64(a, b, result) }
  else { false }
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_u128_u128_u128(u128, u128, &u128) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_u128_u128_u128(u128, u128, &u128) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_u128_u128_u128(u128, u128, &u128) bool
fn calculate_u128_u128_u128(operation u32, a u128, b u128, result &u128) bool {
 return match operation {
  0 { C.vop_add_u128_u128_u128(a, b, result) }
  1 { C.vop_sub_u128_u128_u128(a, b, result) }
  2 { C.vop_mul_u128_u128_u128(a, b, result) }
  else { false }
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_u128_i64_u128(u128, i64, &u128) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_u128_i64_u128(u128, i64, &u128) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_u128_i64_u128(u128, i64, &u128) bool
fn calculate_u128_i64_u128(operation u32, a u128, b i64, result &u128) bool {
 return match operation {
  0 { C.vop_add_u128_i64_u128(a, b, result) }
  1 { C.vop_sub_u128_i64_u128(a, b, result) }
  2 { C.vop_mul_u128_i64_u128(a, b, result) }
  else { false }
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_u128_u128_i64(u128, u128, &i64) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_u128_u128_i64(u128, u128, &i64) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_u128_u128_i64(u128, u128, &i64) bool
fn calculate_u128_u128_i64(operation u32, a u128, b u128, result &i64) bool {
 return match operation {
  0 { C.vop_add_u128_u128_i64(a, b, result) }
  1 { C.vop_sub_u128_u128_i64(a, b, result) }
  2 { C.vop_mul_u128_u128_i64(a, b, result) }
  else { false }
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_i128_i128_i128(C.vop_i128, C.vop_i128, &C.vop_i128) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_i128_i128_i128(C.vop_i128, C.vop_i128, &C.vop_i128) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_i128_i128_i128(C.vop_i128, C.vop_i128, &C.vop_i128) bool
fn calculate_i128_i128_i128(operation u32, a C.vop_i128, b C.vop_i128, result &C.vop_i128) bool {
 return match operation {
  0 { C.vop_add_i128_i128_i128(a, b, result) }
  1 { C.vop_sub_i128_i128_i128(a, b, result) }
  2 { C.vop_mul_i128_i128_i128(a, b, result) }
  else { false }
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_i128_u128_i128(C.vop_i128, u128, &C.vop_i128) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_i128_u128_i128(C.vop_i128, u128, &C.vop_i128) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_i128_u128_i128(C.vop_i128, u128, &C.vop_i128) bool
fn calculate_i128_u128_i128(operation u32, a C.vop_i128, b u128, result &C.vop_i128) bool {
 return match operation {
  0 { C.vop_add_i128_u128_i128(a, b, result) }
  1 { C.vop_sub_i128_u128_i128(a, b, result) }
  2 { C.vop_mul_i128_u128_i128(a, b, result) }
  else { false }
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_u128_u128_i128(u128, u128, &C.vop_i128) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_u128_u128_i128(u128, u128, &C.vop_i128) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_u128_u128_i128(u128, u128, &C.vop_i128) bool
fn calculate_u128_u128_i128(operation u32, a u128, b u128, result &C.vop_i128) bool {
 return match operation {
  0 { C.vop_add_u128_u128_i128(a, b, result) }
  1 { C.vop_sub_u128_u128_i128(a, b, result) }
  2 { C.vop_mul_u128_u128_i128(a, b, result) }
  else { false }
 }
}
@[c: 'check_add_overflow']
fn C.vop_add_bool_i16_i8(bool, i16, &i8) bool
@[c: 'check_sub_overflow']
fn C.vop_sub_bool_i16_i8(bool, i16, &i8) bool
@[c: 'check_mul_overflow']
fn C.vop_mul_bool_i16_i8(bool, i16, &i8) bool
fn calculate_bool_i16_i8(operation u32, a bool, b i16, result &i8) bool {
 return match operation {
  0 { C.vop_add_bool_i16_i8(a, b, result) }
  1 { C.vop_sub_bool_i16_i8(a, b, result) }
  2 { C.vop_mul_bool_i16_i8(a, b, result) }
  else { false }
 }
}

fn narrow(digest &u64) {
 unsafe {
  for operation := u32(0); operation < 3; operation++ {
   for left in 0 .. 256 {
    for right in 0 .. 256 {
     a := i8(left - 128)
     b := u8(right)
     mut byte_result := u8(0)
     mut signed_result := i8(0)
     mut short_result := i16(0)
     overflow_flag_1 := calculate_i8_u8_u8(operation, a, b, &byte_result)
     mix(digest, overflow_flag_1, u128(byte_result))
     overflow_flag_2 := calculate_i8_u8_i8(operation, a, b, &signed_result)
     mix(digest, overflow_flag_2, u128(u8(signed_result)))
     overflow_flag_3 := calculate_i8_u8_i16(operation, a, b, &short_result)
     mix(digest, overflow_flag_3, u128(u16(short_result)))
    }
   }
  }
 }
}
fn wide_pair(digest &u64, a u128, b u128) {
 unsafe {
  for operation := u32(0); operation < 3; operation++ {
   mut unsigned_result := u128(0)
   mut signed_result := C.vop_i128{}
   mut word_result := i64(0)
   mut int_result := i32(0)
   mut unsigned_word_result := u64(0)
   mut boolean_result := i8(0)
   overflow_flag_4 := calculate_u128_u128_u128(operation, a, b, &unsigned_result)
   mix(digest, overflow_flag_4, unsigned_result)
   overflow_flag_5 := calculate_u128_i64_u128(operation, a, i64(u64(b)), &unsigned_result)
   mix(digest, overflow_flag_5, unsigned_result)
   overflow_flag_6 := calculate_u128_u128_i64(operation, a, b, &word_result)
   mix(digest, overflow_flag_6, u128(u64(word_result)))
   overflow_flag_7 := calculate_i128_i128_i128(operation, native_signed(a), native_signed(b), &signed_result)
   mix(digest, overflow_flag_7, signed_bits(signed_result))
   overflow_flag_8 := calculate_i128_u128_i128(operation, native_signed(a), b, &signed_result)
   mix(digest, overflow_flag_8, signed_bits(signed_result))
   overflow_flag_9 := calculate_u128_u128_i128(operation, a, b, &signed_result)
   mix(digest, overflow_flag_9, signed_bits(signed_result))
   overflow_flag_10 := calculate_i16_u64_i32(operation, i16(u16(a)), u64(b), &int_result)
   mix(digest, overflow_flag_10, u128(u32(int_result)))
   overflow_flag_11 := calculate_i16_u64_u64(operation, i16(u16(a)), u64(b), &unsigned_word_result)
   mix(digest, overflow_flag_11, u128(unsigned_word_result))
   overflow_flag_12 := calculate_bool_i16_i8(operation, a & 1 != 0, i16(u16(b)), &boolean_result)
   mix(digest, overflow_flag_12, u128(u8(boolean_result)))
  }
 }
}
fn random_word(seed &u64) u64 {
 unsafe {
  *seed ^= *seed << 13
  *seed ^= *seed >> 7
  *seed ^= *seed << 17
  return *seed
 }
}
fn policies() i32 {
 unsafe {
  mut errors := i32(0)
  if vop_max_i8 != 127 || vop_max_u8 != 255 || vop_max_i16 != 32767 || vop_max_u16 != 65535 || vop_max_i32 != 2147483647 || vop_max_u32 != 4294967295 || vop_max_i64 != 9223372036854775807 || vop_max_u64 != 0xffffffffffffffff { errors++ }
  if vop_max_i128 != (u128(1)<<127)-1 || vop_max_u128 != ~u128(0) || vop_policy_int != 1 || vop_zero_const_i32 != 1 || vop_zero_const_ptr != 1 { errors++ }
  for address := usize(0); address < 20; address++ {
   if (C.ZERO_OR_NULL_PTR(voidptr(address)) != 0) != (address <= 16) { errors++ }
  }
  vop_pointer_calls = 0
  if C.ZERO_OR_NULL_PTR(C.vinix_overflow_fixture_pointer()) != 1 || vop_pointer_calls != 1 { errors++ }
  vop_preempt = 1; vop_preempt_calls = 0; vop_irq_calls = 0
  if C.preemptible() != 0 || vop_preempt_calls != 1 || vop_irq_calls != 0 { errors++ }
  vop_preempt = 0; vop_irq_flags = 0; vop_preempt_calls = 0; vop_irq_calls = 0
  if C.preemptible() != 0 || vop_preempt_calls != 1 || vop_irq_calls != 1 { errors++ }
  vop_irq_flags = 512; vop_preempt_calls = 0; vop_irq_calls = 0
  if C.preemptible() != 1 || vop_preempt_calls != 1 || vop_irq_calls != 1 { errors++ }
  for operation := u32(0); operation < 3; operation++ {
   vop_left_calls = 0; vop_right_calls = 0; vop_result_calls = 0; vop_result = 0
   overflow := match operation {
    0 { C.vop_effect_add(C.vinix_overflow_fixture_left(), C.vinix_overflow_fixture_right(), C.vinix_overflow_fixture_result()) }
    1 { C.vop_effect_sub(C.vinix_overflow_fixture_left(), C.vinix_overflow_fixture_right(), C.vinix_overflow_fixture_result()) }
    else { C.vop_effect_mul(C.vinix_overflow_fixture_left(), C.vinix_overflow_fixture_right(), C.vinix_overflow_fixture_result()) }
   }
   expected := match operation { 0 { i8(-1) } 1 { i8(1) } else { i8(0) } }
   if !overflow || vop_result != expected || vop_left_calls != 1 || vop_right_calls != 1 || vop_result_calls != 1 { errors++ }
  }
  return errors
 }
}

@[export: 'main']
pub fn main_entry() i32 {
 unsafe {
  $if overflow_native_guest ? {
   $if amd64 {
    fd := C.open(c'/dev/com1', 2)
    if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); C.close(fd) }
   }
  }
  mut digest := u64(0xcbf29ce484222325)
  narrow(&digest)
  values := [u128(0), u128(1), u128(127), u128(128), u128(255), u128(32767), u128(32768), u128(65535), u128(2147483647), u128(2147483648), u128(4294967295), u128(9223372036854775807), u128(0x8000000000000000), u128(0xffffffffffffffff), u128(1)<<64, (u128(1)<<127)-1, u128(1)<<127, ~u128(0)]!
  for a in values { for b in values { wide_pair(&digest, a, b) } }
  mut seed := u64(0x0123456789abcdef)
  for _ in 0 .. 1024 {
   a := (u128(random_word(&seed))<<64) | u128(random_word(&seed))
   b := (u128(random_word(&seed))<<64) | u128(random_word(&seed))
   wide_pair(&digest, a, b)
  }
  errors := policies()
  C.printf(c'LinuxKPI overflow exhaustive/mixed/native128 digest=%016lx errors=%d\n', usize(digest), errors)
  C.fflush(nil)
  $if overflow_native_guest ? { if errors == 0 { for { C.pause() } } }
  return if errors == 0 { i32(0) } else { i32(1) }
 }
}
