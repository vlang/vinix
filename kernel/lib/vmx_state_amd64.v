// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
module lib

// Describe the full FXSAVE area to the compiler without copying or allocating.
struct VmxFxState {
	data [512]u8
}

@[export: 'vinix_vmx_fxsave']
fn vmx_fxsave(state voidptr) {
	area := unsafe { &VmxFxState(state) }
	asm volatile amd64 {
		fxsave64 area
		; =m (*area) as area
		; ; memory
	}
}

@[export: 'vinix_vmx_fxrstor']
fn vmx_fxrstor(state voidptr) {
	area := unsafe { &VmxFxState(state) }
	asm volatile amd64 {
		fxrstor64 area
		; ; m (*area) as area
		; memory
	}
}

@[export: 'vinix_vmx_sgdt']
fn vmx_sgdt(descriptor &C.vinix_vmx_descriptor) {
	asm volatile amd64 {
		sgdt descriptor
		; =m (*descriptor) as descriptor
	}
}

@[export: 'vinix_vmx_sidt']
fn vmx_sidt(descriptor &C.vinix_vmx_descriptor) {
	asm volatile amd64 {
		sidt descriptor
		; =m (*descriptor) as descriptor
	}
}

@[export: 'vinix_vmx_read_cs']
fn vmx_read_cs() u16 {
	mut selector := u16(0)
	asm volatile amd64 {
		mov selector, cs
		; =rm (selector)
	}
	return selector
}

@[export: 'vinix_vmx_read_ss']
fn vmx_read_ss() u16 {
	mut selector := u16(0)
	asm volatile amd64 {
		mov selector, ss
		; =rm (selector)
	}
	return selector
}

@[export: 'vinix_vmx_read_ds']
fn vmx_read_ds() u16 {
	mut selector := u16(0)
	asm volatile amd64 {
		mov selector, ds
		; =rm (selector)
	}
	return selector
}

@[export: 'vinix_vmx_read_es']
fn vmx_read_es() u16 {
	mut selector := u16(0)
	asm volatile amd64 {
		mov selector, es
		; =rm (selector)
	}
	return selector
}

@[export: 'vinix_vmx_read_fs']
fn vmx_read_fs() u16 {
	mut selector := u16(0)
	asm volatile amd64 {
		mov selector, fs
		; =rm (selector)
	}
	return selector
}

@[export: 'vinix_vmx_read_gs']
fn vmx_read_gs() u16 {
	mut selector := u16(0)
	asm volatile amd64 {
		mov selector, gs
		; =rm (selector)
	}
	return selector
}

@[export: 'vinix_vmx_read_tr']
fn vmx_read_tr() u16 {
	mut selector := u16(0)
	asm volatile amd64 {
		str selector
		; =rm (selector)
	}
	return selector
}
