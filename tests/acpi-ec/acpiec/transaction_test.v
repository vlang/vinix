// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Exchanges with a controller that works, with one that is slow, and with
// each of the ways one goes wrong: what comes back, how long it took on the
// simulated clock, and when the controller is given up on.
module acpiec

fn test_a_byte_written_is_the_byte_read() {
	mut b, mut c := new_bench()
	assert c.region_write(0x10, 1, 0x5a) == .ok
	assert b.sim.ram[0x10] == 0x5a
	outcome, value := c.region_read(0x10, 1)
	assert outcome == .ok
	assert value == 0x5a
	assert c.transactions == 2
	assert c.completed == 2
	assert c.restarts == 0
	assert c.timeouts == 0
	assert c.stale_bytes == 0
	assert b.sim.reads == 1
	assert b.sim.writes == 1
	assert b.sim.violations() == 0
	assert b.unlocked == 0
	assert !b.locked
	// Three bytes went each way at 50 microseconds each.
	assert b.clock < 2000000
}

fn test_wider_accesses_are_bytes_lowest_first() {
	mut b, mut c := new_bench()
	assert c.region_write(0x20, 4, 0x11223344) == .ok
	assert b.sim.ram[0x20] == 0x44
	assert b.sim.ram[0x21] == 0x33
	assert b.sim.ram[0x22] == 0x22
	assert b.sim.ram[0x23] == 0x11
	b.sim.ram[0x24] = 0x55
	outcome, value := c.region_read(0x20, 8)
	assert outcome == .ok
	assert value == 0x0000005511223344
	word_outcome, word := c.region_read(0x21, 2)
	assert word_outcome == .ok
	assert word == 0x2233
	assert c.transactions == 4 + 8 + 2
	assert b.sim.violations() == 0
	assert b.unlocked == 0
}

fn test_the_last_byte_of_the_space_can_be_reached_and_nothing_past_it() {
	mut b, mut c := new_bench()
	b.sim.ram[0xff] = 0x77
	outcome, value := c.region_read(0xff, 1)
	assert outcome == .ok
	assert value == 0x77
	before := c.transactions
	over, _ := c.region_read(0xff, 2)
	assert over == .invalid
	past, _ := c.region_read(0x100, 1)
	assert past == .invalid
	none_wide, _ := c.region_read(0, 0)
	assert none_wide == .invalid
	too_wide, _ := c.region_read(0, 9)
	assert too_wide == .invalid
	assert c.region_write(0xfe, 4, 0) == .invalid
	assert c.transactions == before
	assert b.sim.ram[0xfe] == 0
}

fn test_a_slow_controller_is_waited_for() {
	mut b, mut c := new_bench()
	b.sim.latency_ns = 30000000
	b.sim.ram[7] = 0x99
	outcome, value := c.region_read(7, 1)
	assert outcome == .ok
	assert value == 0x99
	// Two bytes, 30 ms each.
	assert b.clock >= 60000000
	assert b.clock < 70000000
	assert c.restarts == 0
	assert b.sim.violations() == 0
	// Once it has not answered within a couple of milliseconds the status
	// register is looked at a thousand times a second, not ten thousand.
	assert b.longest_pause == sleep_pause_ns
	assert b.accesses < 200
}

fn test_an_answer_that_takes_longer_than_an_attempt_is_not_asked_for_twice() {
	mut b, mut c := new_bench()
	// Each byte takes 300 ms: the address is taken 600 ms in, after the
	// first attempt has run out.
	b.sim.latency_ns = 300000000
	b.sim.ram[0x31] = 0xc4
	outcome, value := c.region_read(0x31, 1)
	assert outcome == .ok
	assert value == 0xc4
	assert c.restarts == 1
	assert c.late_answers == 1
	assert c.timeouts == 0
	assert c.consecutive == 0
	// The command went out once, so one answer came and none is left over.
	assert b.command_bytes == 1
	assert b.sim.reads == 1
	assert !b.sim.obf
	assert b.sim.violations() == 0
	assert b.clock >= 600000000
	assert b.clock < 700000000
}

fn test_a_slow_query_keeps_its_event() {
	mut b, mut c := new_bench()
	b.sim.latency_ns = 700000000
	b.sim.push_event(0x20)
	b.sim.push_event(0x21)
	step, number := c.next_event(false)
	assert step == .event
	assert number == 0x20
	// The second event was not swallowed by a query sent twice.
	assert b.sim.event_count == 1
	assert b.sim.queries == 1
	assert c.restarts == 1
	b.sim.latency_ns = 50000
	again, second := c.next_event(false)
	assert again == .event
	assert second == 0x21
	assert c.stale_bytes == 0
	assert b.sim.violations() == 0
}

