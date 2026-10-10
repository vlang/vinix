// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// pci-d3: a card that is switched nearly off for a sleep, and works after it.
//
// The machine's network card is one with a power management capability (an
// Intel 82574L). For a sleep the kernel puts it into D3hot once its driver
// has stopped it, and brings it back to D0 and gives it its configuration
// again before the driver resumes. QEMU acts on the state as a card does, in
// that the card's registers cannot be reached in D3hot. So:
//
//   - while the machine is down the controller asks QEMU for the memory map,
//     and the card's registers must not be in it; before and after they must
//     be. That is the machine's account, not the kernel's.
//   - after each sleep the card must be in D0 by its own word, count one
//     more sleep spent in D3hot, and carry a frame out and one back.
//
// A real card need keep nothing across D3hot, and most lose their address
// registers; QEMU's keeps everything. pci-d3-selftest runs the same on a
// kernel built with -d pci_d3_selftest, which clears the card's address and
// command registers while it is down: there the kernel must report that it
// found registers changed and wrote them back, and the frame that comes
// back afterwards came through registers it restored.
//
// A rehearsal, a suspend to idle ended by the alarm and, where the machine
// offers one, a suspend to RAM. Then a run of short rehearsals, after which
// the kernel must hold no more memory than before.
//
// pci-d3-off is the same machine told not to (vinix.pci_d3=off): the card
// stays in D0 and on the bus, and works afterwards all the same.
module main

import os

const d3_report = '/sys/power/pci_d3'
// How long the machine stays down while the controller looks at it: twice
// what the controller waits before looking (d3_look_after_ms).
const d3_down_ms = 6000
// Rehearsals measured for what they leave behind.
const d3_cycles = 40

// The number on the line of /sys/power/pci_d3 that starts with `name`, or -1.
fn d3_figure(name string) int {
	text := read_text(d3_report) or { return -1 }
	for line in text.split_into_lines() {
		if line.starts_with(name + ':') {
			return line.all_after(':').trim_space().int()
		}
	}
	return -1
}

// The one device bound to the e1000 driver, as its directory in /sys.
fn d3_card(mut t Test) ?string {
	entries := list_dir(e1000_driver) or {
		t.check(false, err.msg())
		return none
	}
	bound := entries.filter(os.is_link('${e1000_driver}/${it}'))
	if !t.check(bound.len == 1, 'expected one device bound to e1000, found ${bound.len}') {
		return none
	}
	return '${pci_devices}/${bound[0]}'
}

// What must hold of the card once the machine is back: awake, `sleeps`
// sleeps spent in D3hot, and working.
fn d3_card_is_back(mut t Test, card string, sleeps int, what string) {
	t.check(read_word('${card}/power_state') == 'D0', '${what}: the card says it is in "${read_word(card +
		'/power_state')}", not D0')
	t.check(read_word('${card}/power/d3_count') == sleeps.str(), '${what}: the card has spent ${read_word(card +
		'/power/d3_count')} sleeps in D3hot, not ${sleeps}')
	t.check(read_word('${card}/state') == 'bound', '${what}: the card is "${read_word(card +
		'/state')}", not bound')
	t.check(d3_figure('refused') == 0 && d3_figure('not back') == 0, '${what}: ${d3_figure('refused')} functions would not go into D3 and ${d3_figure('not back')} did not come back')
	t.check(network_works(15), '${what}: nothing comes back over the card')
}

fn scenario_pci_d3(mut t Test) {
	pci_d3_sleeps(mut t, false)
}

fn scenario_pci_d3_selftest(mut t Test) {
	pci_d3_sleeps(mut t, true)
}

// What the last wake had to write back: something if the card forgets,
// which it does only when the kernel makes it.
fn d3_wrote_back(mut t Test, forgetful bool, what string) {
	rewritten := d3_figure('rewritten')
	if forgetful {
		t.check(rewritten >= 2, '${what}: the kernel wrote back ${rewritten} registers of a card that had forgotten its addresses and its command register')
	} else {
		t.check(rewritten == 0, '${what}: the kernel found ${rewritten} registers changed on a card that keeps them')
	}
}

