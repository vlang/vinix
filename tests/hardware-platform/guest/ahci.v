// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// ahci: a SATA disk keeps working across a reset of its controller.
//
// A reset stops the ports, resets the controller and starts everything
// again; whether that worked shows in whether the disk can still be read and
// written, not in the reset reporting success. So data goes to the disk
// before the reset and after it, in two places, and the host looks for both
// in the disk image once the machine is off -- which also says that what the
// guest read back was on the disk and not only in a cache.
module main

import os

const ahci_driver = '/sys/bus/pci/drivers/ahci'
const sata_disk = '/dev/sd0'

// The host checks the same places: `patterns` of the scenario's record.
const pattern_length = 65536

fn scenario_ahci(mut t Test) {
	entries := list_dir(ahci_driver) or {
		t.check(false, err.msg())
		return
	}
	bound := entries.filter(os.is_link('${ahci_driver}/${it}'))
	if !t.check(bound.len == 1, 'expected one controller bound to ahci, found ${bound.len}') {
		return
	}
	device := '${pci_devices}/${bound[0]}'
	t.check(read_word('${device}/state') == 'bound', 'controller ${bound[0]} is "${read_word(device +
		'/state')}" at boot, not bound')
	if !t.check(os.exists(sata_disk), 'there is no ${sata_disk}') {
		return
	}

	write_pattern(sata_disk, 1 << 20, 0x11, pattern_length) or {
		t.check(false, '${sata_disk} at 1 MiB before the reset: ${err.msg()}')
	}

	write_text('${device}/reset', '1\n') or { t.check(false, 'reset: ${err.msg()}') }
	t.check(wait_until(5000, fn [device] () bool {
		return read_word('${device}/health').contains('resets: 1')
	}), 'health after reset is "${read_word(device + '/health')}", without "resets: 1"')
	t.check(wait_until(5000, fn [device] () bool {
		return read_word('${device}/state') == 'bound'
	}), 'state after reset is "${read_word(device + '/state')}"')

	write_pattern(sata_disk, 2 << 20, 0x55, pattern_length) or {
		t.check(false, '${sata_disk} at 2 MiB after the reset: ${err.msg()}')
	}
}
