// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// pci-hotplug: a network card put into a running machine and taken out of
// it again, twice.
//
// The machine boots with an empty PCI Express port and no network card. The
// controller adds an e1000 behind the port when asked, and asks for it back
// when told the card is in use; QEMU lets go of the card only once the guest
// has done its part, and says so in an event the controller waits for.
//
// Two scenarios share this file. In `pci-hotplug` the port is the kernel's
// own to watch, and has a slot in /sys. In `pci-hotplug-acpi` firmware keeps
// the port and announces the card through ACPI; there is then no slot, and
// everything else must hold all the same.
module main

import os

const hot_card = '/sys/bus/pci/devices/0000:01:00.0'
const pci_slots = '/sys/bus/pci/slots'
const pci_rescan = '/sys/bus/pci/rescan'

// How long the card may take to appear after the controller is asked for
// it, and to go after it is asked back: the second includes the five seconds
// in which a press of a slot's button can be called off.
const arrival_ms = 15000
const departure_ms = 20000

// How many times the card is forgotten and found again for the measurement;
// see devices.v for why a hundred, and for the wait before measuring.
const found_again_cycles = 100

fn hot_card_bound() bool {
	return read_word(hot_card + '/state') == 'bound' && os.is_link(hot_card + '/driver')
}

fn hot_card_gone() bool {
	return !os.exists(hot_card) && !os.is_link(hot_card)
}

// A function's configuration space, as its `config` file gives it.
fn read_config(device string) ![]u8 {
	text := read_text(device + '/config')!
	return text.bytes()
}

// A little-endian field of a function's configuration space.
fn config_field(config []u8, offset int, bytes int) u64 {
	mut value := u64(0)
	for i in 0 .. bytes {
		value |= u64(config[offset + i]) << (8 * i)
	}
	return value
}

// The port the card sits behind: the bridge whose secondary bus is 1.
fn hot_port() !string {
	for name in list_dir(pci_devices)! {
		config := read_config('${pci_devices}/${name}') or { continue }
		if config.len >= 64 && config[0x0e] & 0x7f == 1 && config[0x19] == 1 {
			return '${pci_devices}/${name}'
		}
	}
	return error('no bridge leads to bus 1')
}

// The one slot the machine has, when its ports are the kernel's.
fn hot_slot() !string {
	names := list_dir(pci_slots)!
	if names.len != 1 {
		return error('${pci_slots} has ${names.len} slots, not one')
	}
	return '${pci_slots}/${names[0]}'
}

// The card must have been given an address inside what its port forwards,
// and must be allowed to decode it.
fn check_card_addresses(mut t Test) {
	port := hot_port() or {
		t.check(false, err.msg())
		return
	}
	bridge := read_config(port) or {
		t.check(false, 'the port\'s configuration space cannot be read')
		return
	}
	card := read_config(hot_card) or {
		t.check(false, 'the card\'s configuration space cannot be read')
		return
	}
	if !t.check(bridge.len >= 64 && card.len >= 64, 'configuration space is shorter than a header') {
		return
	}
	window_base := (config_field(bridge, 0x20, 2) & 0xfff0) << 16
	window_end := ((config_field(bridge, 0x22, 2) & 0xfff0) << 16) + 0x100000
	address := config_field(card, 0x10, 4) & ~u64(0xf)
	command := config_field(card, 0x04, 2)
	t.check(address != 0, 'the card\'s register memory has no address')
	t.check(address >= window_base && address < window_end, 'the card is at 0x${address:x}, outside what its port forwards (0x${window_base:x} to 0x${window_end:x})')
	t.check(command & 0x2 != 0, 'the card is not decoding memory (command 0x${command:x})')
	t.check(command & 0x4 != 0, 'the card may not master the bus (command 0x${command:x})')
	t.check(config_field(bridge, 0x04, 2) & 0x6 == 0x6, 'the port is not forwarding')
	t.info('card at 0x${address:x} in the port\'s window 0x${window_base:x}-0x${window_end:x}')
}

// One arrival: asked for, found, bound, addressed, and carrying traffic.
fn hot_arrival(mut t Test, round string, own_ports bool) bool {
	t.step('waiting for the card${round}')
	if !t.check(wait_until(arrival_ms, hot_card_bound), 'the card did not appear bound within ${arrival_ms / 1000} s (state "${read_word(
		hot_card + '/state')}")') {
		return false
	}
	t.check(read_word(hot_card + '/vendor') == '0x8086', 'the card\'s vendor is "${read_word(
		hot_card + '/vendor')}"')
	driver := os.readlink(hot_card + '/driver') or { '' }
	t.check(driver.ends_with('/e1000'), 'the card is bound to "${driver}", not to e1000')
	check_card_addresses(mut t)
	if own_ports {
		slot := hot_slot() or {
			t.check(false, err.msg())
			return false
		}
		t.check(read_word(slot + '/state') == 'occupied', 'the slot is "${read_word(slot + '/state')}" with the card in use')
		t.check(read_word(slot + '/adapter') == '1', 'the slot reports no card')
		t.check(read_word(slot + '/power') == '1', 'the slot reports no power')
	}
	return t.check(network_works(10), 'the network does not work through the card that arrived')
}

