// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The ACPI embedded controller's protocol, kept apart from the machine it is
// spoken on.
//
// The controller is a microcontroller of the laptop's own: it reads the
// battery, watches the lid, the charger and the hotkeys, and runs the fans.
// The host reaches it through two registers. One is data. The other is the
// command register when written and the status register when read:
//
//	OBF      the controller has put a byte in the data register
//	IBF      the byte the host wrote has not been taken yet
//	SCI_EVT  the controller has something to report, and wants to be asked
//
// Everything is a short exchange of bytes (ACPI 6.5, 12.3): a command, up to
// two bytes after it, at most one byte back, with the host waiting for IBF
// to clear before each byte it writes and for OBF before the one it reads.
//
//	RD_EC 0x80   address          -> the byte at it
//	WR_EC 0x81   address, value
//	QR_EC 0x84                    -> the number of an event, or 0 for none
//
// The burst commands (BE_EC 0x82, BD_EC 0x83) are not used. They keep the
// controller from doing anything else between the bytes of one access;
// Linux asks for that only around accesses wider than a byte, the
// interpreter here asks for an embedded controller field a byte at a time,
// and a controller that mishandles a command it rarely sees is a larger risk
// than what the mode buys.
//
// What this file adds to the exchange is what a controller that is slow,
// confused or not there needs:
//
//   - every wait ends, by the clock: an exchange gets `attempts` attempts of
//     attempt_ns each, the budget Linux's driver gives it (drivers/acpi/ec.c,
//     whose handling of events this follows too). Linux writes the command
//     again at every attempt. Here an attempt that wrote everything and ran
//     out of time waiting is followed by one that only waits, and the
//     command is written again after that: a controller asked twice answers
//     twice, and a query asked twice loses the event its second answer
//     named;
//   - a byte found in the output buffer before anything was asked is taken
//     out, so that it is not read as the answer;
//   - an output buffer that will not empty fails the exchange at once: no
//     answer could be told from what is stuck there;
//   - a controller that has never answered is given up on after its first
//     failed exchange, and one that has after fail_after in a row. From then
//     on every caller is told so immediately, instead of each waiting out
//     the budget for itself;
//   - events are taken out one query at a time until the controller says it
//     has none, never more than a limit in one go, and an event bit that
//     stays up when the controller has nothing behind it is not asked about
//     again until it has been seen down.
//
// A Controller is plain data and the functions here are plain arithmetic on
// it and on a Port, the six functions that stand for the hardware: the tests
// in tests/acpi-ec run them against a simulated controller and a clock that
// moves only when told to. Nothing in this file may import the kernel.
module acpiec

pub const command_read = u8(0x80)
pub const command_write = u8(0x81)
pub const command_query = u8(0x84)

pub const status_obf = u8(0x01)
pub const status_ibf = u8(0x02)
// The byte in the input buffer was written to the command register.
pub const status_cmd = u8(0x08)
pub const status_burst = u8(0x10)
pub const status_sci_evt = u8(0x20)
pub const status_smi_evt = u8(0x40)

// How long one attempt at an exchange may take, and how many there are.
pub const attempt_ns = u64(500000000)
pub const attempts = u32(5)
// A wait looks at the status register this often to begin with, without
// giving up the CPU: a controller that works answers in well under a
// millisecond.
pub const spin_pause_ns = u64(100000)
pub const spin_looks = u32(20)
// And this often once it has not.
pub const sleep_pause_ns = u64(1000000)
// Bytes taken out of the output buffer before giving up on emptying it.
pub const max_stale_bytes = u32(8)
// Events taken in one go: by the event thread, and when everything the
// controller holds is being cleared out.
pub const drain_limit = u32(32)
pub const clear_limit = u32(100)
// Exchanges that fail in a row before a controller that used to answer is
// given up on.
pub const fail_after = u32(3)
// General purpose events inside one window, none of which brought an event
// out of the controller, before its line is taken for stuck.
pub const storm_gpes = u32(64)
pub const storm_window_ns = u64(1000000000)

