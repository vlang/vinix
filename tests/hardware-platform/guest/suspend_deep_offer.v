// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// suspend-deep-undrawable, suspend-deep-forced and suspend-deep-headless:
// when a suspend to RAM is offered at all.
//
// After S3 firmware does not set the display mode again, and the kernel can
// do it for one adapter only. On a machine with a screen on any other, the
// kernel would come back running and dark, so there `deep` is not offered:
// mem_sleep lists s2idle alone, selecting deep is refused, and deep_sleep
// says why. The kernel command line can overrule that
// (vinix.deep_sleep=force), for someone who knows the machine has no use for
// its screen, and a machine with no framebuffer at all has nothing to lose
// and is offered deep without being asked.
//
// The machines here have QEMU's VirtIO display, which the kernel does not
// drive, or no display.
module main

fn deep_offer() (string, string) {
	report := read_text('/sys/power/deep_sleep') or { '' }
	return read_word('/sys/power/mem_sleep'), report.all_before('\n')
}

// One suspend to RAM, ended by the clock's alarm.
fn one_deep_sleep(mut t Test) {
	write_text('/sys/power/mem_sleep', 'deep') or { t.check(false, 'selecting deep: ${err.msg()}') }
	t.check(read_word('/sys/power/mem_sleep') == 's2idle [deep]', 'deep did not stick: "${read_word('/sys/power/mem_sleep')}"')
	write_text('/sys/class/rtc/rtc0/wakealarm', '+2') or { t.check(false, 'wakealarm: ${err.msg()}') }
	write_text('/sys/power/state', 'mem') or { t.check(false, 'writing mem to state: ${err.msg()}') }
	t.check(deep_stat('last_depth') == 'deep' && deep_stat('last_wake') == 'alarm', 'the sleep is recorded as ${deep_stat('last_depth')}, woken by ${deep_stat('last_wake')}')
	t.check(deep_stat('success') == '1' && deep_stat('fail') == '0', 'success is ${deep_stat('success')} and fail ${deep_stat('fail')}')
	t.check(deep_stat('security_changes') == '0', 'CPU protections changed across the sleep')
	t.check(deep_report('cycles') == 1 && deep_report('processors lost') == 0, 'deep_sleep counts ${deep_report('cycles')} cycles and ${deep_report('processors lost')} processors lost')
	t.check(deep_report('display restored') == 0, 'a display was restored on a machine where the kernel can restore none')
	t.info('slept ${deep_stat('last_sleep_ms')} ms and woke by ${deep_stat('last_wake')}; ${deep_report('pci registers rewritten')} PCI registers written back')
}

fn scenario_suspend_deep_undrawable(mut t Test) {
	offered, why := deep_offer()
	t.info('mem_sleep: ${offered}; deep_sleep: ${why}')
	t.check(offered == '[s2idle]', 'mem_sleep offers "${offered}" on a machine whose display the kernel cannot bring back')
	t.check(why.starts_with('unavailable: ') && why.contains('display'), 'deep_sleep does not say the display is why: "${why}"')
	mut refused := false
	write_text('/sys/power/mem_sleep', 'deep') or { refused = true }
	t.check(refused && read_word('/sys/power/mem_sleep') == '[s2idle]', 'deep could be selected')
	// `mem` is suspend to idle here, and works.
	write_text('/sys/class/rtc/rtc0/wakealarm', '+2') or { t.check(false, 'wakealarm: ${err.msg()}') }
	write_text('/sys/power/state', 'mem') or { t.check(false, 'writing mem to state: ${err.msg()}') }
	t.check(deep_stat('last_depth') == 's2idle' && deep_stat('last_wake') == 'alarm', 'mem slept as ${deep_stat('last_depth')}, woken by ${deep_stat('last_wake')}')
	t.check(deep_stat('deep') == '0' && deep_report('cycles') == 0, 'a suspend to RAM was counted')
}

fn scenario_suspend_deep_forced(mut t Test) {
	offered, why := deep_offer()
	t.info('mem_sleep: ${offered}; deep_sleep: ${why}')
	t.check(offered == '[s2idle] deep' && why == 'available', 'vinix.deep_sleep=force did not make deep available: "${offered}", "${why}"')
	one_deep_sleep(mut t)
}

fn scenario_suspend_deep_headless(mut t Test) {
	offered, why := deep_offer()
	t.info('mem_sleep: ${offered}; deep_sleep: ${why}')
	t.check(C.open(c'/dev/fb0', C.O_RDONLY) < 0, 'the machine has a framebuffer')
	t.check(offered == '[s2idle] deep' && why == 'available', 'a machine with no display is not offered deep: "${offered}", "${why}"')
	one_deep_sleep(mut t)
}
