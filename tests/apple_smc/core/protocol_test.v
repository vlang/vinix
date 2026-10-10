// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
//
// The commands that reach a key by name: describe, read, write. What the
// older calls send, and what gives the channel up, are held to as well.
module core

const key_buic = u32(0x42554943)
const key_none = u32(0x5a5a5a5a) // ZZZZ

fn test_what_the_device_nodes_use_only_reads() {
	mut bench := started_bench(true, true, true)
	assert vinix_smc_shmem_address(bench.state) == sim_sram_base + 0x80000
	assert vinix_smc_refresh(bench.state) == 62
	mut flags := u32(0)
	mut voltage := i32(0)
	mut current := i32(0)
	mut power := i32(0)
	assert vinix_smc_refresh_power(bench.state, &flags, &voltage, &current, &power) == 0
	assert flags == 7 && voltage == 12300 && current == 1500 && power == 18450
	assert vinix_smc_poll(bench.state, 64) == 0
	// One command for the shared memory's address, four reads, and nothing
	// that asks about a key or stores one.
	assert bench.sim.commands == 5
	assert bench.sim.reads == 4
	assert bench.sim.writes == 0
	assert bench.sim.infos == 0
	assert bench.sim.unknown == 0
	assert bench.sim.violations == 0
	assert bench.copies == 0
	assert vinix_smc_key_writes(bench.state) == 0
	assert vinix_smc_failure(bench.state) == 0
	bench.free()
}

fn test_a_signed_current_keeps_its_sign() {
	mut bench := started_bench(false, false, false)
	bench.sim.scene(.unplugged)
	mut flags := u32(0)
	mut voltage := i32(0)
	mut current := i32(0)
	mut power := i32(0)
	assert vinix_smc_refresh_power(bench.state, &flags, &voltage, &current, &power) == 0
	assert voltage == 11700 && current == -1200 && power == -14000
	bench.free()
}

fn test_a_key_is_described() {
	mut bench := started_bench(true, true, true)
	mut size := u8(0)
	mut kind := u32(0)
	mut flags := u8(0)
	assert vinix_smc_key_info(bench.state, key_bcf0, &size, &kind, &flags) == 0
	assert size == 4 && kind == sim_type_ui32 && flags == flag_readable
	assert vinix_smc_key_info(bench.state, key_chwa, &size, &kind, &flags) == 0
	assert size == 1 && kind == sim_type_flag && flags == flag_readable | flag_writable
	assert vinix_smc_key_info(bench.state, key_tchp, &size, &kind, &flags) == 0
	assert size == 8 && kind == type_ioft
	assert vinix_smc_key_info(bench.state, key_bmdn, &size, &kind, &flags) == 0
	assert size == 32 && kind == sim_type_text
	// Any of the three may be left out.
	assert vinix_smc_key_info(bench.state, key_b0fc, unsafe { nil }, unsafe { nil }, unsafe { nil }) == 0
	assert bench.sim.infos == 5
	// A key that is not there is that key's matter.
	assert vinix_smc_key_info(bench.state, key_none, &size, &kind, &flags) == vinix_smc_no_key
	assert vinix_smc_failure(bench.state) == 0
	assert vinix_smc_key_info(bench.state, key_b0fc, &size, &kind, &flags) == 0
	assert size == 2
	assert bench.sim.violations == 0
	bench.free()
}

