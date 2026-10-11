// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// acpi-backlight: a panel's backlight, set through firmware.
//
// QEMU's PC has no panel, so the controller gives it a table with one
// (backlight-bench in hwhost/acpi_bench.v): five levels, listed as firmware
// lists them -- the two it would choose itself first, the rest in no order
// -- and a method that sets one and writes down what it was given, on a port
// QEMU records. Two of the levels stand for a brightness key: asked for the
// second, the panel reports "brighter" as it is set, and asked for the top
// one, "dimmer".
//
// What is checked here is what /sys/class/backlight says at each step. What
// firmware was actually told, and in which order, the controller reads off
// the record once the machine has ended (backlight_said in scenario.v): this
// program cannot see that, and a kernel that kept the level to itself would
// pass everything below.
module main

#include <fcntl.h>

const backlight = '/sys/class/backlight/acpi_video0/'
// Writes measured for what they leave allocated in the kernel.
const backlight_writes = 200

fn backlight_word(file string) string {
	return read_word(backlight + file)
}

fn backlight_is(mut t Test, asked string, actual string, what string) {
	t.check(backlight_word('brightness') == asked, '${what}: brightness is ${backlight_word('brightness')}, not ${asked}')
	t.check(backlight_word('actual_brightness') == actual, '${what}: actual_brightness is ${backlight_word('actual_brightness')}, not ${actual}')
}

// Waits for a brightness key the table pressed to have been acted on.
fn backlight_settles(asked string) bool {
	for _ in 0 .. 100 {
		if backlight_word('brightness') == asked {
			return true
		}
		sleep_ms(50)
	}
	return false
}

