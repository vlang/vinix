// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
//
// The SMC client on the build machine: the protocol core of
// kernel/apple/smc/core with the simulated SMC of the same directory behind
// its mailbox callbacks, and a clock that moves a millisecond each time it is
// read. What a kernel built with -d applesmc_selftest does with a thread, a
// lock and the real clock, a test does here in a straight line.
module core

// kernel/c also holds the kernel's own string.h and ctype.h, which must not
// come before the build machine's: include/ has the one header wanted.
#flag -I @DIR/include
#flag -DVINIX_V_RUNTIME

fn C.calloc(count usize, size usize) voidptr
fn C.free(memory voidptr)

pub const bench_frequency = u64(1000)

@[heap]
pub struct Bench {
pub mut:
	sim   Sim
	state voidptr
	ticks u64 = 1
	// What each look at the clock costs, in ticks: zero is a clock that stopped.
	step u64 = 1
	// The mailbox refuses to take a word, or fails when asked for one.
	send_fails    bool
	receive_fails bool
	// Words sent, and exchanges with the shared memory.
	sent     u64
	copies   u64
}

fn bench_send(context voidptr, word u64, endpoint u8) i32 {
	mut bench := unsafe { &Bench(context) }
	if bench.send_fails {
		return 0
	}
	bench.sent++
	return if bench.sim.send(word, endpoint) { i32(1) } else { i32(0) }
}

fn bench_receive(context voidptr, word &u64, endpoint &u8) i32 {
	mut bench := unsafe { &Bench(context) }
	if bench.receive_fails {
		return -1
	}
	got, value, from := bench.sim.receive()
	if !got {
		return 0
	}
	unsafe {
		*word = value
		*endpoint = from
	}
	return 1
}

fn bench_clock(context voidptr) u64 {
	mut bench := unsafe { &Bench(context) }
	now := bench.ticks
	bench.ticks += bench.step
	return now
}

fn bench_relax(_ voidptr) {
}

fn bench_shared(context voidptr, write i32, offset u32, buffer &u8, length u32) i32 {
	mut bench := unsafe { &Bench(context) }
	bench.copies++
	return if bench.sim.shared(write != 0, offset, buffer, length) { i32(1) } else { i32(0) }
}

// A bench whose SMC is a laptop, not yet started.
pub fn new_bench(fan bool, limit bool, old_order bool) &Bench {
	mut bench := &Bench{}
	bench.sim.laptop(fan, limit, old_order)
	bench.state = C.calloc(1, vinix_smc_state_size())
	return bench
}

// Start the client against it. With `memory`, the client is given the
// shared memory as the kernel gives it.
pub fn (mut bench Bench) boot(memory bool) i32 {
	result := vinix_smc_boot(bench.state, voidptr(bench), bench_send, bench_receive, bench_clock,
		bench_relax, bench_frequency, sim_sram_base, sim_sram_size)
	if result == 0 && memory {
		return vinix_smc_set_shmem(bench.state, bench_shared)
	}
	return result
}

// A started bench, or a failed test.
pub fn started_bench(fan bool, limit bool, old_order bool) &Bench {
	mut bench := new_bench(fan, limit, old_order)
	assert bench.boot(true) == 0
	return bench
}

// Let `milliseconds` pass.
pub fn (mut bench Bench) wait(milliseconds u64) {
	bench.ticks += milliseconds
}

pub fn (mut bench Bench) free() {
	unsafe { C.free(bench.state) }
	bench.state = unsafe { nil }
}
