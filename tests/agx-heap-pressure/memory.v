@[has_globals]
module memory

__global backing = [16384]u8{}
__global outstanding = false
__global allocated = 0
__global freed = 0
__global backing_pages = u64(4)
__global expected_alignment = u64(4)

pub fn set_geometry(granule u64, alignment_pages u64) {
	check_balanced()
	backing_pages = u64(16384) / granule
	expected_alignment = alignment_pages
}

pub fn pmm_alloc_aligned_fallible(pages u64, alignment u64) u64 {
	assert pages == backing_pages && alignment == expected_alignment && !outstanding
	outstanding = true; allocated++
	return u64(&backing[0])
}
pub fn pmm_free(pointer voidptr, pages u64) {
	assert pages == backing_pages && pointer == voidptr(&backing[0]) && outstanding
	outstanding = false; freed++
}
pub fn check_balanced() { assert !outstanding && allocated == freed, 'failed VA placement must return its new physical backing' }
pub fn check_total(expected int) { check_balanced(); assert allocated == expected, 'every exhausted buffer request must exercise physical backing unwind' }
