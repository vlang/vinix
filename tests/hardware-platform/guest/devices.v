// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// devices: what the device core shows of PCI in sysfs, and one driver taken
// through everything the core can do to it.
//
// The e1000 is the device because nothing in this machine depends on it: it
// can be unbound, bound, reset and removed with the system still running.
// Unbinding and binding are repeated, because once proves that a driver can
// let go of a device and many times proves that it gives back what it took.
module main

import os

const pci_devices = '/sys/bus/pci/devices'
const e1000_driver = '/sys/bus/pci/drivers/e1000'

// How much less free memory twenty unbind/bind cycles may leave. A cycle
// allocates the driver's rings and buffers, about a hundred pages; one
// cycle's worth not given back is already more than this.
const leak_limit_kb = 1024

fn scenario_devices(mut t Test) {
	names := list_dir(pci_devices) or {
		t.check(false, err.msg())
		return
	}
	if !t.check(names.len > 0, '${pci_devices} is empty') {
		return
	}
	for name in names {
		link := '${pci_devices}/${name}'
		t.check(os.is_link(link), '${link} is not a link')
		if !t.check(os.is_dir(link), '${link} leads nowhere') {
			continue
		}
		for attribute in ['vendor', 'device', 'class', 'state'] {
			t.check(read_word('${link}/${attribute}') != '', '${link}/${attribute} is missing or empty')
		}
	}
	t.info('${names.len} PCI devices in sysfs')

	// The driver's directory links to each device it is bound to.
	entries := list_dir(e1000_driver) or {
		t.check(false, err.msg())
		return
	}
	bound := entries.filter(os.is_link('${e1000_driver}/${it}'))
	if !t.check(bound.len == 1, 'expected one device bound to e1000, found ${bound.len}') {
		return
	}
	name := bound[0]
	device := '${pci_devices}/${name}'
	line := name + '\n'
	t.check(read_word('${device}/state') == 'bound', 'e1000 ${name} is "${read_word(device +
		'/state')}" at boot, not bound')
	t.check(os.is_link('${device}/driver'), '${device}/driver is missing while bound')

	write_text('${e1000_driver}/unbind', line) or { t.check(false, 'unbind: ${err.msg()}') }
	t.check(read_word('${device}/state') == 'unbound', 'state after unbind is "${read_word(device +
		'/state')}"')
	t.check(!os.is_link('${device}/driver'), '${device}/driver is still there after unbind')
	// An unbound device may reach no memory at all.
	dma := read_word('${device}/dma')
	t.check(dma.contains('domain: none'), 'dma after unbind is "${dma}", not "domain: none"')
	mut refused := false
	write_text('${e1000_driver}/unbind', line) or { refused = true }
	t.check(refused, 'unbinding an unbound device succeeded')

	write_text('${e1000_driver}/bind', line) or { t.check(false, 'bind: ${err.msg()}') }
	t.check(read_word('${device}/state') == 'bound', 'state after bind is "${read_word(device +
		'/state')}"')
	t.check(os.is_link('${device}/driver'), '${device}/driver is missing after bind')

	// The first cycles fill caches that are meant to stay filled; what is
	// measured is whether the cycles after them cost anything.
	if !cycle(mut t, line, 3) {
		return
	}
	before := meminfo_kb('MemFree') or {
		t.check(false, err.msg())
		return
	}
	if !cycle(mut t, line, 20) {
		return
	}
	after := meminfo_kb('MemFree') or {
		t.check(false, err.msg())
		return
	}
	t.info('MemFree before 20 unbind/bind cycles ${before} kB, after ${after} kB (${after - before:+} kB)')
	t.check(before - after <= leak_limit_kb, '20 unbind/bind cycles shrank MemFree by ${before - after} kB (limit ${leak_limit_kb} kB)')
	t.check(read_word('${device}/state') == 'bound', 'state after the cycles is "${read_word(device +
		'/state')}"')

	write_text('${device}/reset', '1\n') or { t.check(false, 'reset: ${err.msg()}') }
	t.check(wait_until(3000, fn [device] () bool {
		return read_word('${device}/health').contains('resets: 1')
	}), 'health after reset is "${read_word(device + '/health')}", without "resets: 1"')
	t.check(wait_until(3000, fn [device] () bool {
		return read_word('${device}/state') == 'bound'
	}), 'state after reset is "${read_word(device + '/state')}"')

	write_text('${device}/remove', '1\n') or { t.check(false, 'remove: ${err.msg()}') }
	t.check(wait_until(3000, fn [device] () bool {
		return !os.exists(device) && !os.is_link(device)
	}), '${device} is still there after remove')
	left := list_dir(pci_devices) or { []string{} }
	t.check(name !in left, '${pci_devices} still lists ${name} after remove')
}

// Unbinds and binds the device `count` times. False once a step fails:
// there is no use in repeating it.
fn cycle(mut t Test, line string, count int) bool {
	for i in 0 .. count {
		write_text('${e1000_driver}/unbind', line) or {
			t.check(false, 'unbind in cycle ${i + 1}: ${err.msg()}')
			return false
		}
		write_text('${e1000_driver}/bind', line) or {
			t.check(false, 'bind in cycle ${i + 1}: ${err.msg()}')
			return false
		}
	}
	return true
}
