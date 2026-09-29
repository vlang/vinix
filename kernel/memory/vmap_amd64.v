module memory

// big_alloc's fallback of separate pages mapped side by side (vmap_arm64.v) is
// not built here: freeing such an allocation must drop its translations on
// every CPU before the pages are reused, and amd64 has no TLB shootdown yet
// (flush_tlb_everywhere() is empty). Without one, a big allocation that finds
// no contiguous run still stops the kernel.

fn vmap_contains(_ u64) bool {
	return false
}

fn vmap_alloc(_ u64) voidptr {
	return unsafe { nil }
}

fn vmap_free(_ u64) u64 {
	return 0
}

// The physical address behind a kernel pointer from the direct map.
pub fn kernel_virt2phys(addr u64) u64 {
	return addr - higher_half
}