fn test_values_of_every_length_come_back_in_the_smc_s_order() {
	mut bench := started_bench(true, true, true)
	mut out := [32]u8{}
	assert vinix_smc_read_key(bench.state, key_buic, 1, &out[0]) == 0
	assert out[0] == 62
	assert vinix_smc_read_key(bench.state, key_b0fc, 2, &out[0]) == 0
	assert little_endian(&out[0], 2) == 4200
	// Stored the old way round on this firmware: 2590 is 0x0a1e.
	assert vinix_smc_read_key(bench.state, key_b0rm, 2, &out[0]) == 0
	assert out[0] == 0x0a && out[1] == 0x1e
	assert vinix_smc_read_key(bench.state, key_chis, 4, &out[0]) == 0
	assert little_endian(&out[0], 4) == 1
	before := bench.copies
	bench.sim.update(key_chnc, 0x0102030405060708)
	assert vinix_smc_read_key(bench.state, key_chnc, 8, &out[0]) == 0
	assert little_endian(&out[0], 8) == 0x0102030405060708
	assert out[0] == 0x08 && out[7] == 0x01
	// More than four bytes came through the shared memory, once.
	assert bench.copies == before + 1
	assert vinix_smc_read_key(bench.state, key_bmdn, 32, &out[0]) == 0
	assert unsafe { tos(&out[0], 8) } == 'bq40z651'
	assert out[8] == 0 && out[31] == 0
	assert vinix_smc_read_key(bench.state, key_bmsn, 21, &out[0]) == 0
	assert unsafe { tos(&out[0], 17) } == 'F5D0VINIX0SIM0001'
	bench.free()
}

fn test_one_key_s_error_is_that_key_s() {
	mut bench := started_bench(true, true, true)
	mut out := [32]u8{}
	assert vinix_smc_read_key(bench.state, key_none, 2, &out[0]) == vinix_smc_no_key
	// Asked for with a size it has not.
	assert vinix_smc_read_key(bench.state, key_b0fc, 4, &out[0]) == vinix_smc_io
	// One that may not be read.
	bench.sim.put(key_none, sim_type_ui8, flag_writable, 1, 7)
	assert vinix_smc_read_key(bench.state, key_none, 1, &out[0]) == vinix_smc_io
	assert vinix_smc_failure(bench.state) == 0
	assert vinix_smc_read_key(bench.state, key_b0fc, 2, &out[0]) == 0
	assert little_endian(&out[0], 2) == 4200
	bench.free()
}

fn test_an_answer_of_another_size_is_refused_and_the_channel_kept() {
	mut bench := started_bench(true, true, true)
	mut out := [32]u8{}
	bench.sim.short_reply = key_b0fc
	assert vinix_smc_read_key(bench.state, key_b0fc, 2, &out[0]) == vinix_smc_protocol
	assert vinix_smc_failure(bench.state) == 0
	assert vinix_smc_read_key(bench.state, key_b0dc, 2, &out[0]) == 0
	assert little_endian(&out[0], 2) == 4380
	assert vinix_smc_refresh(bench.state) == 62
	// The capacity key, which the device nodes are made of, is held to the
	// older rule: such an answer ends the channel.
	bench.sim.short_reply = key_buic
	bench.wait(1000)
	assert vinix_smc_refresh(bench.state) == vinix_smc_protocol
	assert vinix_smc_failure(bench.state) == vinix_smc_protocol
	sent := bench.sent
	assert vinix_smc_read_key(bench.state, key_b0dc, 2, &out[0]) == vinix_smc_protocol
	assert bench.sent == sent
	bench.free()
}

fn test_a_value_is_written_through_the_shared_memory() {
	mut bench := started_bench(true, true, true)
	mut one := [1]u8{}
	one[0] = 1
	assert vinix_smc_write_key(bench.state, key_chwa, 1, &one[0]) == 0
	assert bench.sim.value_of(key_chwa) == 1
	assert bench.sim.writes == 1
	assert bench.sim.last_written == key_chwa && bench.sim.last_byte == 1
	assert vinix_smc_key_writes(bench.state) == 1
	one[0] = 0
	assert vinix_smc_write_key(bench.state, key_chwa, 1, &one[0]) == 0
	assert bench.sim.value_of(key_chwa) == 0
	assert vinix_smc_key_writes(bench.state) == 2
	// A key that may not be written, one that is not there, a wrong size.
	one[0] = 9
	assert vinix_smc_write_key(bench.state, key_bsfc, 1, &one[0]) == vinix_smc_io
	assert bench.sim.value_of(key_bsfc) == 0
	assert vinix_smc_write_key(bench.state, key_none, 1, &one[0]) == vinix_smc_no_key
	mut two := [2]u8{}
	assert vinix_smc_write_key(bench.state, key_chwa, 2, &two[0]) == vinix_smc_io
	assert bench.sim.value_of(key_chwa) == 0
	assert vinix_smc_failure(bench.state) == 0
	assert bench.sim.violations == 0
	bench.free()
}

