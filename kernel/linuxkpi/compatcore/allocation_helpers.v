// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

// Native kmalloc publishes exactly the requested span through ksize. Physical
// page slack is not a bucket capacity available to callers.
@[export: 'kmalloc_size_roundup']
pub fn native_kmalloc_size_roundup(size usize) usize { return size }

@[export: 'krealloc_array']
pub fn native_krealloc_array(ptr voidptr, count usize, size usize, flags u32) voidptr {
	if size != 0 && count > usize(-1) / size { return unsafe { nil } }
	return runtime_krealloc(ptr, count * size, flags)
}
