module sys

fn (mut kernel VKernel) heap_init(addr voidptr, size u64) {
/*	base := phys_to_virtual(addr)
	end := phys_to_virtual(voidptr(u64(addr) + u64(size)))

	mut alloc := libtinyalloc.new_alloc(base, end, 1024, 16, 8)
	kernel.allocator = &alloc*/
}

pub fn (kernel &VKernel) kmalloc(size int) voidptr {
/*	if (kernel.allocator == nullptr) {
		return nullptr
	}
	mut alloc := &libtinyalloc.TinyAlloc(kernel.allocator)*/

	return nullptr
}