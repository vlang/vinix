// SPDX-License-Identifier: GPL-2.0-or-later
module headercore

fn C.vinix_linuxkpi_fpu_begin()
fn C.vinix_linuxkpi_fpu_end()

// The host compatibility model does not borrow scheduler-owned FPU storage.
// The independent instruction fixture compiles the native entry without this
// host-model define, as does the production kernel.
$if !linuxkpi_host_test ? {
	@[export: 'kernel_fpu_begin']
	pub fn kernel_fpu_begin() {
		C.vinix_linuxkpi_fpu_begin()
		mxcsr := u32(0x1f80)
		asm volatile amd64 {
		fninit
		ldmxcsr mxcsr
		; ; m (mxcsr)
		; memory
	}
	}

	@[export: 'kernel_fpu_end']
	pub fn kernel_fpu_end() {
		C.vinix_linuxkpi_fpu_end()
	}
}
