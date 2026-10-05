// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

#include "linuxkpi_v_primitives.h"
#include <string.h>

fn C.kmalloc(usize, u32) voidptr
fn C.kzalloc(usize, u32) voidptr
fn C.kmalloc_array(usize, usize, u32) voidptr
fn C.kfree(voidptr)
fn C.vinix_linuxkpi_bug(&char, i32)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.strlen(&char) usize

@[c: '__atomic_load_n']
fn C.vkp_load32(&u32, i32) u32

@[c: '__atomic_load_n']
fn C.vkp_load64(&u64, i32) u64

@[c: '__atomic_load_n']
fn C.vkp_load_signed(&i32, i32) i32

@[c: '__atomic_store_n']
fn C.vkp_store32(&u32, u32, i32)

@[c: '__atomic_store_n']
fn C.vkp_store_signed(&i32, i32, i32)

@[c: '__atomic_fetch_or']
fn C.vkp_or64(&u64, u64, i32) u64

@[c: '__atomic_exchange_n']
fn C.vkp_exchange32(&u32, u32, i32) u32

@[c: '__atomic_compare_exchange_n']
fn C.vkp_compare_signed(&i32, &i32, i32, bool, i32, i32) bool

fn C.vinix_linuxkpi_page_size() usize
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_gfp_supported(u32) bool
fn C.vinix_linuxkpi_alloc_gfp_pages(usize, u32) voidptr
fn C.vinix_linuxkpi_free_pages(voidptr, usize)
fn C.vkp_spin_init(voidptr)
fn C.vkp_spin_lock(voidptr)
fn C.vkp_spin_unlock(voidptr)
fn C.vkp_spin_lock_irqsave(voidptr) u64
fn C.vkp_spin_unlock_irqrestore(voidptr, u64)
fn C.vkp_mutex_lock(voidptr)
fn C.vkp_mutex_unlock(voidptr)
fn C.vkp_refcount_dec_and_test(voidptr) bool
fn C.vkp_cache_ctor_warning(bool)
fn C.vkp_current() voidptr
fn C.vkp_iowait_field(voidptr) voidptr
fn C.vkp_schedule()
fn C.vkp_schedule_timeout(i64) i64
fn C.vkp_signal_pending(i32) bool
fn C.vkp_jiffies() u64
fn C.vkp_bit_timeout(voidptr) u64
fn C.vinix_linuxkpi_iowait_count(u32) u32
fn C.vkp_warn(&char, i32)
fn C.vkp_refcount_warning(i32)
fn C.vkp_warn_note(&char, i32)
fn C.vkp_refcount_note(i32)

fn native_isspace(c i32) bool { return u8(c) == 160 || c == 32 || (c >= 9 && c <= 13) }

fn native_isxdigit(c i32) bool {
	return (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)
}

fn native_hweight_long(value u64) u32 {
	mut v := value
	mut count := u32(0)
	for v != 0 {
		v &= v - 1
		count++
	}
	return count
}

fn native_test_bit(bit u32, bits &u64) bool {
	unsafe { return (bits[bit / 64] & (u64(1) << (bit % 64))) != 0
	 }
}

fn require(ok bool) { if !ok { C.vinix_linuxkpi_bug(c'V LinuxKPI helper invariant', 0) } }

fn is_null(p voidptr) bool { return usize(p) == 0 }
