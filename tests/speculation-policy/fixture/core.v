// SPDX-License-Identifier: GPL-2.0-or-later
// Independent CPUID/MSR oracle, preserving the original 6,144 cases.
@[has_globals]
module fixture

#include <speculation-fixture-native-abi.h>

fn C.printf(&char, ...) i32
fn C.speculation_fixture_assert_failure(&char, i32, &char)
fn C.vinix_speculation_select(u32, u32, u64) u64
fn C.vinix_speculation_init(u64) u64
fn C.vinix_speculation_switch(u64)

__global sf_max_leaf u32
__global sf_max_subleaf u32
__global sf_features u32
__global sf_features2 u32
__global sf_queries u32
__global sf_reads u32
__global sf_writes u32
__global sf_last_msr u32
__global sf_caps u64
__global sf_spec_ctrl u64
__global sf_last_value u64

fn require(ok bool, function &char, line i32, expression &char) {
	if !ok { C.speculation_fixture_assert_failure(function, line, expression) }
}

@[export: 'vinix_spec_test_cpuid']
pub fn cpuid(leaf u32, subleaf u32, a &u32, b &u32, c &u32, d &u32) {
	sf_queries++
	unsafe {
		*a = 0
		*b = 0
		*c = 0
		*d = 0
		if leaf == 0 {
			require(sf_queries == 1 && subleaf == 0, c'vinix_spec_test_cpuid', 17, c'queries == 1 && subleaf == 0')
			*a = sf_max_leaf
			return
		}
		require(leaf == 7 && sf_max_leaf >= 7, c'vinix_spec_test_cpuid', 21, c'leaf == 7 && max_leaf >= 7')
		if subleaf == 0 {
			require(sf_queries == 2, c'vinix_spec_test_cpuid', 23, c'queries == 2')
			*a = sf_max_subleaf
			*d = sf_features
			return
		}
		require(subleaf == 2 && sf_max_subleaf >= 2 && sf_queries == 3, c'vinix_spec_test_cpuid', 30, c'subleaf == 2 && max_subleaf >= 2 && queries == 3')
		*d = sf_features2
	}
}

fn supported_ctrl() u64 {
	if sf_max_leaf < 7 { return 0 }
	return (if sf_features & (u32(1) << 26) != 0 { u64(1) } else { u64(0) }) |
		(if sf_features & (u32(1) << 27) != 0 { u64(2) } else { u64(0) }) |
		(if sf_features & (u32(1) << 31) != 0 { u64(4) } else { u64(0) }) |
		(if sf_max_subleaf >= 2 && sf_features2 & (u32(1) << 4) != 0 {
			u64(1) << 10
		} else {
			u64(0)
		})
}

@[export: 'vinix_spec_test_rdmsr']
pub fn rdmsr(msr u32) u64 {
	sf_reads++
	if msr == 0x10a {
		require(sf_max_leaf >= 7 && sf_features & (u32(1) << 29) != 0, c'vinix_spec_test_rdmsr', 48, c'max_leaf >= 7 && (features & (UINT32_C(1) << 29))')
		return sf_caps
	}
	require(msr == 0x48 && supported_ctrl() != 0, c'vinix_spec_test_rdmsr', 51, c'msr == 0x48 && supported_ctrl()')
	return sf_spec_ctrl
}

@[export: 'vinix_spec_test_wrmsr']
pub fn wrmsr(msr u32, value u64) {
	require(msr == 0x48 || msr == 0x49, c'vinix_spec_test_wrmsr', 56, c'msr == 0x48 || msr == 0x49')
	sf_writes++
	sf_last_msr = msr
	sf_last_value = value
	if msr == 0x49 {
		require(sf_max_leaf >= 7 && sf_features & (u32(1) << 26) != 0, c'vinix_spec_test_wrmsr', 59, c'max_leaf >= 7 && (features & (UINT32_C(1) << 26))')
		require(value == 1, c'vinix_spec_test_wrmsr', 60, c'value == 1')
	} else {
		supported := supported_ctrl()
		require(supported != 0, c'vinix_spec_test_wrmsr', 63, c'supported')
		require((value & ~supported) == (sf_spec_ctrl & ~supported), c'vinix_spec_test_wrmsr', 66, c'(value & ~supported) == (spec_ctrl & ~supported)')
		require((value & sf_spec_ctrl) == sf_spec_ctrl, c'vinix_spec_test_wrmsr', 67, c'(value & spec_ctrl) == spec_ctrl')
		sf_spec_ctrl = value
	}
}

