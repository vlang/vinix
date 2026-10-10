// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Putting the machine to sleep and bringing it back.
//
// A sleep is the same sequence whatever the machine does at the bottom of it:
//
//  1. cached writes go to their devices, so that a battery which runs out
//     during the sleep costs what a power cut would and no more;
//  2. userspace is frozen (sched/freeze.v);
//  3. the devices are suspended through the device core, last added first; a
//     driver that refuses stops the sleep, and the ones already down come
//     back;
//  4. the state the machine must have when it comes back is recorded (see
//     security_amd64.v and security_arm64.v), the screen goes dark
//     (screen.v), and wake sources start being listened to -- only now, so
//     that the release of the key that asked for the sleep does not end it;
//  5. the platform sleeps until a wake source reports;
//  6. the screen comes back, the recorded state is compared with what the
//     CPU has now, the devices are resumed, first added first, and userspace
//     thaws.
//
// Two depths are offered, by the names Linux gives them in /sys/power/state:
//
//	freeze   suspend to idle. Nothing loses power that the hardware does not
//	         take away by itself: the CPUs idle, the devices are in whatever
//	         low state their drivers put them in, and any interrupt of an
//	         allowed wake source ends it. It works on every machine.
//	mem      what /sys/power/mem_sleep selects: `s2idle`, which is the same
//	         as freeze, or `deep`, the platform's suspend to RAM, where the
//	         platform has one.
//
// A sleep can be rehearsed. With `devices` in /sys/power/pm_test the sequence
// runs through step 4, waits pm_test_delay_ms instead of sleeping, and comes
// back: every driver's suspend and resume are exercised without depending on
// anything waking the machine, which is how a new machine's drivers are
// checked before it is trusted to sleep.
@[has_globals]
module syspower

import devcore
import katomic
import pagecache
import sched
import wakesrc

pub enum SleepDepth {
	// Suspend to idle.
	idle
	// The platform's suspend to RAM.
	deep
}

pub enum Rehearsal {
	none
	// Stop after the devices are suspended.
	devices
}

// How long userspace is given to leave the CPUs. A thread in userspace leaves
// at its next timer interrupt; this is several time slices.
const freeze_settle_ms = u64(50)
pub const default_test_delay_ms = u64(2000)

pub struct SleepStats {
pub mut:
	success u64
	fail    u64
	// What stopped the last sleep that failed.
	failed_step   string
	failed_device string
	// The last sleep that worked: what ended it, how long it lasted, and how
	// long the machine took to go down and to come back.
	last_wake       string
	last_sleep_ms   u64
	last_suspend_ms u64
	last_resume_ms  u64
	// Whether the CPU state checked on the way back was as it was left.
	security_checks  u64
	security_changes u64
}

__global (
	// One sleep at a time; a second request is refused.
	syspower_sleeping   u32
	syspower_stats      SleepStats
	syspower_rehearsal  Rehearsal
	syspower_test_delay u64
	// What `mem` means; see the top of this file.
	syspower_mem_deep bool
)

pub fn stats() &SleepStats {
	return &syspower_stats
}

pub fn rehearsal() Rehearsal {
	return syspower_rehearsal
}

pub fn set_rehearsal(kind Rehearsal) {
	syspower_rehearsal = kind
}

pub fn test_delay_ms() u64 {
	return if syspower_test_delay == 0 { default_test_delay_ms } else { syspower_test_delay }
}

pub fn set_test_delay_ms(ms u64) {
	syspower_test_delay = ms
}

// Whether the platform has a suspend to RAM.
pub fn deep_available() bool {
	return platform_deep_available()
}

pub fn mem_is_deep() bool {
	return syspower_mem_deep && platform_deep_available()
}

pub fn set_mem_deep(deep bool) bool {
	if deep && !platform_deep_available() {
		return false
	}
	syspower_mem_deep = deep
	return true
}

fn fail_sleep(step string, device string) {
	syspower_stats.fail++
	syspower_stats.failed_step = step
	// A copy the statistics keep: the device can go away, its name with it.
	unsafe { syspower_stats.failed_device.free() }
	syspower_stats.failed_device = if device.len == 0 { '' } else { device.clone() }
}

// Sleep. Returns when the machine is awake again: true if it slept (or
// rehearsed) and came back, false if the sleep was refused, with the reason
// in the statistics. Called from a thread, never from an interrupt.
pub fn enter_sleep(kind SleepDepth) bool {
	if !katomic.cas(mut &syspower_sleeping, u32(0), u32(1)) {
		return false
	}
	defer {
		katomic.store(mut &syspower_sleeping, u32(0))
	}
	started := devcore.now_ns()
	if !pagecache.sync_all() {
		fail_sleep('sync', '')
		return false
	}
	sched.freeze_userspace()
	devcore.sleep_ms(freeze_settle_ms)
	// What userspace wrote before it stopped.
	pagecache.sync_all()

	devcore.freeze_bindings()
	refused := devcore.suspend_all()
	if refused != unsafe { nil } {
		fail_sleep('devices', refused.name)
		devcore.thaw_bindings()
		sched.thaw_userspace()
		return false
	}
	before := platform_security_state()
	screen_down()
	// Only now: what is seen while the machine is still going down -- the
	// release of the key that asked for the sleep, the click that chose it
	// from a menu -- is not a reason to come straight back.
	wakesrc.arm()
	asleep := devcore.now_ns()

	rehearsing := syspower_rehearsal == .devices
	mut slept := true
	if rehearsing {
		devcore.sleep_ms(test_delay_ms())
	} else if kind == .deep && mem_is_deep() {
		slept = platform_deep_sleep()
	} else {
		platform_idle_sleep()
	}

	woke := devcore.now_ns()
	screen_up()
	syspower_stats.security_checks++
	if security_changed(before) {
		// Not survivable silently: the machine came back without a
		// protection it went down with.
		syspower_stats.security_changes++
		platform_security_restore(before)
		if security_changed(before) {
			panic('syspower: CPU protections were lost across a sleep and could not be restored')
		}
		print('syspower: CPU protections changed across a sleep; restored\n')
	}
	devcore.resume_all()
	devcore.thaw_bindings()
	mut woken_by := if rehearsing { 'rehearsal' } else { 'unknown' }
	if source := wakesrc.disarm() {
		if !rehearsing {
			woken_by = wakesrc.name(source)
		}
	}
	sched.thaw_userspace()
	done := devcore.now_ns()
	// Woken by a battery about to give out: now that init runs again, ask
	// for the shutdown the battery woke the machine for.
	if katomic.cas(mut &syspower_critical_wake, u32(1), u32(0)) {
		request_power_off()
	}

	if !slept {
		fail_sleep('platform', '')
		return false
	}
	syspower_stats.success++
	syspower_stats.last_wake = woken_by
	syspower_stats.last_suspend_ms = (asleep - started) / devcore.millisecond
	syspower_stats.last_sleep_ms = (woke - asleep) / devcore.millisecond
	syspower_stats.last_resume_ms = (done - woke) / devcore.millisecond
	return true
}

// Whether a sleep is in progress.
pub fn sleeping() bool {
	return katomic.load(&syspower_sleeping) != 0
}

// Suspend to idle: the calling thread waits for a wake source, and with
// userspace frozen and the devices down the CPUs have nothing else to do and
// idle. Returns when a wake source has reported.
fn platform_idle_sleep() {
	wakesrc.wait()
}