fn test_a_stale_byte_is_not_taken_for_the_answer() {
	mut b, mut c := new_bench()
	b.sim.obf = true
	b.sim.output = 0xee
	b.sim.ram[5] = 0x42
	outcome, value := c.region_read(5, 1)
	assert outcome == .ok
	assert value == 0x42
	assert c.stale_bytes == 1
	assert b.sim.violations() == 0
	// Nor does it stop a write, which reads nothing back.
	b.sim.obf = true
	b.sim.output = 0xee
	assert c.region_write(6, 1, 0x13) == .ok
	assert b.sim.ram[6] == 0x13
	assert c.stale_bytes == 2
}

fn test_an_input_buffer_that_never_empties_times_out() {
	mut b, mut c := new_bench()
	b.sim.ibf = true
	b.sim.stuck_ibf = true
	outcome, value := c.region_read(1, 1)
	assert outcome == .timeout
	assert value == 0
	// Nothing was written into the full buffer, on any attempt.
	assert b.command_bytes == 0
	assert b.sim.overwrites == 0
	assert c.restarts == attempts - 1
	assert c.timeouts == 1
	// All five attempts were waited out, and no more than that.
	assert b.clock >= u64(attempts) * attempt_ns
	assert b.clock <= exchange_limit()
	assert !b.locked
	assert b.unlocked == 0
}

fn test_a_controller_that_takes_the_command_and_then_nothing() {
	mut b, mut c := new_bench()
	b.sim.stuck_ibf = true
	outcome, _ := c.region_read(1, 1)
	assert outcome == .timeout
	// The command went in while the buffer was still empty; the address
	// never could, and the command was not written on top of itself.
	assert b.command_bytes == 1
	assert b.sim.overwrites == 0
	assert b.clock >= u64(attempts) * attempt_ns
	assert b.clock <= exchange_limit()
}

fn test_a_controller_that_never_answers_times_out() {
	mut b, mut c := new_bench()
	b.sim.silent = true
	outcome, value := c.region_read(9, 1)
	assert outcome == .timeout
	assert value == 0
	assert c.restarts == attempts - 1
	// Asked, waited, asked again: three times in five attempts.
	assert b.command_bytes == 3
	assert b.sim.reads == 3
	assert b.sim.violations() == 0
	assert b.clock >= u64(attempts) * attempt_ns
	assert b.clock <= exchange_limit()
}

fn test_a_write_the_controller_never_takes_times_out() {
	mut b, mut c := new_bench()
	assert c.region_write(1, 1, 1) == .ok
	b.sim.stuck_ibf = true
	started := b.clock
	assert c.region_write(2, 1, 2) == .timeout
	assert b.sim.ram[2] == 0
	assert b.clock - started >= u64(attempts) * attempt_ns
	assert b.clock - started <= exchange_limit()
}

fn test_a_controller_that_never_answered_is_given_up_on_at_once() {
	mut b, mut c := new_bench()
	b.sim.silent = true
	first, _ := c.region_read(0, 1)
	assert first == .timeout
	assert c.failed
	assert c.failure == .timeout
	// From here on nobody waits, and the registers are left alone.
	clock := b.clock
	accesses := b.accesses
	second, _ := c.region_read(0, 1)
	assert second == .failed
	assert c.region_write(0, 1, 1) == .failed
	step, _ := c.next_event(false)
	assert step == .error
	assert !c.event_waiting()
	assert b.clock == clock
	assert b.accesses == accesses
	assert c.refused == 3
	assert c.transactions == 1
}

fn test_a_controller_that_used_to_answer_gets_three_failures() {
	mut b, mut c := new_bench()
	b.sim.ram[3] = 0x33
	good, _ := c.region_read(3, 1)
	assert good == .ok
	b.sim.silent = true
	one, _ := c.region_read(3, 1)
	assert one == .timeout
	assert !c.failed
	two, _ := c.region_read(3, 1)
	assert two == .timeout
	assert !c.failed
	// One that works in between starts the count again.
	b.sim.silent = false
	back, value := c.region_read(3, 1)
	assert back == .ok
	assert value == 0x33
	assert c.consecutive == 0
	b.sim.silent = true
	for round in 0 .. 3 {
		assert !c.failed, 'given up on after ${round} failures'
		outcome, _ := c.region_read(3, 1)
		assert outcome == .timeout
	}
	assert c.failed
	clock := b.clock
	after, _ := c.region_read(3, 1)
	assert after == .failed
	assert b.clock == clock
	assert c.timeouts == 5
}

fn test_a_wide_access_stops_at_the_byte_that_failed() {
	mut b, mut c := new_bench()
	assert c.region_write(0, 1, 0) == .ok
	b.sim.silent = true
	started := b.clock
	outcome, value := c.region_read(0x40, 4)
	assert outcome == .timeout
	assert value == 0
	// One byte's budget, not four.
	assert b.clock - started <= exchange_limit()
	assert c.timeouts == 1
}

