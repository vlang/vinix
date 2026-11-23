// SPDX-License-Identifier: GPL-2.0-or-later
module numa

import errno
import memory
import proc
import usercopy

// The native Linux memory policy syscalls read maxnode-1 bits.
pub fn import_nodemask(address u64, maxnode u64) ?u64 {
	if address == 0 || maxnode == 1 { return u64(0) }
	if maxnode == 0 || maxnode - 1 > memory.page_size * 8 {
		errno.set(errno.einval)
		return none
	}
	bits := maxnode - 1
	words := (bits + 63) / 64
	if !usercopy.user_range(address, words * sizeof(u64)) {
		errno.set(errno.efault)
		return none
	}
	mut mask := u64(0)
	for word := words; word > 0; word-- {
		mut value := u64(0)
		if !usercopy.copy_from_user(unsafe { &value }, address + (word - 1) * sizeof(u64), sizeof(u64)) {
			errno.set(errno.efault)
			return none
		}
		valid := bits - (word - 1) * 64
		if valid < 64 { value &= (u64(1) << valid) - 1 }
		if word == 1 {
			mask = value
		} else if value != 0 {
			errno.set(errno.einval)
			return none
		}
	}
	return mask
}

pub fn normalize_policy(mode i32, mask u64) ?proc.NumaPolicy {
	allowed := mask & all_nodes_mask()
	match mode {
		mpol_default, mpol_local {
			if mask != 0 { return none }
			return proc.NumaPolicy{mode: int(mode)}
		}
		mpol_preferred {
			if mask == 0 { return proc.NumaPolicy{mode: mpol_local} }
			if allowed == 0 { return none }
			return proc.NumaPolicy{mode: int(mode), mask: allowed & (~allowed + 1)}
		}
		else {
			if allowed == 0 { return none }
			return proc.NumaPolicy{mode: int(mode), mask: allowed}
		}
	}
}

pub fn alloc_range_page(range_policy proc.NumaPolicy, index u64, zero bool) voidptr {
	if !numa_multinode {
		return if zero { memory.pmm_alloc_user(1) } else { memory.pmm_alloc_user_nozero(1) }
	}
	mut policy := range_policy
	if policy.mode == mpol_default {
		caller := proc.current_thread()
		if caller != unsafe { nil } { policy = caller.numa_policy }
	}
	if !memory.user_room(1) { return unsafe { nil } }
	home := current_node()
	match policy.mode {
		mpol_bind {
			mut remaining := policy.mask
			for remaining != 0 {
				mut nearest := first_node_in(remaining)
				for node in 0 .. node_count() {
					if remaining & (u64(1) << node) != 0 && distance(home, node) < distance(home, nearest) {
						nearest = node
					}
				}
				page := alloc_policy_node(nearest, true, zero)
				if page != unsafe { nil } { return page }
				remaining &= ~(u64(1) << nearest)
			}
			return unsafe { nil }
		}
		mpol_interleave {
			mut count := u64(0)
			for node in 0 .. node_count() {
				if policy.mask & (u64(1) << node) != 0 { count++ }
			}
			mut slot := index % count
			for node in 0 .. node_count() {
				if policy.mask & (u64(1) << node) == 0 { continue }
				if slot == 0 { return alloc_policy_node(node, false, zero) }
				slot--
			}
		}
		mpol_preferred {
			return alloc_policy_node(first_node_in(policy.mask), false, zero)
		}
		else {}
	}
	return alloc_policy_node(home, false, zero)
}

fn alloc_policy_node(node int, strict bool, zero bool) voidptr {
	page := if zero {
		memory.pmm_alloc_on_node(1, node, strict)
	} else {
		memory.pmm_alloc_nozero_on_node(1, node, strict)
	}
	return note_node_exhaustion(page, strict)
}
