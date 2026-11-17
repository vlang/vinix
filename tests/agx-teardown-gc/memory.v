@[has_globals]
module memory

__global teardown_freed = [128]bool{}
__global teardown_free_count = 0
pub fn reset() { teardown_freed = [128]bool{}; teardown_free_count = 0 }
pub fn count() int { return teardown_free_count }
pub fn pmm_free(pointer voidptr, pages u64) {
	id := int(u64(pointer))
	assert id > 0 && id < 128 && pages == 1 && !teardown_freed[id], 'physical backing releases once'
	teardown_freed[id] = true; teardown_free_count++
}
