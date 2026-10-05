// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module initialisation

#include "x86_mitigations.h"

struct C.vinix_x86_mitigation_policy {
mut:
	kernel_control u64
	user_control u64
	flags u64
	reserved u64
}

struct MitigationCaps {
mut:
	intel bool
	amd bool
	leaf7_edx u32
	leaf7_2_edx u32
	amd_ebx u32
	arch_caps u64
}

// Assembly consumes this boot-owned array with a 32-byte stride and flags at
// offset 16. Only setup allocates; entry/return/switch paths stay in assembly.
@[export: 'vinix_x86_mitigation_policies']
__global mitigation_policies &C.vinix_x86_mitigation_policy
__global mitigation_cpu_count u64

fn C.calloc(count usize, size usize) voidptr
fn C.kprintf(fmt charptr, ...voidptr) i32

fn mitigation_capabilities() MitigationCaps {
	mut caps := MitigationCaps{}
	mut a := u32(0)
	mut b := u32(0)
	mut c := u32(0)
	mut d := u32(0)
	mitigation_cpuid(0, 0, unsafe { &a }, unsafe { &b }, unsafe { &c }, unsafe { &d })
	max_leaf := a
	caps.intel = b == 0x756e6547 && d == 0x49656e69 && c == 0x6c65746e
	caps.amd = b == 0x68747541 && d == 0x69746e65 && c == 0x444d4163
	if max_leaf >= 7 {
		mitigation_cpuid(7, 0, unsafe { &a }, unsafe { &b }, unsafe { &c }, unsafe { &d })
		caps.leaf7_edx = d
		if a >= 2 {
			mitigation_cpuid(7, 2, unsafe { &a }, unsafe { &b }, unsafe { &c }, unsafe { &d })
			caps.leaf7_2_edx = d
		}
		// Never read an unenumerated MSR or interpret another vendor's caps.
		if caps.intel && caps.leaf7_edx & (u32(1) << 29) != 0 {
			caps.arch_caps = mitigation_rdmsr(0x10a)
		}
	}
	if caps.amd {
		mitigation_cpuid(0x80000000, 0, unsafe { &a }, unsafe { &b }, unsafe { &c }, unsafe { &d })
		if a >= 0x80000008 {
			mitigation_cpuid(0x80000008, 0, unsafe { &a }, unsafe { &b }, unsafe { &c }, unsafe { &d })
			caps.amd_ebx = b
		}
	}
	return caps
}

fn mitigation_select(caps MitigationCaps) C.vinix_x86_mitigation_policy {
	mut policy := C.vinix_x86_mitigation_policy{}
	mut ibrs := false
	mut enhanced := false
	mut stibp := false
	mut ssbd := false
	if caps.intel {
		ibrs = caps.leaf7_edx & (u32(1) << 26) != 0
		enhanced = ibrs && caps.arch_caps & (u64(1) << 1) != 0
		stibp = caps.leaf7_edx & (u32(1) << 27) != 0
		ssbd = caps.leaf7_edx & (u32(1) << 31) != 0
		if ibrs { policy.flags |= u64(C.VINIX_SPEC_IBPB) }
		if caps.leaf7_2_edx & (u32(1) << 4) != 0 {
			policy.user_control |= u64(1) << 10
			policy.flags |= u64(C.VINIX_SPEC_BHI)
		}
		if caps.leaf7_2_edx & (u32(1) << 2) != 0 {
			policy.user_control |= u64(1) << 6
			policy.flags |= u64(C.VINIX_SPEC_RRSBA)
		}
		// RFDS_CLEAR still requires VERW when MDS_NO is also advertised.
		if caps.leaf7_edx & (u32(1) << 10) != 0 || caps.arch_caps & (u64(1) << 28) != 0 {
			policy.flags |= u64(C.VINIX_SPEC_CLEAR)
		}
	} else if caps.amd {
		ibrs = caps.amd_ebx & (u32(1) << 14) != 0
		enhanced = ibrs && caps.amd_ebx & (u32(1) << 16) != 0
		stibp = caps.amd_ebx & (u32(1) << 15) != 0
		// VIRT_SSBD and family-specific LS_CFG are different controls.
		ssbd = caps.amd_ebx & (u32(1) << 24) != 0
		if caps.amd_ebx & (u32(1) << 12) != 0 { policy.flags |= u64(C.VINIX_SPEC_IBPB) }
	}
	if stibp {
		policy.user_control |= u64(1) << 1
		policy.flags |= u64(C.VINIX_SPEC_STIBP)
	}
	if ssbd {
		policy.user_control |= u64(1) << 2
		policy.flags |= u64(C.VINIX_SPEC_SSBD)
	}
	if enhanced {
		policy.user_control |= u64(1)
		policy.flags |= u64(C.VINIX_SPEC_EIBRS)
	} else if ibrs {
		policy.flags |= u64(C.VINIX_SPEC_LEGACY)
	}
	policy.kernel_control = policy.user_control | if ibrs { u64(1) } else { u64(0) }
	if policy.flags & u64(C.VINIX_SPEC_IBPB) != 0 { policy.flags |= u64(C.VINIX_SPEC_PENDING) }
	return policy
}

@[export: 'vinix_x86_mitigations_setup']
fn mitigation_setup(count u64) bool {
	if count == 0 || count > u64(~usize(0)) / u64(sizeof(C.vinix_x86_mitigation_policy))
		|| usize(mitigation_policies) != 0 { return false }
	unsafe {
		mitigation_policies = &C.vinix_x86_mitigation_policy(C.calloc(usize(count), sizeof(C.vinix_x86_mitigation_policy)))
	}
	if usize(mitigation_policies) == 0 { return false }
	mitigation_cpu_count = count
	return true
}

@[export: 'vinix_x86_mitigations_initialise']
fn mitigation_initialise(number u64) bool {
	if number >= mitigation_cpu_count { return false }
	caps := mitigation_capabilities()
	mut policy := mitigation_select(caps)
	requested := policy.kernel_control
	if requested != 0 {
		original := mitigation_rdmsr(0x48)
		policy.kernel_control |= original
		policy.user_control |= original
		mitigation_wrmsr(0x48, policy.kernel_control)
		if mitigation_rdmsr(0x48) & requested != requested { return false }
	}
	unsafe { mitigation_policies[number] = policy }
	C.kprintf(c'security: x86 mitigation CPU %llu flags=0x%llx control=0x%llx cpuid7=0x%x cpuid7.2=0x%x amd=0x%x arch=0x%llx\n',
		number, policy.flags & ~u64(C.VINIX_SPEC_PENDING), requested,
		caps.leaf7_edx, caps.leaf7_2_edx, caps.amd_ebx, caps.arch_caps)
	return true
}