// The hardware, and the two things the protocol needs besides it.
pub struct Port {
pub mut:
	context voidptr
	// Read the data register or, with `command`, the status register.
	read fn (context voidptr, command bool) u8 = unsafe { nil }
	// Write the data register or the command register.
	write fn (context voidptr, command bool, value u8) = unsafe { nil }
	// Nanoseconds, from a clock that only goes forward.
	now fn (context voidptr) u64 = unsafe { nil }
	// Let about `ns` pass.
	pause fn (context voidptr, ns u64) = unsafe { nil }
	// Take, and give back, whatever keeps two exchanges apart. Taking it
	// may be refused. Nil when nothing does.
	enter fn (context voidptr) bool = unsafe { nil }
	leave fn (context voidptr) = unsafe { nil }
}

pub enum Outcome {
	ok
	// The controller has been given up on; nothing was tried.
	failed
	// It did not take a byte, or did not answer, in the time allowed.
	timeout
	// Its output buffer could not be emptied.
	stuck_output
	// Not something a controller can be asked.
	invalid
	// What keeps exchanges apart could not be taken.
	busy
}

pub fn outcome_name(outcome Outcome) string {
	return match outcome {
		.ok { 'ok' }
		.failed { 'given up on' }
		.timeout { 'no answer in time' }
		.stuck_output { 'output buffer would not empty' }
		.invalid { 'invalid request' }
		.busy { 'lock not available' }
	}
}

pub struct Controller {
pub mut:
	port Port
	// Given up on, and what the exchange that settled it died of.
	failed  bool
	failure Outcome
	// Exchanges that have failed since the last one that worked.
	consecutive u32
	// Every byte of the exchange in hand has been written, and an attempt
	// has since been spent only waiting for it to finish.
	sent   bool
	waited bool
	// The status register as it was last read.
	last_status u8
	// An exchange ended with the event bit up: somebody should ask.
	sci_seen bool
	// The event bit is up and asking about it gets nothing, or does not get
	// to the end of it.
	sci_stuck bool

	transactions  u64
	completed     u64
	restarts      u64
	timeouts      u64
	stuck_outputs u64
	stale_bytes   u64
	late_answers  u64
	// Callers turned away because the controller was given up on.
	refused u64
	// Queries that named an event, and those that named none.
	queries       u64
	empty_queries u64
	// Drains that stopped at their limit.
	drain_limits u64

	gpes         u64
	idle_gpes    u32
	storm_window u64
	storms       u64
}

fn (mut c Controller) status() u8 {
	c.last_status = c.port.read(c.port.context, true)
	return c.last_status
}

// Look at the status register until its bits in `mask` read `want`, or the
// attempt that began at `started` has had its time. The register is always
// read once more after a pause, so a caller that was itself held up past the
// deadline does not report a timeout for something that happened.
fn (mut c Controller) wait(mask u8, want u8, started u64) bool {
	mut looks := u32(0)
	for {
		if c.status() & mask == want {
			return true
		}
		if c.port.now(c.port.context) - started >= attempt_ns {
			return false
		}
		looks++
		c.port.pause(c.port.context, if looks <= spin_looks { spin_pause_ns } else { sleep_pause_ns })
	}
	return false
}

// Wait for what ends an exchange whose bytes are all written: the answer,
// or for one without an answer the input buffer emptying, which is the
// controller having the last byte.
fn (mut c Controller) finish(answers bool, started u64) (Outcome, u8) {
	if answers {
		if !c.wait(status_obf, status_obf, started) {
			return Outcome.timeout, u8(0)
		}
		value := c.port.read(c.port.context, false)
		return Outcome.ok, value
	}
	if !c.wait(status_ibf, 0, started) {
		return Outcome.timeout, u8(0)
	}
	return Outcome.ok, u8(0)
}