fn scenario_acpi_backlight(mut t Test) {
	// Five levels, places 0 to 4; the panel says it is at the fourth.
	t.check(backlight_word('type') == 'firmware', 'type is "${backlight_word('type')}"')
	t.check(backlight_word('max_brightness') == '4', 'max_brightness is ${backlight_word('max_brightness')}, not 4: the levels were not told from the two firmware prefers')
	t.check(backlight_word('bl_power') == '0', 'bl_power is ${backlight_word('bl_power')} at boot')
	backlight_is(mut t, '3', '3', 'at boot')
	// The second panel: three levels with nothing in front of them, and no
	// way to ask it, so it is shown at its brightest and known to be nowhere.
	second := '/sys/class/backlight/acpi_video1/'
	t.check(read_word(second + 'max_brightness') == '2', 'the second panel has max_brightness ${read_word(second + 'max_brightness')}, not 2: its first two levels were taken for the preferred ones')
	t.check(read_word(second + 'brightness') == '2' && read_word(second + 'actual_brightness') == '2', 'the second panel is at ${read_word(second + 'brightness')} (${read_word(second + 'actual_brightness')}), not 2')

	write_text(backlight + 'brightness', '0') or { t.check(false, 'brightness 0: ${err.msg()}') }
	backlight_is(mut t, '0', '0', 'asked for the dimmest')

	// The second level presses "brighter" as it is set, the top one "dimmer".
	write_text(backlight + 'brightness', '1') or { t.check(false, 'brightness 1: ${err.msg()}') }
	t.check(backlight_settles('2'), 'the brighter key was not acted on: brightness is ${backlight_word('brightness')}')
	backlight_is(mut t, '2', '2', 'after the brighter key')
	write_text(backlight + 'brightness', '4') or { t.check(false, 'brightness 4: ${err.msg()}') }
	t.check(backlight_settles('3'), 'the dimmer key was not acted on: brightness is ${backlight_word('brightness')}')
	backlight_is(mut t, '3', '3', 'after the dimmer key')

	// Off is the dimmest level there is; what was asked for is kept.
	write_text(backlight + 'bl_power', '4') or { t.check(false, 'bl_power 4: ${err.msg()}') }
	backlight_is(mut t, '3', '0', 'switched off')
	write_text(backlight + 'bl_power', '0') or { t.check(false, 'bl_power 0: ${err.msg()}') }
	backlight_is(mut t, '3', '3', 'switched on again')

	// A level there is not.
	mut refused := false
	write_text(backlight + 'brightness', '5') or { refused = true }
	t.check(refused, 'a level past the highest was taken')
	backlight_is(mut t, '3', '3', 'after a level that does not exist')

	// A sleep: every device suspended and resumed, the panel among them.
	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err.msg()}') }
	write_text('/sys/power/pm_test_delay_ms', '300') or { t.check(false, 'pm_test_delay_ms: ${err.msg()}') }
	write_text('/sys/power/state', 'freeze') or { t.check(false, 'the rehearsal: ${err.msg()}') }
	write_text('/sys/power/pm_test', 'none') or { t.check(false, 'pm_test: ${err.msg()}') }
	t.check(stat_word('success') == '1', 'the rehearsal failed: step "${stat_word('last_failed_step')}", device "${stat_word('last_failed_dev')}"')
	backlight_is(mut t, '3', '3', 'after the sleep')
	stats := read_text(backlight + 'stats') or { '' }
	t.check(stats.contains('sleeps: 1\n') && stats.contains('failures: 0\n'), 'stats after one sleep: "${stats.replace('\n', '; ')}"')

	// The second panel was left as it was: nobody knew what to give it back.
	// Once it has been set it goes down with the other and comes back.
	t.check((read_text(second + 'stats') or { '' }).contains('sleeps: 0\n'), 'a panel at a level nobody knew was put down for a sleep')
	write_text(second + 'brightness', '1') or { t.check(false, 'the second panel, brightness 1: ${err.msg()}') }
	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err.msg()}') }
	write_text('/sys/power/state', 'freeze') or { t.check(false, 'the second rehearsal: ${err.msg()}') }
	write_text('/sys/power/pm_test', 'none') or { t.check(false, 'pm_test: ${err.msg()}') }
	t.check(stat_word('success') == '2', 'the second rehearsal failed: step "${stat_word('last_failed_step')}"')
	backlight_is(mut t, '3', '3', 'after the second sleep')
	t.check(read_word(second + 'brightness') == '1' && read_word(second + 'actual_brightness') == '1', 'the second panel is at ${read_word(second + 'brightness')} (${read_word(second + 'actual_brightness')}) after a sleep, not 1')
	t.check((read_text(second + 'stats') or { '' }).contains('sleeps: 1\n'), 'the second panel was not put down for the second sleep')

	// What setting a level leaves behind. Written with nothing allocated
	// here: this program's own heap growing costs the kernel objects too.
	fd := C.open(c'/sys/class/backlight/acpi_video0/brightness', C.O_WRONLY)
	if !t.check(fd >= 0, 'brightness cannot be opened for writing') {
		return
	}
	before := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	mut wrote := 0
	for i in 0 .. backlight_writes {
		level := if i % 2 == 0 { c'0' } else { c'2' }
		if C.pwrite(fd, level, 1, 0) == 1 {
			wrote++
		}
	}
	after := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	C.close(fd)
	t.check(wrote == backlight_writes, 'only ${wrote} of ${backlight_writes} writes of a level were taken')
	t.check(after.objects - before.objects <= heap_noise_objects, '${backlight_writes} levels set left ${after.objects - before.objects} more heap objects allocated (limit ${heap_noise_objects})')
	t.info('heap objects: ${before.objects} before ${backlight_writes} levels were set, ${after.objects} after')
	backlight_is(mut t, '2', '2', 'at the end')
}

// The same machine with vinix.acpi_backlight=off: no panel is listed, and a
// sleep goes by without firmware being told anything, which the controller
// reads off an empty record.
fn scenario_acpi_backlight_off(mut t Test) {
	entries := list_dir('/sys/class/backlight') or { []string{} }
	t.check(entries.len == 0, '/sys/class/backlight lists ${entries.len} panels with vinix.acpi_backlight=off')
	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err.msg()}') }
	write_text('/sys/power/pm_test_delay_ms', '300') or { t.check(false, 'pm_test_delay_ms: ${err.msg()}') }
	write_text('/sys/power/state', 'freeze') or { t.check(false, 'the rehearsal: ${err.msg()}') }
	t.check(stat_word('success') == '1', 'the rehearsal failed: step "${stat_word('last_failed_step')}", device "${stat_word('last_failed_dev')}"')
}
