// SPDX-License-Identifier: GPL-2.0-or-later
module cpu

import x86.msr

// Classify only the L1TF branch of Linux 6.6.157 cpu_set_bug_bits(). Vendor
// words have CPUID leaf zero's EBX, EDX, ECX order. The original first-match
// whitelist has NO_SPECULATION, NO_MELTDOWN or NO_L1TF for precisely the
// exemptions below; flags such as Tiger Lake's NO_MMIO do not exempt L1TF.
// This is a vulnerability observation, not a mitigation or mapping policy.
pub fn linuxkpi_classify_l1tf(vendor_b u32, vendor_d u32, vendor_c u32, signature u32,
	arch_caps u64) bool {
	mut family := (signature >> 8) & 0xf
	if family == 0xf {
		family += (signature >> 20) & 0xff
	}
	mut model := (signature >> 4) & 0xf
	// Preserve the pinned x86_model() helper, including extended families.
	if family >= 6 {
		model += ((signature >> 16) & 0xf) << 4
	}
	// cpu_detect() then assigns the helper results to cpuinfo_x86's u8
	// fields. Preserve family narrowing even for synthetic CPUID signatures.
	family = u32(u8(family))
	intel := vendor_b == 0x756e6547 && vendor_d == 0x49656e69 && vendor_c == 0x6c65746e
	amd := vendor_b == 0x68747541 && vendor_d == 0x69746e65 && vendor_c == 0x444d4163
	hygon := vendor_b == 0x6f677948 && vendor_d == 0x6e65476e && vendor_c == 0x656e6975
	centaur := vendor_b == 0x746e6543 && vendor_d == 0x48727561 && vendor_c == 0x736c7561
	nsc := vendor_b == 0x646f6547 && vendor_d == 0x79622065 && vendor_c == 0x43534e20
	vortex := vendor_b == 0x74726f56 && vendor_d == 0x36387865 && vendor_c == 0x436f5320
	if family == 4 || (family == 5 && (intel || centaur || nsc || vortex))
		|| (family == 6 && vortex) {
		return false
	}
	if amd || hygon {
		return false
	}
	// IA32_ARCH_CAPABILITIES.RDCL_NO is tested before NO_L1TF in the
	// original classifier. The caller supplies zero only if unenumerated.
	if arch_caps & u64(1) != 0 {
		return false
	}
	if intel && family == 6 {
		match model {
			// Bonnell and Saltwell: NO_SPECULATION.
			0x1c, 0x26, 0x27, 0x35, 0x36 { return false }
			// Silvermont, Airmont, Goldmont and Xeon Phi: NO_L1TF.
			0x37, 0x4a, 0x4c, 0x4d, 0x57, 0x5a, 0x5c, 0x5f, 0x75, 0x7a, 0x85 {
				return false
			}
			else {}
		}
	}
	return true
}

// Boot CPU initialization calls this with IRQs disabled before publishing
// Local.online. Zero means that the observation is unresolved and must fail
// initialization; one and two mean observed unaffected and affected. No
// unenumerated MSR is touched, even when the CPU is absent from the whitelist.
pub fn linuxkpi_sample_l1tf() u32 {
	// A caller may not migrate between the identifying leaves and MSR read.
	if interrupt_state() {
		return 0
	}
	available, max_leaf, vendor_b, vendor_c, vendor_d := cpuid(0, 0)
	if !available || max_leaf < 1 {
		return 0
	}
	leaf1_available, signature, _, _, _ := cpuid(1, 0)
	if !leaf1_available {
		return 0
	}
	mut arch_caps := u64(0)
	if max_leaf >= 7 {
		leaf7_available, _, _, _, leaf7_edx := cpuid(7, 0)
		if !leaf7_available {
			return 0
		}
		// The original x86_read_arch_cap_msr() gate is this advertised bit,
		// without a vendor restriction. Read before whitelist classification.
		if leaf7_edx & (u32(1) << 29) != 0 {
			arch_caps = msr.read_safe(0x10a) or { return 0 }
		}
	}
	return if linuxkpi_classify_l1tf(vendor_b, vendor_d, vendor_c, signature, arch_caps) {
		u32(2)
	} else {
		u32(1)
	}
}
