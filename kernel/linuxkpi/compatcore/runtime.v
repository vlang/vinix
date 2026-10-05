// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

fn C.vinix_linuxkpi_alloc_pages(usize, bool) voidptr

// The old aligned C metadata occupied 32 bytes. Keep that complete size,
// including its unused tail, immediately before the aligned payload.
struct RuntimeAllocation {
mut:
	requested usize
	pages     usize
	base      voidptr
	padding   u64
}

@[export: 'vinix_linuxkpi_gfp_supported']
pub fn runtime_gfp_supported(flags u32) bool {
	supported := u32(3264 | 0x20 | 0x100 | 0x2000 | 0x10000 | 0x4000)
	return (flags & ~supported) == 0
}

@[export: 'vinix_linuxkpi_alloc_gfp_pages']
pub fn runtime_alloc_gfp_pages(pages usize, flags u32) voidptr {
	if pages == 0 || !runtime_gfp_supported(flags) { return unsafe { nil } }
	page_size := C.vinix_linuxkpi_page_size()
	if page_size == 0 || pages > usize(-1) / page_size { return unsafe { nil } }
	reclaim := (flags & 3264) == 3264 && C.vinix_linuxkpi_may_sleep()
	return C.vinix_linuxkpi_alloc_pages(pages, reclaim)
}

@[export: 'vkr_kmalloc']
pub fn runtime_kmalloc(size usize, flags u32) voidptr {
	unsafe {
		if size == 0 { return voidptr(16) }
		if !runtime_gfp_supported(flags) { return nil }
		page_size := C.vinix_linuxkpi_page_size()
		mut alignment := size & (usize(0) - size)
		if alignment < 16 { alignment = 16 }
		if size > usize(-1) - sizeof(RuntimeAllocation) { return nil }
		mut total := size + sizeof(RuntimeAllocation)
		if total > usize(-1) - (alignment - 1) { return nil }
		total += alignment - 1
		if total > usize(-1) - (page_size - 1) { return nil }
		total += page_size - 1
		pages := total / page_size
		base := runtime_alloc_gfp_pages(pages, flags)
		if usize(base) == 0 { return nil }
		result := voidptr((usize(base) + sizeof(RuntimeAllocation) + alignment - 1) & ~(alignment - 1))
		allocation := &RuntimeAllocation(usize(result) - sizeof(RuntimeAllocation))
		allocation.requested = size
		allocation.pages = pages
		allocation.base = base
		if (flags & 0x100) != 0 { C.memset(result, 0, size) }
		return result
	}
}

@[export: 'vkr_kzalloc']
pub fn runtime_kzalloc(size usize, flags u32) voidptr {
	return runtime_kmalloc(size, flags | 0x100)
}

@[export: 'vkr_kmalloc_array']
pub fn runtime_kmalloc_array(count usize, size usize, flags u32) voidptr {
	if size != 0 && count > usize(-1) / size { return unsafe { nil } }
	return runtime_kmalloc(count * size, flags)
}

@[export: 'vkr_kcalloc']
pub fn runtime_kcalloc(count usize, size usize, flags u32) voidptr {
	return runtime_kmalloc_array(count, size, flags | 0x100)
}

@[export: 'vkr_ksize']
pub fn runtime_ksize(ptr voidptr) usize {
	unsafe {
		if usize(ptr) <= 16 { return 0 }
		return (&RuntimeAllocation(usize(ptr) - sizeof(RuntimeAllocation))).requested
	}
}

@[export: 'vkr_kfree']
pub fn runtime_kfree(ptr voidptr) {
	unsafe {
		if usize(ptr) <= 16 { return }
		allocation := &RuntimeAllocation(usize(ptr) - sizeof(RuntimeAllocation))
		pages := allocation.pages
		C.vinix_linuxkpi_free_pages(allocation.base, pages)
	}
}

@[export: 'vkr_krealloc']
pub fn runtime_krealloc(old voidptr, size usize, flags u32) voidptr {
	unsafe {
		if size == 0 {
			runtime_kfree(old)
			return voidptr(16)
		}
		result := runtime_kmalloc(size, flags)
		if usize(result) == 0 { return nil }
		previous := runtime_ksize(old)
		if previous != 0 { C.memcpy(result, old, if previous < size { previous } else { size }) }
		runtime_kfree(old)
		return result
	}
}

@[export: 'vkr_kmemdup']
pub fn runtime_kmemdup(src voidptr, size usize, flags u32) voidptr {
	result := runtime_kmalloc(size, flags)
	if usize(result) != 0 && size != 0 { C.memcpy(result, src, size) }
	return result
}

@[export: 'vinix_linuxkpi_tigerlake_id']
pub fn runtime_tigerlake_id(vendor u16, device u16, class_code u32) bool {
 // The supported device is the imported INTEL_TGL_12_GT2_IDS 0x9a49 entry.
 return vendor == 0x8086 && device == 0x9a49 && (class_code & 0xff0000) == 0x030000
}

@[export: 'kmalloc']
pub fn native_kmalloc(size usize, flags u32) voidptr { return runtime_kmalloc(size, flags) }
@[export: 'kzalloc']
pub fn native_kzalloc(size usize, flags u32) voidptr { return runtime_kzalloc(size, flags) }
@[export: 'kmalloc_array']
pub fn native_kmalloc_array(count usize, size usize, flags u32) voidptr { return runtime_kmalloc_array(count, size, flags) }
@[export: 'kcalloc']
pub fn native_kcalloc(count usize, size usize, flags u32) voidptr { return runtime_kcalloc(count, size, flags) }
@[export: 'ksize']
pub fn native_ksize(ptr voidptr) usize { return runtime_ksize(ptr) }
@[export: 'kfree']
pub fn native_kfree(ptr voidptr) { runtime_kfree(ptr) }
@[export: 'krealloc']
pub fn native_krealloc(ptr voidptr, size usize, flags u32) voidptr { return runtime_krealloc(ptr, size, flags) }
@[export: 'kmemdup']
pub fn native_kmemdup(ptr voidptr, size usize, flags u32) voidptr { return runtime_kmemdup(ptr, size, flags) }
