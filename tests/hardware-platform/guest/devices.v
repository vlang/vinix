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

// How many more live heap objects the measured cycles may leave. A cycle
// makes and frees a few dozen -- two links in /sys, the device's DMA domain
// and its buffer records -- so one object lost per cycle is three times
// this. The allowance is for this program itself: reading and taking apart
// /proc/slabinfo grows its own heap, and each page of that costs the kernel
// an object or two.
const leaked_objects_limit = 30
const measured_cycles = 100

// The kernel frees a removed /sys entry only after a grace period of five
// seconds, checked once a second, so that a lookup still holding it finishes
// first. Memory measured sooner counts entries that are merely not freed yet.
const grace_ms = 7000

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

	// The first cycles fill caches that are meant to stay filled, and grow
	// the kernel's queue of entries waiting to be freed to the size a burst
	// of cycles needs; what is measured is whether the cycles after them
	// leave anything allocated. Free memory is reported and not judged: the
	// heap keeps pages it has emptied, so it moves without anything leaking.
	if !cycle(mut t, line, measured_cycles + 5) {
		return
	}
	sleep_ms(grace_ms)
	before := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	free_before := meminfo_kb('MemFree') or { 0 }
	if !cycle(mut t, line, measured_cycles) {
		return
	}
	sleep_ms(grace_ms)
	after := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	free_after := meminfo_kb('MemFree') or { 0 }
	t.info('${measured_cycles} unbind/bind cycles: live heap objects ${before.objects} -> ${after.objects}, large pages ${before.large_pages} -> ${after.large_pages}, MemFree ${free_after - free_before:+} kB')
	t.check(after.objects - before.objects <= leaked_objects_limit, '${measured_cycles} unbind/bind cycles left ${after.objects - before.objects} more heap objects allocated (limit ${leaked_objects_limit})')
	t.check(after.large_pages <= before.large_pages, '${measured_cycles} unbind/bind cycles left ${after.large_pages - before.large_pages} more large-allocation pages')
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
// there is no use in repeating it. The paths are made once: this program
// frees nothing, and what it allocated inside the loop would show up in the
// kernel's own figures as the pages of a growing heap.
fn cycle(mut t Test, line string, count int) bool {
	unbind := e1000_driver + '/unbind'
	bind := e1000_driver + '/bind'
	for i in 0 .. count {
		write_text(unbind, line) or {
			t.check(false, 'unbind in cycle ${i + 1}: ${err.msg()}')
			return false
		}
		write_text(bind, line) or {
			t.check(false, 'bind in cycle ${i + 1}: ${err.msg()}')
			return false
		}
	}
	return true
}
