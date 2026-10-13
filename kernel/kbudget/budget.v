// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module kbudget

import klock
import cgcontrol

// Metadata and buffers created on behalf of users must not consume the
// reserve needed to finish exit, close and unmap. These are reservations,
// including allocator rounding and capacity growth, rather than slab RSS.
pub enum Kind {
	file
	descriptor
	socket
	ipc
	mapping
	process
	thread
	scratch
}

pub const kinds = 8
pub const max_accounts = 4096

pub struct Owner {
pub:
	slot       u32
	generation u64
}

pub struct Charge {
pub mut:
	owner Owner
	bytes u64
	kind  Kind
	group_retired bool
}

struct Account {
mut:
	group      &cgcontrol.Group = unsafe { nil }
	generation u64
	open       bool
	bytes      u64
	group_bytes u64
	refs       u64
}

pub enum DenialReason {
	invalid
	accounts
	objects
	global
	owner
	group
}

pub const denial_reasons = 6

pub struct Snapshot {
pub mut:
	limit       u64
	owner_limit u64
	bytes       u64
	denials     u64
	denied_by_reason [denial_reasons]u64
	last_reason int = -1
	last_owner Owner
	last_kind Kind
	last_requested u64
	last_global_bytes u64
	last_owner_bytes u64
	accounts    u64
	objects     [kinds]u64
	charged     [kinds]u64
}

__global (
	resource_budget_lock       klock.Lock
	resource_budget_accounts   [max_accounts]Account
	resource_budget_stats      Snapshot
	resource_budget_generation u64
)

fn budget_limit(total u64) u64 {
	mut limit := total / 8
	if limit < 2 * 1024 * 1024 { limit = 2 * 1024 * 1024 }
	// Retain the RAM fraction on development machines above 4 GiB. A fixed
	// 512 MiB ceiling left an 8 GiB machine's compiler with only 256 MiB of
	// mapping metadata even while most physical memory remained available.
	maximum := u64(2) * 1024 * 1024 * 1024
	if limit > maximum { limit = maximum }
	return limit
}

// Called before publishing the first user process. Subsequent calls preserve
// live reservations. No dynamically allocated accounting object is needed.
pub fn configure(total u64) {
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	if resource_budget_stats.limit != 0 { return }
	limit := budget_limit(total)
	resource_budget_stats.limit = limit
	resource_budget_stats.owner_limit = limit / 2
	if resource_budget_stats.denials == 0 { resource_budget_stats.last_reason = -1 }
}

pub fn open_owner() ?Owner {
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	for i in 0 .. max_accounts {
		if resource_budget_accounts[i].open || resource_budget_accounts[i].refs != 0 { continue }
		resource_budget_generation++
		if resource_budget_generation == 0 { resource_budget_generation++ }
		resource_budget_accounts[i] = Account{ generation: resource_budget_generation, open: true }
		resource_budget_stats.accounts++
		return Owner{ slot: u32(i + 1), generation: resource_budget_generation }
	}
	note_denial(.accounts, Owner{}, .process, 0)
	return none
}

fn valid(owner Owner) bool {
	return owner.slot > 0 && owner.slot <= max_accounts
		&& resource_budget_accounts[owner.slot - 1].generation == owner.generation
		&& (resource_budget_accounts[owner.slot - 1].open || resource_budget_accounts[owner.slot - 1].refs != 0)
}

pub fn close_owner(owner Owner) {
	if owner.slot == 0 { return }
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	if !valid(owner) || !resource_budget_accounts[owner.slot - 1].open { return }
	resource_budget_accounts[owner.slot - 1].open = false
	if resource_budget_accounts[owner.slot - 1].refs == 0 { resource_budget_stats.accounts-- }
}

// Caller serializes process membership and task publication with pid_lock.
// Creator-owned objects stay charged here after their process has exited.
pub fn bind_group(owner Owner, group &cgcontrol.Group, tasks u64) bool {
	return bind_group_memory(owner, group, tasks, 0)
}

pub fn bind_group_memory(owner Owner, group &cgcontrol.Group, tasks u64, anonymous u64) bool {
	if owner.slot == 0 { return tasks == 0 }
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	if !valid(owner) { return false }
	mut account := unsafe { &resource_budget_accounts[owner.slot - 1] }
	if !cgcontrol.move_workload(account.group, group, account.group_bytes, tasks, anonymous) { return false }
	account.group = unsafe { group }
	return true
}

// Called under resource_budget_lock. Capture the rejected reservation before
// its caller rolls back earlier work; scalar evidence survives that rollback.
fn note_denial(reason DenialReason, owner Owner, kind Kind, bytes u64) {
	resource_budget_stats.denials++
	resource_budget_stats.denied_by_reason[int(reason)]++
	resource_budget_stats.last_reason = int(reason)
	resource_budget_stats.last_owner = owner
	resource_budget_stats.last_kind = kind
	resource_budget_stats.last_requested = bytes
	resource_budget_stats.last_global_bytes = resource_budget_stats.bytes
	resource_budget_stats.last_owner_bytes = if valid(owner) {
		resource_budget_accounts[owner.slot - 1].bytes
	} else { u64(0) }
}

