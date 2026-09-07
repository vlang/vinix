// SPDX-License-Identifier: GPL-2.0-only OR MIT
// Copyright (c) 2026 Alexander Medvednikov
module core

fn new_test_state(layout Layout, maximum u32, scale u32, known bool) State {
	mut state := State{}
	assert state.initialise(layout, maximum, scale, 50 * scale, known) == .ok
	return state
}

fn snapshot(state &State) string {
	mut text := []u8{len: text_capacity}
	length := state.format(mut text) or { panic('format failed') }
	assert text[length] == 0
	return text[..length].bytestr()
}

fn test_calibration() {
	mut previous := u32(0)
	for nits in min_nits .. max_nits + 1 {
		dac := nits_to_dac(nits) or { panic('valid calibration rejected') }
		assert dac >= previous
		assert dac & 15 == 0
		previous = dac
	}
	for nits, expected in {
		u32(2): u32(0)
		99:     0x58f058d0
		100:    0x592858d0
		101:    0x596058e0
		102:    0x599858e0
		103:    0x59d058f0
	} {
		assert nits_to_dac(nits) or { panic('missing calibration') } == expected
	}
	for nits in [u32(0), 1, 510, ~u32(0)] {
		if _ := nits_to_dac(nits) {
			assert false, 'invalid nits accepted'
		}
	}
}

fn test_parser() {
	for text, expected in {
		'2':     u32(2)
		'400\n': 400
		'0509':  509
	} {
		assert parse_nits(text.bytes()) or { panic('valid command rejected') } == expected
	}
	for text in ['', '\n', '0', '1', '510', '-20', '+20', ' 20', '20 ', '20\n\n', '20\r\n', '20junk',
		'20 30', '4294967296', '9999999999999999', '20\x00', '00000000000000020'] {
		if _ := parse_nits(text.bytes()) {
			assert false, 'invalid command accepted'
		}
	}
	for byte in 0 .. 256 {
		text := [u8(`2`), `0`, u8(byte)]
		mut accepted := false
		if _ := parse_nits(text) {
			accepted = true
		}
		assert accepted == ((byte >= `0` && byte <= `9`) || byte == `\n`)
	}
}

// Independent packed layout of the upstream swap prefix. These tests check
// sizeof/offsetof of native V packed structs, not C helper structs.
@[packed]
struct Rectangle {
	x      u32
	y      u32
	width  u32
	height u32
}

@[packed]
struct SwapPrefix {
	timestamps      [8]u64
	flags           [2]u64
	swap_id         u32
	surface_ids     [4]u32
	src             [4]Rectangle
	surface_flags   [4]u32
	surface_unknown [4]u32
	dst             [4]Rectangle
	enabled         u32
	completed       u32
	background      u32
	unknown_110     [0x1b8]u8
	unknown_2c8     u32
	unknown_2cc     [0x14]u8
	unknown_2e0     u32
}

@[packed]
struct Swap12 {
	prefix      SwapPrefix
	unknown_2e2 u16
	bl_unk      u64
	bl_value    u32
	bl_power    u8
	tail        [0x2d]u8
}

@[packed]
struct Swap13 {
	prefix        SwapPrefix
	unknown_2e2   [3]u8
	bl_unk        u64
	bl_value      u32
	bl_power      u8
	tail          [0x2d]u8
	new_tail      [0x13f]u8
	unknown_final u64
}

fn test_packed_wire_layouts_and_bounds() {
	assert sizeof(Swap12) == 0x320
	assert sizeof(Swap13) == 0x468
	assert __offsetof(Swap12, bl_unk) == 0x2e6
	assert __offsetof(Swap13, bl_unk) == 0x2e7
	for layout in [Layout.v12_3, .v13_3] {
		size := if layout == .v12_3 { int(sizeof(Swap12)) } else { int(sizeof(Swap13)) }
		offset := 1 + if layout == .v12_3 { 0x2e6 } else { 0x2e7 }
		mut buffer := []u8{len: 0x500, init: 0xa5}
		original := buffer.clone()
		mut unaligned := unsafe { buffer[1..1 + size] }
		assert patch_swap(layout, 99, mut unaligned) == .ok
		for i in 0 .. buffer.len {
			if i < offset || i >= offset + 13 {
				assert buffer[i] == original[i]
			}
		}
		assert buffer[offset..offset + 13] == [u8(1), 0, 0, 0, 0, 0, 0, 0, 0xd0, 0x58, 0xf0, 0x58,
			0x40]
		for length in 0 .. size {
			mut short := []u8{len: length, init: 0xa5}
			before := short.clone()
			assert patch_swap(layout, 99, mut short) == .invalid
			assert short == before
		}
		mut invalid := original.clone()
		assert patch_swap(layout, 510, mut invalid) == .invalid
		assert invalid == original
	}
	mut swap := []u8{len: 0x468}
	assert patch_swap(.unsupported, 99, mut swap) == .unsupported
}

