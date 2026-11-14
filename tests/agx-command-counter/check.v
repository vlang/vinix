// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw

#include <stdio.h>
#define kprintf printf
fn C.kprintf(format &char, ...) i32

fn word(bytes voidptr, offset u64) u64 {
	mut value := u64(0)
	unsafe { C.memcpy(&value, voidptr(u64(bytes) + offset), sizeof(u64)) }
	return value
}

fn check_render(fragment_counter u64, vertex_counter u64) {
	vertex := fw.G13RunVertex{tag: fw.cmd_type_run_vertex}
	fragment := fw.G13RunFragment{tag: fw.cmd_type_run_fragment}
	v := fw.make_g13_vertex_v13_5(&vertex, vertex_counter)
	f := fw.make_g13_fragment_v13_5(&fragment, fragment_counter)
	assert word(voidptr(&v), 4) == vertex_counter && word(voidptr(&f), 4) == fragment_counter
	start_v := fw.G13MicroseqStartVertex{header: fw.g13_useq_start_vertex}
	start_f := fw.G13MicroseqStartFragment{header: fw.g13_useq_start_fragment}
	mut bytes := [512]u8{init: 0xa5}
	size_v := write_g13_start_vertex(unsafe { &bytes[0] }, true, &start_v, vertex_counter, 0x12340000)
	assert size_v == 0x18c && bytes[size_v] == 0xa5
	assert word(unsafe { &bytes[0] }, 0x178) == word(voidptr(&v), 4)
	assert word(unsafe { &bytes[0] }, 0x180) == 0x12340000
	bytes = [512]u8{init: 0xa5}
	size_f := write_g13_start_fragment(unsafe { &bytes[0] }, true, &start_f, fragment_counter, 0x23450000)
	assert size_f == 0x1ac && bytes[size_f] == 0xa5
	assert word(unsafe { &bytes[0] }, 0x19c) == word(voidptr(&f), 4)
	assert word(unsafe { &bytes[0] }, 0x1a4) == 0x23450000
	// Monterey has no counter in either packet. Preserve every legacy byte.
	size_old_v := write_g13_start_vertex(unsafe { &bytes[0] }, false, &start_v, vertex_counter, 1)
	assert size_old_v == sizeof(start_v)
	assert unsafe { C.memcmp(&bytes[0], &start_v, sizeof(start_v)) } == 0
	size_old_f := write_g13_start_fragment(unsafe { &bytes[0] }, false, &start_f, fragment_counter, 2)
	assert size_old_f == sizeof(start_f)
	assert unsafe { C.memcmp(&bytes[0], &start_f, sizeof(start_f)) } == 0
}

fn check_compute(counter u64) {
	command := fw.G13RunCompute{tag: fw.cmd_type_run_compute}
	run := fw.make_g13_compute_v13_5(&command, counter)
	assert word(voidptr(&run), 4) == counter
	start := fw.G13MicroseqStartCompute{header: fw.g13_useq_start_compute}
	mut bytes := [512]u8{init: 0xa5}
	size := write_g13_start_compute(unsafe { &bytes[0] }, true, &start, 0x45670000, counter, 0x34560000)
	assert size == 0x16c && bytes[size] == 0xa5
	assert word(unsafe { &bytes[0] }, 0x154) == 0x45670000
	assert word(unsafe { &bytes[0] }, 0x15c) == word(voidptr(&run), 4)
	assert word(unsafe { &bytes[0] }, 0x164) == 0x34560000
	size_old := write_g13_start_compute(unsafe { &bytes[0] }, false, &start, 1, counter, 2)
	assert size_old == sizeof(start)
	assert unsafe { C.memcmp(&bytes[0], &start, sizeof(start)) } == 0
}

pub fn check_counters() {
	mut ids := G13QueueIds{}
	assert ids.allocate() == 2 && ids.allocate() == 3
	assert ids.allocate() == 4 // failed queue creation still consumes its ID
	assert ids.allocate() == 5
	ids.next = u64(0x1_0000_00ff)
	id := ids.allocate()
	assert u32(id) == 0xff && u8(id & 0xff) == 0xff
	assert ids.allocate() == 0x1_0000_0100
	ids.next = ~u64(0)
	assert ids.allocate() == ~u64(0) && ids.allocate() == 0
	// Upstream shared-counter sequence: render(0,1), compute(2),
	// compute(3), render(4,5). A second queue begins independently at zero.
	mut next := G13CommandCounter{}
	mut other := G13CommandCounter{}
	a := next.reserve(2, true)
	assert a == 0
	check_render(a, a + 1)
	b := next.reserve(1, true)
	assert b == 2
	check_compute(b)
	assert other.reserve(1, true) == 0
	assert next.reserve(1, true) == 3
	c := next.reserve(2, true)
	assert c == 4 && next.next == 6 && other.next == 1
	check_render(c, c + 1)
	// Canceled construction consumes its sequence just like fetch_add.
	assert next.reserve(2, true) == 6
	for i := u64(0); i < 200; i++ {
		comp := next.reserve(1, true)
		assert comp == 8 + 3 * i
		check_compute(comp)
		frag := next.reserve(2, true)
		assert frag == 9 + 3 * i
		check_render(frag, frag + 1)
	}
	assert other.reserve(2, false) == 0 && other.next == 1
	next.next = ~u64(0) - 1
	assert next.reserve(2, true) == ~u64(0) - 1 && next.next == 0
	check_render(~u64(0) - 1, ~u64(0))
	assert next.reserve(1, true) == 0 && next.next == 1
	next.next = ~u64(0)
	wrapped := next.reserve(2, true)
	check_render(wrapped, wrapped + 1)
	assert next.next == 1
	check_compute(0xabcdef0100000002)
	println('AGX firmware identity/counters: device-wide queue IDs, mixed shared-queue sequence, independent queues, canceled gaps, wrap, command/microsequence agreement and byte-exact legacy encoding passed')
}
