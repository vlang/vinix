// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import errno
import kbudget
import numa
import proc
import vmstorage

struct SharedPolicyRange {
mut:
	begin u64
	end u64
	policy proc.NumaPolicy
}

@[heap]
struct SharedPolicies {
mut:
	charge kbudget.Charge
	ranges []SharedPolicyRange
}

// The shadow lock protects the policy intervals and page publication together.
// The caller's mapped local range keeps the global alive while taking the lock.
fn (global &MmapRangeGlobal) shared_policy_locked(key u64) proc.NumaPolicy {
	policies := global.shared_policies
	if policies != unsafe { nil } {
		for part in policies.ranges {
			if key < part.begin { break }
			if key < part.end { return part.policy }
		}
	}
	return proc.NumaPolicy{}
}

fn explicit_policy(local &MmapRangeLocal, address u64) proc.NumaPolicy {
	if !local.shared_anonymous() { return local.policy }
	mut global := local.global
	global.shadow_pagemap.l.acquire()
	defer { global.shadow_pagemap.l.release() }
	return global.shared_policy_locked(shadow_address(local, address))
}

fn free_shared_policies(policies &SharedPolicies) {
	if policies == unsafe { nil } { return }
	charge := policies.charge
	unsafe { policies.ranges.free(); free(policies) }
	kbudget.release(charge)
}

fn allocate_shared_policies(global &MmapRangeGlobal) ?&SharedPolicies {
	object := vmstorage.allocation_bytes(sizeof(SharedPolicies)) or { errno.set(errno.enomem); return none }
	buffer := vmstorage.allocation_bytes(2 * sizeof(SharedPolicyRange)) or { errno.set(errno.enomem); return none }
	charge := proc.reserve_kernel_for(global.shadow_pagemap.kernel_owner, .mapping, object + buffer)?
	mut policies := &SharedPolicies{charge: charge, ranges: []SharedPolicyRange{cap: 2}} @[freed]
	policies.ranges.flags |= .noslices
	return policies
}

fn replace_shared_policy(local &MmapRangeLocal, start u64, end u64, policy proc.NumaPolicy) ? {
	mut global := local.global
	begin := shadow_address(local, start)
	limit := begin + (end - start)
	global.shadow_pagemap.l.acquire()
	defer { global.shadow_pagemap.l.release() }
	mut policies := global.shared_policies
	if policies == unsafe { nil } {
		if policy.mode == numa.mpol_default { return }
		policies = allocate_shared_policies(global)?
		global.shared_policies = policies
	}

	// Find intersecting intervals and retain the two outer fragments.
	mut first := 0
	for first < policies.ranges.len && policies.ranges[first].end <= begin { first++ }
	mut last := first
	for last < policies.ranges.len && policies.ranges[last].begin < limit { last++ }
	if first == last && policy.mode == numa.mpol_default { return }
	if last == first + 1 && policies.ranges[first].begin <= begin
		&& policies.ranges[first].end >= limit && policies.ranges[first].policy == policy {
		return
	}
	mut parts := [3]SharedPolicyRange{}
	mut count := 0
	if first < last && policies.ranges[first].begin < begin {
		parts[0] = policies.ranges[first]
		parts[0].end = begin
		count++
	}
	if policy.mode != numa.mpol_default {
		unsafe { parts[count] = SharedPolicyRange{begin: begin, end: limit, policy: policy} }
		count++
	}
	if first < last && policies.ranges[last - 1].end > limit {
		unsafe {
			parts[count] = policies.ranges[last - 1]
			parts[count].begin = limit
		}
		count++
	}
	needed := policies.ranges.len - (last - first) + count
	vmstorage.ensure_capacity(mut policies.ranges, mut policies.charge, needed)?
	if last > first { policies.ranges.delete_many(first, last - first) }
	tail := policies.ranges.len
	for _ in 0 .. count { policies.ranges << SharedPolicyRange{} }
	for index := tail - 1; index >= first; index-- {
		policies.ranges[index + count] = policies.ranges[index]
	}
	for index in 0 .. count {
		policies.ranges[first + index] = unsafe { parts[index] }
	}
	// Coalesce matching neighbors so repeated edits do not retain boundaries.
	mut kept := 0
	for part in policies.ranges {
		if kept > 0 && policies.ranges[kept - 1].end == part.begin
			&& policies.ranges[kept - 1].policy == part.policy {
			policies.ranges[kept - 1].end = part.end
		} else {
			policies.ranges[kept] = part
			kept++
		}
	}
	if kept == 0 {
		global.shared_policies = unsafe { nil }
		free_shared_policies(policies)
	} else if kept < policies.ranges.len {
		policies.ranges.delete_many(kept, policies.ranges.len - kept)
	}
}
