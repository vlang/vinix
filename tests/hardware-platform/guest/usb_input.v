// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// usb-input: a keyboard and a mouse on USB, behind an xHCI controller.
//
// The machine has a qemu-xhci controller with a keyboard and a mouse plugged
// into its root ports. The controller types "a" and Enter and moves the mouse
// when asked (QMP), and the console and /dev/pointer must show it -- the same
// two checks the suspend-to-RAM scenario makes of a PS/2 keyboard and mouse.
// On the PC there is no keyboard controller at all (i8042=off), so a key can
// have come no other way; on AArch64, where the machine also has VirtIO
// input, the driver's own count of reports must have gone up.
//
// Then the sleeps. A rehearsal, after which both still work. A suspend to
// idle, which a key on the USB keyboard must end: the controller is left
// running for that. And, where there is one, a suspend to RAM: the
// controller loses its power and everything it was told, and must be found
// halted and set up again from nothing -- counted in /sys/bus/usb/xhci --
// with the keyboard and the mouse back, and with the memory it was given the
// first time given back, which three more such sleeps are measured for.
module main

const usb_stats = '/sys/bus/usb/xhci'

// The number on the line of /sys/bus/usb/xhci that starts with `name`.
fn usb_stat(name string) int {
	text := read_text(usb_stats) or { return -1 }
	for line in text.split_into_lines() {
		if line.starts_with(name + ':') {
			return line.all_after(':').trim_space().int()
		}
	}
	return -1
}

// Type and move, and see that it was the USB devices that said so.
fn usb_works(mut t Test, mut run DeepRun, when string) {
	keys := usb_stat('keyboard reports')
	run.check_keyboard(mut t, when)
	t.check(usb_stat('keyboard reports') > keys, '${when}: the USB keyboard reported nothing (${keys} reports before, ${usb_stat('keyboard reports')} after)')
	moves := usb_stat('pointer reports')
	run.check_pointer(mut t, when)
	t.check(usb_stat('pointer reports') > moves, '${when}: the USB mouse reported nothing (${moves} reports before, ${usb_stat('pointer reports')} after)')
}

fn scenario_usb_input(mut t Test) {
	t.check(usb_stat('keyboards') == 1 && usb_stat('pointers') == 1, 'the controller has ${usb_stat('keyboards')} keyboards and ${usb_stat('pointers')} pointers, not one of each')
	t.check(bound_devices('xhci') == 1, '${bound_devices('xhci')} devices are bound to xhci, not one')
	mut run := DeepRun{
		keyboard: C.open(c'/dev/console', C.O_RDONLY)
		pointer:  C.open(c'/dev/pointer', C.O_RDONLY)
	}
	if !t.check(run.keyboard >= 0 && run.pointer >= 0, '/dev/console or /dev/pointer cannot be opened') {
		return
	}
	usb_works(mut t, mut run, 'before any sleep')

	// A rehearsal: every device suspended and resumed.
	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err.msg()}') }
	write_text('/sys/power/pm_test_delay_ms', '300') or { t.check(false, 'pm_test_delay_ms: ${err.msg()}') }
	write_text('/sys/power/state', 'freeze') or { t.check(false, 'the rehearsal: ${err.msg()}') }
	write_text('/sys/power/pm_test', 'none') or { t.check(false, 'pm_test: ${err.msg()}') }
	t.check(stat_word('success') == '1', 'the rehearsal failed: step "${stat_word('last_failed_step')}", device "${stat_word('last_failed_dev')}"')
	t.check(usb_stat('set up again') == 0, 'the controller was set up again after a rehearsal, in which it lost nothing')
	usb_works(mut t, mut run, 'after the rehearsal')

	// A suspend to idle. The alarm is only there so that a key that does
	// not wake the machine fails the test instead of hanging it.
	write_text('/sys/class/rtc/rtc0/wakealarm', '+15') or { t.check(false, 'wakealarm: ${err.msg()}') }
	t.step('asleep for a key')
	took := sleep_now(mut t, 'freeze')
	t.check(stat_word('success') == '2' && stat_word('last_wake') == 'keyboard', 'the suspend to idle: ${stat_word('success')} successes, woken by ${stat_word('last_wake')}, not by the keyboard')
	t.info('a key on the USB keyboard ended a suspend to idle after ${took} ms')
	write_text('/sys/class/rtc/rtc0/wakealarm', '0') or {}

	offered, why := deep_offer()
	if !offered.contains('deep') {
		t.info('no suspend to RAM on this machine (${why})')
		usb_works(mut t, mut run, 'after the suspend to idle')
		return
	}
	// A suspend to RAM: the controller comes back blank.
	pages := usb_stat('pages')
	write_text('/sys/power/mem_sleep', 'deep') or { t.check(false, 'selecting deep: ${err.msg()}') }
	write_text('/sys/class/rtc/rtc0/wakealarm', '+4') or { t.check(false, 'wakealarm: ${err.msg()}') }
	write_text('/sys/power/state', 'mem') or { t.check(false, 'writing mem to state: ${err.msg()}') }
	t.check(stat_word('success') == '3' && deep_stat('last_depth') == 'deep', 'the suspend to RAM: ${stat_word('success')} successes, the last one "${deep_stat('last_depth')}", step "${stat_word('last_failed_step')}", device "${stat_word('last_failed_dev')}", ${stat_word('last_failed_reason')}')
	t.check(usb_stat('set up again') == 1, 'the controller was set up again ${usb_stat('set up again')} times after a suspend to RAM, not once')
	t.check(usb_stat('keyboards') == 1 && usb_stat('pointers') == 1, 'after a suspend to RAM the controller has ${usb_stat('keyboards')} keyboards and ${usb_stat('pointers')} pointers')
	t.check(usb_stat('pages') == pages, 'the controller holds ${usb_stat('pages')} pages after being set up again, ${pages} before')
	usb_works(mut t, mut run, 'after a suspend to RAM')

	// What setting it up again leaves behind.
	free_before := meminfo_kb('MemFree') or { 0 }
	heap_before := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	for _ in 0 .. 3 {
		write_text('/sys/class/rtc/rtc0/wakealarm', '+3') or { t.check(false, 'wakealarm: ${err.msg()}') }
		write_text('/sys/power/state', 'mem') or { t.check(false, 'writing mem to state: ${err.msg()}') }
	}
	heap_after := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	free_after := meminfo_kb('MemFree') or { 0 }
	t.check(usb_stat('set up again') == 4 && usb_stat('pages') == pages, 'after three more sleeps the controller was set up again ${usb_stat('set up again')} times and holds ${usb_stat('pages')} pages')
	t.check(heap_after.objects - heap_before.objects <= heap_noise_objects, 'three more sleeps left ${heap_after.objects - heap_before.objects} more heap objects allocated')
	// A page is 4 kB; the controller holds a dozen or so. Losing them every
	// time would be far more than this allows.
	t.check(free_before - free_after < 3 * pages * 4, 'three more sleeps took ${free_before - free_after} kB of free memory: the controller holds ${pages} pages')
	t.info('${pages} pages held; MemFree ${free_before} kB before three more sleeps, ${free_after} kB after')
	t.check(stat_word('fail') == '0', '${stat_word('fail')} sleeps failed')
}
