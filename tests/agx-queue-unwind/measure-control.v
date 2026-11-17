// SPDX-License-Identifier: GPL-2.0-or-later
// Host-only control for malloc-zone accounting of immediately freed records.
#include <malloc/malloc.h>
struct C.malloc_statistics_t { blocks_in_use u32 size_in_use u64 }
fn C.malloc_zone_statistics(voidptr, &C.malloc_statistics_t)
fn C.malloc_size(voidptr) u64
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn stats() (u32, u64) {
	mut result := C.malloc_statistics_t{}
	C.malloc_zone_statistics(unsafe { nil }, unsafe { &result })
	return result.blocks_in_use, result.size_in_use
}
fn churn() {
	for _ in 0 .. 10000 { p := C.malloc(144); assert p != unsafe { nil }; C.free(p) }
}
fn main() {
	probe := C.malloc(144); C.printf(c'AGX-UNWIND-MALLOC-CONTROL allocation_bytes=%llu\n', C.malloc_size(probe)); C.free(probe)
	churn(); stats()
	for round in 0 .. 3 {
		a, b := stats(); churn(); c, d := stats()
		C.printf(c'AGX-UNWIND-MALLOC-CONTROL round=%d freed_operations=10000 reported_blocks=%lld reported_bytes=%lld\n', round, i64(c) - i64(a), i64(d) - i64(b))
	}
}