// One departure: asked back, let go of, gone.
fn hot_departure(mut t Test, round string, own_ports bool) bool {
	t.step('card in use${round}')
	if !t.check(wait_until(departure_ms, hot_card_gone), 'the card is still listed ${departure_ms / 1000} s after it was asked back') {
		return false
	}
	entries := list_dir(e1000_driver) or { []string{} }
	t.check(entries.filter(os.is_link('${e1000_driver}/${it}')).len == 0, 'the driver still lists a card')
	if own_ports {
		slot := hot_slot() or {
			t.check(false, err.msg())
			return false
		}
		t.check(wait_until(3000, fn [slot] () bool {
			return read_word(slot + '/state') == 'empty'
		}), 'the slot is "${read_word(slot + '/state')}" after the card left')
		t.check(read_word(slot + '/adapter') == '0', 'the slot still reports a card')
		t.check(read_word(slot + '/power') == '0', 'the slot still reports power')
	}
	return true
}

fn C.access(path &char, mode int) int

// The two things the measured loop waits for, asked without allocating: this
// program frees nothing, every mapping its heap grows by costs the kernel
// three objects of its own, and a loop that reads files to find out what it
// is waiting for was measured as leaking one such mapping a second.
fn card_is_listed() bool {
	return C.access(c'/sys/bus/pci/devices/0000:01:00.0', 0) == 0
}

fn card_is_not_listed() bool {
	return !card_is_listed()
}

// The link to its driver is the last thing a binding makes.
fn card_has_driver() bool {
	return C.access(c'/sys/bus/pci/devices/0000:01:00.0/driver', 0) == 0
}

// Has the kernel forget the card and find it again `count` times: its own
// `remove` file, then a rescan of the buses. False once a step fails.
fn forget_and_find(mut t Test, count int) bool {
	remove := hot_card + '/remove'
	for i in 0 .. count {
		write_text(remove, '1\n') or {
			t.check(false, 'remove in cycle ${i + 1}: ${err.msg()}')
			return false
		}
		if !wait_until(3000, card_is_not_listed) {
			t.check(false, 'the card was still listed after remove in cycle ${i + 1}')
			return false
		}
		write_text(pci_rescan, '1\n') or {
			t.check(false, 'rescan in cycle ${i + 1}: ${err.msg()}')
			return false
		}
		if !wait_until(5000, card_has_driver) {
			t.check(false, 'the card was not found again by the rescan in cycle ${i + 1}')
			return false
		}
	}
	return true
}

fn pci_hotplug(mut t Test, own_ports bool) {
	t.check(hot_card_gone(), 'the card is there before it was put in')
	slots := list_dir(pci_slots) or { []string{} }
	if own_ports {
		slot := hot_slot() or {
			t.check(false, err.msg())
			return
		}
		t.check(read_word(slot + '/address') == '0000:01:00', 'the slot leads to "${read_word(
			slot + '/address')}"')
		t.check(read_word(slot + '/state') == 'empty', 'the empty slot is "${read_word(slot + '/state')}"')
		t.check(read_word(slot + '/adapter') == '0', 'the empty slot reports a card')
		t.check(read_word(slot + '/power') == '0', 'the empty slot reports power')
	} else {
		t.check(slots.len == 0, 'firmware kept the ports, yet ${slots.len} slots are listed')
	}

	if !hot_arrival(mut t, '', own_ports) {
		return
	}
	// The arrival path again and again, without the controller: what the
	// kernel makes for a function that arrives it must give back when the
	// function goes, and find the function's addresses still good.
	if !forget_and_find(mut t, found_again_cycles + 5) {
		return
	}
	sleep_ms(grace_ms)
	before := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	if !forget_and_find(mut t, found_again_cycles) {
		return
	}
	sleep_ms(grace_ms)
	after := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	t.info('${found_again_cycles} remove/rescan cycles: live heap objects ${before.objects} -> ${after.objects}, large pages ${before.large_pages} -> ${after.large_pages}')
	t.check(after.objects - before.objects <= heap_noise_objects, '${found_again_cycles} remove/rescan cycles left ${after.objects - before.objects} more heap objects allocated (limit ${heap_noise_objects})')
	t.check(after.large_pages <= before.large_pages, '${found_again_cycles} remove/rescan cycles left ${after.large_pages - before.large_pages} more large-allocation pages')
	t.check(network_works(10), 'the network does not work after the remove/rescan cycles')

	if !hot_departure(mut t, '', own_ports) {
		return
	}
	// A second card in the same place gets the first one's record, and must
	// work as the first did.
	if !hot_arrival(mut t, ' again', own_ports) {
		return
	}
	if !hot_departure(mut t, ' again', own_ports) {
		return
	}
	if own_ports {
		slot := hot_slot() or { return }
		events := read_text(slot + '/events') or { '' }
		t.check(events.contains('arrivals: 2') && events.contains('departures: 2')
			&& events.contains('failures: 0'), 'the slot counted "${events.replace('\n',
			' ')}", not two arrivals and two departures')
	}
}

fn scenario_pci_hotplug(mut t Test) {
	pci_hotplug(mut t, true)
}

fn scenario_pci_hotplug_acpi(mut t Test) {
	pci_hotplug(mut t, false)
}
