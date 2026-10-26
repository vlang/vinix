module main

import alloctrack

#include <sys/mman.h>
#include <unistd.h>
#include <malloc/malloc.h>

fn C.getpagesize() i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32

struct C.malloc_statistics_t {
	blocks_in_use u32
	size_in_use usize
	max_size_in_use usize
	size_allocated usize
}

fn C.malloc_zone_statistics(voidptr, &C.malloc_statistics_t)

fn expect(name string, frame &u64, minimum u64, wanted [10]u64) ! {
	got := alloctrack.frame_page_chain(frame, minimum)
	for i in 0 .. 10 {
		if got[i] != wanted[i] { return error('${name}: slot ${i}: ${got[i]} != ${wanted[i]}') }
	}
	println('FRAME-PAGE ${name} PASS')
}

fn check() ! {
	$if !macos { return error('this checker requires macOS malloc-zone statistics') }
	page_size := usize(C.getpagesize())
	if page_size < 4096 || page_size % 4096 != 0 { return error('unsupported host page size') }
	area := C.mmap(unsafe { nil }, page_size * 2, C.PROT_READ | C.PROT_WRITE,
		C.MAP_ANON | C.MAP_PRIVATE, -1, 0)
	if area == voidptr(-1) { return error('mmap failed') }
	defer { if C.munmap(area, page_size * 2) != 0 { eprintln('munmap failed'); exit(1) } }
	guard := u64(area) + u64(page_size)
	if C.mprotect(voidptr(guard), page_size, C.PROT_NONE) != 0 { return error('mprotect failed') }
	base := guard - 4096
	frame := unsafe { &u64(base + 64) }
	mut wanted := [10]u64{}
	unsafe {
		for i in 0 .. 11 {
			fp := &u64(base + 64 + u64(i) * 16)
			fp[0] = u64(fp) + 16
			fp[1] = u64(100 + i)
			if i < 10 { wanted[i] = u64(100 + i) }
		}
	}
	expect('ten-frame-limit', frame, 0, wanted)!
	mut one := [10]u64{}
	one[0] = 100
	unsafe { frame[0] = 0 }
	expect('null-next', frame, 0, one)!
	unsafe { frame[0] = u64(frame) }
	expect('self-cycle', frame, 0, one)!
	unsafe { frame[0] = u64(frame) - 16 }
	expect('backward', frame, 0, one)!
	unsafe { frame[0] = u64(frame) + 17 }
	expect('misaligned-next', frame, 0, one)!
	unsafe { frame[0] = guard }
	expect('unmapped-next-page', frame, 0, one)!
	unsafe { frame[0] = base - 16 }
	expect('previous-page', frame, 0, one)!
	unsafe { frame[0] = u64(0xffffffffffffff00) }
	expect('reported-panic-pointer', frame, 0, one)!
	unsafe { frame[0] = guard - 8 }
	expect('straddling-next-frame', frame, 0, one)!
	expect('straddling-first-frame', unsafe { &u64(guard - 8) }, 0, [10]u64{})!
	expect('misaligned-first-frame', unsafe { &u64(base + 65) }, 0, [10]u64{})!
	expect('below-minimum-first-frame', frame, u64(frame) + 1, [10]u64{})!
	expect('null-first-frame', unsafe { &u64(0) }, 1, [10]u64{})!
	last := unsafe { &u64(guard - 16) }
	unsafe { last[0] = guard; last[1] = 999 }
	mut edge := [10]u64{}
	edge[0] = 999
	expect('last-complete-frame', last, 0, edge)!
	// A mapped neighbouring 4KiB page still must not extend the proven window.
	if page_size > 4096 {
		preceding := unsafe { &u64(base - 16) }
		unsafe { preceding[0] = u64(frame); preceding[1] = 777 }
		mut earlier := [10]u64{}
		earlier[0] = 777
		expect('mapped-next-page', preceding, 0, earlier)!
	} else { println('FRAME-PAGE mapped-next-page SKIP host page is 4KiB') }
	unsafe { frame[0] = guard }
	mut warm := C.malloc_statistics_t{}
	C.malloc_zone_statistics(unsafe { nil }, &warm)
	mut checksum := u64(0)
	for _ in 0 .. 100 { checksum += alloctrack.frame_page_chain(frame, 0)[0] }
	mut before := C.malloc_statistics_t{}
	C.malloc_zone_statistics(unsafe { nil }, &before)
	for _ in 0 .. 10_000 { checksum += alloctrack.frame_page_chain(frame, 0)[0] }
	mut after := C.malloc_statistics_t{}
	C.malloc_zone_statistics(unsafe { nil }, &after)
	if checksum != 1_010_000 { return error('loop checksum mismatch') }
	if before.blocks_in_use != after.blocks_in_use || before.size_in_use != after.size_in_use {
		return error('walker kept heap allocations: ${before.blocks_in_use}/${before.size_in_use} -> ${after.blocks_in_use}/${after.size_in_use}')
	}
	println('FRAME-PAGE 10000-flat PASS blocks=${before.blocks_in_use}->${after.blocks_in_use} bytes=${before.size_in_use}->${after.size_in_use} checksum=${checksum}')
	println('FRAME-PAGE complete PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
