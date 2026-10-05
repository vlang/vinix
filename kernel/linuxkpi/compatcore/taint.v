// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module compatcore

__global compat_tainted_mask u64

@[export: 'add_taint']
pub fn add_taint(flag u32, lockdep_ok i32) {
	unsafe {
		require(flag < 19)
		C.vkp_or64(&compat_tainted_mask, u64(1) << flag, 0)
	}
}

@[export: 'test_taint']
pub fn test_taint(flag u32) i32 {
	unsafe {
		require(flag < 19)
		return i32((get_taint() & (u64(1) << flag)) != 0)
	}
}

@[export: 'get_taint']
pub fn get_taint() u64 {
	unsafe {
		return C.vkp_load64(&compat_tainted_mask, 0)
	}
}

@[export: 'vinix_linuxkpi_warn']
pub fn vinix_linuxkpi_warn(file &char, line i32) {
	unsafe {
		C.vkp_warn_note(file, line)
		C.vkp_warn(file, line)
	}
}

@[export: 'vinix_linuxkpi_refcount_warning']
pub fn vinix_linuxkpi_refcount_warning(kind i32) {
	unsafe {
		C.vkp_refcount_note(kind)
		add_taint(9, 0)
		C.vkp_refcount_warning(kind)
	}
}
