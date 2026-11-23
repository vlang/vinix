// SPDX-License-Identifier: GPL-2.0-or-later
module numa

import errno
import kbudget
import proc
import vmstorage

struct SharedPolicyRange {
mut:
	begin u64
	end u64
	policy proc.NumaPolicy
}

@[heap]
struct SharedPolicyState {
mut:
	charge kbudget.Charge
	ranges []SharedPolicyRange
}

// The backing owner serializes the interval operations and frees the state
// once its last reference is dropped. Lookups return an independent value.
pub struct SharedPolicies {
mut:
	state &SharedPolicyState = unsafe { nil }
}

pub fn (this &SharedPolicies) lookup(key u64) proc.NumaPolicy {
	policies := this.state
	if policies != unsafe { nil } {
		for part in policies.ranges {
			if key < part.begin { break }
			if key < part.end { return part.policy }
		}
	}
	return proc.NumaPolicy{}
}

pub fn (mut this SharedPolicies) release() {
	policies := this.state
	if policies == unsafe { nil } { return }
	this.state = unsafe { nil }
	charge := policies.charge
	unsafe { policies.ranges.free(); free(policies) }
	kbudget.release(charge)
}

fn allocate_shared_policies(owner kbudget.Owner) ?&SharedPolicyState {
	object := vmstorage.allocation_bytes(sizeof(SharedPolicyState)) or { errno.set(errno.enomem); return none }
	buffer := vmstorage.allocation_bytes(2 * sizeof(SharedPolicyRange)) or { errno.set(errno.enomem); return none }
	charge := proc.reserve_kernel_for(owner, .mapping, object + buffer)?
	mut policies := &SharedPolicyState{charge: charge, ranges: []SharedPolicyRange{cap: 2}} @[freed]
	policies.ranges.flags |= .noslices
	return policies
}

pub fn (mut this SharedPolicies) replace(owner kbudget.Owner, begin u64, limit u64, policy proc.NumaPolicy) ? {
	mut policies := this.state
	if policies == unsafe { nil } {
		if policy.mode == mpol_default { return }
		policies = allocate_shared_policies(owner)?
		this.state = policies
	}

	// Find intersecting intervals and retain the two outer fragments.
	mut first := 0
	for first < policies.ranges.len && policies.ranges[first].end <= begin { first++ }
	mut last := first
	for last < policies.ranges.len && policies.ranges[last].begin < limit { last++ }
	if first == last && policy.mode == mpol_default { return }
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
	if policy.mode != mpol_default {
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
		this.release()
	} else if kept < policies.ranges.len {
		policies.ranges.delete_many(kept, policies.ranges.len - kept)
	}
}
