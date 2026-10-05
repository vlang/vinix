// SPDX-License-Identifier: GPL-2.0-or-later
module m1core
fn m1_clock_us() u64 {
 mut c := u64(0); mut f := u64(0)
 asm volatile aarch64 { mrs c, cntvct_el0 ; =r (c) }
 asm volatile aarch64 { mrs f, cntfrq_el0 ; =r (f) }
 return if f != 0 { (c / f) * 1000000 + (c % f) * 1000000 / f } else { 0 }
}
fn m1_delay(us u32) {
 begin := m1_clock_us()
 for m1_clock_us() - begin < us { asm volatile aarch64 { yield ; ; ; memory } }
}
fn m1_barrier() { asm volatile aarch64 { dsb sy ; ; ; memory } }
fn m1_cache_sync(p voidptr, n usize, to_device i32) {
 mut ctr := u64(0)
 asm volatile aarch64 { mrs ctr, ctr_el0 ; =r (ctr) }
 line := usize(4) << ((ctr >> 16) & 15)
 end := usize(p) + n
 for a := usize(p) & ~(line - 1); a < end; a += line {
  if to_device != 0 { asm volatile aarch64 { dc civac, a ; ; r (a) ; memory } }
  else { asm volatile aarch64 { dc ivac, a ; ; r (a) ; memory } }
 }
 m1_barrier()
}
