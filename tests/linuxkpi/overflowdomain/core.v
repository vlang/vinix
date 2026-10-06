// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native operand-domain oracle. The compiler owns the actual scalar
// type selected by declaration flags; V owns bounded inputs and observations.
@[translated]
module overflowdomain

#include <linux/overflow.h>
#include "vinix/integer_policy.h"
@[typedef]
struct C.vop_domain_t {}
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.printf(&char, ...) i32
@[c: 'check_add_overflow']
fn C.domain_add(C.vop_domain_t, C.vop_domain_t, &C.vop_domain_t) bool
@[c: 'check_sub_overflow']
fn C.domain_sub(C.vop_domain_t, C.vop_domain_t, &C.vop_domain_t) bool
@[c: 'check_mul_overflow']
fn C.domain_mul(C.vop_domain_t, C.vop_domain_t, &C.vop_domain_t) bool
@[c_extern]
__global (
 C.VOP_DOMAIN_SIZE u32
 C.VOP_DOMAIN_BOOL u32
 C.VOP_DOMAIN_MAX C.vop_domain_t
)
@[cinit]
__global vop_domain_max C.vop_domain_t = C.VOP_DOMAIN_MAX

enum DomainValue { zero one }

fn pattern(storage &u8, width u32, seed u32) {
 unsafe {
  for index := u32(0); index < width; index++ {
   storage[index] = u8((seed * 37 + index * 19) ^ (seed >> (index % 7)))
  }
 }
}
fn observe(digest &u64, storage &u8, width u32) {
 unsafe {
  for index := u32(0); index < width; index++ {
   *digest = (*digest ^ u64(storage[index])) * u64(1099511628211)
  }
 }
}
@[export: 'main']
pub fn main_entry() i32 {
 unsafe {
  width := C.VOP_DOMAIN_SIZE
  if width == 0 || width > 64 { return 1 }
  mut digest := u64(0xcbf29ce484222325)
  mut left_bytes := [64]u8{}
  mut right_bytes := [64]u8{}
  mut result_bytes := [64]u8{}
  for seed := u32(0); seed < 128; seed++ {
   pattern(&left_bytes[0], width, seed)
   pattern(&right_bytes[0], width, seed + 17)
   if C.VOP_DOMAIN_BOOL != 0 { left_bytes[0] &= 1; right_bytes[0] &= 1 }
   mut left := C.vop_domain_t{}
   mut right := C.vop_domain_t{}
   C.memcpy(voidptr(&left), &left_bytes[0], usize(width))
   C.memcpy(voidptr(&right), &right_bytes[0], usize(width))
   for operation := u32(0); operation < 3; operation++ {
    mut result := C.vop_domain_t{}
    overflow := match operation {
     0 { C.domain_add(left, right, &result) }
     1 { C.domain_sub(left, right, &result) }
     else { C.domain_mul(left, right, &result) }
    }
    C.memcpy(&result_bytes[0], voidptr(&result), usize(width))
    digest = (digest ^ u64(overflow)) * u64(1099511628211)
    observe(&digest, &result_bytes[0], width)
   }
  }
  C.memcpy(&result_bytes[0], voidptr(&vop_domain_max), usize(width))
  observe(&digest, &result_bytes[0], width)
  C.printf(c'LinuxKPI native operand domain bytes=%u digest=%016lx\n', width, usize(digest))
  return 0
 }
}
