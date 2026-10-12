// SPDX-License-Identifier: ISC
module ath10k

#include <malloc/malloc.h>
struct C.malloc_statistics_t {
	size_in_use usize
}

fn C.malloc_default_zone() voidptr
fn C.malloc_zone_statistics(voidptr, &C.malloc_statistics_t)

fn fixture_live_bytes() usize {
	mut statistics := C.malloc_statistics_t{}
	C.malloc_zone_statistics(C.malloc_default_zone(), unsafe { &statistics })
	return statistics.size_in_use
}
