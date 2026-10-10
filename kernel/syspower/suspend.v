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
// checked before it is trusted to sleep. With `platform`, and `deep` selected,
// the platform's part is rehearsed as well: it goes as far down as it can
// without asking firmware, and comes back the way it does when firmware
// refuses.
//
// On the way back from a suspend to RAM the devices have been without power.
// The platform puts back what belongs to no driver -- the interrupt
// controllers, the clocks, PCI configuration space, the IOMMUs, the display
// mode -- before it returns here, and says so (devcore.set_power_lost()) for
// the drivers whose devices a suspend to idle leaves untouched.
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
	// Suspend to disk: an image of memory is written to a device and the
	// machine is switched off; a later boot goes back into the image.
	disk
}

pub enum Rehearsal {
	none
	// Stop after the devices are suspended.
	devices
	// Go all the way down for a suspend to RAM -- the processors parked, the
	// machine's state read out -- and come back without asking firmware.
	platform
}

// How long userspace is given to leave the CPUs. A thread in userspace leaves
// at its next timer interrupt; this is several time slices.
const freeze_settle_ms = u64(50)
pub const default_test_delay_ms = u64(2000)

pub struct SleepStats {
pub mut:
	success u64
	fail    u64
	// What stopped the last sleep that failed, and for a step that can fail
	// in more than one way, how.
	failed_step   string
	failed_device string
	failed_reason string
	// The last sleep that worked: what ended it, how deep it was, how long it
	// lasted, and how long the machine took to go down and to come back.
	last_wake       string
	last_depth      string
	last_sleep_ms   u64
	last_suspend_ms u64
	last_resume_ms  u64
	// How many of the sleeps that worked were suspends to RAM, and how many
	// were suspends to disk.
	deep u64
	disk u64
	// Whether the CPU state checked on the way back was as it was left, and
	// on how many processors it was last checked.
	security_checks  u64
	security_changes u64
	security_cpus    u64
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

// `reason` is a literal, or empty.
fn fail_sleep(step string, device string, reason string) {
	syspower_stats.fail++
	syspower_stats.failed_step = step
	syspower_stats.failed_reason = reason
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
	if kind == .disk && !platform_hibernate_available() {
		fail_sleep('platform', '', platform_hibernate_reason())
		return false
	}
	if !pagecache.sync_all() {
		fail_sleep('sync', '', '')
		return false
	}
	// A rehearsal of the platform's part is one of a suspend to RAM: where
	// `mem` means suspend to idle the platform has no part, and the devices
	// are what is rehearsed. So they are for a suspend to disk.
	deep_wanted := kind == .deep && mem_is_deep()
	rehearsing_platform := syspower_rehearsal == .platform && deep_wanted
	rehearsing := syspower_rehearsal != .none && !rehearsing_platform
	going_deep := deep_wanted && !rehearsing
	going_disk := kind == .disk && !rehearsing
	// Either way the devices come back from having had no power.
	powering_down := going_deep || going_disk
	sched.freeze_userspace()
	devcore.sleep_ms(freeze_settle_ms)
	// What userspace wrote before it stopped. For a suspend to disk this is
	// the last thing any filesystem writes: see platform_hibernate_finish().
	if !pagecache.sync_all() && going_disk {
		fail_sleep('sync', '', '')
		sched.thaw_userspace()
		return false
	}
	// Whether the device is still the image's is asked now: after the last
	// program that could have written to it has stopped, and while it can
	// still be read -- its driver is about to be suspended with the rest.
	if going_disk && !platform_hibernate_ready() {
		fail_sleep('platform', '', platform_hibernate_failure())
		sched.thaw_userspace()
		return false
	}

	if powering_down {
		// The thread that watches hot-plug slots stays off them from here
		// until the buses are back: a port without power, or with its
		// registers not yet written back, shows cards missing that are
		// there. Asked before the bindings are frozen, so that a card on its
		// way in or out can get there.
		if !devcore.pause_pci_hotplug() {
			fail_sleep('devices', '', 'a PCI hot-plug operation would not finish')
			sched.thaw_userspace()
			return false
		}
	}
	devcore.freeze_bindings()
	if powering_down {
		// A device whose driver cannot bring it back from nothing would come
		// out of a suspend to RAM, or to disk, dead, with its driver none
		// the wiser.
		blocker := platform_deep_blocker()
		if blocker != unsafe { nil } {
			C.kprintf(c'syspower: %.*s (%.*s) cannot be powered down; no suspend to RAM or to disk\n', i32(blocker.name.len),
				blocker.name.str, i32(blocker.driver.name.len), blocker.driver.name.str)
			fail_sleep('devices', blocker.name, 'its driver cannot resume a device that lost power')
			devcore.thaw_bindings()
			devcore.resume_pci_hotplug()
			sched.thaw_userspace()
			return false
		}
	}
	refused := devcore.suspend_all()
	if refused != unsafe { nil } {
		fail_sleep('devices', refused.name, 'its driver refused')
		devcore.thaw_bindings()
		if powering_down {
			devcore.resume_pci_hotplug()
		}
		sched.thaw_userspace()
		return false
	}
	// Quiet is not off: what can be powered down and brought back is.
	devcore.pci_sleep_all()
	before := platform_security_state()
	syspower_stats.security_cpus = platform_security_cpus(before)
	screen_down()
	// Only now: what is seen while the machine is still going down -- the
	// release of the key that asked for the sleep, the click that chose it
	// from a menu -- is not a reason to come straight back.
	wakesrc.arm()
	asleep := devcore.now_ns()

	mut slept := true
	mut from_disk := false
	if rehearsing {
		devcore.sleep_ms(test_delay_ms())
	} else if going_deep {
		slept = platform_deep_sleep()
	} else if going_disk {
		match platform_hibernate() {
			.resumed {
				// This kernel has been put back into memory by a later
				// boot. From here it is a wake from a sleep that cut the
				// power, and the write that asked for the sleep returns.
				from_disk = true
			}
			.snapshotted {
				// The machine is as it was a moment ago, and that moment is
				// held in memory. With the devices back and userspace still
				// frozen it is written to its device, and the machine is
				// switched off. If this returns, neither happened.
				devcore.resume_all()
				platform_hibernate_finish()
				slept = false
			}
			.failed {
				slept = false
			}
		}
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
	devcore.set_power_lost(false)
	devcore.thaw_bindings()
	if powering_down {
		// The slots are looked at again, now: a card pulled or put in while
		// the machine slept is found by comparing each slot with its port.
		devcore.resume_pci_hotplug()
	}
	mut woken_by := if rehearsing || rehearsing_platform { 'rehearsal' } else { 'unknown' }
	if source := wakesrc.disarm() {
		if !rehearsing && !rehearsing_platform {
			woken_by = wakesrc.name(source)
		}
	}
	if from_disk {
		// Whatever a wake source reported on the way back, what ended this
		// sleep was the machine being switched on.
		woken_by = 'resume-from-disk'
	}
	sched.thaw_userspace()
	done := devcore.now_ns()
	// Woken by a battery about to give out: now that init runs again, ask
	// for the shutdown the battery woke the machine for.
	if katomic.cas(mut &syspower_critical_wake, u32(1), u32(0)) {
		request_power_off()
	}

	if !slept {
		fail_sleep('platform', '', if going_disk {
			platform_hibernate_failure()
		} else {
			platform_deep_failure()
		})
		return false
	}
	syspower_stats.success++
	if going_deep && !rehearsing_platform {
		syspower_stats.deep++
	}
	if from_disk {
		syspower_stats.disk++
	}
	syspower_stats.last_depth = if rehearsing || rehearsing_platform {
		'rehearsal'
	} else if going_deep {
		'deep'
	} else if going_disk {
		'disk'
	} else {
		's2idle'
	}
	syspower_stats.last_wake = woken_by
	syspower_stats.last_suspend_ms = (asleep - started) / devcore.millisecond
	// What the kernel's clock saw of the sleep, and what it could not: the
	// time a suspend to RAM kept the machine away.
	syspower_stats.last_sleep_ms = (woke - asleep) / devcore.millisecond + if going_deep {
		platform_deep_away_ms()
	} else if going_disk {
		platform_hibernate_away_ms()
	} else {
		u64(0)
	}
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
