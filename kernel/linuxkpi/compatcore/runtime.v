// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

fn C.vinix_linuxkpi_alloc_pages(usize, bool) voidptr

struct C.vkr_pci_match {
	vendor     u32
	device     u32
	subvendor  u32
	subdevice  u32
	class_code u32
	class_mask u32
	data       u64
}

fn C.vkr_tigerlake_table(&usize) &C.vkr_pci_match

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
	unsafe {
		if device != 0x9a49 { return false }
		mut count := usize(0)
		ids := C.vkr_tigerlake_table(&count)
		for i := usize(0); i < count; i++ {
			id := &ids[i]
			if vendor == id.vendor && device == id.device && (class_code & id.class_mask) == id.class_code {
				return true
			}
		}
		return false
	}
}
