// SPDX-License-Identifier: GPL-2.0-or-later
// One broker event loop owns this bounded table. Tickets authorize a single
// launch in the selected origin process; no Java object crosses this boundary.
module accountinteraction

import crypto.rand
import nativeaccountauth
import time

pub struct Target {
pub:
	package_name string
	class_name   string
}

pub struct Offer {
pub:
	origin              nativeaccountauth.Caller
	caller              nativeaccountauth.Caller
	session             u64
	request             u64
	response_capability []u8
	local_handle        []u8
	target              Target
	deadline            i64 // absolute time.sys_mono_now() nanoseconds
}

// The successful redeemer owns this descriptor and must call dispose(). The
// local handle is meaningful only to the authenticated selected origin.
pub struct Launch {
pub:
	session             u64
	request             u64
	response_capability []u8
	local_handle        []u8
	target              Target
mut:
	disposed bool
}

struct Record {
	caller              nativeaccountauth.Caller
	request             u64
	ticket              [32]u8
	response_capability [32]u8
	local_handle        [32]u8
	target              Target
	deadline            i64
}

@[heap]
pub struct Table {
	origin  nativeaccountauth.Caller
	targets []Target
mut:
	records map[u64]Record
	closed  bool
}

fn identifier(value string, class_name bool) bool {
	if value.len == 0 || value.len > 255 { return false }
	mut first := true
	mut dot := false
	for index in 0 .. value.len {
		byte := value[index]
		if byte == `.` {
			if first { return false }
			first = true
			dot = true
			continue
		}
		if first && !(byte.is_letter() || byte == `_`) { return false }
		if !(byte.is_alnum() || byte == `_` || (class_name && byte == `$`)) { return false }
		first = false
	}
	return dot && !first
}