// One attempt at an exchange: `command`, then `wlen` of the bytes `w0` and
// `w1`, then one byte back if it `answers`.
fn (mut c Controller) attempt(command u8, wlen u8, w0 u8, w1 u8, answers bool) (Outcome, u8) {
	started := c.port.now(c.port.context)
	if c.sent && !c.waited {
		// The attempt before wrote everything and ran out of time waiting.
		// A controller that slow gets this attempt to finish in before it
		// is asked again: asked twice it answers twice, and the second
		// answer would lie in the output buffer for the next exchange.
		c.waited = true
		outcome, value := c.finish(answers, started)
		if outcome == .ok {
			c.late_answers++
		}
		return outcome, value
	}
	mut discarded := u32(0)
	for c.status() & status_obf != 0 {
		value := c.port.read(c.port.context, false)
		if c.sent && answers {
			// Later still: the answer to what two attempts waited for.
			c.late_answers++
			return Outcome.ok, value
		}
		c.stale_bytes++
		discarded++
		if discarded >= max_stale_bytes {
			return Outcome.stuck_output, u8(0)
		}
		c.port.pause(c.port.context, spin_pause_ns)
	}
	c.sent = false
	c.waited = false
	if !c.wait(status_ibf, 0, started) {
		return Outcome.timeout, u8(0)
	}
	c.port.write(c.port.context, true, command)
	if wlen > 0 {
		if !c.wait(status_ibf, 0, started) {
			return Outcome.timeout, u8(0)
		}
		c.port.write(c.port.context, false, w0)
	}
	if wlen > 1 {
		if !c.wait(status_ibf, 0, started) {
			return Outcome.timeout, u8(0)
		}
		c.port.write(c.port.context, false, w1)
	}
	c.sent = true
	outcome, value := c.finish(answers, started)
	return outcome, value
}

// One exchange, with its restarts and its part in giving the controller up.
// The caller holds whatever keeps exchanges apart.
pub fn (mut c Controller) transact(command u8, wlen u8, w0 u8, w1 u8, answers bool) (Outcome, u8) {
	if c.failed {
		c.refused++
		return Outcome.failed, u8(0)
	}
	c.transactions++
	c.sent = false
	c.waited = false
	mut outcome := Outcome.timeout
	mut value := u8(0)
	for attempt in u32(0) .. attempts {
		if attempt != 0 {
			c.restarts++
		}
		outcome, value = c.attempt(command, wlen, w0, w1, answers)
		if outcome != .timeout {
			break
		}
	}
	if outcome == .ok {
		c.completed++
		c.consecutive = 0
		if c.last_status & status_sci_evt == 0 {
			c.sci_stuck = false
		} else if !c.sci_stuck {
			c.sci_seen = true
		}
		return Outcome.ok, value
	}
	if outcome == .timeout {
		c.timeouts++
	} else {
		c.stuck_outputs++
	}
	c.consecutive++
	limit := if c.completed == 0 { u32(1) } else { fail_after }
	if c.consecutive >= limit {
		c.failed = true
		c.failure = outcome
	}
	return outcome, u8(0)
}

fn (mut c Controller) enter() bool {
	if c.port.enter == unsafe { nil } {
		return true
	}
	return c.port.enter(c.port.context)
}

fn (mut c Controller) leave() {
	if c.port.leave != unsafe { nil } {
		c.port.leave(c.port.context)
	}
}

fn region_valid(address u64, width u8) bool {
	return width != 0 && width <= 8 && address <= 0xff && address + u64(width) <= 0x100
}

// What an EmbeddedControl field reads: `width` bytes from `address` on, the
// first the lowest. The controller's space is 256 bytes.
pub fn (mut c Controller) region_read(address u64, width u8) (Outcome, u64) {
	if !region_valid(address, width) {
		return Outcome.invalid, u64(0)
	}
	if c.failed {
		c.refused++
		return Outcome.failed, u64(0)
	}
	if !c.enter() {
		return Outcome.busy, u64(0)
	}
	mut value := u64(0)
	mut outcome := Outcome.ok
	for i in u32(0) .. u32(width) {
		result, part := c.transact(command_read, 1, u8(address + u64(i)), 0, true)
		if result != .ok {
			outcome = result
			value = 0
			break
		}
		value |= u64(part) << (i * 8)
	}
	c.leave()
	return outcome, value
}

