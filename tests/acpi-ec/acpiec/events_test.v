// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Events: the queries that take them out of the controller, where that stops
// when the controller does not behave, and the hints and counts that decide
// whether anybody asks at all.
module acpiec

fn test_a_controller_with_nothing_to_report_is_not_asked() {
	mut b, mut c := new_bench()
	assert !c.event_waiting()
	report := c.drain(false, drain_limit, bench_dispatch, voidptr(b))
	assert report.events == 0
	assert !report.limited
	assert !report.error
	assert b.sim.queries == 0
	assert b.events.len == 0
	assert b.unlocked == 0
}

fn test_events_come_out_in_order_until_there_are_none() {
	mut b, mut c := new_bench()
	b.sim.push_event(0x20)
	b.sim.push_event(0x21)
	b.sim.push_event(0x22)
	assert c.event_waiting()
	report := c.drain(false, drain_limit, bench_dispatch, voidptr(b))
	assert report.events == 3
	assert !report.limited
	assert b.events == [u8(0x20), 0x21, 0x22]
	// The event bit going down ends it: no fourth query to hear "none".
	assert b.sim.queries == 3
	assert c.queries == 3
	assert c.empty_queries == 0
	assert !c.event_waiting()
	assert !c.take_hint()
	assert b.sim.violations() == 0
	assert b.unlocked == 0
}

fn test_a_method_runs_with_nothing_held_and_may_use_the_controller() {
	mut b, mut c := new_bench()
	b.sim.ram[0x02] = 0x01
	b.sim.push_event(0x22)
	b.sim.push_event(0x23)
	b.read_back = true
	b.read_address = 0x02
	report := c.drain(false, drain_limit, bench_dispatch, voidptr(b))
	assert report.events == 2
	assert b.dispatched_locked == 0
	assert b.read_values == [u64(1), 1]
	assert !b.locked
	assert b.unlocked == 0
}

fn test_a_query_that_names_nothing_ends_the_drain() {
	mut b, mut c := new_bench()
	b.sim.phantom = 1
	assert c.event_waiting()
	report := c.drain(false, drain_limit, bench_dispatch, voidptr(b))
	assert report.events == 0
	assert !report.limited
	assert b.events.len == 0
	assert b.sim.queries == 1
	assert c.empty_queries == 1
	// The bit went down with the query, so nothing is held against it.
	assert !c.sci_stuck
}

fn test_an_event_bit_stuck_up_is_asked_about_once() {
	mut b, mut c := new_bench()
	b.sim.stuck_sci = true
	report := c.drain(false, drain_limit, bench_dispatch, voidptr(b))
	assert report.events == 0
	assert b.sim.queries == 1
	assert c.sci_stuck
	// Nobody is sent back to ask: not by looking, and not by the exchanges
	// that see the bit up as they go.
	assert !c.event_waiting()
	for _ in 0 .. 10 {
		c.region_read(0, 1)
		assert !c.take_hint()
	}
	assert b.sim.queries == 1
	// Its line being raised again does get it asked, once more.
	c.drain(false, drain_limit, bench_dispatch, voidptr(b))
	assert b.sim.queries == 2
	assert b.events.len == 0
	// Once the bit has been seen down, the next event counts again.
	b.sim.stuck_sci = false
	c.region_read(0, 1)
	assert !c.sci_stuck
	b.sim.push_event(0x30)
	c.region_read(0, 1)
	assert c.take_hint()
	assert c.event_waiting()
}

fn test_a_controller_that_never_runs_out_is_left_at_the_limit() {
	mut b, mut c := new_bench()
	b.sim.endless = 0x66
	report := c.drain(false, drain_limit, bench_dispatch, voidptr(b))
	assert report.events == drain_limit
	assert report.limited
	assert b.events.len == int(drain_limit)
	assert b.sim.queries == u64(drain_limit)
	assert c.drain_limits == 1
	// Nothing brings the drain back by itself.
	assert !c.event_waiting()
	c.region_read(0, 1)
	assert !c.take_hint()
	// Thirty-two exchanges with a controller that works: milliseconds.
	assert b.clock < 20000000
	// Raised again, it gets the same and no more.
	second := c.drain(false, drain_limit, bench_dispatch, voidptr(b))
	assert second.events == drain_limit
	assert b.sim.queries == u64(2 * drain_limit)
}

