// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Suspend to RAM on a PC: ACPI's S3.
//
// Memory keeps its power and nothing else does. The sequence in suspend.v has
// by now flushed the caches, frozen userspace and suspended every device; what
// is left is the machine itself:
//
//  1. the thread carrying out the sleep moves to the boot processor, which is
//     the one firmware resumes;
//  2. firmware prepares (the _PTS method) and is told where to resume: the
//     real-mode entry in x86/wake;
//  3. an alarm that is set is handed to the battery-backed clock, the only
//     timer that runs while the machine is down;
//  4. every other processor is parked, and the configuration space of every
//     PCI function and what is on the screen are read out;
//  5. with interrupts off: the interrupt controllers and the clocks are read
//     out, the processor is saved, and firmware is asked for S3.
//
// When the machine wakes, firmware runs first, then the trampoline, and the
// processor continues after step 5 as if a call had returned. Everything is
// then put back in the order it is needed: the interrupt controllers, the
// timer chip, the counter time is kept with -- moved on by as long as the
// battery-backed clock says the machine was away -- the other processors,
// interrupts, firmware's wake method, the IOMMUs, PCI configuration space,
// the display. The devices' own drivers resume after that, back in suspend.v.
//
// A sleep that firmware does not carry out -- it returns from the request, or
// a wake source reported before it could be made -- takes the same way back,
// with nothing lost, and is counted as a failed sleep.
@[has_globals]
module syspower

import devcore
import dma
import event
import katomic
import proc
import sched
import time
import uacpi
import wakesrc
import x86.apic
import x86.cpu
import x86.hpet as hpet_clock
import x86.kio
import x86.rtc
import x86.wake

// How long the thread is given to reach the boot processor, and uACPI's event
// handling to fall quiet.
const move_timeout_ns = 2 * devcore.second
const quiet_timeout_ns = devcore.second

// The keyboard controller's status port, and what its bits say.
const i8042_status = u16(0x64)
const i8042_output_full = u8(0x01)
const i8042_from_pointer = u8(0x20)

const no_source = -1

__global (
	// Whether deep sleep is offered, worked out once, and why not.
	syspower_deep_decided bool
	syspower_deep_offered bool
	syspower_deep_reason  string
	// What stopped the last deep sleep that failed.
	syspower_deep_failure string
	// How uACPI answered the last request for S3.
	syspower_deep_status uacpi.UACPIStatus
	// How many times the machine has been through S3 and back.
	syspower_deep_cycles u64
)

// Suspend to RAM is offered when firmware has an S3 to ask for, the kernel
// has its real-mode entry in place to come back through, and what is on the
// screen can be brought back afterwards (display_amd64.v).
fn platform_deep_available() bool {
	if !syspower_deep_decided {
		decide_deep()
	}
	return syspower_deep_offered
}

fn decide_deep() {
	mut reason := ''
	policy := devcore.boot_option('vinix.deep_sleep=') or { '' }
	if policy == 'off' {
		reason = 'switched off with vinix.deep_sleep=off'
	} else if !wake.available() {
		reason = wake.unavailable_reason()
	} else if !uacpi.sleep_state_supported(uacpi.sleep_state_s3) {
		reason = 'firmware offers no S3'
	} else if policy != 'force' && !display_survives_deep() {
		reason = 'the display could not be brought back afterwards (vinix.deep_sleep=force offers it anyway)'
	}
	syspower_deep_reason = reason
	syspower_deep_offered = reason.len == 0
	syspower_deep_decided = true
	if reason.len == 0 {
		print('syspower: suspend to RAM (S3) is available\n')
	} else {
		C.kprintf(c'syspower: suspend to RAM is not offered: %.*s\n', i32(reason.len), reason.str)
	}
}

// Why deep sleep is not offered, or '' when it is.
fn platform_deep_reason() string {
	platform_deep_available()
	return syspower_deep_reason
}

// What stopped the last deep sleep that failed.
fn platform_deep_failure() string {
	return syspower_deep_failure
}

// A device that would not survive a loss of power, or nil.
fn platform_deep_blocker() &devcore.Device {
	return devcore.pci_power_down_blocker()
}

fn deep_failed(why string) bool {
	syspower_deep_failure = why
	C.kprintf(c'syspower: suspend to RAM failed: %.*s\n', i32(why.len), why.str)
	return false
}

fn on_boot_cpu(context voidptr) bool {
	asking := unsafe { &proc.Thread(context) }
	return katomic.load(&asking.running_on) == 0
}

fn events_quiet(_ voidptr) bool {
	return uacpi.events_idle()
}

// The request itself. Interrupts off.
fn enter_s3() {
	syspower_deep_status = uacpi.enter_sleep(uacpi.sleep_state_s3)
}

fn platform_deep_sleep() bool {
	syspower_deep_failure = ''
	// Firmware resumes the processor the machine boots on, so that is the
	// one that has to ask.
	mut me := proc.current_thread()
	affinity := katomic.load(&me.affinity_mask)
	katomic.store(mut &me.affinity_mask, u64(1))
	sched.wake_cpu(0)
	mut slept := false
	if devcore.sleep_until(on_boot_cpu, voidptr(me), move_timeout_ns, 1) {
		slept = deep_sleep_here()
	} else {
		deep_failed('could not move to the boot processor')
	}
	katomic.store(mut &me.affinity_mask, affinity)
	return slept
}

// What the keyboard controller is holding, read before anything empties it:
// the key or the movement that woke the machine, if one did.
fn i8042_waiting() int {
	status := kio.port_in[u8](i8042_status)
	// All ones is a machine with no such controller.
	if status == 0xff || status & i8042_output_full == 0 {
		return no_source
	}
	return if status & i8042_from_pointer != 0 {
		int(wakesrc.Source.pointer)
	} else {
		int(wakesrc.Source.keyboard)
	}
}

