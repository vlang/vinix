// SPDX-License-Identifier: GPL-2.0-or-later
module initialisation

$if mitigation_test ? {
	fn C.vinix_mitigation_test_cpuid(leaf u32, subleaf u32, a &u32, b &u32, c &u32, d &u32)
	fn C.vinix_mitigation_test_rdmsr(msr u32) u64
	fn C.vinix_mitigation_test_wrmsr(msr u32, value u64)
}

fn mitigation_cpuid(leaf u32, subleaf u32, a &u32, b &u32, c &u32, d &u32) {
	$if mitigation_test ? {
		C.vinix_mitigation_test_cpuid(leaf, subleaf, a, b, c, d)
	} $else {
		mut eax := u32(0)
		mut ebx := u32(0)
		mut ecx := u32(0)
		mut edx := u32(0)
		asm volatile amd64 {
			cpuid
			; =a (eax)
			  =b (ebx)
			  =c (ecx)
			  =d (edx)
			; a (leaf)
			  c (subleaf)
		}
		unsafe { *a = eax; *b = ebx; *c = ecx; *d = edx }
	}
}

fn mitigation_rdmsr(msr u32) u64 {
	$if mitigation_test ? {
		return C.vinix_mitigation_test_rdmsr(msr)
	} $else {
		mut low := u32(0)
		mut high := u32(0)
		asm volatile amd64 {
			rdmsr
			; =a (low)
			  =d (high)
			; c (msr)
			; memory
		}
		return u64(high) << 32 | u64(low)
	}
}

fn mitigation_wrmsr(msr u32, value u64) {
	$if mitigation_test ? {
		C.vinix_mitigation_test_wrmsr(msr, value)
	} $else {
		asm volatile amd64 {
			wrmsr
			; ; c (msr)
			    a (u32(value))
			    d (u32(value >> 32))
			; memory
		}
	}
}
