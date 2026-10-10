// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A kernel with a made-up embedded controller, for testing the driver on a
// machine that has none: every emulator. Only in a kernel built with
// -d acpiec_selftest.
//
// In such a kernel the two ports are not read or written at all. The
// simulated controller of sim_d_acpiec_selftest.v stands behind the
// protocol's port functions instead, with the real clock, so that everything
// above the instruction that touches a port is the code a laptop runs:
// uACPI's region handler, the lock, the exchanges and their timeouts, the
// queries, the methods. What firmware says of the controller still comes
// from the machine's ACPI tables, which a test supplies.
//
// The controller starts out as a laptop on its charger, so that what the
// kernel reads at boot -- before any program can set anything -- is a
// battery:
//
//	0x00 state      2 (charging)        0x08 voltage, mV       11800
//	0x01 charger    1 (present)         0x0a last full, mWh    48000
//	0x02 lid        1 (open)            0x0c design, mWh       50000
//	0x03 battery    1 (present)         0x0e cycles            77
//	0x04 rate, mW   15000               0x12 design voltage    11400
//	0x06 left, mWh  40000
//
// Words are low byte first. What the bytes mean is the test table's business
// (tests/hardware-platform/hwhost/acpi_bench.v); this file only holds them.
//
// The test drives it through two files beside the driver's own:
//
//	/sys/bus/acpi/devices/PNP0C09:00/ec/selftest        (write)
//	    ram <address> <value>      set a byte of the controller's memory
//	    event <number>             queue an event: the event bit goes up
//	    raise                      call the driver's general purpose event
//	                               handler, as uACPI does when the event is
//	                               raised -- by this file, not by hardware
//	    later <ms> <number> [<address> <value>]
//	                               in <ms>, set the byte if given, queue the
//	                               event and raise: for what happens while
//	                               the test itself is frozen in a sleep
//	    latency <microseconds>     how long the controller takes over a byte
//	    fault none|silent|stuck-ibf|absent|stuck-sci
//	    phantom <count>            the event bit up for that many queries
//	                               with no event behind it
//	    endless <number>           every query names this event; 0 ends it
//	    stale <value>              leave a byte in the output buffer
//	    storm                      raise more often than a working line does
//	/sys/bus/acpi/devices/PNP0C09:00/ec/selftest_state  (read)
//	    what the controller was asked, how often the protocol was broken
//	    towards it, and its memory
//
// Numbers are decimal, or hexadecimal with 0x.
@[has_globals]
module acpiec

import devcore
import errno
import event
import event.eventstruct
import fs
import katomic
import klock
import lib
import sched

struct Later {
mut:
	used    bool
	due     u64
	number  u8
	set     bool
	address u8
	value   u8
}

const later_slots = 4

__global (
	acpiec_sim       Sim
	// The controller's state: exchanges come from several threads' turns at
	// the mutex, and the test's commands from yet another.
	acpiec_sim_lock  klock.Lock
	acpiec_sim_later [later_slots]Later
	acpiec_sim_wake  eventstruct.Event
)

fn sim_port_read(_ voidptr, command bool) u8 {
	acpiec_sim_lock.acquire()
	value := acpiec_sim.read(devcore.now_ns(), command)
	acpiec_sim_lock.release()
	return value
}

fn sim_port_write(_ voidptr, command bool, value u8) {
	acpiec_sim_lock.acquire()
	acpiec_sim.write(devcore.now_ns(), command, value)
	acpiec_sim_lock.release()
}

fn sim_word(address int, value u16) {
	acpiec_sim.ram[address] = u8(value)
	acpiec_sim.ram[address + 1] = u8(value >> 8)
}

