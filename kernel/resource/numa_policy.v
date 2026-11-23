// SPDX-License-Identifier: GPL-2.0-or-later
module resource

// A shared file policy covers backing byte offsets and is visible through
// independent mappings. The mapping already holds the resource reference.
pub interface SharedMappingPolicy {
mut:
	shared_policy_at(offset u64) (i32, u64)
	replace_shared_policy(begin u64, end u64, mode i32, mask u64) ?
}

struct SharedMappingPolicyScratch {
mut:
	backend SharedMappingPolicy
}

pub fn shared_mapping_policy(mut res Resource, offset u64) (i32, u64) {
	if mut res is SharedMappingPolicy {
		mut scratch := unsafe { &SharedMappingPolicyScratch(C.__builtin_alloca(sizeof(SharedMappingPolicyScratch))) }
		unsafe { scratch.backend = SharedMappingPolicy(res) }
		return scratch.backend.shared_policy_at(offset)
	}
	return 0, 0
}

pub fn set_shared_mapping_policy(mut res Resource, begin u64, end u64, mode i32, mask u64) ? {
	if mut res is SharedMappingPolicy {
		mut scratch := unsafe { &SharedMappingPolicyScratch(C.__builtin_alloca(sizeof(SharedMappingPolicyScratch))) }
		unsafe { scratch.backend = SharedMappingPolicy(res) }
		scratch.backend.replace_shared_policy(begin, end, mode, mask)?
	}
}
