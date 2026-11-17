@[has_globals]
module memory

struct Page { aligned u64 raw voidptr }
__global pages_live = []Page{}
__global cancel_remaining_allocations = int(-1)
__global observer = fn (_ voidptr, _ u64) {}
__global cancel_failure_observer = fn () {}

pub fn fail_after(count int) { cancel_remaining_allocations = count }
pub fn observe_free(callback fn (voidptr, u64)) { observer = callback }
pub fn observe_failure(callback fn ()) { cancel_failure_observer = callback }
pub fn pmm_alloc_aligned_fallible(pages u64, alignment u64) &u64 {
	if cancel_remaining_allocations == 0 { cancel_failure_observer(); return unsafe { nil } }; if cancel_remaining_allocations > 0 { cancel_remaining_allocations-- }
	pages_live.flags |= .noslices
	boundary := alignment * 16384
	raw := unsafe { malloc(int(pages * 16384 + boundary)) }
	aligned := (u64(raw) + boundary - 1) & ~(boundary - 1)
	unsafe { C.memset(voidptr(aligned), 0, pages * 16384) }
	pages_live << Page{aligned, raw}; return unsafe { &u64(aligned) }
}
pub fn pmm_free(pointer voidptr, pages u64) {
	observer(pointer, pages)
	for index, page in pages_live { if page.aligned == u64(pointer) {
		unsafe { free(page.raw) }; pages_live.delete(index); return
	} }
	panic('free of unknown physical backing')
}
pub fn live_pages() int { return pages_live.len }