// Put the simulated controller behind the protocol. Called before anything
// can ask the controller anything.
fn selftest_take_ports() {
	acpiec_sim.latency_ns = 20000
	acpiec_sim.ram[0x00] = 2
	acpiec_sim.ram[0x01] = 1
	acpiec_sim.ram[0x02] = 1
	acpiec_sim.ram[0x03] = 1
	sim_word(0x04, 15000)
	sim_word(0x06, 40000)
	sim_word(0x08, 11800)
	sim_word(0x0a, 48000)
	sim_word(0x0c, 50000)
	sim_word(0x0e, 77)
	sim_word(0x12, 11400)
	acpiec_controller.port.read = sim_port_read
	acpiec_controller.port.write = sim_port_write
}

// The first word of `text` and what follows it: views, not copies.
fn first_word(text string) (string, string) {
	mut start := 0
	for start < text.len && text[start] == ` ` {
		start++
	}
	mut end := start
	for end < text.len && text[end] != ` ` {
		end++
	}
	word := unsafe { tos(text.str + start, end - start) }
	rest := unsafe { tos(text.str + end, text.len - end) }
	return word, rest
}

// The value of a hexadecimal digit, or 16 for anything else.
fn hex_value(c u8) u64 {
	if c >= `0` && c <= `9` {
		return u64(c - `0`)
	}
	if c >= `a` && c <= `f` {
		return u64(c - `a`) + 10
	}
	if c >= `A` && c <= `F` {
		return u64(c - `A`) + 10
	}
	return 16
}

fn number_of(word string) ?u64 {
	if word.len == 0 || word.len > 18 {
		return none
	}
	mut value := u64(0)
	if word.len > 2 && word[0] == `0` && (word[1] == `x` || word[1] == `X`) {
		for i in 2 .. word.len {
			digit := hex_value(word[i])
			if digit > 15 {
				return none
			}
			value = value * 16 + digit
		}
		return value
	}
	for i in 0 .. word.len {
		c := word[i]
		if c < `0` || c > `9` {
			return none
		}
		value = value * 10 + u64(c - `0`)
	}
	return value
}

// Does what has come due, and sleeps until the next thing is.
fn selftest_thread() {
	for {
		generation := event.generation(mut acpiec_sim_wake)
		now := devcore.now_ns()
		mut next := u64(0)
		mut fired := false
		acpiec_sim_lock.acquire()
		for i in 0 .. later_slots {
			mut later := unsafe { &acpiec_sim_later[i] }
			if !later.used {
				continue
			}
			if later.due <= now {
				later.used = false
				if later.set {
					acpiec_sim.ram[later.address] = later.value
				}
				acpiec_sim.push_event(later.number)
				fired = true
			} else if next == 0 || later.due < next {
				next = later.due
			}
		}
		acpiec_sim_lock.release()
		if fired {
			// The self-test standing in for the chipset.
			gpe_raised()
			continue
		}
		if next == 0 {
			event.await_one_from_generation(mut acpiec_sim_wake, true, generation) or {}
			continue
		}
		devcore.wait_event(mut acpiec_sim_wake, generation, (next - now) / devcore.millisecond + 1)
	}
}