fn test_ports_nothing_answers_at_fail_quickly() {
	mut b, mut c := new_bench()
	b.sim.absent = true
	outcome, value := c.region_read(0, 1)
	assert outcome == .stuck_output
	assert value == 0
	assert c.failed
	assert c.failure == .stuck_output
	assert c.stale_bytes == u64(max_stale_bytes)
	assert c.stuck_outputs == 1
	assert c.restarts == 0
	// Nothing was written to whatever is not there.
	assert b.command_bytes == 0
	// And it took a millisecond, not the budget of an exchange.
	assert b.clock < 2000000
	again, _ := c.region_read(0, 1)
	assert again == .failed
}

fn test_a_given_up_controller_can_be_tried_again() {
	mut b, mut c := new_bench()
	b.sim.absent = true
	c.region_read(0, 1)
	assert c.failed
	// Still not there: one try, and it is given up on again.
	still, _ := c.probe()
	assert still == .stuck_output
	assert c.failed
	// Now it is.
	b.sim.absent = false
	b.sim.ram[0] = 0x21
	found, number := c.probe()
	assert found == .ok
	assert number == 0
	assert !c.failed
	assert c.failure == .ok
	outcome, value := c.region_read(0, 1)
	assert outcome == .ok
	assert value == 0x21
	assert !b.locked
	assert b.unlocked == 0
}

fn test_a_controller_that_used_to_answer_gets_one_more_try() {
	mut b, mut c := new_bench()
	c.region_read(0, 1)
	b.sim.silent = true
	for _ in 0 .. 3 {
		c.region_read(0, 1)
	}
	assert c.failed
	timeouts := c.timeouts
	started := b.clock
	outcome, _ := c.probe()
	assert outcome == .timeout
	assert c.failed
	assert c.failure == .timeout
	assert c.timeouts == timeouts + 1
	assert b.clock - started <= exchange_limit()
	// Answering again, one try is enough, and the count starts afresh.
	b.sim.silent = false
	again, _ := c.probe()
	assert again == .ok
	assert !c.failed
	assert c.consecutive == 0
}

fn test_nobody_waits_behind_a_try_at_a_given_up_controller() {
	mut b, mut c := new_bench()
	c.region_read(0, 1)
	b.sim.silent = true
	for _ in 0 .. 3 {
		c.region_read(0, 1)
	}
	assert c.failed
	// Somebody asks for a byte every time the try pauses.
	b.intrude = true
	refused := c.refused
	outcome, _ := c.probe()
	b.intrude = false
	assert outcome == .timeout
	assert b.intruder_told.len > 100
	for told in b.intruder_told {
		assert told == .failed
	}
	// They were turned away without touching a register or the lock.
	assert b.intruder_touched == 0
	assert c.refused == refused + u64(b.intruder_told.len)
	assert b.unlocked == 0
}

fn test_a_probe_hands_back_the_event_it_took() {
	mut b, mut c := new_bench()
	b.sim.push_event(0x44)
	outcome, number := c.probe()
	assert outcome == .ok
	assert number == 0x44
	assert c.queries == 1
}

fn test_a_lock_that_cannot_be_taken_is_reported_and_nothing_is_touched() {
	mut b, mut c := new_bench()
	b.refuse = true
	outcome, _ := c.region_read(0, 1)
	assert outcome == .busy
	assert c.region_write(0, 1, 1) == .busy
	step, _ := c.next_event(false)
	assert step == .error
	assert !c.event_waiting()
	assert b.accesses == 0
	assert c.transactions == 0
	assert !c.failed
}

fn test_no_exchange_outlasts_its_budget() {
	// Whatever is wrong with the controller, and whichever byte it stops at.
	for fault in 0 .. 4 {
		for latency in [u64(0), 50000, 40000000, 260000000, 2000000000] {
			mut b, mut c := new_bench()
			b.sim.latency_ns = latency
			match fault {
				0 { b.sim.stuck_ibf = true }
				1 { b.sim.silent = true }
				2 {
					b.sim.ibf = true
					b.sim.stuck_ibf = true
				}
				else {}
			}
			started := b.clock
			c.region_read(0x12, 1)
			assert b.clock - started <= exchange_limit(), 'a read took ${b.clock - started} ns with fault ${fault} at latency ${latency}'
			mut b2, mut c2 := new_bench()
			b2.sim.latency_ns = latency
			if fault == 0 {
				b2.sim.stuck_ibf = true
			}
			c2.region_write(0x12, 1, 0x34)
			assert b2.clock <= exchange_limit(), 'a write took ${b2.clock} ns with fault ${fault} at latency ${latency}'
			assert b.unlocked == 0
			assert !b.locked
			assert b.sim.overwrites == 0
		}
	}
}

fn test_outcomes_have_names() {
	assert outcome_name(.timeout) == 'no answer in time'
	assert outcome_name(.stuck_output) == 'output buffer would not empty'
	assert outcome_name(.ok) == 'ok'
}
