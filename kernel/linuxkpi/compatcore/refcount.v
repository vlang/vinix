// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

// Saturation and final-release decisions live here; Linux header primitives
// retain their original atomic, preemption and guard semantics.
@[export: 'refcount_warn_saturate']
pub fn refcount_warn_saturate(r &i32, kind i32) {
	unsafe {
		C.vkp_store_signed(r, -1073741824, 0)
		vinix_linuxkpi_refcount_warning(kind)
	}
}

@[export: 'refcount_dec_if_one']
pub fn refcount_dec_if_one(r &i32) bool {
	unsafe {
		mut old := i32(1)
		return C.vkp_compare_signed(r, &old, 0, false, 3, 0)
	}
}

@[export: 'refcount_dec_not_one']
pub fn refcount_dec_not_one(r &i32) bool {
	unsafe {
		mut old := C.vkp_load_signed(r, 0)
		for {
			if old < 0 { return true }
			if old == 1 { return false }
			if old == 0 {
				refcount_warn_saturate(r, 3)
				return true
			}
			if C.vkp_compare_signed(r, &old, old - 1, false, 3, 0) { return true }
		}
	}
}

@[export: 'refcount_dec_and_lock']
pub fn refcount_dec_and_lock(r &i32, guard voidptr) bool {
	unsafe {
		if refcount_dec_not_one(r) { return false }
		C.vkp_spin_lock(guard)
		if C.vkp_refcount_dec_and_test(r) { return true }
		C.vkp_spin_unlock(guard)
		return false
	}
}

@[export: 'refcount_dec_and_mutex_lock']
pub fn refcount_dec_and_mutex_lock(r &i32, guard voidptr) bool {
	unsafe {
		if refcount_dec_not_one(r) { return false }
		C.vkp_mutex_lock(guard)
		if C.vkp_refcount_dec_and_test(r) { return true }
		C.vkp_mutex_unlock(guard)
		return false
	}
}

@[export: 'refcount_dec_and_lock_irqsave']
pub fn refcount_dec_and_lock_irqsave(r &i32, guard voidptr, flags &u64) bool {
	unsafe {
		if refcount_dec_not_one(r) { return false }
		*flags = C.vkp_spin_lock_irqsave(guard)
		if C.vkp_refcount_dec_and_test(r) { return true }
		C.vkp_spin_unlock_irqrestore(guard, *flags)
		return false
	}
}
