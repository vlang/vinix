// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// ACPI's sleeping states, for the code that suspends the machine to RAM.
//
// uACPI does the firmware's side of a sleep in four calls: prepare (the _PTS
// method, with interrupts on), enter (write the sleep type to the PM1 control
// register, with interrupts off -- the machine stops there), and after the
// wake the same two in reverse. These are thin names for them, with what else
// the platform has to ask firmware on the way: whether the state exists, where
// to resume, and which fixed event ended the sleep.
module uacpi

import acpi

pub const sleep_state_s3 = 3

// uACPI's register fields, by its numbers (uacpi/registers.h).
const field_power_button_status = 3
const field_sleep_button_status = 4
const field_rtc_status = 5
const field_rtc_enable = 13
const field_sci_enable = 15

// FADT: offsets of the fields read here, and the flag for a machine with no
// PM1 registers at all.
const fadt_firmware_ctrl = u64(36)
const fadt_flags = u64(112)
const fadt_x_firmware_ctrl = u64(132)
const fadt_hw_reduced = u32(1) << 20

@[c_extern]
fn C.uacpi_set_waking_vector(addr32 u64, addr64 u64) UACPIStatus
@[c_extern]
fn C.uacpi_prepare_for_wake_from_sleep_state(state int) UACPIStatus
@[c_extern]
fn C.uacpi_wake_from_sleep_state(state int) UACPIStatus
@[c_extern]
fn C.uacpi_read_register_field(field int, value &u64) UACPIStatus
@[c_extern]
fn C.uacpi_write_register_field(field int, value u64) UACPIStatus
@[c_extern]
fn C.uacpi_namespace_root() voidptr
@[c_extern]
fn C.uacpi_enable_fixed_event(event int) UACPIStatus

// Whether firmware describes sleeping state `state` (the \_Sx package) and a
// place to leave the address to resume at (the FACS). A machine built to the
// hardware-reduced profile has neither the registers nor the waking vector.
pub fn sleep_state_supported(state int) bool {
	fadt := acpi.find_sdt('FACP', 0) or { return false }
	length := unsafe { *&u32(u64(fadt) + 4) }
	if length < 116 {
		return false
	}
	if unsafe { *&u32(u64(fadt) + fadt_flags) } & fadt_hw_reduced != 0 {
		return false
	}
	mut facs := u64(unsafe { *&u32(u64(fadt) + fadt_firmware_ctrl) })
	if facs == 0 && length >= 140 {
		facs = unsafe { *&u64(u64(fadt) + fadt_x_firmware_ctrl) }
	}
	if facs == 0 {
		return false
	}
	mut name := [u8(`_`), `S`, `0`, 0]!
	name[2] = u8(`0`) + u8(state)
	mut package := unsafe { nil }
	if C.uacpi_eval_simple_package(C.uacpi_namespace_root(), &char(&name[0]), &package) != .ok {
		return false
	}
	C.uacpi_object_unref(package)
	return true
}

// Run firmware's preparation for the state. Interrupts on.
pub fn prepare_sleep(state int) UACPIStatus {
	return C.uacpi_prepare_for_sleep_state(state)
}

// Where firmware is to jump, in real mode, when the machine wakes. The 64-bit
// vector is left empty: with it set, firmware would enter the kernel in a
// mode it does not expect.
pub fn set_waking_vector(address u64) UACPIStatus {
	return C.uacpi_set_waking_vector(address, 0)
}

// Ask for the state. Interrupts off. For S3 this returns only when the
// machine did not sleep: with the power cut, execution continues at the
// waking vector instead.
pub fn enter_sleep(state int) UACPIStatus {
	return C.uacpi_enter_sleep_state(state)
}

// The machine is awake again, interrupts still off: put the PM1 control
// register back to the working state, and say once more that events are to
// arrive as the ACPI interrupt. Firmware is to hand the machine back that
// way; some hands it back as it was before the kernel first asked, and
// asking again costs nothing.
pub fn leave_sleep_early(state int) {
	C.uacpi_prepare_for_wake_from_sleep_state(state)
	C.uacpi_write_register_field(field_sci_enable, 1)
}

// And with interrupts on: the _WAK method, and the events of a running
// machine enabled again. uACPI does that for the general purpose events; the
// enable bits of the fixed ones went with the power as well, and a power
// button that is not enabled again is one that no longer does anything. One
// with no handler is refused, which is the right answer for it.
pub fn leave_sleep(state int) UACPIStatus {
	status := C.uacpi_wake_from_sleep_state(state)
	C.uacpi_enable_fixed_event(fixed_event_power_button)
	C.uacpi_enable_fixed_event(fixed_event_sleep_button)
	return status
}

// Which fixed events the PM1 status register showed when the machine woke.
pub struct WakeStatus {
pub mut:
	power_button bool
	sleep_button bool
	rtc          bool
}

fn take_field(field int) bool {
	mut value := u64(0)
	if C.uacpi_read_register_field(field, &value) != .ok || value == 0 {
		return false
	}
	// Status bits are cleared by writing them.
	C.uacpi_write_register_field(field, 1)
	return true
}

// Read and clear what woke the machine. Cleared so that the press that woke
// it is not acted on again as a press once the event interrupt is back on.
pub fn take_wake_status() WakeStatus {
	return WakeStatus{
		power_button: take_field(field_power_button_status)
		sleep_button: take_field(field_sleep_button_status)
		rtc:          take_field(field_rtc_status)
	}
}

// Let the clock's alarm wake the machine, or not.
pub fn set_rtc_wake(enabled bool) {
	if enabled {
		// A status bit left set would end the sleep at once.
		C.uacpi_write_register_field(field_rtc_status, 1)
	}
	C.uacpi_write_register_field(field_rtc_enable, if enabled { u64(1) } else { u64(0) })
}
