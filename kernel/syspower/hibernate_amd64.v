// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Suspend to disk on a PC: the machine's part.
//
// It is a suspend to RAM with the RAM taken out. The sequence in suspend.v
// has flushed the caches, frozen userspace and suspended every device, as it
// does for any sleep. Then, here:
//
//  1. the thread moves to the boot processor, which is the one a later boot
//     will be running on when it comes back into this kernel;
//  2. free pages are taken for a copy of every page in use
//     (hibernate.prepare());
//  3. every other processor is parked, and PCI configuration space and the
//     display's mode are read out;
//  4. with interrupts off the interrupt controllers and the clocks are read
//     out and the processor is saved, exactly as for a suspend to RAM -- and
//     where that would ask firmware for the sleep, memory is copied instead
//     (hibernate.take_snapshot()).
//
// The copy is the machine at that instant, and two kernels come out of step
// 4. The one that took the copy carries on at once, as from a sleep that
// firmware refused: nothing lost power, its processors start again, its
// devices are resumed, and with userspace still frozen it writes the copy to
// the device named for it and switches the machine off (finish(), below).
// The other is the copy itself, entered by a later boot from the device
// (hibernate/resume_amd64.v). For it the saved processor returns a second
// time, as it does after a suspend to RAM, into a machine that has been
// through power-off and firmware since: everything is put back as on the way
// back from S3 -- interrupt controllers, the timer chip, the clock from
// where it stopped, the IOMMUs, the other processors, the wall clock by the
// battery-backed clock, PCI configuration space as this kernel had it, the
// display mode -- less what only an S3 needs, since firmware was not asked
// for a sleeping state and has no wake method to run. What ACPI hardware
// loses with the power is the enable bits of its events, which are written
// again from what the kernel has on record.
//
// What is refused is what a suspend to RAM refuses, for the same reason --
// a bound PCI device whose driver cannot bring it back from nothing -- with
// one difference. A suspend to RAM needs a display the kernel can set a mode
// on, because firmware does not set one on the way back from S3. A machine
// that is switched off and on is given its mode by firmware and the boot
// loader as on any boot; what the image needs is the same framebuffer in the
// same place, which is one of the things a boot is compared on before an
// image is entered. So the display does not decide whether hibernation is
// offered.
@[has_globals]
module syspower

import acpisync
import devcore
import dma
import hibernate
import katomic
import lib
import proc
import sched
import time
import uacpi
import x86.apic
import x86.cpu
import x86.hpet as hpet_clock
import x86.rtc
import x86.wake

enum HibernateOutcome {
	// No snapshot was taken, and nothing is held: a failed sleep.
	failed
	// The snapshot is in memory and this is the kernel that took it.
	snapshotted
	// This is the kernel inside an image, entered by a later boot.
	resumed
}

__global (
	syspower_hibernate_failure string
	// How long the last suspend to disk kept the machine away, by the
	// battery-backed clock, and how many there have been.
	syspower_hibernate_away_ns u64
	syspower_hibernate_cycles  u64
)

fn hibernate_failed(why string) HibernateOutcome {
	syspower_hibernate_failure = why
	C.kprintf(c'syspower: suspend to disk failed: %.*s\n', i32(why.len), why.str)
	return .failed
}

// Whether `disk` is offered: a device was named for the image, is there, and
// is this system's to write; and the kernel has the entry a processor comes
// back through.
fn platform_hibernate_available() bool {
	return platform_hibernate_reason().len == 0
}

// Why not, or ''.
fn platform_hibernate_reason() string {
	if !wake.available() {
		return wake.unavailable_reason()
	}
	return hibernate.unavailable_reason()
}

fn platform_hibernate_supported() bool {
	return true
}

fn platform_hibernate_failure() string {
	return syspower_hibernate_failure
}

fn platform_hibernate_away_ms() u64 {
	return syspower_hibernate_away_ns / devcore.millisecond
}

fn platform_hibernate() HibernateOutcome {
	syspower_hibernate_failure = ''
	syspower_hibernate_away_ns = 0
	// A later boot enters the image on the processor the machine boots on.
	mut me := proc.current_thread()
	affinity := katomic.load(&me.affinity_mask)
	katomic.store(mut &me.affinity_mask, u64(1))
	sched.wake_cpu(0)
	mut outcome := HibernateOutcome.failed
	if devcore.sleep_until(on_boot_cpu, voidptr(me), move_timeout_ns, 1) {
		outcome = hibernate_here()
	} else {
		hibernate_failed('could not move to the boot processor')
	}
	katomic.store(mut &me.affinity_mask, affinity)
	return outcome
}