fn test_initialization_is_atomic_and_never_changes_boot_brightness() {
	mut state := new_test_state(.v12_3, 400, 65536, true)
	before := state
	assert state.initialise(.v12_3, 400, 0, 0, false) == .invalid
	assert state.initialise(.v12_3, 1, 100, 0, false) == .invalid
	assert state.initialise(.unsupported, 400, 100, 0, false) == .unsupported
	assert state.initialise(.v12_3, 400, 100, 40100, true) == .invalid
	assert state == before
	assert state.request(200) == .offline
	mut swap := []u8{len: 0x468, init: 0xa5}
	original := swap.clone()
	status, token := state.prepare(mut swap)
	assert status == .offline && token == 0
	assert state.set_online(true) == .ok
	idle, idle_token := state.prepare(mut swap)
	assert idle == .idle && idle_token == 0
	assert swap == original
	assert snapshot(&state).contains('requested_nits=unknown\n')
	assert snapshot(&state).contains('actual_nits=50\n')
	assert snapshot(&state).contains('pending=0\n')
	assert state.write('401'.bytes()) == .invalid
	assert snapshot(&state).contains('requested_nits=unknown\n')
	large := new_test_state(.v13_3, 1600, 100, false)
	assert snapshot(&large).contains('max_nits=509\n')
	assert snapshot(&large).contains('actual_nits=unknown\n')
}

fn prepare_token(mut state State, mut swap []u8) u64 {
	status, token := state.prepare(mut swap)
	assert status == .ok && token != 0
	return token
}

fn test_transaction_coalescing_errors_and_stale_replies() {
	mut state := new_test_state(.v12_3, 400, 1000, true)
	mut swap := []u8{len: 0x468}
	assert state.set_online(true) == .ok
	assert state.write('100\n'.bytes()) == .ok
	mut short := []u8{len: 10}
	bad, zero := state.prepare(mut short)
	assert bad == .invalid && zero == 0
	assert snapshot(&state).contains('pending=1\n')
	a := prepare_token(mut state, mut swap)
	busy, none_token := state.prepare(mut swap)
	assert busy == .busy && none_token == 0
	assert state.request(200) == .ok
	assert state.complete(a, true) == .ok
	assert snapshot(&state).contains('requested_nits=200\n')
	assert snapshot(&state).contains('pending=1\n')
	assert snapshot(&state).contains('actual_nits=50\n')
	b := prepare_token(mut state, mut swap)
	assert b > a
	assert state.complete(a, true) == .stale
	assert state.complete(b, false) == .ok
	assert snapshot(&state).contains('pending=1\n')
	c := prepare_token(mut state, mut swap)
	assert c > b
	assert state.complete(b, true) == .stale
	assert state.complete(c, true) == .ok
	assert snapshot(&state).contains('pending=0\n')
	assert snapshot(&state).contains('actual_nits=50\n')
	assert state.publish(199999) == .ok
	assert snapshot(&state).contains('actual_nits=199\n')
	idle, idle_token := state.prepare(mut swap)
	assert idle == .idle && idle_token == 0
	assert state.complete(c, true) == .stale
}

fn test_recovery_preserves_request_and_invalidates_old_tokens() {
	mut state := new_test_state(.v13_3, 400, 100, false)
	mut swap := []u8{len: 0x468}
	assert state.set_online(true) == .ok
	assert state.request(100) == .ok
	old := prepare_token(mut state, mut swap)
	assert state.set_online(false) == .ok
	assert snapshot(&state).contains('actual_nits=unknown\n')
	assert snapshot(&state).contains('online=0\n')
	assert state.publish(10000) == .offline
	assert state.complete(old, true) == .offline
	assert state.write('200'.bytes()) == .offline
	assert state.set_online(true) == .ok
	assert snapshot(&state).contains('requested_nits=100\n')
	next := prepare_token(mut state, mut swap)
	assert next > old
	assert state.complete(old, true) == .stale
	assert state.complete(next, true) == .ok
	assert snapshot(&state).contains('pending=0\n')
	assert state.set_online(false) == .ok
	assert state.set_online(true) == .ok
	assert snapshot(&state).contains('pending=1\n')
}

fn test_format_bounds_and_unknown_state() {
	mut state := new_test_state(.v13_3, 400, 1, false)
	assert state.set_online(true) == .ok
	assert state.publish(~u32(0)) == .ok
	valid := snapshot(&state)
	assert valid.contains('actual_nits=4294967295\n')
	for size in 0 .. valid.len + 1 {
		mut guard := []u8{len: size, init: 0x5a}
		before := guard.clone()
		if _ := state.format(mut guard) {
			assert false, 'short output accepted'
		}
		assert guard == before
	}
	mut enough := []u8{len: valid.len + 1}
	assert state.format(mut enough) or { panic('exact output rejected') } == valid.len
	assert enough[..valid.len].bytestr() == valid
	mut empty := State{}
	assert empty.request(100) == .invalid
	assert empty.set_online(true) == .invalid
	assert empty.complete(1, true) == .invalid
	assert empty.publish(100) == .invalid
	if _ := empty.format(mut enough) {
		assert false
	}
}

fn test_overflow_never_wraps_tokens_or_changes_pending_state() {
	mut state := new_test_state(.v13_3, 400, 100, true)
	assert state.set_online(true) == .ok
	state.generation = ~u64(0)
	before := state
	assert state.request(200) == .overflow
	assert state == before
	state.generation = 0
	assert state.request(200) == .ok
	state.next_token = ~u64(0)
	mut swap := []u8{len: 0x468, init: 0xa5}
	original := swap.clone()
	status, token := state.prepare(mut swap)
	assert status == .overflow && token == 0
	assert swap == original
	assert snapshot(&state).contains('pending=1\n')
}