fn store_selftest(_ voidptr, data &u8, length u64) u64 {
	command, after := first_word(fs.sysfs_word(data, length))
	first, after_first := first_word(after)
	second, after_second := first_word(after_first)
	third, after_third := first_word(after_second)
	fourth, _ := first_word(after_third)
	a := number_of(first) or { u64(0) }
	b := number_of(second) or { u64(0) }
	if command == 'raise' {
		gpe_raised()
		return 0
	}
	if command == 'storm' {
		for _ in u32(0) .. storm_gpes + 2 {
			gpe_raised()
		}
		return 0
	}
	mut result := u64(0)
	acpiec_sim_lock.acquire()
	if command == 'ram' && first.len != 0 && second.len != 0 && a <= 0xff && b <= 0xff {
		acpiec_sim.ram[a] = u8(b)
	} else if command == 'event' && a != 0 && a <= 0xff {
		if !acpiec_sim.push_event(u8(a)) {
			result = u64(errno.enospc)
		}
	} else if command == 'later' && b != 0 && b <= 0xff {
		result = u64(errno.enospc)
		for i in 0 .. later_slots {
			mut later := unsafe { &acpiec_sim_later[i] }
			if later.used {
				continue
			}
			later.due = devcore.now_ns() + a * devcore.millisecond
			later.number = u8(b)
			later.set = third.len != 0 && fourth.len != 0
			later.address = u8(number_of(third) or { u64(0) })
			later.value = u8(number_of(fourth) or { u64(0) })
			later.used = true
			result = 0
			break
		}
	} else if command == 'latency' && first.len != 0 {
		acpiec_sim.latency_ns = a * devcore.microsecond
	} else if command == 'fault' {
		acpiec_sim.silent = first == 'silent'
		acpiec_sim.stuck_ibf = first == 'stuck-ibf'
		acpiec_sim.absent = first == 'absent'
		acpiec_sim.stuck_sci = first == 'stuck-sci'
		if first != 'none' && !acpiec_sim.silent && !acpiec_sim.stuck_ibf && !acpiec_sim.absent
			&& !acpiec_sim.stuck_sci {
			result = u64(errno.einval)
		}
		if first == 'none' {
			// A controller that comes back has an empty input buffer.
			acpiec_sim.ibf = false
		}
	} else if command == 'phantom' {
		acpiec_sim.phantom = u32(a)
	} else if command == 'endless' && a <= 0xff {
		acpiec_sim.endless = u8(a)
	} else if command == 'stale' && a <= 0xff {
		acpiec_sim.obf = true
		acpiec_sim.output = u8(a)
	} else {
		result = u64(errno.einval)
	}
	acpiec_sim_lock.release()
	if command == 'later' && result == 0 {
		event.trigger(mut acpiec_sim_wake, false)
	}
	return result
}

fn state_line(mut text lib.Text, name string, value u64) {
	text.add(name)
	text.add_byte(` `)
	text.add_unsigned(value)
	text.add_byte(`\n`)
}

fn show_selftest_state(_ voidptr, mut text lib.Text) {
	state_line(mut text, 'reads', acpiec_sim.reads)
	state_line(mut text, 'writes', acpiec_sim.writes)
	state_line(mut text, 'queries', acpiec_sim.queries)
	state_line(mut text, 'waiting', u64(acpiec_sim.event_count))
	state_line(mut text, 'violations', acpiec_sim.violations())
	state_line(mut text, 'unknown', acpiec_sim.unknown + acpiec_sim.strays)
	state_line(mut text, 'lock_failures', katomic.load(&acpiec_wiring.lock_failures))
	state_line(mut text, 'dropped', katomic.load(&acpiec_wiring.dropped))
	state_line(mut text, 'methods_failed', katomic.load(&acpiec_wiring.methods_failed))
	state_line(mut text, 'late_answers', acpiec_controller.late_answers)
	state_line(mut text, 'empty_queries', acpiec_controller.empty_queries)
	state_line(mut text, 'drain_limits', acpiec_controller.drain_limits)
	state_line(mut text, 'storms', acpiec_controller.storms)
	for row in 0 .. 16 {
		text.add('ram')
		for column in 0 .. 16 {
			text.add_byte(` `)
			text.add_radix(u64(acpiec_sim.ram[row * 16 + column]), 16, 2)
		}
		text.add_byte(`\n`)
	}
}

// Publish the two files and start the thread behind `later`. Called once
// the controller's own files are there.
fn selftest_start() {
	if acpiec_wiring.device == unsafe { nil } || acpiec_wiring.device.sysfs_path.len == 0 {
		return
	}
	control := status_path('selftest')
	fs.sysfs_attribute(control, 0o200, unsafe { nil }, store_selftest, unsafe { nil })
	unsafe { control.free() }
	state := status_path('selftest_state')
	fs.sysfs_attribute(state, 0o444, show_selftest_state, unsafe { nil }, unsafe { nil })
	unsafe { state.free() }
	sched.new_kernel_thread(voidptr(selftest_thread), unsafe { nil }, true)
	print('acpiec: self-test kernel: the controller is simulated, the ports are not touched\n')
}
