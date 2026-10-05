// SPDX-License-Identifier: GPL-2.0-or-later
module krandom

import lib
import memory

fn reseed_require(ok bool) {
	if !ok { lib.kpanic(unsafe { nil }, c'RANDOM-RESEED: FAIL') }
}

fn reseed_snapshot(sizes &[32]u64, live &[32]u64) int {
	classes := memory.heap_classes()
	count := classes.len
	reseed_require(count > 0 && count <= 32)
	for i, class in classes {
		unsafe {
			sizes[i] = class.size
			live[i] = class.live
		}
	}
	unsafe { classes.free() }
	return count
}

// Opt-in native test runs during random-device initialization, before PID 1
// and the maintenance thread. Only the entropy pool's lock-free timing
// samples can change concurrently; no test workspace survives a call.
fn reseed_selftest() {
	mut digest := [32]u8{}
	sha256_digest(c'abc', 3, unsafe { &digest })
	expected := [u8(0xba), 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
		0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
		0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
		0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad]!
	for i in 0 .. 32 { reseed_require(digest[i] == expected[i]) }
	mut output := [65]u8{}
	for i in 0 .. 20 {
		add_event(u64(i))
		stir()
		reseed_require(fill(unsafe { &output[0] }, u64(output.len), true))
	}
	mut sizes := [32]u64{}
	mut before := [32]u64{}
	mut after_sizes := [32]u64{}
	mut after := [32]u64{}
	count := reseed_snapshot(unsafe { &sizes }, unsafe { &before })
	large_before := memory.heap_big_pages()
	for i in 0 .. 10000 {
		add_event(u64(i))
		stir()
		reseed_require(fill(unsafe { &output[0] }, u64(output.len), true))
	}
	large_after := memory.heap_big_pages()
	reseed_require(reseed_snapshot(unsafe { &after_sizes }, unsafe { &after }) == count)
	mut flat := large_before == large_after
	for i in 0 .. count {
		C.kprintf(c'RANDOM-RESEED: class=%llu objects=%lld\n', sizes[i], i64(after[i]) - i64(before[i]))
		flat = flat && sizes[i] == after_sizes[i] && before[i] == after[i]
	}
	C.kprintf(c'RANDOM-RESEED: large-pages=%lld\n', i64(large_after) - i64(large_before))
	reseed_require(flat)
	explicit_bzero(unsafe { &digest[0] }, sizeof(digest))
	explicit_bzero(unsafe { &output[0] }, sizeof(output))
	C.kprintf(c'RANDOM-RESEED: 10000 reseeds and partial reads PASS\n')
}