fn test_a_drain_that_ends_at_the_limit_exactly_is_not_held_against_the_controller() {
	mut b, mut c := new_bench()
	for i in 0 .. 4 {
		b.sim.push_event(u8(0x40 + i))
	}
	report := c.drain(false, 4, bench_dispatch, voidptr(b))
	assert report.events == 4
	assert !report.limited
	assert !c.sci_stuck
	assert c.drain_limits == 0
}

fn test_clearing_asks_whatever_the_event_bit_says() {
	mut b, mut c := new_bench()
	// Nothing waiting: one query, to hear so.
	empty := c.drain(true, clear_limit, bench_dispatch, voidptr(b))
	assert empty.events == 0
	assert b.sim.queries == 1
	b.sim.push_event(0x51)
	b.sim.push_event(0x52)
	report := c.drain(true, clear_limit, bench_dispatch, voidptr(b))
	assert report.events == 2
	assert b.events == [u8(0x51), 0x52]
	// And a third to hear that those were all.
	assert b.sim.queries == 4
	// A controller that never says "none" is cleared of a hundred and left.
	b.sim.endless = 0x53
	endless := c.drain(true, clear_limit, bench_dispatch, voidptr(b))
	assert endless.events == clear_limit
	assert endless.limited
}

fn test_a_controller_that_dies_in_the_middle_ends_the_drain() {
	mut b, mut c := new_bench()
	for i in 0 .. 5 {
		b.sim.push_event(u8(0x60 + i))
	}
	b.silence_after = 2
	started := b.clock
	report := c.drain(false, drain_limit, bench_dispatch, voidptr(b))
	assert report.events == 2
	assert report.error
	assert b.events == [u8(0x60), 0x61]
	// One query's budget was spent finding out.
	assert b.clock - started <= exchange_limit() + 10000000
	assert !b.locked
}

fn test_a_given_up_controller_is_not_drained() {
	mut b, mut c := new_bench()
	b.sim.absent = true
	c.region_read(0, 1)
	assert c.failed
	accesses := b.accesses
	report := c.drain(false, drain_limit, bench_dispatch, voidptr(b))
	assert report.error
	assert report.events == 0
	assert b.accesses == accesses
}

fn test_an_exchange_that_sees_the_event_bit_says_so_once() {
	mut b, mut c := new_bench()
	c.region_read(0, 1)
	assert !c.take_hint()
	b.sim.push_event(0x70)
	c.region_read(0, 1)
	assert c.take_hint()
	assert !c.take_hint()
	// Draining leaves no hint behind for an event that is gone.
	c.region_read(0, 1)
	report := c.drain(false, drain_limit, bench_dispatch, voidptr(b))
	assert report.events == 1
	assert !c.take_hint()
}

fn test_a_stuck_line_is_noticed_and_a_busy_one_is_not() {
	mut b, mut c := new_bench()
	// Sixty-four events in a second that brought nothing are allowed.
	for i in 0 .. int(storm_gpes) {
		assert c.note_gpe(u64(i) * 1000000), 'event ${i} was taken for a storm'
	}
	// The next one is not.
	assert !c.note_gpe(u64(storm_gpes) * 1000000)
	assert c.storms == 1
	assert c.gpes == u64(storm_gpes) + 1
	// A line whose events each bring something out is never stuck.
	mut b2, mut c2 := new_bench()
	for i in 0 .. 1000 {
		assert c2.note_gpe(u64(i) * 1000000)
		c2.calm()
	}
	assert c2.storms == 0
	// Nor is one that brings nothing but takes its time about it.
	mut b3, mut c3 := new_bench()
	for i in 0 .. 1000 {
		assert c3.note_gpe(u64(i) * 20000000)
	}
	assert c3.storms == 0
	assert b.accesses + b2.accesses + b3.accesses == 0
}

fn test_event_methods_are_named_in_capital_hex() {
	assert query_method(0x20)[..4].bytestr() == '_Q20'
	assert query_method(0x0a)[..4].bytestr() == '_Q0A'
	assert query_method(0xff)[..4].bytestr() == '_QFF'
	assert query_method(0x01)[..4].bytestr() == '_Q01'
	assert query_method(0xff)[4] == 0
}
