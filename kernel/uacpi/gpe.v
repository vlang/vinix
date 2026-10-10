// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// General purpose events a driver handles itself.
//
// Most of them firmware handles: a method named after the event's number
// runs and sends a Notify. A few belong to a device with a driver, the
// embedded controller's first of all, and that driver installs a handler
// for the number firmware gives in _GPE. uACPI switches the event off and
// clears it before it calls the handler, from the thread the SCI wakes
// (events.v); the handler says whether to switch it on again.
//
// An event is named by a number and the device of the block it is in. Nil is
// the two blocks the FADT describes, which is where nearly every event is.
module uacpi

// What a handler returns: that the event was its own, and whether it is to
// be switched on again now.
pub const gpe_handled = u32(1)
pub const gpe_reenable = u32(1) << 7

// uACPI's numbers for how an event is raised.
pub const gpe_level = u32(0)
pub const gpe_edge = u32(1)

pub type GpeHandler = fn (context voidptr, device voidptr, index u16) u32

@[c_extern]
fn C.uacpi_install_gpe_handler(device voidptr, index u16, triggering u32, handler voidptr, context voidptr) UACPIStatus
@[c_extern]
fn C.uacpi_enable_gpe(device voidptr, index u16) UACPIStatus
@[c_extern]
fn C.uacpi_suspend_gpe(device voidptr, index u16) UACPIStatus
@[c_extern]
fn C.uacpi_resume_gpe(device voidptr, index u16) UACPIStatus
@[c_extern]
fn C.uacpi_finish_handling_gpe(device voidptr, index u16) UACPIStatus
@[c_extern]
fn C.uacpi_setup_gpe_for_wake(device voidptr, index u16, wake_device voidptr) UACPIStatus
@[c_extern]
fn C.uacpi_enable_gpe_for_wake(device voidptr, index u16) UACPIStatus

// Have `handler` called when event `index` of `device`'s block is raised. It
// replaces a method of firmware's for the same event. The event stays off
// until enable_gpe().
pub fn install_gpe_handler(device Node, index u16, triggering u32, handler GpeHandler, context voidptr) UACPIStatus {
	return C.uacpi_install_gpe_handler(voidptr(device), index, triggering, voidptr(handler),
		context)
}

// Switch the event on. One that is already raised is handled at once.
pub fn enable_gpe(device Node, index u16) UACPIStatus {
	return C.uacpi_enable_gpe(voidptr(device), index)
}

// Switch the event off, and on again, whoever else has it enabled: for a
// driver that must not hear from its device for a while.
pub fn suspend_gpe(device Node, index u16) UACPIStatus {
	return C.uacpi_suspend_gpe(voidptr(device), index)
}

pub fn resume_gpe(device Node, index u16) UACPIStatus {
	return C.uacpi_resume_gpe(voidptr(device), index)
}

// Switch an event on again whose handler said not to.
pub fn finish_gpe(device Node, index u16) UACPIStatus {
	return C.uacpi_finish_handling_gpe(voidptr(device), index)
}

// Say that the event may end a sleep, so that a sleep which switches off
// what may not leaves it on.
pub fn mark_gpe_for_wake(device Node, index u16) bool {
	if C.uacpi_setup_gpe_for_wake(voidptr(device), index, unsafe { nil }) != .ok {
		return false
	}
	return C.uacpi_enable_gpe_for_wake(voidptr(device), index) == .ok
}