fn pci_d3_sleeps(mut t Test, forgetful bool) {
	card := d3_card(mut t) or { return }
	t.check(read_text(d3_report) or { '' }.starts_with('on\n'), '${d3_report} does not start with "on"')
	t.check(read_word('${card}/power_state') == 'D0', 'the card says it is in "${read_word(card +
		'/power_state')}" at boot, not D0')
	t.check(read_word('${card}/power/d3_count') == '0', 'the card has been in D3hot before any sleep')
	t.check(network_works(30), 'nothing comes back over the card before any sleep')
	t.step('the card is awake')
	sleep_ms(1000)

	// A rehearsal: the devices go down and come back, and nothing else.
	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err.msg()}') }
	write_text('/sys/power/pm_test_delay_ms', d3_down_ms.str()) or {
		t.check(false, 'pm_test_delay_ms: ${err.msg()}')
	}
	t.step('a rehearsal, the card asleep')
	mut took := sleep_now(mut t, 'freeze')
	t.check(stat_word('success') == '1', 'the rehearsal failed: step "${stat_word('last_failed_step')}", device "${stat_word('last_failed_dev')}"')
	t.check(d3_figure('last') == 1, 'the rehearsal put ${d3_figure('last')} functions into D3hot, not one')
	d3_card_is_back(mut t, card, 1, 'after the rehearsal')
	d3_wrote_back(mut t, forgetful, 'after the rehearsal')
	t.info('rehearsal: ${took} ms')
	t.step('awake after the rehearsal')
	sleep_ms(1000)
	write_text('/sys/power/pm_test', 'none') or { t.check(false, 'pm_test: ${err.msg()}') }

	// A suspend to idle, ended by the alarm.
	write_text('/sys/class/rtc/rtc0/wakealarm', '+${d3_down_ms / 1000}') or {
		t.check(false, 'wakealarm: ${err.msg()}')
	}
	t.step('a suspend to idle, the card asleep')
	took = sleep_now(mut t, 'freeze')
	t.check(stat_word('success') == '2' && stat_word('last_wake') == 'alarm', 'the suspend to idle: ${stat_word('success')} successes, woken by ${stat_word('last_wake')}')
	d3_card_is_back(mut t, card, 2, 'after the suspend to idle')
	d3_wrote_back(mut t, forgetful, 'after the suspend to idle')
	t.info('suspend to idle: ${took} ms')
	t.step('awake after the suspend to idle')
	sleep_ms(1000)

	// A suspend to RAM, where there is one: the card is in D3hot when the
	// power goes, and is found blank and in D0 when it is back.
	mut sleeps := 2
	if read_word('/sys/power/mem_sleep').contains('deep') {
		write_text('/sys/power/mem_sleep', 'deep') or { t.check(false, 'selecting deep: ${err.msg()}') }
		write_text('/sys/class/rtc/rtc0/wakealarm', '+4') or { t.check(false, 'wakealarm: ${err.msg()}') }
		took = sleep_now(mut t, 'mem')
		sleeps++
		t.check(stat_word('success') == '3' && stat_word('last_depth') == 'deep', 'the suspend to RAM: ${stat_word('success')} successes, the last one "${stat_word('last_depth')}", step "${stat_word('last_failed_step')}", ${stat_word('last_failed_reason')}')
		d3_card_is_back(mut t, card, sleeps, 'after the suspend to RAM')
		t.info('suspend to RAM: ${took} ms')
		write_text('/sys/power/mem_sleep', 's2idle') or { t.check(false, 'selecting s2idle: ${err.msg()}') }
	} else {
		t.info('no suspend to RAM on this machine')
	}

	// What a sleep leaves behind in the kernel.
	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err.msg()}') }
	write_text('/sys/power/pm_test_delay_ms', '20') or { t.check(false, 'pm_test_delay_ms: ${err.msg()}') }
	sleep_now(mut t, 'freeze')
	sleeps++
	before := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	for _ in 0 .. d3_cycles {
		sleep_now(mut t, 'freeze')
	}
	sleeps += d3_cycles
	after := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	t.check(after.objects - before.objects <= heap_noise_objects, '${d3_cycles} sleeps left ${after.objects - before.objects} more heap objects allocated (limit ${heap_noise_objects})')
	t.info('heap objects: ${before.objects} before ${d3_cycles} sleeps, ${after.objects} after')
	write_text('/sys/power/pm_test', 'none') or { t.check(false, 'pm_test: ${err.msg()}') }
	d3_card_is_back(mut t, card, sleeps, 'after ${d3_cycles} more sleeps')
	t.check(d3_figure('total') == sleeps, '${d3_figure('total')} functions put into D3hot in all, not ${sleeps}')
	t.check(stat_word('fail') == '0', '${stat_word('fail')} sleeps failed')
}

fn scenario_pci_d3_off(mut t Test) {
	card := d3_card(mut t) or { return }
	t.check(read_text(d3_report) or { '' }.starts_with('off\n'), '${d3_report} does not start with "off"')
	t.check(network_works(30), 'nothing comes back over the card before any sleep')
	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err.msg()}') }
	write_text('/sys/power/pm_test_delay_ms', d3_down_ms.str()) or {
		t.check(false, 'pm_test_delay_ms: ${err.msg()}')
	}
	t.step('a rehearsal, the card left awake')
	sleep_now(mut t, 'freeze')
	t.check(stat_word('success') == '1', 'the rehearsal failed: step "${stat_word('last_failed_step')}", device "${stat_word('last_failed_dev')}"')
	t.check(d3_figure('last') == 0 && d3_figure('total') == 0, 'functions were put into D3hot with vinix.pci_d3=off: ${d3_figure('last')}')
	t.check(read_word('${card}/power/d3_count') == '0', 'the card has spent ${read_word(card +
		'/power/d3_count')} sleeps in D3hot with vinix.pci_d3=off')
	t.check(read_word('${card}/power_state') == 'D0', 'the card says it is in "${read_word(card +
		'/power_state')}", not D0')
	t.check(network_works(15), 'nothing comes back over the card after the rehearsal')
}
