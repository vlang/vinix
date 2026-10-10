// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the tests put the protocol on: the simulated controller, a clock that
// moves only when the protocol reads a register or waits, and a lock that
// only remembers whether it is held -- so that a test can ask how much time
// an exchange took, and whether anything touched the registers without it.
module acpiec

// What reading or writing a register costs on the clock.
const access_ns = u64(1000)

@[heap]
struct Bench {
mut:
	sim   Sim
	clock u64
	// The lock: held, refused on request, and what was done without it.
	locked   bool
	refuse   bool
	unlocked u64
	// Register accesses, and the longest single wait asked for.
	accesses      u64
	command_bytes u64
	longest_pause u64
	// What dispatch was handed, and whether the lock was held when it was.
	events            []u8
	dispatched_locked u64
	// What dispatch does besides: read this address through the protocol,
	// as a method of firmware's would.
	controller   &Controller = unsafe { nil }
	read_back    bool
	read_address u64
	read_values  []u64
	// Stop answering after this many events have been dispatched.
	silence_after int = -1
	// While the protocol waits, another caller asks for a byte: what it was
	// told each time, and how many register accesses its asking cost.
	intrude          bool
	intruding        bool
	intruder_told    []Outcome
	intruder_touched u64
}

fn bench_read(context voidptr, command bool) u8 {
	mut b := unsafe { &Bench(context) }
	if !b.locked {
		b.unlocked++
	}
	b.accesses++
	b.clock += access_ns
	return b.sim.read(b.clock, command)
}

fn bench_write(context voidptr, command bool, value u8) {
	mut b := unsafe { &Bench(context) }
	if !b.locked {
		b.unlocked++
	}
	b.accesses++
	if command {
		b.command_bytes++
	}
	b.clock += access_ns
	b.sim.write(b.clock, command, value)
}

fn bench_now(context voidptr) u64 {
	b := unsafe { &Bench(context) }
	return b.clock
}

fn bench_pause(context voidptr, ns u64) {
	mut b := unsafe { &Bench(context) }
	if ns > b.longest_pause {
		b.longest_pause = ns
	}
	b.clock += ns
	if b.intrude && !b.intruding {
		b.intruding = true
		accesses := b.accesses
		mut c := b.controller
		outcome, _ := c.region_read(0, 1)
		b.intruder_told << outcome
		b.intruder_touched += b.accesses - accesses
		b.intruding = false
	}
}

fn bench_enter(context voidptr) bool {
	mut b := unsafe { &Bench(context) }
	if b.refuse {
		return false
	}
	assert !b.locked, 'the lock was taken twice'
	b.locked = true
	return true
}

fn bench_leave(context voidptr) {
	mut b := unsafe { &Bench(context) }
	assert b.locked, 'the lock was given back without being held'
	b.locked = false
}

fn bench_dispatch(context voidptr, number u8) {
	mut b := unsafe { &Bench(context) }
	if b.locked {
		b.dispatched_locked++
	}
	b.events << number
	if b.read_back {
		mut c := b.controller
		_, value := c.region_read(b.read_address, 1)
		b.read_values << value
	}
	if b.silence_after >= 0 && b.events.len >= b.silence_after {
		b.sim.silent = true
	}
}

// A controller that works, answering each byte 50 microseconds after it is
// written, and the protocol's side of it.
fn new_bench() (&Bench, &Controller) {
	mut b := &Bench{}
	b.sim.latency_ns = 50000
	mut c := &Controller{
		port: Port{
			context: voidptr(b)
			read:    bench_read
			write:   bench_write
			now:     bench_now
			pause:   bench_pause
			enter:   bench_enter
			leave:   bench_leave
		}
	}
	b.controller = c
	return b, c
}

// The time one exchange may take at the very most: every attempt run to its
// end, each overrunning by the longest pause and a register read.
fn exchange_limit() u64 {
	return u64(attempts) * (attempt_ns + sleep_pause_ns + 4 * access_ns)
}
