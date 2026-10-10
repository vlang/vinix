// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// suspend-deep-arrival and suspend-deep-departure: a card that comes or goes
// while the machine is suspended to RAM.
//
// Nothing tells the kernel. A port's record of what happened to its slot is
// lost with its power, and firmware sends no notice of what it saw while the
// system was not running. So on the way back the kernel asks every function
// it has who it is, looks at every slot it watches, and scans the buses
// (kernel/devcore/hotplug.v, compare_buses()).
//
// In `suspend-deep-arrival` the port is the kernel's own to watch and its
// slot is empty when the machine goes down; the controller puts a network
// card into it while QEMU reports the machine suspended. Once awake the
// kernel must find the card, give it addresses, bind it and carry traffic
// through it, as it does for a card that arrives while it is running. The
// machine then sleeps again with the card in, and afterwards the slot must
// still give the card up when asked.
//
// In `suspend-deep-departure` firmware keeps the ports, which is QEMU's
// default, and the machine boots with the card. The controller asks for the
// card back while the machine is down, and QEMU, with no system running to
// agree, takes it at the wake-up: the kernel comes back to a driver whose
// device is not there. It must not resume that driver against nothing; it
// must remove the device. A second sleep has a card put in, with no ACPI
// notice of it ever sent, and the scan after the wake must find it.
module main

import os

// One suspend to RAM, and what the kernel says of it. `first` and `second`
// are printed just before the machine goes down, for the controller to act
// on once QEMU reports it suspended; `wake` is what must have ended it, and
// with 'alarm' the clock is set to.
fn hot_sleep(mut t Test, what string, first string, second string, wake string, sleeps int) {
	if wake == 'alarm' {
		write_text('/sys/class/rtc/rtc0/wakealarm', '+2') or { t.check(false, '${what}: wakealarm: ${err.msg()}') }
	}
	if first != '' {
		t.step(first)
	}
	if second != '' {
		t.step(second)
	}
	write_text('/sys/power/state', 'mem') or { t.check(false, '${what}: writing mem to state: ${err.msg()}') }
	t.check(deep_stat('last_depth') == 'deep' && deep_stat('last_wake') == wake, '${what}: recorded as ${deep_stat('last_depth')}, woken by ${deep_stat('last_wake')}')
	t.check(deep_stat('deep') == sleeps.str() && deep_stat('fail') == '0', '${what}: ${deep_stat('deep')} suspends to RAM and ${deep_stat('fail')} failures counted, not ${sleeps} and none')
	t.check(deep_stat('security_changes') == '0', '${what}: CPU protections changed across the sleep')
	t.check(deep_report('processors lost') == 0, '${what}: ${deep_report('processors lost')} processors did not come back')
	t.info('${what}: woke by ${deep_stat('last_wake')} after ${deep_stat('last_sleep_ms')} ms; ${deep_report('pci registers rewritten')} PCI registers written back, ${deep_report('pci functions not restored')} functions not restored so far')
}

fn hot_deep_offered(mut t Test) bool {
	offered, why := deep_offer()
	if !t.check(offered == '[s2idle] deep' && why == 'available', 'suspend to RAM is not offered: "${offered}", "${why}"') {
		return false
	}
	write_text('/sys/power/mem_sleep', 'deep') or {
		t.check(false, 'selecting deep: ${err.msg()}')
		return false
	}
	return true
}

fn scenario_suspend_deep_arrival(mut t Test) {
	if !hot_deep_offered(mut t) {
		return
	}
	slot := hot_slot() or {
		t.check(false, err.msg())
		return
	}
	t.check(hot_card_gone(), 'the card is there before it was put in')
	t.check(read_word(slot + '/state') == 'empty', 'the empty slot is "${read_word(slot + '/state')}"')

	hot_sleep(mut t, 'the sleep a card arrives in', 'a card while asleep', 'a wakeup with the card in',
		'power-button', 1)
	t.check(deep_report('pci functions not restored') == 0, '${deep_report('pci functions not restored')} functions were not restored after a sleep nothing left in')
	if !hot_arrival(mut t, ' put in during the sleep', true) {
		return
	}
	events := (read_text(slot + '/events') or { '' }).replace('\n', ' ')
	t.check(events.contains('arrivals: 1') && events.contains('departures: 0') && events.contains('failures: 0'), 'the slot counts "${events}" after one card arrived')

	// With the card in: it was not there at boot, and is saved and restored
	// like one that was.
	hot_sleep(mut t, 'the sleep with the card in', '', '', 'alarm', 2)
	t.check(deep_report('pci functions not restored') == 0, 'a function was not restored after the second sleep')
	t.check(hot_card_bound(), 'the card is "${read_word(hot_card + '/state')}" after a sleep it was in for')
	t.check(read_word(slot + '/state') == 'occupied' && read_word(slot + '/power') == '1', 'the slot is "${read_word(
		slot + '/state')}", power ${read_word(slot + '/power')}, after a sleep its card was in for')
	check_card_addresses(mut t)
	t.check(network_works(10), 'the network does not work through the card after the second sleep')
	t.step('screen after the sleeps')

	// And the slot is still the kernel's to run: its port's interrupt and
	// power switch were given back what they had.
	hot_departure(mut t, ' after the sleeps', true)
}

fn scenario_suspend_deep_departure(mut t Test) {
	if !hot_deep_offered(mut t) {
		return
	}
	if !t.check(wait_until(5000, hot_card_bound), 'the card the machine booted with is "${read_word(
		hot_card + '/state')}"') {
		return
	}
	t.check(network_works(10), 'the network does not work before any sleep')

	hot_sleep(mut t, 'the sleep the card leaves in', 'the card goes while asleep', 'a wakeup without the card',
		'power-button', 1)
	t.check(deep_report('pci functions not restored') == 1, '${deep_report('pci functions not restored')} functions were found changed after the sleep; the card alone was to be')
	if !t.check(wait_until(5000, hot_card_gone), 'the card that left during the sleep is still listed, as "${read_word(
		hot_card + '/state')}"') {
		return
	}
	entries := list_dir(e1000_driver) or { []string{} }
	t.check(entries.filter(os.is_link('${e1000_driver}/${it}')).len == 0, 'the driver still lists a card')
	t.check(read_word('/sys/power/suspend_stats/last_failed_dev') == '', 'a device is named as having failed: "${read_word('/sys/power/suspend_stats/last_failed_dev')}"')

	hot_sleep(mut t, 'the sleep a card arrives in', 'a card while asleep', 'a wakeup with the card in',
		'power-button', 2)
	if !hot_arrival(mut t, ' put in during the sleep', false) {
		return
	}

	hot_sleep(mut t, 'the sleep with the card in', '', '', 'alarm', 3)
	t.check(deep_report('pci functions not restored') == 1, 'a function was not restored after the third sleep')
	t.check(hot_card_bound(), 'the card is "${read_word(hot_card + '/state')}" after a sleep it was in for')
	check_card_addresses(mut t)
	t.check(network_works(10), 'the network does not work through the card after the third sleep')
	t.step('screen after the sleeps')
	sleep_ms(500)
}
