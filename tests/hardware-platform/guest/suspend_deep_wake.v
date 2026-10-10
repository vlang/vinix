// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// suspend-deep-wake: the devices that may end a suspend to RAM are made able
// to.
//
// The machine has a table (wake-bench in hwhost/acpi_bench.v) with a lid, a
// sleep button and a power button, each saying in _PRW by which event it
// wakes the machine and from how deep a sleep: the lid from S3, the sleep
// button from S4, the power button from S1 only. For a suspend to RAM the
// kernel must leave the first two events enabled when it switches the rest
// off, tell each device through its method (_PSW for the lid, _DSW for the
// button), and leave the power button alone -- it cannot end a sleep that
// deep -- and afterwards tell both they need not any more. With the lid not
// allowed as a wake source, the lid is left alone too.
//
// QEMU cannot be woken through such an event, so the machine is woken by the
// clock. What is checked is what would have let the lid wake it:
//
//   - while the machine is suspended, the controller reads the register that
//     enables the events (the third byte of the block: events 0x10 to 0x17):
//     the lid's and the sleep button's bits and no other, then the sleep
//     button's alone;
//   - the methods write what they were called with to a port QEMU records,
//     and the controller compares the file once the machine has ended: the
//     order, the arguments, and that the power button's was never run;
//   - /sys/power/acpi_wakeup says the same from the kernel's side.
module main

const wakeup_report = '/sys/power/acpi_wakeup'

// The line of /sys/power/acpi_wakeup about the device called `name`.
fn wakeup_line(name string) string {
	text := read_text(wakeup_report) or { return '' }
	for line in text.split_into_lines() {
		if line.starts_with(name + ' ') {
			return line
		}
	}
	return ''
}

// The directory in /sys/class/wakeup of the wake source called `name`.
fn wake_source_called(name string) string {
	entries := list_dir('/sys/class/wakeup') or { return '' }
	for entry in entries {
		if read_word('/sys/class/wakeup/${entry}/name') == name {
			return '/sys/class/wakeup/${entry}/'
		}
	}
	return ''
}

fn wakeup_is(mut t Test, name string, expected string, when string) {
	found := wakeup_line(name)
	t.check(found == expected, '${when}: acpi_wakeup says "${found}", not "${expected}"')
}

// One suspend to RAM ended by the clock, after the step the controller
// waits for.
fn wake_sleep(mut t Test, step string, successes int) {
	write_text('/sys/class/rtc/rtc0/wakealarm', '+4') or { t.check(false, 'wakealarm: ${err.msg()}') }
	t.step(step)
	write_text('/sys/power/state', 'mem') or { t.check(false, 'writing mem to state: ${err.msg()}') }
	t.check(deep_stat('last_depth') == 'deep' && deep_stat('last_wake') == 'alarm', '${step}: the sleep is recorded as ${deep_stat('last_depth')}, woken by ${deep_stat('last_wake')}')
	t.check(deep_stat('success') == successes.str() && deep_stat('fail') == '0', '${step}: success is ${deep_stat('success')} and fail ${deep_stat('fail')}')
}

fn scenario_suspend_deep_wake(mut t Test) {
	offered, why := deep_offer()
	if !t.check(offered.contains('deep'), 'mem_sleep does not offer deep: "${offered}" (${why})') {
		return
	}
	write_text('/sys/power/mem_sleep', 'deep') or { t.check(false, 'selecting deep: ${err.msg()}') }
	wakeup_is(mut t, 'LID0', 'LID0 lid S3 gpe 0x10 armed 0 times', 'at boot')
	wakeup_is(mut t, 'BTNP', 'BTNP power-button S1 gpe 0x12 armed 0 times', 'at boot')
	wakeup_is(mut t, 'BTNS', 'BTNS sleep-button S4 gpe 0x11 armed 0 times', 'at boot')
	t.check(read_word('/sys/power/lid/state') == 'closed', 'the lid is "${read_word('/sys/power/lid/state')}" at boot, not closed')
	t.step('awake, nothing armed')
	sleep_ms(500)

	// A rehearsal goes the whole way down without telling firmware: nothing
	// is armed, and no method runs.
	write_text('/sys/power/pm_test', 'platform') or { t.check(false, 'pm_test: ${err.msg()}') }
	write_text('/sys/power/pm_test_delay_ms', '500') or { t.check(false, 'pm_test_delay_ms: ${err.msg()}') }
	write_text('/sys/power/state', 'mem') or { t.check(false, 'the rehearsal: ${err.msg()}') }
	write_text('/sys/power/pm_test', 'none') or { t.check(false, 'pm_test: ${err.msg()}') }
	t.check(deep_stat('success') == '1', 'the rehearsal: success is ${deep_stat('success')}')
	wakeup_is(mut t, 'LID0', 'LID0 lid S3 gpe 0x10 armed 0 times', 'after the rehearsal')
	wakeup_is(mut t, 'BTNS', 'BTNS sleep-button S4 gpe 0x11 armed 0 times', 'after the rehearsal')
	t.check(read_word('/sys/power/lid/state') == 'closed', 'the lid is "${read_word('/sys/power/lid/state')}" after the rehearsal, not closed')

	wake_sleep(mut t, 'deep sleep, lid and sleep button armed', 2)
	wakeup_is(mut t, 'LID0', 'LID0 lid S3 gpe 0x10 told by _PSW armed 1 times', 'after the first sleep')
	wakeup_is(mut t, 'BTNS', 'BTNS sleep-button S4 gpe 0x11 told by _DSW armed 1 times', 'after the first sleep')
	wakeup_is(mut t, 'BTNP', 'BTNP power-button S1 gpe 0x12 armed 0 times', 'after the first sleep')
	// The table opened the lid during the sleep and sent no notification:
	// the kernel asked.
	t.check(read_word('/sys/power/lid/state') == 'open', 'the lid is "${read_word('/sys/power/lid/state')}" after a sleep during which it was opened')

	// The lid may no longer end a sleep: it is not armed for the next one.
	lid := wake_source_called('lid')
	if !t.check(lid != '', 'no wake source is called lid') {
		return
	}
	write_text(lid + 'enabled', 'disabled') or { t.check(false, 'disabling the lid: ${err.msg()}') }
	wake_sleep(mut t, 'deep sleep, the lid not allowed', 3)
	wakeup_is(mut t, 'LID0', 'LID0 lid S3 gpe 0x10 told by _PSW armed 1 times', 'after the second sleep')
	wakeup_is(mut t, 'BTNS', 'BTNS sleep-button S4 gpe 0x11 told by _DSW armed 2 times', 'after the second sleep')
	wakeup_is(mut t, 'BTNP', 'BTNP power-button S1 gpe 0x12 armed 0 times', 'after the second sleep')
	t.check(deep_stat('security_changes') == '0', 'CPU protections changed across a sleep')
}

// The same machine told to leave wake devices alone: there is no list of
// them, and a suspend to RAM goes down with none of their events on -- which
// the controller reads -- and without any of their methods having been run.
fn scenario_suspend_deep_wake_off(mut t Test) {
	offered, why := deep_offer()
	if !t.check(offered.contains('deep'), 'mem_sleep does not offer deep: "${offered}" (${why})') {
		return
	}
	write_text('/sys/power/mem_sleep', 'deep') or { t.check(false, 'selecting deep: ${err.msg()}') }
	mut listed := true
	read_text(wakeup_report) or { listed = false }
	t.check(!listed, '${wakeup_report} exists with vinix.acpi_wake=off')
	wake_sleep(mut t, 'deep sleep, nothing armed', 1)
}
