// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
module lib

#include "vmx.h"

pub struct C.vinix_vmx_descriptor {
pub mut:
	limit u16
	base  u64
}

pub struct C.vinix_vmx_registers {}

// VMfailInvalid sets CF; VMfailValid sets ZF. SETNA combines both flags.
// C's int is 32 bits, unlike the kernel's V int.
fn vmx_result(failed u8) i32 {
	return if failed != 0 { i32(-1) } else { i32(0) }
}

@[export: 'vinix_vmx_on']
fn vmx_on(physical_address u64) i32 {
	return vmx_result(vmx_on_status(physical_address))
}

@[export: 'vinix_vmx_off']
fn vmx_off() i32 {
	return vmx_result(vmx_off_status())
}

@[export: 'vinix_vmx_clear']
fn vmx_clear(physical_address u64) i32 {
	return vmx_result(vmx_clear_status(physical_address))
}

@[export: 'vinix_vmx_load']
fn vmx_load(physical_address u64) i32 {
	return vmx_result(vmx_load_status(physical_address))
}

@[export: 'vinix_vmx_write']
fn vmx_write(field u64, value u64) i32 {
	return vmx_result(vmx_write_status(field, value))
}

@[export: 'vinix_vmx_read']
fn vmx_read(field u64, value &u64) i32 {
	mut result := u64(0)
	failed := vmx_read_status(field, unsafe { &result })
	// A failed VMREAD must leave the caller's value untouched.
	if failed == 0 {
		unsafe { *value = result }
	}
	return vmx_result(failed)
}