// What ended the sleep, as well as can be told on the way back: the clock's
// alarm, something the keyboard controller is holding, or a button. Read
// before interrupts are on, and cleared, so that the press that woke the
// machine is not taken for a press once the event interrupt is back.
fn wake_cause() int {
	fixed := uacpi.take_wake_status()
	if fixed.rtc {
		return int(wakesrc.Source.alarm)
	}
	held := i8042_waiting()
	if held != no_source {
		return held
	}
	if fixed.power_button {
		return int(wakesrc.Source.power_button)
	}
	if fixed.sleep_button {
		return int(wakesrc.Source.sleep_button)
	}
	return no_source
}

// On the boot processor, pinned there.
fn deep_sleep_here() bool {
	status := uacpi.prepare_sleep(uacpi.sleep_state_s3)
	if status != .ok {
		C.kprintf(c'syspower: firmware would not prepare for S3: %s\n', C.uacpi_status_to_string(status))
		return deep_failed('firmware would not prepare')
	}
	// From here firmware has been told the machine is going down, and is
	// told it is back whatever happens.
	uacpi.set_waking_vector(wake.entry_address())
	alarm := arm_clock_alarm()

	mut slept := false
	mut why := ''
	mut cause := no_source
	mut away_seconds := u64(0)
	if !wake.park_secondaries() {
		why = 'a processor would not park'
	} else if !devcore.sleep_until(events_quiet, unsafe { nil }, quiet_timeout_ns, 1) {
		why = 'firmware events would not fall quiet'
	} else {
		deep_save_devices()
		ints := cpu.interrupt_toggle(false)
		if !uacpi.events_idle() {
			why = 'firmware events would not fall quiet'
		} else if wakesrc.pending() {
			why = 'a wake source reported before the machine was down'
		} else if !apic.io_apic_save() {
			why = 'no memory for the interrupt routes'
		} else {
			before_ns := hpet_clock.nanoseconds()
			before_clock := rtc.now() or { u64(0) }
			slept = wake.sleep_processor(enter_s3)
			uacpi.leave_sleep_early(uacpi.sleep_state_s3)
			if slept {
				apic.io_apic_restore()
				time.pit_resume()
				after_clock := rtc.now() or { u64(0) }
				if before_clock != 0 && after_clock > before_clock {
					away_seconds = after_clock - before_clock
				}
				hpet_clock.resume(before_ns + away_seconds * devcore.second)
				cause = wake_cause()
			} else {
				why = 'firmware did not put the machine to sleep'
			}
		}
		// Every wait from here on is against a clock that runs again. The
		// other processors need no interrupts to be started.
		wake.start_secondaries()
		cpu.interrupt_toggle(ints)
	}
	// Those that parked while another would not, and the end of parking
	// itself; nothing to do when they are all back already.
	wake.start_secondaries()
	// The boot processor's timer was stopped with the rest of its APIC; its
	// next pass through the scheduler arms it.
	sched.wake_cpu(0)
	uacpi.leave_sleep(uacpi.sleep_state_s3)
	if alarm {
		disarm_clock_alarm(cause == int(wakesrc.Source.alarm))
	}
	if slept {
		syspower_deep_cycles++
		deep_restore_devices()
		if cause != no_source {
			wakesrc.woke(unsafe { wakesrc.Source(cause) })
		}
		C.kprintf(c'syspower: back from S3 after about %llu s\n', away_seconds)
	} else {
		display_discard()
	}
	if wake.lost_processors() != 0 {
		C.kprintf(c'syspower: %llu processors have not come back from a sleep\n', wake.lost_processors())
	}
	if why.len != 0 {
		return deep_failed(why)
	}
	return slept
}

// What must be read out of the devices while they still have power.
fn deep_save_devices() {
	devcore.pci_save_all()
	display_save()
}

// And put back before any driver's resume runs: the IOMMUs first, so that no
// device can reach memory until each has been told again what it may reach;
// then the configuration space the drivers find their devices by; then the
// screen, which needs its adapter's memory to answer.
fn deep_restore_devices() {
	dma.resume_units()
	devcore.pci_restore_all()
	display_restore()
}

// Hand a set alarm to the battery-backed clock. True if it was.
fn arm_clock_alarm() bool {
	deadline := katomic.load(&syspower_alarm_ns)
	if deadline == 0 || !wakesrc.allowed(.alarm) {
		return false
	}
	now := devcore.now_ns()
	// A whole number of seconds, rounded up, and at least one: the clock's
	// alarm matches a second that is yet to come.
	mut seconds := if deadline > now {
		(deadline - now + devcore.second - 1) / devcore.second
	} else {
		u64(1)
	}
	if seconds == 0 {
		seconds = 1
	}
	if seconds > rtc.alarm_limit_seconds {
		// Further off than the clock can be set. The machine sleeps until
		// something else wakes it; the alarm is still the kernel's then.
		print('syspower: the alarm is more than a day off and will not wake the machine from S3\n')
		return false
	}
	if !rtc.set_alarm(seconds) {
		print('syspower: the clock would not take the alarm; it will not wake the machine from S3\n')
		return false
	}
	uacpi.set_rtc_wake(true)
	return true
}

// Take the alarm back from the clock. One that went off is done with, and the
// kernel's own timer for it is cancelled.
fn disarm_clock_alarm(went_off bool) {
	rtc.cancel_alarm()
	uacpi.set_rtc_wake(false)
	if went_off {
		katomic.store(mut &syspower_alarm_ns, u64(0))
		event.trigger(mut syspower_alarm_changed, false)
	}
}
