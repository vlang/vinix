// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import errno
import lib
import memory
import numa
import proc

const mbind_strict = u32(1)
const mbind_move = u32(2)
const mbind_move_all = u32(4)

pub fn syscall_mbind(_ voidptr, address u64, length u64, mode i32, nodes u64, maxnode u64,
	flags u32) (u64, u64) {
	if mode < 0 || mode >= numa.mpol_max { return errno.err, errno.einval }
	raw_mask := numa.import_nodemask(nodes, maxnode) or { return errno.err, errno.get() }
	if flags & ~(mbind_strict | mbind_move | mbind_move_all) != 0 {
		return errno.err, errno.einval
	}
	process := proc.current_thread().process
	if flags & mbind_move_all != 0 && !proc.has_capability(process, proc.cap_sys_nice) {
		return errno.err, errno.eperm
	}
	mut base := address
	$if arm64 {
		base &= u64(0x00ffffffffffffff)
	}
	if base % page_size != 0 { return errno.err, errno.einval }
	span := lib.align_up(length, page_size)
	if span < length || base > u64(-1) - span { return errno.err, errno.einval }
	if span == 0 { return 0, 0 }
	if flags & (mbind_move | mbind_move_all) != 0 { return errno.err, errno.eopnotsupp }

	policy := numa.normalize_policy(mode, raw_mask) or { return errno.err, errno.einval }
	mut pagemap := process.pagemap
	begin_mapping_update(mut pagemap) or { return errno.err, errno.get() }
	defer { end_mapping_update(mut pagemap) }
	pagemap.l.acquire()
	strict_mask := if flags & mbind_strict != 0 && mode != numa.mpol_default { ?u64(raw_mask) } else { none }
	result := bind_range_unlocked(mut pagemap, base, base + span, policy, strict_mask)
	pagemap.l.release()
	if result != 0 { return errno.err, result }
	return 0, 0
}

fn bind_range_unlocked(mut pagemap memory.Pagemap, base u64, end u64, policy proc.NumaPolicy,
	strict_mask ?u64) u64 {
	// Validate the whole interval before changing policies. Default can
	// clear mapped pieces across holes, provided at least one piece exists.
	mut cursor := base
	mut mapped := false
	for cursor < end {
		local, _, _ := addr2range(pagemap, cursor) or {
			if policy.mode != numa.mpol_default { return errno.efault }
			cursor = next_mapped_start(pagemap, cursor, end)
			continue
		}
		next := min_u64(end, local.base + local.length)
		if policy.mode != numa.mpol_default {
			if local.flags & (map_shared | map_anonymous | map_brk_reservation) != map_anonymous
				|| !page_mapping_has_node(local) {
				return errno.eopnotsupp
			}
			if mask := strict_mask {
				if !range_pages_match_policy(pagemap, cursor, next, mask) { return errno.eio }
			}
		}
		mapped = true
		cursor = next
	}
	if !mapped { return errno.efault }

	// Both outer cuts must succeed before policy updates become visible.
	split_policy_boundary_unlocked(mut pagemap, end, policy) or { return errno.get() }
	split_policy_boundary_unlocked(mut pagemap, base, policy) or { return errno.get() }
	cursor = base
	for cursor < end {
		mut local, _, _ := addr2range(pagemap, cursor) or {
			cursor = next_mapped_start(pagemap, cursor, end)
			continue
		}
		local.policy = policy
		cursor = local.base + local.length
	}
	return 0
}

fn split_policy_boundary_unlocked(mut pagemap memory.Pagemap, boundary u64, policy proc.NumaPolicy) ? {
	local, _, _ := addr2range(pagemap, boundary) or { return }
	if local.base != boundary && local.policy != policy {
		split_upper_range_unlocked(mut pagemap, local, boundary)?
	}
}

fn range_pages_match_policy(pagemap &memory.Pagemap, base u64, end u64, mask u64) bool {
	mut address := pagemap.next_present(base, end)
	for address < end {
		if physical := pagemap.virt2phys(address) {
			node := physical_page_node(physical)
			if node >= 0 && mask & (u64(1) << node) == 0 { return false }
		}
		address = pagemap.next_present(address + page_size, end)
	}
	return true
}
