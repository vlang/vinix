// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module kbudget

import klock

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
}

struct Account {
mut:
	generation u64
	open       bool
	bytes      u64
	refs       u64
}

pub struct Snapshot {
pub mut:
	limit       u64
	owner_limit u64
	bytes       u64
	denials     u64
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

// Called before publishing the first user process. Subsequent calls preserve
// live reservations. No dynamically allocated accounting object is needed.
pub fn configure(total u64) {
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	if resource_budget_stats.limit != 0 { return }
	mut limit := total / 8
	if limit < 2 * 1024 * 1024 { limit = 2 * 1024 * 1024 }
	if limit > 512 * 1024 * 1024 { limit = 512 * 1024 * 1024 }
	resource_budget_stats.limit = limit
	resource_budget_stats.owner_limit = limit / 2
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
	resource_budget_stats.denials++
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

pub fn reserve(owner Owner, kind Kind, bytes u64) ?Charge {
	// Boot-time objects and internal kernel tasks have no user account.
	if owner.slot == 0 { return Charge{} }
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	if bytes == 0 || !valid(owner) || resource_budget_stats.objects[int(kind)] >= object_limit(kind)
		|| bytes > resource_budget_stats.limit - resource_budget_stats.bytes
		|| bytes > resource_budget_stats.owner_limit - resource_budget_accounts[owner.slot - 1].bytes {
		resource_budget_stats.denials++
		return none
	}
	resource_budget_accounts[owner.slot - 1].refs++
	resource_budget_accounts[owner.slot - 1].bytes += bytes
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
	if !valid(charge.owner) || bytes > resource_budget_stats.limit - resource_budget_stats.bytes
		|| bytes > resource_budget_stats.owner_limit - resource_budget_accounts[charge.owner.slot - 1].bytes {
		resource_budget_stats.denials++
		return false
	}
	resource_budget_accounts[charge.owner.slot - 1].bytes += bytes
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
	account.bytes -= charge.bytes
	account.refs--
	resource_budget_stats.bytes -= charge.bytes
	resource_budget_stats.objects[int(charge.kind)]--
	resource_budget_stats.charged[int(charge.kind)] -= charge.bytes
	if !account.open && account.refs == 0 { resource_budget_stats.accounts-- }
}

pub fn owned_bytes(owner Owner) u64 {
	resource_budget_lock.acquire()
	defer { resource_budget_lock.release() }
	return if valid(owner) { resource_budget_accounts[owner.slot - 1].bytes } else { u64(0) }
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
		.thread { u64(256) }
		.scratch { u64(512) }
	}
}