fn test_without_the_shared_memory_what_needs_it_is_refused_unsent() {
	mut bench := new_bench(true, true, true)
	assert bench.boot(false) == 0
	mut out := [32]u8{}
	mut size := u8(0)
	sent := bench.sent
	assert vinix_smc_key_info(bench.state, key_b0fc, &size, unsafe { nil }, unsafe { nil }) == vinix_smc_unsupported
	assert vinix_smc_read_key(bench.state, key_chnc, 8, &out[0]) == vinix_smc_unsupported
	out[0] = 1
	assert vinix_smc_write_key(bench.state, key_chwa, 1, &out[0]) == vinix_smc_unsupported
	assert bench.sent == sent
	assert vinix_smc_key_writes(bench.state) == 0
	// What fits in a reply still does.
	assert vinix_smc_read_key(bench.state, key_b0fc, 2, &out[0]) == 0
	assert little_endian(&out[0], 2) == 4200
	bench.free()
}

fn test_lengths_and_buffers_are_checked_before_anything_is_sent() {
	mut bench := started_bench(true, true, true)
	mut out := [40]u8{}
	sent := bench.sent
	assert vinix_smc_read_key(bench.state, key_b0fc, 0, &out[0]) == vinix_smc_argument
	assert vinix_smc_read_key(bench.state, key_b0fc, 33, &out[0]) == vinix_smc_argument
	assert vinix_smc_read_key(bench.state, key_b0fc, 2, unsafe { nil }) == vinix_smc_argument
	assert vinix_smc_write_key(bench.state, key_chwa, 0, &out[0]) == vinix_smc_argument
	assert vinix_smc_write_key(bench.state, key_chwa, 33, &out[0]) == vinix_smc_argument
	assert vinix_smc_write_key(bench.state, key_chwa, 1, unsafe { nil }) == vinix_smc_argument
	assert bench.sent == sent
	assert vinix_smc_key_writes(bench.state) == 0
	assert unsafe { cstring_to_vstring(vinix_smc_error(vinix_smc_argument)) } == 'key length or buffer not acceptable'
	// Nothing is possible before the client has started, or with no client.
	mut cold := new_bench(true, true, true)
	assert vinix_smc_read_key(cold.state, key_b0fc, 2, &out[0]) == vinix_smc_not_ready
	assert vinix_smc_set_shmem(cold.state, bench_shared) == vinix_smc_not_ready
	assert vinix_smc_shmem_address(cold.state) == 0
	assert vinix_smc_read_key(unsafe { nil }, key_b0fc, 2, &out[0]) == vinix_smc_not_ready
	assert vinix_smc_key_writes(unsafe { nil }) == 0
	assert cold.sent == 0
	cold.free()
	bench.free()
}

fn test_a_reply_that_never_comes_gives_the_channel_up() {
	mut bench := started_bench(true, true, true)
	mut out := [32]u8{}
	bench.sim.silent = true
	started := bench.ticks
	assert vinix_smc_read_key(bench.state, key_b0fc, 2, &out[0]) == vinix_smc_timeout
	// Half a second by the clock, and not a look more.
	assert bench.ticks - started >= 500 && bench.ticks - started < 520
	assert vinix_smc_failure(bench.state) == vinix_smc_timeout
	bench.sim.silent = false
	sent := bench.sent
	mut size := u8(0)
	assert vinix_smc_read_key(bench.state, key_b0fc, 2, &out[0]) == vinix_smc_timeout
	assert vinix_smc_key_info(bench.state, key_b0fc, &size, unsafe { nil }, unsafe { nil }) == vinix_smc_timeout
	out[0] = 1
	assert vinix_smc_write_key(bench.state, key_chwa, 1, &out[0]) == vinix_smc_timeout
	assert vinix_smc_refresh(bench.state) == vinix_smc_timeout
	assert bench.sent == sent
	assert bench.sim.writes == 0
	bench.free()
}

