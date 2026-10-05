// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
module lib

// Intel VT-x is unavailable on ARM. Preserve the original C no-op ABI.
fn vmx_on_status(physical_address u64) u8 {
	_ = physical_address
	return 1
}

fn vmx_off_status() u8 {
	return 1
}

fn vmx_clear_status(physical_address u64) u8 {
	_ = physical_address
	return 1
}

fn vmx_load_status(physical_address u64) u8 {
	_ = physical_address
	return 1
}

fn vmx_write_status(field u64, value u64) u8 {
	_ = field
	_ = value
	return 1
}

fn vmx_read_status(field u64, value &u64) u8 {
	_ = field
	_ = value
	return 1
}

@[export: 'vinix_vmx_enter']
fn vmx_enter(registers &C.vinix_vmx_registers) i32 {
	_ = registers
	return -1
}

@[export: 'vinix_vmx_fxsave']
fn vmx_fxsave(state voidptr) {
	_ = state
}

@[export: 'vinix_vmx_fxrstor']
fn vmx_fxrstor(state voidptr) {
	_ = state
}

@[export: 'vinix_vmx_sgdt']
fn vmx_sgdt(descriptor &C.vinix_vmx_descriptor) {
	_ = descriptor
}

@[export: 'vinix_vmx_sidt']
fn vmx_sidt(descriptor &C.vinix_vmx_descriptor) {
	_ = descriptor
}

@[export: 'vinix_vmx_read_cs']
fn vmx_read_cs() u16 { return 0 }

@[export: 'vinix_vmx_read_ss']
fn vmx_read_ss() u16 { return 0 }

@[export: 'vinix_vmx_read_ds']
fn vmx_read_ds() u16 { return 0 }

@[export: 'vinix_vmx_read_es']
fn vmx_read_es() u16 { return 0 }

@[export: 'vinix_vmx_read_fs']
fn vmx_read_fs() u16 { return 0 }

@[export: 'vinix_vmx_read_gs']
fn vmx_read_gs() u16 { return 0 }

@[export: 'vinix_vmx_read_tr']
fn vmx_read_tr() u16 { return 0 }
