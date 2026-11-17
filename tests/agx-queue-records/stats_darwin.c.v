module file
#include <malloc/malloc.h>
struct C.malloc_statistics_t { blocks_in_use u32 size_in_use u64 }
fn C.malloc_zone_statistics(voidptr, &C.malloc_statistics_t)
fn live_record_heap() (u32, u64) {
	mut stats := C.malloc_statistics_t{}
	C.malloc_zone_statistics(unsafe { nil }, unsafe { &stats })
	return stats.blocks_in_use, stats.size_in_use
}
