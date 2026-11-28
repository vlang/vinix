// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The serial ports after a suspend to RAM.
//
// A UART that lost power has forgotten its speed, its line format and which
// interrupts it is to raise: it would still send, at whatever speed power-on
// gives it, and a reader waiting on its interrupt would wait for good. Each
// port that answered at boot is programmed again as initialise_port()
// programmed it then.
//
// This module cannot name the device core -- the memory allocator and the
// kernel's own logging use the first port, and the device core is built on
// both -- so the platform's sleep code registers the ports there and calls
// resume() from its resume.
module serial

// Program every port that was found at boot again. Returns how many were.
pub fn resume() int {
	mut programmed := 0
	for port in com_ports {
		present := initialise_port(u16(port))
		if port == com1_port {
			com1_present = present
			com1_tx_failed = false
		}
		if present {
			enable_port_interrupts(u16(port))
			programmed++
		}
	}
	return programmed
}
