// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// An embedded controller that is not there: 256 bytes of memory, the three
// commands, a queue of events, and the ways a real one goes wrong.
//
// No emulator has an embedded controller, so nothing in protocol.v could
// otherwise run anywhere but on a laptop. This stands behind the same two
// registers. It is built into the kernel only with -d acpiec_selftest, where
// it takes the place of the ports (selftest_d_acpiec_selftest.v), and into
// the tests of tests/acpi-ec, which give it a clock of their own.
//
// It keeps the protocol's own rules: a byte written is taken `latency_ns`
// later, and the input buffer is full until then; an answer stays in the
// output buffer until it is read; the event bit is up while events wait.
// What the host does against the rules is counted rather than tolerated in
// silence, so that a test can ask for none of it.
//
// How it misbehaves is a matter of setting fields:
//
//	absent      nothing answers at the ports: every read is all ones
//	stuck_ibf   it never takes a byte
//	silent      it takes bytes and never answers
//	stuck_sci   its event bit stays up whatever is asked
//	phantom     its event bit is up for that many queries with no event
//	            behind it
//	endless     every query names this event, for ever
//	obf, output a byte left in the output buffer, set directly
//
// Like protocol.v, this imports nothing.
module acpiec

pub const sim_event_slots = 32

// The burst commands, which the simulated controller knows although the
// driver does not use them, and what it answers the first with.
const sim_burst_enable = u8(0x82)
const sim_burst_disable = u8(0x83)
const sim_burst_ack = u8(0x90)

enum SimState {
	idle
	// RD_EC was given: the next byte is the address.
	read_address
	// WR_EC was given: the next byte is the address, the one after the value.
	write_address
	write_value
}

pub struct Sim {
pub mut:
	ram [256]u8
	// The registers as the host sees them.
	obf    bool
	ibf    bool
	output u8
	// The byte in the input buffer, and when it will be taken.
	input            u8
	input_is_command bool
	take_at          u64
	burst            bool
	state            SimState
	address          u8
	// Events waiting to be asked about, oldest first.
	events      [sim_event_slots]u8
	event_count u32

	latency_ns u64
	absent     bool
	stuck_ibf  bool
	silent     bool
	stuck_sci  bool
	phantom    u32
	endless    u8

	// What it was asked.
	reads   u64
	writes  u64
	queries u64
	// Commands it does not know, and data bytes that came with no command.
	unknown u64
	strays  u64
	// What the host did against the rules: wrote into a full input buffer,
	// read an empty output buffer, left an answer to be overwritten.
	overwrites  u64
	empty_reads u64
	overruns    u64
}

// Whether the controller wants to be asked.
pub fn (s &Sim) wants_query() bool {
	return s.stuck_sci || s.endless != 0 || s.phantom != 0 || s.event_count != 0
}

// Queue an event. False when the queue is full.
pub fn (mut s Sim) push_event(number u8) bool {
	if s.event_count >= sim_event_slots {
		return false
	}
	s.events[s.event_count] = number
	s.event_count++
	return true
}

fn (mut s Sim) pop_event() u8 {
	if s.event_count == 0 {
		return 0
	}
	number := s.events[0]
	for i in u32(0) .. s.event_count - 1 {
		s.events[i] = s.events[i + 1]
	}
	s.event_count--
	return number
}

fn (mut s Sim) answer(value u8) {
	if s.silent {
		return
	}
	if s.obf {
		s.overruns++
	}
	s.obf = true
	s.output = value
}

// Do what the byte in the input buffer asks.
fn (mut s Sim) take() {
	value := s.input
	if s.input_is_command {
		match value {
			command_read {
				s.state = .read_address
			}
			command_write {
				s.state = .write_address
			}
			command_query {
				s.state = .idle
				s.queries++
				if s.endless != 0 {
					s.answer(s.endless)
				} else if s.phantom != 0 {
					s.phantom--
					s.answer(0)
				} else {
					s.answer(s.pop_event())
				}
			}
			sim_burst_enable {
				s.state = .idle
				s.burst = true
				s.answer(sim_burst_ack)
			}
			sim_burst_disable {
				s.state = .idle
				s.burst = false
			}
			else {
				s.state = .idle
				s.unknown++
			}
		}
		return
	}
	match s.state {
		.read_address {
			s.state = .idle
			s.reads++
			s.answer(s.ram[value])
		}
		.write_address {
			s.address = value
			s.state = .write_value
		}
		.write_value {
			s.state = .idle
			s.writes++
			s.ram[s.address] = value
		}
		.idle {
			s.strays++
		}
	}
}

// Let the controller do what has come due by `now`.
pub fn (mut s Sim) tick(now u64) {
	if s.ibf && !s.stuck_ibf && now >= s.take_at {
		s.ibf = false
		s.take()
	}
}

// The host reads the data register or, with `command`, the status register.
pub fn (mut s Sim) read(now u64, command bool) u8 {
	if s.absent {
		return 0xff
	}
	s.tick(now)
	if command {
		mut status := u8(0)
		if s.obf {
			status |= status_obf
		}
		if s.ibf {
			status |= status_ibf
			if s.input_is_command {
				status |= status_cmd
			}
		}
		if s.burst {
			status |= status_burst
		}
		if s.wants_query() {
			status |= status_sci_evt
		}
		return status
	}
	if !s.obf {
		s.empty_reads++
	}
	s.obf = false
	return s.output
}

// The host writes the data register or the command register.
pub fn (mut s Sim) write(now u64, command bool, value u8) {
	if s.absent {
		return
	}
	s.tick(now)
	if s.ibf {
		s.overwrites++
	}
	s.ibf = true
	s.input = value
	s.input_is_command = command
	s.take_at = now + s.latency_ns
}

// How often the host broke the protocol.
pub fn (s &Sim) violations() u64 {
	return s.overwrites + s.empty_reads + s.overruns
}
