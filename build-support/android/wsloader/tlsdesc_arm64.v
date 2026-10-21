// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module wsloader

// AArch64 TLSDESC returns an offset from TP and preserves every register
// except x0. In particular, an ordinary C/V call may clobber all SIMD lanes.
// No compiler operands/clobbers: the entire ABI frame is managed here.
@[export: 'vinix_ws_tlsdesc_resolver']
pub fn tlsdesc_resolver() {
	$if linux || vinix {
		asm volatile aarch64 {
		sub sp, sp, #672
		stp x29, x30, [sp]
		mov x29, sp
		stp x1, x2, [sp, #16]
		stp x3, x4, [sp, #32]
		stp x5, x6, [sp, #48]
		stp x7, x8, [sp, #64]
		stp x9, x10, [sp, #80]
		stp x11, x12, [sp, #96]
		stp x13, x14, [sp, #112]
		stp x15, x16, [sp, #128]
		stp x17, x18, [sp, #144]
		stp q0, q1, [sp, #160]
		stp q2, q3, [sp, #192]
		stp q4, q5, [sp, #224]
		stp q6, q7, [sp, #256]
		stp q8, q9, [sp, #288]
		stp q10, q11, [sp, #320]
		stp q12, q13, [sp, #352]
		stp q14, q15, [sp, #384]
		stp q16, q17, [sp, #416]
		stp q18, q19, [sp, #448]
		stp q20, q21, [sp, #480]
		stp q22, q23, [sp, #512]
		stp q24, q25, [sp, #544]
		stp q26, q27, [sp, #576]
		stp q28, q29, [sp, #608]
		stp q30, q31, [sp, #640]
		bl vinix_ws_tlsdesc_address
		mrs x1, tpidr_el0
		sub x0, x0, x1
		ldp q0, q1, [sp, #160]
		ldp q2, q3, [sp, #192]
		ldp q4, q5, [sp, #224]
		ldp q6, q7, [sp, #256]
		ldp q8, q9, [sp, #288]
		ldp q10, q11, [sp, #320]
		ldp q12, q13, [sp, #352]
		ldp q14, q15, [sp, #384]
		ldp q16, q17, [sp, #416]
		ldp q18, q19, [sp, #448]
		ldp q20, q21, [sp, #480]
		ldp q22, q23, [sp, #512]
		ldp q24, q25, [sp, #544]
		ldp q26, q27, [sp, #576]
		ldp q28, q29, [sp, #608]
		ldp q30, q31, [sp, #640]
		ldp x1, x2, [sp, #16]
		ldp x3, x4, [sp, #32]
		ldp x5, x6, [sp, #48]
		ldp x7, x8, [sp, #64]
		ldp x9, x10, [sp, #80]
		ldp x11, x12, [sp, #96]
		ldp x13, x14, [sp, #112]
		ldp x15, x16, [sp, #128]
		ldp x17, x18, [sp, #144]
		ldp x29, x30, [sp]
		add sp, sp, #672
		ret
	}
	} $else {
		C.abort()
	}
}