fn capacity_allowed(owner Owner, kind Kind, bytes u64, check_objects bool) bool {
	if bytes == 0 || !valid(owner) {
		note_denial(.invalid, owner, kind, bytes)
		return false
	}
	if check_objects && resource_budget_stats.objects[int(kind)] >= object_limit(kind) {
		note_denial(.objects, owner, kind, bytes)
		return false
	}
	if bytes > resource_budget_stats.limit - resource_budget_stats.bytes {
		note_denial(.global, owner, kind, bytes)
		return false
	}
	if bytes > resource_budget_stats.owner_limit - resource_budget_accounts[owner.slot - 1].bytes {
		note_denial(.owner, owner, kind, bytes)
		return false
	}
	return true
}

pub fn reserve(owner Owner, kind Kind, bytes u64) ?Charge {
	// Boot-time objects and internal kernel tasks have no user account.
	if owner.slot == 0 { return Charge{} }
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	if !capacity_allowed(owner, kind, bytes, true) {
		return none
	}
	if !cgcontrol.reserve(resource_budget_accounts[owner.slot - 1].group, bytes, 0) {
		note_denial(.group, owner, kind, bytes)
		return none
	}
	resource_budget_accounts[owner.slot - 1].refs++
	resource_budget_accounts[owner.slot - 1].bytes += bytes
	resource_budget_accounts[owner.slot - 1].group_bytes += bytes
	resource_budget_stats.bytes += bytes
	resource_budget_stats.objects[int(kind)]++
	resource_budget_stats.charged[int(kind)] += bytes
	return Charge{ owner: owner, bytes: bytes, kind: kind }
}

// Grow before allocating replacement storage; shrink only after freeing the
// old allocation. The reservation therefore covers both at the peak.
pub fn grow(mut charge Charge, bytes u64) bool {
	if charge.owner.slot == 0 || bytes == 0 { return true }
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	if !capacity_allowed(charge.owner, charge.kind, bytes, false) {
		return false
	}
	if !charge.group_retired && !cgcontrol.reserve(resource_budget_accounts[charge.owner.slot - 1].group, bytes, 0) {
		note_denial(.group, charge.owner, charge.kind, bytes)
		return false
	}
	resource_budget_accounts[charge.owner.slot - 1].bytes += bytes
	if !charge.group_retired { resource_budget_accounts[charge.owner.slot - 1].group_bytes += bytes }
	resource_budget_stats.bytes += bytes
	resource_budget_stats.charged[int(charge.kind)] += bytes
	charge.bytes += bytes
	return true
}

pub fn shrink(mut charge Charge, bytes u64) {
	if charge.owner.slot == 0 || bytes == 0 { return }
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	assert valid(charge.owner) && bytes < charge.bytes
	if !charge.group_retired {
		cgcontrol.release(resource_budget_accounts[charge.owner.slot - 1].group, bytes, 0)
		resource_budget_accounts[charge.owner.slot - 1].group_bytes -= bytes
	}
	charge.bytes -= bytes
	resource_budget_accounts[charge.owner.slot - 1].bytes -= bytes
	resource_budget_stats.bytes -= bytes
	resource_budget_stats.charged[int(charge.kind)] -= bytes
}

// A charge belongs to one object and is released exactly once. Its owner can
// have exited: scalar slot/generation identity never borrows a Process pointer.
pub fn release(charge Charge) {
	if charge.owner.slot == 0 { return }
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	assert valid(charge.owner) && charge.bytes != 0
	mut account := unsafe { &resource_budget_accounts[charge.owner.slot - 1] }
	if !charge.group_retired {
		cgcontrol.release(account.group, charge.bytes, 0)
		account.group_bytes -= charge.bytes
	}
	account.bytes -= charge.bytes
	account.refs--
	resource_budget_stats.bytes -= charge.bytes
	resource_budget_stats.objects[int(charge.kind)]--
	resource_budget_stats.charged[int(charge.kind)] -= charge.bytes
	if !account.open && account.refs == 0 { resource_budget_stats.accounts-- }
}

// One dead stack per CPU may wait for a later scheduler death before being
// physically freed. Keep its global/creator reservation, but retire its task
// workload charge when its TID disappears so it cannot block group recovery.
pub fn retire_thread_group(mut charge Charge) {
	if charge.owner.slot == 0 || charge.group_retired { return }
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	assert valid(charge.owner) && charge.kind == .thread
	mut account := unsafe { &resource_budget_accounts[charge.owner.slot - 1] }
	cgcontrol.release(account.group, charge.bytes, 0)
	account.group_bytes -= charge.bytes
	charge.group_retired = true
}

pub fn owned_bytes(owner Owner) u64 {
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	return if valid(owner) { resource_budget_accounts[owner.slot - 1].bytes } else { u64(0) }
}

pub fn group_of(owner Owner) &cgcontrol.Group {
	if owner.slot == 0 { return unsafe { nil } }
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	return if valid(owner) { resource_budget_accounts[owner.slot - 1].group } else { unsafe { nil } }
}

pub fn snapshot() Snapshot {
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	return resource_budget_stats
}

fn object_limit(kind Kind) u64 {
	return match kind {
		.descriptor { u64(65536) }
		.file, .mapping { u64(65536) }
		.socket, .ipc, .process { u64(4096) }
		.thread { u64(4096) }
		.scratch { u64(512) }
	}
}
