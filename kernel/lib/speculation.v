// SPDX-License-Identifier: GPL-2.0-or-later
module lib

// Preserve the original helper ABI independently of the active per-CPU policy.
// Its IBPB flag is bit 32; the assembly policy uses a different flag layout.
const spec_compat_ibpb = u64(1) << 32
const spec_compat_bhi = u64(1) << 10
const spec_compat_ibrs_ibpb = u32(1) << 26
const spec_compat_stibp = u32(1) << 27
const spec_compat_arch = u32(1) << 29
const spec_compat_ssbd = u32(1) << 31
const spec_compat_bhi_ctrl = u32(1) << 4

@[export: 'vinix_speculation_select']
fn speculation_select(edx u32, edx2 u32, arch_caps u64) u64 {
	mut policy := u64(0)
	if edx & spec_compat_ibrs_ibpb != 0 {
		policy |= spec_compat_ibpb
		// Legacy IBRS needs entry programming, so only select enhanced IBRS.
		if edx & spec_compat_arch != 0 && arch_caps & (u64(1) << 1) != 0 { policy |= 1 }
	}
	if edx & spec_compat_stibp != 0 { policy |= 2 }
	if edx & spec_compat_ssbd != 0 { policy |= 4 }
	// BHI_NO does not enumerate an MSR control; BHI_CTRL does.
	if edx2 & spec_compat_bhi_ctrl != 0
		&& !(edx & spec_compat_arch != 0 && arch_caps & (u64(1) << 20) != 0) {
		policy |= spec_compat_bhi
	}
	return policy
}
