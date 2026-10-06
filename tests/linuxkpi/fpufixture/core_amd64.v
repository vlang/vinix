// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the real instructions, with a synchronous FPU ownership model.
@[translated]
module fpufixture

#include <stdio.h>
#include <asm/fpu/api.h>

fn C.kernel_fpu_begin()
fn C.kernel_fpu_end()
fn C.puts(&char) i32

@[aligned: 16]
struct FxState {
mut:
	bytes [512]u8
}

__global saved FxState
__global borrowed bool
__global protocol_errors u32
__global begin_count u32
__global end_count u32

fn save(state &FxState) {
	asm volatile amd64 {
		fxsave64 area
		; =m (*state) as area
		; ; memory
	}
}

fn restore(state &FxState) {
	asm volatile amd64 {
		fxrstor64 area
		; ; m (*state) as area
		; memory
	}
}

fn control() u16 {
	mut value := u16(0)
	asm volatile amd64 {
		fnstcw value
		; =m (value)
		; ; memory
	}
	return value
}

fn csr() u32 {
	mut value := u32(0)
	asm volatile amd64 {
		stmxcsr value
		; =m (value)
		; ; memory
	}
	return value
}

fn set_control(value u16, mxcsr u32) {
	asm volatile amd64 {
		fldcw value
		ldmxcsr mxcsr
		; ; m (value)
		  m (mxcsr)
		; memory
	}
}

@[export: 'vinix_linuxkpi_fpu_begin']
pub fn borrow_begin() {
	unsafe {
		if borrowed { protocol_errors++ }
		borrowed = true
		begin_count++
		save(&saved)
	}
}

@[export: 'vinix_linuxkpi_fpu_end']
pub fn borrow_end() {
	unsafe {
		if !borrowed { protocol_errors++ }
		restore(&saved)
		borrowed = false
		end_count++
	}
}

@[export: 'main']
pub fn run() i32 {
	mut original := FxState{}
	save(unsafe { &original })
	mut failed := false
	for i in 0 .. 1024 {
		word := u16(0x037f | ((i % 4) << 10))
		mxcsr := u32(0x1f80 | ((i % 4) << 13))
		set_control(word, mxcsr)
		C.kernel_fpu_begin()
		unsafe {
			if !borrowed || control() != 0x037f || csr() != 0x1f80 { failed = true }
		}
		set_control(0x0f7f, 0x7f80)
		C.kernel_fpu_end()
		unsafe {
			if borrowed || control() != word || csr() != mxcsr { failed = true }
		}
	}
	restore(unsafe { &original })
	unsafe {
		if protocol_errors != 0 || begin_count != 1024 || end_count != 1024 { failed = true }
	}
	if failed {
		C.puts(c'LinuxKPI FPU header: FAIL')
		return 1
	}
	C.puts(c'LinuxKPI FPU header: PASS 1024 x87/MXCSR borrows')
	return 0
}
