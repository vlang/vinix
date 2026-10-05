// SPDX-License-Identifier: GPL-2.0-or-later
module lib

$if speculation_test ? {
	fn C.vinix_spec_test_cpuid(leaf u32, subleaf u32, a &u32, b &u32, c &u32, d &u32)
	fn C.vinix_spec_test_rdmsr(msr u32) u64
	fn C.vinix_spec_test_wrmsr(msr u32, value u64)
}

fn speculation_cpuid(leaf u32, subleaf u32, a &u32, b &u32, c &u32, d &u32) {
	$if speculation_test ? {
		C.vinix_spec_test_cpuid(leaf, subleaf, a, b, c, d)
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

fn speculation_rdmsr(msr u32) u64 {
	$if speculation_test ? {
		return C.vinix_spec_test_rdmsr(msr)
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

fn speculation_wrmsr(msr u32, value u64) {
	$if speculation_test ? {
		C.vinix_spec_test_wrmsr(msr, value)
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

@[export: 'vinix_speculation_init']
fn speculation_init(cpu_number u64) u64 {
	mut a := u32(0)
	mut b := u32(0)
	mut c := u32(0)
	mut d := u32(0)
	mut edx := u32(0)
	mut edx2 := u32(0)
	speculation_cpuid(0, 0, unsafe { &a }, unsafe { &b }, unsafe { &c }, unsafe { &d })
	if a >= 7 {
		speculation_cpuid(7, 0, unsafe { &a }, unsafe { &b }, unsafe { &c }, unsafe { &d })
		edx = d
		if a >= 2 {
			speculation_cpuid(7, 2, unsafe { &a }, unsafe { &b }, unsafe { &c }, unsafe { &d })
			edx2 = d
		}
	}
	caps := if edx & spec_compat_arch != 0 { speculation_rdmsr(0x10a) } else { u64(0) }
	policy := speculation_select(edx, edx2, caps)
	if edx & (spec_compat_ibrs_ibpb | spec_compat_stibp | spec_compat_ssbd) != 0
		|| edx2 & spec_compat_bhi_ctrl != 0 {
		old := speculation_rdmsr(0x48)
		speculation_wrmsr(0x48, old | (policy & (u64(7) | spec_compat_bhi)))
	}
	$if speculation_test ? {
		_ = cpu_number
	} $else {
		C.kprintf(c'security: CPU %llu speculation retpoline=1 eibrs=%u ibpb=%u stibp=%u ssbd=%u bhi_dis_s=%u bhi_no=%u\n',
			cpu_number, u32(policy & 1 != 0), u32(policy & spec_compat_ibpb != 0),
			u32(policy & 2 != 0), u32(policy & 4 != 0), u32(policy & spec_compat_bhi != 0),
			u32(caps & (u64(1) << 20) != 0))
	}
	return policy
}

@[export: 'vinix_speculation_switch']
fn speculation_switch(policy u64) {
	if policy & spec_compat_ibpb != 0 { speculation_wrmsr(0x49, 1) }
}