// What a write to such a field does.
pub fn (mut c Controller) region_write(address u64, width u8, value u64) Outcome {
	if !region_valid(address, width) {
		return .invalid
	}
	if c.failed {
		c.refused++
		return .failed
	}
	if !c.enter() {
		return .busy
	}
	mut outcome := Outcome.ok
	for i in u32(0) .. u32(width) {
		result, _ := c.transact(command_write, 2, u8(address + u64(i)), u8(value >> (i * 8)),
			false)
		if result != .ok {
			outcome = result
			break
		}
	}
	c.leave()
	return outcome
}

pub enum EventStep {
	// The controller has no event.
	none
	// It has this one, and may have more.
	event
	// It could not be asked.
	error
}

// Whether the controller wants to be asked: its event bit is up, and is not
// known to be stuck there.
pub fn (mut c Controller) event_waiting() bool {
	if c.failed || !c.enter() {
		return false
	}
	up := c.status() & status_sci_evt != 0
	if !up {
		c.sci_stuck = false
	}
	c.leave()
	return up && !c.sci_stuck
}

// Take one event out of the controller. Without `blind` it is asked only
// when its event bit is up; with it, whatever the bit says, which is how a
// controller that stops raising the bit once its queue is full is emptied.
pub fn (mut c Controller) next_event(blind bool) (EventStep, u8) {
	if c.failed {
		c.refused++
		return EventStep.error, u8(0)
	}
	if !c.enter() {
		return EventStep.error, u8(0)
	}
	if !blind && c.status() & status_sci_evt == 0 {
		c.sci_stuck = false
		c.sci_seen = false
		c.leave()
		return EventStep.none, u8(0)
	}
	outcome, number := c.transact(command_query, 0, 0, 0, true)
	if outcome != .ok {
		c.leave()
		return EventStep.error, u8(0)
	}
	if number == 0 {
		// Nothing to report, whatever the event bit says. One that is still
		// up now would bring every caller straight back here.
		c.empty_queries++
		c.sci_stuck = c.status() & status_sci_evt != 0
		c.sci_seen = false
		c.leave()
		return EventStep.none, u8(0)
	}
	c.queries++
	c.leave()
	return EventStep.event, number
}

pub struct DrainReport {
pub mut:
	events u32
	// Stopped at the limit, with the controller still offering events.
	limited bool
	// Stopped because the controller could not be asked.
	error bool
}

// Take events out of the controller until it has none, handing each to
// `dispatch`, which is called with nothing held. At most `limit` are taken:
// a controller that never runs out does not keep its caller for ever, and is
// then left alone until its line is raised again.
pub fn (mut c Controller) drain(blind bool, limit u32, dispatch fn (context voidptr, number u8), context voidptr) DrainReport {
	mut report := DrainReport{}
	for report.events < limit {
		step, number := c.next_event(blind)
		if step == .error {
			report.error = true
			return report
		}
		if step == .none {
			return report
		}
		report.events++
		if dispatch != unsafe { nil } {
			dispatch(context, number)
		}
	}
	if c.failed || !c.enter() {
		return report
	}
	if c.status() & status_sci_evt != 0 {
		c.drain_limits++
		c.sci_stuck = true
		report.limited = true
	}
	c.sci_seen = false
	c.leave()
	return report
}

// Whether an exchange since the last call ended with the event bit up.
pub fn (mut c Controller) take_hint() bool {
	seen := c.sci_seen
	c.sci_seen = false
	return seen && !c.failed
}