fn digest(value string) bool {
	if value.len != 64 { return false }
	for index in 0 .. value.len {
		byte := value[index]
		if !((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`)) { return false }
	}
	return true
}

fn identity_valid(caller nativeaccountauth.Caller) bool {
	return identifier(caller.package_name, false) && caller.uid >= 10000 && caller.uid <= 19999
		&& caller.gid >= 10000 && caller.gid <= 19999 && caller.pid > 0
		&& digest(caller.apk_sha256) && digest(caller.certificate_sha256)
}

fn same_identity(a nativeaccountauth.Caller, b nativeaccountauth.Caller) bool {
	return a.uid == b.uid && a.gid == b.gid && a.pid == b.pid && a.package_name == b.package_name
		&& a.apk_sha256 == b.apk_sha256 && a.certificate_sha256 == b.certificate_sha256
}

fn copy_identity(caller nativeaccountauth.Caller) nativeaccountauth.Caller {
	return nativeaccountauth.Caller{caller.package_name.clone(), caller.uid, caller.gid, caller.pid, caller.apk_sha256.clone(), caller.certificate_sha256.clone()}
}

fn free_identity(caller nativeaccountauth.Caller) {
	unsafe {
		caller.package_name.free()
		caller.apk_sha256.free()
		caller.certificate_sha256.free()
	}
}

fn copy_target(target Target) Target {
	return Target{target.package_name.clone(), target.class_name.clone()}
}

fn free_target(target Target) {
	unsafe {
		target.package_name.free()
		target.class_name.free()
	}
}

fn same_target(a Target, b Target) bool {
	return a.package_name == b.package_name && a.class_name == b.class_name
}

fn capability_valid(value []u8) bool {
	if value.len != 32 { return false }
	mut nonzero := u8(0)
	for byte in value { nonzero |= byte }
	return nonzero != 0
}

fn same_capability(a []u8, b []u8) bool {
	if a.len != 32 || b.len != 32 { return false }
	mut difference := u8(0)
	for index in 0 .. 32 { difference |= a[index] ^ b[index] }
	return difference == 0
}

fn fixed_matches(a [32]u8, b []u8) bool {
	if b.len != 32 { return false }
	mut difference := u8(0)
	for index in 0 .. 32 { difference |= a[index] ^ b[index] }
	return difference == 0
}

fn fixed_capability(value []u8) [32]u8 {
	mut result := [32]u8{}
	for index in 0 .. 32 { result[index] = value[index] }
	return result
}

fn owned_capability(value [32]u8) []u8 {
	mut result := []u8{len: 32}
	for index in 0 .. 32 { result[index] = value[index] }
	return result
}

// The administrator chooses the origin and exact component allowlist. Offers
// may select one of those components, never add a new component to the table.
pub fn create(origin nativeaccountauth.Caller, targets []Target) !&Table {
	if !identity_valid(origin) || targets.len == 0 || targets.len > 256 {
		return error('invalid interaction origin or target count')
	}
	for index, target in targets {
		if target.package_name != origin.package_name || !identifier(target.class_name, true) {
			return error('invalid interaction target')
		}
		for previous in 0 .. index {
			if same_target(targets[previous], target) {
				return error('duplicate interaction target')
			}
		}
	}
	mut selected := []Target{cap: targets.len}
	for target in targets { selected << copy_target(target) }
	return &Table{ origin: copy_identity(origin), targets: selected }
}

fn (table Table) target_allowed(target Target) bool {
	for selected in table.targets {
		if same_target(selected, target) { return true }
	}
	return false
}

// The root broker must authenticate origin and caller from their Unix peers,
// and compare the offered response capability with its original live session
// before calling offer. This table never treats wire identity claims as proof.
pub fn (mut table Table) offer(offer Offer) ![]u8 {
	return table.offer_at(offer, time.sys_mono_now())
}

fn (mut table Table) offer_at(offer Offer, now i64) ![]u8 {
	if table.closed { return error('interaction table is closed') }
	table.expire_at(now)
	if !same_identity(table.origin, offer.origin) || !identity_valid(offer.caller)
		|| offer.session == 0 || offer.request == 0 || offer.session in table.records
		|| !capability_valid(offer.response_capability) || !capability_valid(offer.local_handle)
		|| same_capability(offer.response_capability, offer.local_handle)
		|| !table.target_allowed(offer.target) || now < 0 || offer.deadline <= now
		|| offer.deadline - now > 5 * time.minute || table.records.len >= 32 {
		return error('invalid or unavailable interaction offer')
	}
	for _, record in table.records {
		if fixed_matches(record.ticket, offer.local_handle)
			|| fixed_matches(record.ticket, offer.response_capability) {
			return error('interaction secrets must be distinct from public tickets')
		}
	}
	// A random collision cannot make an internal handle or response capability
	// usable as a public ticket. Retry a bounded number of times on collisions.
	for _ in 0 .. 8 {
		ticket := rand.bytes(32)!
		mut collision := !capability_valid(ticket)
			|| same_capability(ticket, offer.response_capability)
			|| same_capability(ticket, offer.local_handle)
		for _, record in table.records {
			collision = collision || fixed_matches(record.ticket, ticket)
				|| fixed_matches(record.response_capability, ticket)
				|| fixed_matches(record.local_handle, ticket)
		}
		if collision {
			unsafe { ticket.free() }
			continue
		}
		table.records[offer.session] = Record{
			caller:              copy_identity(offer.caller)
			request:             offer.request
			ticket:              fixed_capability(ticket)
			response_capability: fixed_capability(offer.response_capability)
			local_handle:        fixed_capability(offer.local_handle)
			target:              copy_target(offer.target)
			deadline:            offer.deadline
		}
		return ticket
	}
	return error('cannot mint a distinct interaction ticket')
}

// Caller is an authenticated peer identity, never a package supplied by the
// redeemer. Redemption accepts no replacement response or target fields.
pub fn (mut table Table) redeem(caller nativeaccountauth.Caller, request u64, ticket []u8) !Launch {
	return table.redeem_at(caller, request, ticket, time.sys_mono_now())
}

fn (mut table Table) redeem_at(caller nativeaccountauth.Caller, request u64, ticket []u8, now i64) !Launch {
	if table.closed { return error('interaction table is closed') }
	table.expire_at(now)
	if !identity_valid(caller) || request == 0 || !capability_valid(ticket) {
		return error('invalid interaction redemption')
	}
	for session, record in table.records {
		if !fixed_matches(record.ticket, ticket) { continue }
		if record.request != request || !same_identity(record.caller, caller) {
			return error('interaction caller or request does not match')
		}
		launch := Launch{
			session:             session
			request:             record.request
			response_capability: owned_capability(record.response_capability)
			local_handle:        owned_capability(record.local_handle)
			target:              copy_target(record.target)
		}
		table.revoke(session)
		return launch
	}
	return error('unknown or expired interaction ticket')
}

// Revocation also covers completion, service disconnect and caller disconnect.
pub fn (mut table Table) revoke(session u64) {
	if table.closed { return }
	record := table.records[session] or { return }
	free_identity(record.caller)
	free_target(record.target)
	// Overwrite the retained map value before deletion, including all secrets.
	table.records[session] = Record{}
	table.records.delete(session)
}

pub fn (mut table Table) expire() {
	table.expire_at(time.sys_mono_now())
}

fn (mut table Table) expire_at(now i64) {
	if table.closed { return }
	mut expired := []u64{cap: table.records.len}
	for session, record in table.records {
		if record.deadline <= now { expired << session }
	}
	for session in expired { table.revoke(session) }
	unsafe { expired.free() }
}

pub fn (table Table) len() int {
	return if table.closed { 0 } else { table.records.len }
}

pub fn (mut table Table) close() {
	if table.closed { return }
	mut sessions := []u64{cap: table.records.len}
	for session, _ in table.records { sessions << session }
	for session in sessions { table.revoke(session) }
	unsafe { sessions.free() }
	free_identity(table.origin)
	for target in table.targets { free_target(target) }
	unsafe {
		table.targets.free()
		table.records.free()
	}
	table.closed = true
}

pub fn (mut launch Launch) dispose() {
	if launch.disposed { return }
	free_target(launch.target)
	unsafe {
		launch.response_capability.free()
		launch.local_handle.free()
	}
	launch.disposed = true
}
