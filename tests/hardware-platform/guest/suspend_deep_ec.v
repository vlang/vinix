// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// suspend-deep-ec: the embedded controller driver through a suspend to RAM.
//
// For a kernel built with `-d acpiec_selftest`, on the machine and tables of
// acpi-ec-selftest (see acpi_ec.v and the README for what the simulated
// controller is). The controller here is memory of the kernel's, so it does
// not lose power, and nothing is learnt about a real one. What does lose
// power is the chipset: the enable bits of its general purpose events and
// the SCI itself, which are what brings the controller's event to the
// driver. After a suspend to RAM:
//
//   - a value must still be read through the controller, which is uACPI's
//     region handler, the driver's lock, the global lock and an exchange;
//   - an event the chipset raises (the host adds a processor, as in
//     acpi-ec-selftest) must be heard again: the event was enabled before the
//     sleep and nothing but the way back from S3 enables it afterwards;
//   - with wakeup disabled for the device its event is switched off for the
//     sleep, and what the controller raised meanwhile is asked for on resume,
//     as after a suspend to idle.
module main

import os

fn scenario_suspend_deep_ec(mut t Test) {
	if !t.check(os.exists(ec + 'selftest'), 'no ${ec}selftest: not a self-test kernel, or no controller found') {
		return
	}
	if !hot_deep_offered(mut t) {
		return
	}
	ec_check_word(mut t, ec + 'events', 'gpe')
	ec_check_word(mut t, ec + 'failed', '0')
	ec_check_word(mut t, ec_device + 'power/wakeup', 'enabled')
	write_text(ec_lid + 'action', 'ignore') or { t.check(false, 'lid action: ${err}') }

	// Before any sleep the chipset's event reaches the driver.
	gpes := ec_count('gpe_count')
	queries := ec_count('queries')
	ec_sim(mut t, 'ram 2 0')
	ec_sim(mut t, 'event 0x22')
	t.step('controller event before the sleep')
	t.check(ec_wait_word(ec_lid + 'state', 'closed', 10000), 'the lid is ${read_word(ec_lid + 'state')} after it shut, before any sleep')
	t.check(ec_count('gpe_count') == gpes + 1, 'gpe_count went from ${gpes} to ${ec_count('gpe_count')} before any sleep')

	// The lid opening would end a sleep; it stays shut through this one.
	hot_sleep(mut t, 'the first sleep', '', '', 'alarm', 1)
	ec_check_word(mut t, ec + 'failed', '0')
	ec_check_word(mut t, ec_device + 'state', 'bound')

	// A value read through the controller.
	exchanges := ec_count('transactions')
	ec_sim(mut t, 'ram 0 1') // discharging
	ec_sim_word(mut t, 4, 9000)
	sleep_ms(ec_stale_ms)
	ec_check_word(mut t, ec_battery + 'status', 'Discharging')
	ec_check_word(mut t, ec_battery + 'power_now', '9000000')
	t.check(ec_count('transactions') > exchanges, 'no exchange with the controller after the sleep')
	t.check(ec_count('timeouts') == 0, '${ec_count('timeouts')} exchanges ran out of time')

	// The chipset's event, whose enable bit went with the power.
	ec_sim(mut t, 'ram 2 1')
	ec_sim(mut t, 'event 0x22')
	t.step('controller event after the sleep')
	t.check(ec_wait_word(ec_lid + 'state', 'open', 10000), 'the lid is ${read_word(ec_lid + 'state')} after it opened: gpe_count ${ec_count('gpe_count')}, queries ${ec_count('queries')} (were ${
		gpes + 1} and ${queries + 1} before the sleep)')
	t.check(ec_count('gpe_count') == gpes + 2, 'gpe_count went from ${gpes + 1} to ${ec_count('gpe_count')} for the event after the sleep')
	t.check(ec_count('queries') == queries + 2, 'queries went from ${queries + 1} to ${ec_count('queries')}')
	t.info('after a suspend to RAM: ${ec_count('transactions') - exchanges} exchanges, and the chipset\'s event heard (gpe_count ${ec_count('gpe_count')})')

	// With wakeup disabled the event is off for the sleep; the lid that shut
	// meanwhile is found on resume.
	write_text(ec_device + 'power/wakeup', 'disabled') or { t.check(false, 'disabling wakeup: ${err}') }
	asked := ec_count('queries')
	ec_sim(mut t, 'ram 2 0')
	ec_sim(mut t, 'event 0x22')
	hot_sleep(mut t, 'the sleep with the event off', '', '', 'alarm', 2)
	t.check(ec_wait_word(ec_lid + 'state', 'closed', 3000), 'the lid that shut for the sleep is ${read_word(ec_lid +
		'state')} after it')
	t.check(ec_count('queries') == asked + 1, 'queries went from ${asked} to ${ec_count('queries')} over the sleep with the event off')
	write_text(ec_device + 'power/wakeup', 'enabled') or { t.check(false, 'enabling wakeup: ${err}') }

	// And the event is on again after that one too.
	heard := ec_count('gpe_count')
	ec_sim(mut t, 'ram 2 1')
	ec_sim(mut t, 'event 0x22')
	t.step('controller event after the second sleep')
	t.check(ec_wait_word(ec_lid + 'state', 'open', 10000), 'the lid is ${read_word(ec_lid + 'state')} after it opened again: gpe_count ${ec_count('gpe_count')}, was ${heard}')
	t.check(ec_count('gpe_count') == heard + 1, 'gpe_count went from ${heard} to ${ec_count('gpe_count')} after the second sleep')

	ec_check_word(mut t, ec + 'failed', '0')
	t.check(ec_sim_count('violations') == 0, 'the protocol was broken ${ec_sim_count('violations')} times')
	t.check(ec_sim_count('dropped') == 0, '${ec_sim_count('dropped')} queries could not be queued')
	t.check(ec_sim_count('methods_failed') == 0, '${ec_sim_count('methods_failed')} methods failed')
	t.info('in all: ${ec_count('transactions')} exchanges, ${ec_count('queries')} events, ${ec_count('timeouts')} timeouts, protocol violations ${ec_sim_count('violations')}')
}