// The controller's general purpose event arrived at `now`. False when they
// have come so thick, and brought so little, that the line is stuck and
// should be left off. The caller keeps this and calm() apart.
pub fn (mut c Controller) note_gpe(now u64) bool {
	c.gpes++
	if c.idle_gpes == 0 || now - c.storm_window > storm_window_ns {
		c.storm_window = now
		c.idle_gpes = 0
	}
	c.idle_gpes++
	if c.idle_gpes > storm_gpes {
		c.idle_gpes = 0
		c.storms++
		return false
	}
	return true
}

// An event came out of the controller: its line is doing its job.
pub fn (mut c Controller) calm() {
	c.idle_gpes = 0
}

// Forget that the controller was given up on, for one more try: a single
// failed exchange gives it up again.
pub fn (mut c Controller) revive() {
	c.failed = false
	c.failure = .ok
	c.consecutive = if c.completed == 0 { u32(0) } else { fail_after - 1 }
	c.sci_stuck = false
	c.sci_seen = false
}

// Whether a revived controller answers: one query, which every controller
// has an answer to. The event it names, if any, is the caller's to deliver.
pub fn (mut c Controller) probe() (Outcome, u8) {
	if !c.enter() {
		return Outcome.busy, u8(0)
	}
	c.revive()
	outcome, number := c.transact(command_query, 0, 0, 0, true)
	if outcome == .ok && number != 0 {
		c.queries++
	}
	c.leave()
	return outcome, number
}

fn hex_digit(value u8) u8 {
	return if value < 10 { `0` + value } else { `A` + (value - 10) }
}

// Character `index`, of four, of the name of the method firmware gives event
// `number`: _Q and the number in two capital hexadecimal digits.
pub fn query_method_char(number u8, index u32) u8 {
	return match index {
		0 { `_` }
		1 { `Q` }
		2 { hex_digit(number >> 4) }
		else { hex_digit(number & 0xf) }
	}
}

// Where firmware says a controller is: its two ports and the general purpose
// event it raises.
pub struct Description {
pub mut:
	valid   bool
	data    u64
	command u64
	has_gpe bool
	gpe     u64
}

pub enum Source {
	none
	// The ECDT, the table that describes the controller before the
	// namespace exists.
	table
	// The PNP0C09 device in the namespace.
	device
	// Both, agreeing about the ports.
	both
}

pub fn source_name(source Source) string {
	return match source {
		.none { 'none' }
		.table { 'ECDT' }
		.device { 'namespace' }
		.both { 'ECDT and namespace' }
	}
}

pub struct Choice {
pub mut:
	source Source
	found  Description
	// The table and the device name different ports.
	conflict bool
}

// Ports are I/O ports, and neither may be port 0: firmware that fills a
// description with zeroes has no controller to describe.
pub fn usable(description Description) bool {
	return description.valid && description.data != 0 && description.command != 0
		&& description.data <= 0xffff && description.command <= 0xffff
		&& description.data != description.command
}

// Which description to drive the controller by when the table and the
// device each give one. They are Linux's rules (acpi_ec_add): where the two
// agree about the ports, the table's event is the one to trust unless told
// otherwise, since firmware is more often wrong in _GPE; where they do not,
// the device is what the rest of the namespace was written against.
pub fn choose(table Description, device Description, trust_device_gpe bool) Choice {
	table_ok := usable(table)
	device_ok := usable(device)
	if !table_ok && !device_ok {
		return Choice{}
	}
	if !device_ok {
		return Choice{
			source: .table
			found:  table
		}
	}
	if !table_ok {
		return Choice{
			source: .device
			found:  device
		}
	}
	if table.data != device.data || table.command != device.command {
		return Choice{
			source:   .device
			found:    device
			conflict: true
		}
	}
	mut found := table
	if (trust_device_gpe && device.has_gpe) || !table.has_gpe {
		found.has_gpe = device.has_gpe
		found.gpe = device.gpe
	}
	return Choice{
		source: .both
		found:  found
	}
}
