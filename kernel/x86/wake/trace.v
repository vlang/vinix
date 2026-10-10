// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Following a suspend to RAM on the first serial port.
//
// A machine that does not come back from S3 has no screen and no console to
// say where it stopped, and a production kernel keeps its messages off the
// serial port. A kernel built with `-d wake_trace` writes a line there at
// each step of the way down and back -- the trampoline adds a letter for
// each of its three modes -- so that the last line says how far it got.
// Without the flag these compile to nothing.
module wake

import x86.kio

const trace_port = u16(0x3f8)

fn trace_byte(value u8) {
	// Bounded: a port that never empties is not waited for.
	for _ in 0 .. 100000 {
		if kio.port_in[u8](trace_port + 5) & 0x20 != 0 {
			break
		}
	}
	kio.port_out[u8](trace_port, value)
}

// Write `label`, a literal, and `value` in hexadecimal, on a line of their own.
pub fn trace(label string, value u64) {
	$if wake_trace ? {
		for c in 'S3: ' {
			trace_byte(c)
		}
		for c in label {
			trace_byte(c)
		}
		trace_byte(` `)
		for shift := 60; shift >= 0; shift -= 4 {
			trace_byte('0123456789abcdef'[(value >> u64(shift)) & 0xf])
		}
		trace_byte(`\r`)
		trace_byte(`\n`)
	}
}