// On the boot processor, pinned there.
fn hibernate_here() HibernateOutcome {
	if !hibernate.prepare() {
		return hibernate_failed(hibernate.failure())
	}
	mut slept := false
	mut why := ''
	mut away_seconds := u64(0)
	if !wake.park_secondaries() {
		why = 'a processor would not park'
	} else if !devcore.sleep_until(events_quiet, unsafe { nil }, quiet_timeout_ns, 1) {
		why = 'firmware events would not fall quiet'
	} else if !deep_save_devices() {
		why = 'no memory to keep the PCI configuration in'
	} else {
		ints := cpu.interrupt_toggle(false)
		before_clock := rtc.now() or { u64(0) }
		if !uacpi.events_idle() {
			why = 'firmware events would not fall quiet'
		} else if !apic.io_apic_save() {
			why = 'no memory for the interrupt routes'
		} else {
			before_ns := hpet_clock.nanoseconds()
			hibernate.set_taken_at(before_clock)
			slept = wake.sleep_processor(hibernate.take_snapshot)
			if slept {
				// The kernel inside the image, in a machine that has been
				// switched off and started since. Nobody else is running to
				// let go of a lock ACPI's code might wait for.
				acpisync.forbid_waiting()
				apic.io_apic_restore()
				time.pit_resume()
				after_clock := rtc.now() or { u64(0) }
				if before_clock != 0 && after_clock > before_clock {
					away_seconds = after_clock - before_clock
				}
				// The counter carries on from where it stopped, as after
				// a suspend to RAM.
				hpet_clock.resume(before_ns)
				// The press that switched the machine on is not a press.
				uacpi.take_wake_status()
				acpisync.allow_waiting()
				// Before anything on the bus may move.
				dma.resume_units()
			} else if !hibernate.snapshot_taken() {
				why = hibernate.failure()
			}
		}
		wake.start_secondaries()
		cpu.interrupt_toggle(ints)
	}
	// Those that parked while another would not; nothing when all are back.
	wake.start_secondaries()
	sched.wake_cpu(0)
	if slept {
		syspower_hibernate_cycles++
		syspower_hibernate_away_ns = away_seconds * devcore.second
		// What the snapshot held is given back, and what the kernel that
		// loaded the image had to say is read.
		hibernate.resumed()
		time.advance_realtime(syspower_hibernate_away_ns)
		// For the drivers that resume next: their devices are blank.
		devcore.set_power_lost(true)
		// Firmware numbered the buses and placed the devices again; what
		// this kernel's drivers know is where they were.
		deep_restore_devices()
		// The enable bits of ACPI's events, which this kernel had set and a
		// later boot did not, or not yet.
		uacpi.resume_events()
		alarm_skipped(syspower_hibernate_away_ns)
		C.kprintf(c'syspower: back from disk after about %llu s\n', away_seconds)
		if wake.lost_processors() != 0 {
			C.kprintf(c'syspower: %llu processors have not come back from a sleep\n', wake.lost_processors())
		}
		return .resumed
	}
	display_discard()
	if why.len != 0 {
		hibernate.release()
		return hibernate_failed(why)
	}
	return .snapshotted
}

// The kernel that took the snapshot, with its devices resumed and userspace
// frozen: write the image and switch the machine off. Returns only when that
// did not happen, with nothing held, no image on the device, and the reason
// kept.
fn platform_hibernate_finish() {
	if !hibernate.write_image() {
		why := hibernate.failure()
		hibernate.release()
		hibernate_failed(why)
		return
	}
	// Not transition(): its first step is to flush the filesystems, and what
	// reaches a disk after the snapshot is what the image must never find
	// changed. They were flushed before the snapshot; the devices' own
	// caches are flushed by their shutdown.
	carry_out(.power_off)
	// Still here. The image describes a machine this kernel is about to
	// carry on changing; it must not be entered later.
	if !hibernate.withdraw_image() {
		print('syspower: THE IMAGE COULD NOT BE WITHDRAWN and must not be resumed: clear the device before the next start\n')
	}
	hibernate.release()
	hibernate_failed('the machine did not switch off')
}

// The lines of /sys/power/hibernate after the first.
fn platform_hibernate_report(mut text lib.Text) {
	hibernate.report(mut text)
	report_line(mut text, 'cycles', syspower_hibernate_cycles)
	report_line(mut text, 'away ms', platform_hibernate_away_ms())
}
