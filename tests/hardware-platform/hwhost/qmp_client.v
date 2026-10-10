// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The QMP socket of one QEMU.
//
// QEMU listens on a unix socket in the state directory. The controller is
// its only client: it sends the commands a scenario's actions name, and it
// reads the events, of which one matters to every scenario -- SHUTDOWN says
// whether the guest powered the machine off or something else ended it. The
// names of the others are kept, for a scenario that must have seen one:
// DEVICE_DELETED is QEMU saying the guest let go of a device.
//
// Every line in either direction goes to qmp.log with the time since QEMU
// started, so a run can be read afterwards as a conversation.
module hwhost

import net.unix
import os
import time

pub struct QmpClient {
mut:
	connection &unix.StreamConn = unsafe { nil }
	splitter   LineSplitter
	log        os.File
	started    i64
	closed     bool // QEMU has closed its end
pub mut:
	// From the SHUTDOWN event: guest-shutdown, guest-reset, host-signal...
	shutdown_reason string
	// Every event that arrived, by name.
	events EventLog
}

// Connects to a QEMU that has just been started. Its socket appears a moment
// after the process does, so the connection is retried for as long as QEMU
// is alive and the user has not given up.
pub fn qmp_connect(socket string, log_path string, mut machine Child, started i64) !&QmpClient {
	mut log := os.open_append(log_path) or {
		return error('cannot write ${log_path}: ${err.msg()}')
	}
	deadline := now_ms() + 15000
	for {
		if interrupted() {
			log.close()
			return Interrupted{}
		}
		if machine.poll() {
			log.close()
			return error('QEMU ended before its QMP socket was up (${machine.outcome()})')
		}
		if os.exists(socket) {
			if connection := unix.connect_stream(socket) {
				mut client := &QmpClient{
					connection: connection
					log:        log
					started:    started
				}
				client.greet() or {
					client.close()
					return err
				}
				return client
			}
		}
		if now_ms() >= deadline {
			log.close()
			return error('QEMU did not open its QMP socket ${socket} in 15 s')
		}
		time.sleep(20 * time.millisecond)
	}
	return error('unreachable')
}

fn (mut q QmpClient) record(direction string, text string) {
	seconds := f64(now_ms() - q.started) / 1000.0
	q.log.writeln('[${seconds:8.3f}] ${direction} ${text}') or {}
	q.log.flush()
}

// Reads what QEMU has sent, waiting up to `wait_ms` for there to be any.
fn (mut q QmpClient) receive(wait_ms int) []QmpMessage {
	mut messages := []QmpMessage{}
	if q.closed {
		return messages
	}
	// The socket library turns the timeout into a deadline and looks at the
	// socket only while that has not passed: zero means "no limit" to it,
	// and a microsecond has passed before it looks. A millisecond is the
	// shortest wait that still reads what is already there.
	q.connection.set_read_timeout(if wait_ms > 0 { wait_ms } else { 1 } * time.millisecond)
	q.connection.wait_for_read() or { return messages }
	mut buffer := []u8{len: 4096}
	count := q.connection.read(mut buffer) or {
		// Readable with nothing to read: QEMU is gone.
		q.closed = true
		return messages
	}
	for line in q.splitter.feed(buffer[..count]) {
		message := qmp_parse(line)
		if message.text == '' {
			continue
		}
		q.record('<-', message.text)
		if message.kind == .event {
			q.events.note(message.event)
			if message.event == 'SHUTDOWN' {
				q.shutdown_reason = message.reason
			}
		}
		messages << message
	}
	return messages
}

fn (mut q QmpClient) greet() ! {
	deadline := now_ms() + 5000
	mut greeted := false
	for !greeted {
		for message in q.receive(100) {
			if message.kind == .greeting {
				greeted = true
			}
		}
		if q.closed {
			return error('QEMU closed its QMP socket before greeting')
		}
		if now_ms() >= deadline {
			return error('no QMP greeting from QEMU in 5 s')
		}
		if interrupted() {
			return Interrupted{}
		}
	}
	q.execute('{"execute":"qmp_capabilities"}')!
}

// Sends one command and returns QEMU's answer to it. An "error" answer is an
// error here: an action that QEMU refused did not happen, and a scenario
// that goes on as if it had would fail later for a reason that is not the
// real one.
pub fn (mut q QmpClient) execute(command string) !QmpMessage {
	frame := qmp_frame(command)!
	if q.closed {
		return error('QEMU has closed its QMP socket; cannot send ${frame.trim_space()}')
	}
	q.record('->', frame.trim_space())
	q.connection.set_write_timeout(5 * time.second)
	q.connection.write_string(frame) or {
		return error('cannot send ${frame.trim_space()} to QEMU: ${err.msg()}')
	}
	deadline := now_ms() + 10000
	for {
		for message in q.receive(100) {
			if message.kind == .reply {
				return message
			}
			if message.kind == .failure {
				return error('QEMU refused ${frame.trim_space()}: ${message.detail}')
			}
		}
		if q.closed {
			return error('QEMU closed its QMP socket without answering ${frame.trim_space()}')
		}
		if now_ms() >= deadline {
			return error('QEMU did not answer ${frame.trim_space()} in 10 s')
		}
		if interrupted() {
			return Interrupted{}
		}
	}
	return error('unreachable')
}

// Takes in the events that have arrived, without waiting for more.
pub fn (mut q QmpClient) drain() {
	for !q.closed {
		if q.receive(0).len == 0 {
			break
		}
	}
}

pub fn (mut q QmpClient) close() {
	if !isnil(q.connection) {
		q.connection.close() or {}
		q.connection = unsafe { nil }
	}
	q.closed = true
	q.log.close()
}
