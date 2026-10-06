// Independent original live-count, call-chain and bounded-output fixture.
@[has_globals]
module fixture

#include <fixture-v-abi.h>
@[typedef]
struct C.vtrack_ull {}
fn C.assert(bool)
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.strchr(&char, i32) &char
fn C.sscanf(&char, &char, ...) i32
fn C.vinix_alloc_track_enter(voidptr, u64, &u64)
fn C.alloc_untrack(voidptr)
fn C.alloc_track_start()
fn C.alloc_track_dump(&char, u64, u64) u64

__global (
	track_fixture_frames [20]u64
	track_fixture_output [30000]char
)

fn record(index u32, size u32) {
	unsafe { C.vinix_alloc_track_enter(voidptr(usize(0x10000 + 16 * index)), u64(size), &track_fixture_frames[0]) }
}

fn check(expected u32, count16 u32, count32 u32) {
	unsafe {
		n := C.alloc_track_dump(&track_fixture_output[0], 29999, 1)
		C.assert(n < 30000)
		track_fixture_output[n] = 0
		mut live := u32(0)
		mut dropped := u32(0)
		C.assert(C.sscanf(&track_fixture_output[0], c'live %u dropped %u', &live, &dropped) == 2)
		C.assert(live == expected && dropped == 0)
		mut seen16 := u32(0)
		mut seen32 := u32(0)
		for cursor := C.strchr(&track_fixture_output[0], i32(`\n`)) + 1; *cursor != 0; cursor = C.strchr(cursor, i32(`\n`)) + 1 {
			mut count := u32(0)
			mut size := u32(0)
			mut pcs := [10]C.vtrack_ull{}
			C.assert(C.sscanf(cursor, c'%u %u %llx %llx %llx %llx %llx %llx %llx %llx %llx %llx',
				&count, &size, &pcs[0], &pcs[1], &pcs[2], &pcs[3], &pcs[4], &pcs[5], &pcs[6], &pcs[7], &pcs[8], &pcs[9]) == 12)
			for j in 0 .. 10 {
				mut value := u64(0)
				C.memcpy(&value, &pcs[j], sizeof(u64))
				C.assert(value == 0x1000 + u64(j))
			}
			if size == 16 { seen16 += count } else { C.assert(size == 32); seen32 += count }
		}
		C.assert(seen16 == count16 && seen32 == count32)
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		for i in 0 .. 10 {
			track_fixture_frames[i * 2] = if i < 9 { u64(usize(&track_fixture_frames[(i + 1) * 2])) } else { u64(0) }
			track_fixture_frames[i * 2 + 1] = 0x1000 + u64(i)
		}
		record(1, 16)
		check(0, 0, 0)
		C.alloc_track_start()
		for i in u32(1) .. u32(8193) { record(i, if i & 1 != 0 { u32(16) } else { u32(32) }) }
		check(8192, 4096, 4096)
		record(1, 32)
		check(8192, 4095, 4097)
		mut odd := u32(1)
		for odd <= 8192 { C.alloc_untrack(voidptr(usize(0x10000 + 16 * odd))); odd += 2 }
		check(4096, 0, 4096)
		mut even := u32(2)
		for even <= 8192 { C.alloc_untrack(voidptr(usize(0x10000 + 16 * even))); even += 2 }
		check(0, 0, 0)
		for i in u32(1) .. u32(1025) { record(i, 16) }
		check(1024, 1024, 0)
		mut golden := [30000]char{}
		full := C.alloc_track_dump(&golden[0], 30000, 1)
		for cap := u32(0); u64(cap) <= full + 2; cap++ {
			C.memset(&track_fixture_output[0], 0xa5, 30000)
			count := C.alloc_track_dump(&track_fixture_output[0], u64(cap), 1)
			C.assert(count == if u64(cap) < full { u64(cap) } else { full })
			C.assert(C.memcmp(&track_fixture_output[0], &golden[0], usize(count)) == 0)
			C.assert(u8(track_fixture_output[cap]) == 0xa5)
		}
		C.alloc_track_start()
		check(0, 0, 0)
		C.alloc_untrack(nil)
		record(1, 16)
		C.alloc_untrack(voidptr(usize(0x1234)))
		check(1, 1, 0)
		return 0
	}
}
