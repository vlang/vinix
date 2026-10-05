// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

__global (
	compat_cpu_count       u32
	compat_template_begin  voidptr
	compat_template_size   usize
	compat_static_stride   usize
	compat_static_copies   &u8
	compat_allocations     &PerCPUAllocation
	compat_allocation_lock u32
)

struct PerCPUAllocation {
mut:
	next   &PerCPUAllocation
	prev   &PerCPUAllocation
	data   &u8
	size   usize
	stride usize
}

// Export the original array symbol; callers still add byte offsets to their
// per-CPU template addresses. A V global cannot carry an export attribute.
// The array binding is supplied by the C declaration-only ABI object.
pub fn C.vkp_percpu_offsets() voidptr
pub fn C.vkp_percpu_begin() voidptr
pub fn C.vkp_percpu_end() voidptr

@[export: 'vinix_linuxkpi_percpu_count']
pub fn percpu_count() u32 {
	unsafe {
		return C.vkp_load32(&compat_cpu_count, 2)
	}
}

@[export: 'vinix_linuxkpi_percpu_init']
pub fn percpu_init(count u32, begin voidptr, end voidptr) i32 {
	unsafe {
		if percpu_count() != 0 { return -16 }
		if count == 0 || count > 256 || usize(end) < usize(begin) { return -22 }
		size := usize(end) - usize(begin)
		page := C.vinix_linuxkpi_page_size()
		if size > usize(-1) - (page - 1) { return -75 }
		stride := (size + page - 1) & ~(page - 1)
		if stride != 0 && usize(count) > usize(-1) / stride { return -75 }
		total := stride * usize(count)
		copies := if size != 0 { &u8(C.kzalloc(total, 3264)) } else { &u8(nil) }
		if size != 0 && usize(copies) == 0 { return -12 }
		offsets := &u64(C.vkp_percpu_offsets())
		for cpu := u32(0); cpu < count; cpu++ {
			if size != 0 { C.memcpy(copies + usize(cpu) * stride, begin, size) }
			offsets[cpu] = if size != 0 {
				u64(usize(copies) + usize(cpu) * stride - usize(begin))
			} else {
				0
			}
		}
		compat_template_begin = begin
		compat_template_size = size
		compat_static_stride = stride
		compat_static_copies = copies
		C.vkp_store32(&compat_cpu_count, count, 3)
		return 0
	}
}

@[export: 'vinix_linuxkpi_percpu_bootstrap']
pub fn percpu_bootstrap(count u32) i32 {
	unsafe {
		return percpu_init(count, C.vkp_percpu_begin(), C.vkp_percpu_end())
	}
}

@[export: 'vinix_linuxkpi_percpu_ptr']
pub fn percpu_ptr(ptr voidptr, cpu u32) voidptr {
	unsafe {
		if usize(ptr) == 0 { return nil }
		require(cpu < percpu_count())
		mut offset := usize(ptr) - usize(compat_template_begin)
		if offset < compat_template_size {
			return compat_static_copies + usize(cpu) * compat_static_stride + offset
		}
		irq := C.vkp_spin_lock_irqsave(&compat_allocation_lock)
		mut result := voidptr(nil)
		for a := compat_allocations; usize(a) != 0; a = a.next {
			offset = usize(ptr) - usize(a.data)
			if offset < a.size {
				result = a.data + usize(cpu) * a.stride + offset
				break
			}
		}
		C.vkp_spin_unlock_irqrestore(&compat_allocation_lock, irq)
		require(usize(result) != 0)
		return result
	}
}

@[export: '__alloc_percpu_gfp']
pub fn alloc_percpu_gfp(size usize, align usize, flags u32) voidptr {
	unsafe {
		count := percpu_count()
		page := C.vinix_linuxkpi_page_size()
		if count == 0 || size == 0 || align == 0 || (align & (align - 1)) != 0 || align > page {
			return nil
		}
		alignment := if align > 64 { align } else { usize(64) }
		if size > usize(-1) - (alignment - 1) { return nil }
		stride := (size + alignment - 1) & ~(alignment - 1)
		if usize(count) > usize(-1) / stride { return nil }
		mut total := stride * usize(count)
		if total > usize(-1) - sizeof(PerCPUAllocation) { return nil }
		total += sizeof(PerCPUAllocation)
		if total > usize(-1) - (alignment - 1) { return nil }
		total += alignment - 1
		a := &PerCPUAllocation(C.kzalloc(total, flags))
		if usize(a) == 0 { return nil }
		a.data = &u8((usize(a) + sizeof(PerCPUAllocation) + alignment - 1) & ~(alignment - 1))
		a.size = size
		a.stride = stride
		irq := C.vkp_spin_lock_irqsave(&compat_allocation_lock)
		a.next = compat_allocations
		if usize(compat_allocations) != 0 { compat_allocations.prev = a }
		compat_allocations = a
		C.vkp_spin_unlock_irqrestore(&compat_allocation_lock, irq)
		return a.data
	}
}

@[export: '__alloc_percpu']
pub fn alloc_percpu(size usize, align usize) voidptr {
	unsafe {
		return alloc_percpu_gfp(size, align, 3264)
	}
}

@[export: 'free_percpu']
pub fn free_percpu(ptr voidptr) {
	unsafe {
		if usize(ptr) == 0 { return }
		irq := C.vkp_spin_lock_irqsave(&compat_allocation_lock)
		mut found := &PerCPUAllocation(nil)
		for a := compat_allocations; usize(a) != 0; a = a.next {
			if usize(a.data) == usize(ptr) {
				found = a
				if usize(a.prev) != 0 { a.prev.next = a.next } else { compat_allocations = a.next }
				if usize(a.next) != 0 { a.next.prev = a.prev }
				break
			}
		}
		C.vkp_spin_unlock_irqrestore(&compat_allocation_lock, irq)
		require(usize(found) != 0)
		// Same caller-owned lifetime as Linux: all remote readers must have stopped.
		C.kfree(found)
	}
}

@[export: 'vinix_linuxkpi_percpu_destroy_for_test']
pub fn percpu_destroy_for_test() {
	unsafe {
		require(usize(compat_allocations) == 0)
		C.kfree(compat_static_copies)
		compat_static_copies = nil
		C.vkp_store32(&compat_cpu_count, 0, 3)
	}
}