fn test_a_write_that_is_never_answered_gives_the_channel_up_too() {
	mut bench := started_bench(true, true, true)
	mut one := [1]u8{}
	one[0] = 1
	bench.sim.silent = true
	assert vinix_smc_write_key(bench.state, key_chwa, 1, &one[0]) == vinix_smc_timeout
	assert vinix_smc_failure(bench.state) == vinix_smc_timeout
	bench.free()
}

fn test_a_stopped_clock_does_not_hold_a_read_for_ever() {
	mut bench := started_bench(true, true, true)
	mut out := [32]u8{}
	bench.sim.silent = true
	bench.step = 0
	assert vinix_smc_read_key(bench.state, key_b0fc, 2, &out[0]) == vinix_smc_timeout
	bench.free()
}

fn test_what_the_firmware_says_unasked_is_not_taken_for_an_answer() {
	mut bench := started_bench(true, true, true)
	mut out := [32]u8{}
	bench.sim.notify(0x71010101)
	bench.sim.notify(0x71020000)
	assert vinix_smc_read_key(bench.state, key_b0fc, 2, &out[0]) == 0
	assert little_endian(&out[0], 2) == 4200
	mut size := u8(0)
	bench.sim.notify(0x71130000)
	assert vinix_smc_key_info(bench.state, key_b0fc, &size, unsafe { nil }, unsafe { nil }) == 0
	assert size == 2
	bench.free()
}

fn test_the_four_bit_request_number_wraps() {
	mut bench := started_bench(true, true, true)
	mut out := [32]u8{}
	for i in 0 .. 40 {
		bench.sim.update(key_b0ct, u64(i))
		assert vinix_smc_read_key(bench.state, key_b0ct, 2, &out[0]) == 0
		assert little_endian(&out[0], 2) == u64(i)
	}
	bench.free()
}

fn test_a_mailbox_that_fails_ends_the_channel() {
	mut bench := started_bench(true, true, true)
	mut out := [32]u8{}
	bench.send_fails = true
	assert vinix_smc_read_key(bench.state, key_b0fc, 2, &out[0]) == vinix_smc_io
	assert vinix_smc_failure(bench.state) == vinix_smc_io
	bench.free()
	bench = started_bench(true, true, true)
	bench.receive_fails = true
	assert vinix_smc_read_key(bench.state, key_b0fc, 2, &out[0]) == vinix_smc_io
	assert vinix_smc_failure(bench.state) == vinix_smc_io
	bench.free()
}

fn test_the_simulated_smc_lists_its_keys_by_number() {
	mut bench := started_bench(false, false, false)
	// GET_KEY_BY_INDEX is not a command the client sends; the simulated SMC
	// has it because a real one does. Asked directly, it answers.
	bench.sim.send((u64(0) << 32) | (u64(3) << 12) | 0x12, 32)
	got, word, endpoint := bench.sim.receive()
	assert got && endpoint == 32
	assert word & 0xff == 0 && (word >> 12) & 0xf == 3
	// Its first key is B0FC, as the four characters in memory order.
	assert u32(word >> 32) == 0x43463042
	bench.sim.send((u64(999) << 32) | 0x12, 32)
	_, missing, _ := bench.sim.receive()
	assert missing & 0xff == u64(sim_no_key)
	// A command nobody has is answered with an error and counted.
	bench.sim.send(u64(0x55), 32)
	_, unknown, _ := bench.sim.receive()
	assert unknown & 0xff != 0
	assert bench.sim.unknown == 1
	bench.free()
}
