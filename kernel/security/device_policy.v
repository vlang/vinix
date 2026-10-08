// SPDX-License-Identifier: GPL-2.0-or-later
module security

import errno
import klock
import resource
import stat

struct BlockDevicePolicy {
mut:
	identity resource.BlockIdentity
	active_writes u64
	pending_mounts u64
	protected bool
	swap_claimed bool
}

__global (
	block_policy_lock klock.Lock
	block_device_policies []BlockDevicePolicy
)

// The inventory owns scalar rows for the lifetime of the device registry.
// Rows are never deleted or reordered; tokens are indices, so neither an
// array reallocation nor sleeping in a driver leaves a borrowed pointer.
pub fn register_block_device(identity resource.BlockIdentity) {
	if !identity.valid() { return }
	block_policy_lock.acquire()
	defer { block_policy_lock.release() }
	if block_policy_index(identity) >= 0 { return }
	block_device_policies.flags |= .noslices
	block_device_policies << BlockDevicePolicy{identity: identity}
}

fn block_policy_index(identity resource.BlockIdentity) int {
	for index, entry in block_device_policies {
		if entry.identity.disk_id == identity.disk_id && entry.identity.start == identity.start
			&& entry.identity.length == identity.length { return index }
	}
	return -1
}

fn block_write_allowed_locked(identity resource.BlockIdentity) bool {
	for entry in block_device_policies {
		if entry.swap_claimed && identity.overlaps(entry.identity) {
			errno.set(errno.ebusy); return false
		}
	}
	level := securelevel()
	if level >= 2 || (level >= 1 && !identity.valid()) {
		errno.set(errno.eperm)
		return false
	}
	if level < 1 { return true }
	for entry in block_device_policies {
		if (entry.protected || entry.pending_mounts != 0) && identity.overlaps(entry.identity) {
			errno.set(errno.eperm)
			return false
		}
	}
	return true
}

// Enforce at the open-description/userspace boundary, not in a disk driver:
// the latter would also prohibit filesystem cache and metadata writeback.
pub fn user_device_write_allowed(mut res resource.Resource) bool {
	identity := resource.block_identity(mut res)
	if !stat.isblk(res.stat.mode) && !identity.is_block { return true }
	block_policy_lock.acquire()
	defer { block_policy_lock.release() }
	return block_write_allowed_locked(identity)
}

// Linearize a direct userspace write with mount reservation. The short lock
// is released before any handle/device lock or I/O; a successful token is
// returned exactly once after the physical operation finishes.
pub fn begin_user_device_write(mut res resource.Resource) ?int {
	identity := resource.block_identity(mut res)
	if !stat.isblk(res.stat.mode) && !identity.is_block { return -1 }
	block_policy_lock.acquire()
	defer { block_policy_lock.release() }
	if !block_write_allowed_locked(identity) { return none }
	if !identity.valid() { return -1 } // Insecure RAM-backed block-mode inode.
	index := block_policy_index(identity)
	if index < 0 {
		errno.set(errno.enodev)
		return none
	}
	if block_device_policies[index].active_writes == u64(-1) {
		errno.set(errno.ebusy)
		return none
	}
	block_device_policies[index].active_writes++
	return index
}

pub fn end_user_device_write(token int) {
	if token < 0 { return }
	block_policy_lock.acquire()
	defer { block_policy_lock.release() }
	if token < block_device_policies.len && block_device_policies[token].active_writes != 0 {
		block_device_policies[token].active_writes--
	}
}

// Reserve before constructing/publishing a disk-backed filesystem. A mount
// racing a prior overlapping raw write retries with EBUSY rather than holding
// an interrupt-disabling lock across the driver's potentially sleeping I/O.
pub fn begin_block_mount(identity resource.BlockIdentity) ?int {
	block_policy_lock.acquire()
	defer { block_policy_lock.release() }
	index := block_policy_index(identity)
	if !identity.valid() || index < 0 {
		errno.set(errno.enodev)
		return none
	}
	for entry in block_device_policies {
		if (entry.active_writes != 0 || entry.swap_claimed) && identity.overlaps(entry.identity) {
			errno.set(errno.ebusy)
			return none
		}
	}
	if block_device_policies[index].pending_mounts == u64(-1) {
		errno.set(errno.eoverflow)
		return none
	}
	block_device_policies[index].pending_mounts++
	return index
}

// Swap owns its whole physical extent at every securelevel. Reservations
// exclude mounts, existing raw writes, and alias/whole-disk userspace writes.
pub fn claim_swap(identity resource.BlockIdentity) ?int {
	block_policy_lock.acquire()
	defer { block_policy_lock.release() }
	index := block_policy_index(identity)
	if !identity.valid() || index < 0 { errno.set(errno.enodev); return none }
	for entry in block_device_policies {
		if identity.overlaps(entry.identity) && (entry.protected || entry.pending_mounts != 0
			|| entry.active_writes != 0 || entry.swap_claimed) { errno.set(errno.ebusy); return none }
	}
	block_device_policies[index].swap_claimed = true
	return index
}

pub fn release_swap(token int) {
	block_policy_lock.acquire()
	if token >= 0 && token < block_device_policies.len { block_device_policies[token].swap_claimed = false }
	block_policy_lock.release()
}

pub fn finish_block_mount(token int, committed bool) {
	if token < 0 { return }
	block_policy_lock.acquire()
	defer { block_policy_lock.release() }
	if token >= block_device_policies.len || block_device_policies[token].pending_mounts == 0 { return }
	block_device_policies[token].pending_mounts--
	if committed { block_device_policies[token].protected = true }
}