fn check(bits u32, enhanced u32, bhi u32, bhi_no u32, firmware u64) {
	sf_features = (if bits & 1 != 0 { u32(1) << 26 } else { u32(0) }) |
		(if bits & 2 != 0 { u32(1) << 27 } else { u32(0) }) |
		(if bits & 4 != 0 { u32(1) << 29 } else { u32(0) }) |
		(if bits & 8 != 0 { u32(1) << 31 } else { u32(0) }) | (u32(1) << 10)
	sf_features2 = (if bhi != 0 { u32(1) << 4 } else { u32(0) }) | 7
	sf_caps = (if enhanced != 0 { u64(2) } else { u64(0) }) |
		(if bhi_no != 0 { u64(1) << 20 } else { u64(0) })
	sf_queries = 0
	sf_reads = 0
	sf_writes = 0
	sf_spec_ctrl = firmware
	selected := (if bits & 1 != 0 { u64(C.VINIX_SPEC_IBPB) } else { u64(0) }) |
		(if bits & 1 != 0 && bits & 4 != 0 && enhanced != 0 { u64(1) } else { u64(0) }) |
		(if bits & 2 != 0 { u64(2) } else { u64(0) }) |
		(if bits & 8 != 0 { u64(4) } else { u64(0) }) |
		(if bhi != 0 && !(bits & 4 != 0 && bhi_no != 0) { u64(1) << 10 } else { u64(0) })
	require(u64(C.VINIX_SPEC_BHI_DIS_S) == u64(1) << 10, c'check', 90, c'VINIX_SPEC_BHI_DIS_S == UINT64_C(1) << 10')
	require(C.vinix_speculation_select(sf_features, sf_features2, sf_caps) == selected, c'check', 91, c'vinix_speculation_select(features, features2, caps) == selected')
	mut expected := if sf_max_leaf >= 7 { selected } else { u64(0) }
	if sf_max_subleaf < 2 { expected &= ~(u64(1) << 10) }
	policy := C.vinix_speculation_init(0)
	require(policy == expected, c'check', 97, c'policy == expected')
	require(sf_queries == 1 + u32(sf_max_leaf >= 7) * (1 + u32(sf_max_subleaf >= 2)), c'check', 98, c'queries == 1 + (max_leaf >= 7) * (1 + (max_subleaf >= 2))')
	arch_reads := u32(sf_max_leaf >= 7 && bits & 4 != 0)
	ctrl_reads := u32(supported_ctrl() != 0)
	require(sf_reads == arch_reads + ctrl_reads, c'check', 101, c'reads == arch_reads + ctrl_reads')
	require(sf_writes == ctrl_reads, c'check', 102, c'writes == ctrl_reads')
	require(sf_spec_ctrl == (firmware | (expected & u64(0x407))), c'check', 103, c'spec_ctrl == (firmware | (expected & UINT64_C(0x407)))')
	old_writes := sf_writes
	C.vinix_speculation_switch(policy)
	barrier := u32(sf_max_leaf >= 7 && bits & 1 != 0)
	require(sf_writes == old_writes + barrier, c'check', 107, c'writes == old_writes + barrier')
	if barrier != 0 {
		require(sf_last_msr == 0x49 && sf_last_value == 1, c'check', 108, c'last_msr == 0x49 && last_value == 1')
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		leaf_maxima := [u32(0), 6, 7, 0xffffffff]!
		subleaf_maxima := [u32(0), 1, 2, 0xffffffff]!
		firmware_values := [u64(0), 0x100, 0x1000000000000407]!
		mut cases := u32(0)
		for leaf in 0 .. 4 {
			for subleaf in 0 .. 4 {
				for bits in 0 .. 16 {
					for enhanced in 0 .. 2 {
						for bhi in 0 .. 2 {
							for bhi_no in 0 .. 2 {
								for firmware in 0 .. 3 {
									sf_max_leaf = leaf_maxima[leaf]
									sf_max_subleaf = subleaf_maxima[subleaf]
									check(u32(bits), u32(enhanced), u32(bhi), u32(bhi_no), firmware_values[firmware])
									cases++
								}
							}
						}
					}
				}
			}
		}
		C.printf(c'SPECULATION POLICY PASS (%u cases)\n', cases)
	}
	return 0
}
