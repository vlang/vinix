module kbudget

import cgcontrol

fn test_metadata_ceiling_scales_for_development_machines_and_stays_bounded() {
	assert budget_limit(0) == 2 * 1024 * 1024
	assert budget_limit(16 * 1024 * 1024) == 2 * 1024 * 1024
	for gib in [1, 2, 4, 8, 16] {
		ram := u64(gib) * 1024 * 1024 * 1024
		assert budget_limit(ram) == ram / 8
		assert budget_limit(ram) / 2 == ram / 16
	}
	assert budget_limit(u64(32) * 1024 * 1024 * 1024) == u64(2) * 1024 * 1024 * 1024
	assert budget_limit(~u64(0)) == u64(2) * 1024 * 1024 * 1024
}

fn test_configuration_cannot_change_limits_of_live_accounts() {
	configure(64 * 1024 * 1024)
	before := snapshot()
	owner := open_owner() or { panic('account') }
	charge := reserve(owner, .mapping, 64) or { panic('reservation') }
	configure(u64(16) * 1024 * 1024 * 1024)
	after := snapshot()
	assert after.limit == before.limit && after.owner_limit == before.owner_limit
	assert owned_bytes(owner) == charge.bytes
	release(charge)
	close_owner(owner)
	assert snapshot().bytes == before.bytes && snapshot().accounts == before.accounts
}

fn test_budget_and_surviving_owner() {
	configure(64 * 1024 * 1024)
	initial := snapshot()
	assert initial.denials != 0 || initial.last_reason == -1
	owner := open_owner() or { panic('account') }
	mut charge := reserve(owner, .socket, initial.owner_limit - 8192) or { panic('reserve') }
	reserve(owner, .descriptor, 8193) or { assert snapshot().bytes == charge.bytes }
	assert !grow(mut charge, 8193)
	assert charge.bytes == initial.owner_limit - 8192
	assert grow(mut charge, 8192)
	assert snapshot().charged[int(Kind.socket)] == initial.owner_limit
	close_owner(owner)
	assert owned_bytes(owner) == initial.owner_limit
	other := open_owner() or { panic('second account') }
	assert other.slot != owner.slot
	mut second := reserve(other, .mapping, initial.owner_limit) or { panic('second charge') }
	assert snapshot().bytes == initial.limit
	assert !grow(mut second, 1)
	shrink(mut charge, 8192)
	assert grow(mut second, 8192) == false // Owner ceiling also applies.
	release(charge)
	assert owned_bytes(owner) == 0
	third := open_owner() or { panic('recycled account') }
	assert third.slot == owner.slot && third.generation != owner.generation
	mut stale_denied := false
	reserve(owner, .ipc, 1) or { stale_denied = true }
	assert stale_denied
	release(second)
	close_owner(other)
	close_owner(third)
	assert snapshot().bytes == initial.bytes
	assert snapshot().accounts == initial.accounts
	assert snapshot().objects == initial.objects
}

fn exercise(owner Owner) {
	for _ in 0 .. 10000 {
		mut charge := reserve(owner, .descriptor, 256) or { panic('parallel reserve') }
		assert grow(mut charge, 1024)
		shrink(mut charge, 1024)
		release(charge)
	}
}

fn test_parallel_charges_and_account_bound() {
	configure(64 * 1024 * 1024)
	initial := snapshot()
	owner := open_owner() or { panic('account') }
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn exercise(owner) }
	workers.wait()
	close_owner(owner)
	assert snapshot().bytes == initial.bytes
	assert snapshot().objects == initial.objects
	mut owners := []Owner{cap: max_accounts}
	for _ in 0 .. max_accounts { owners << open_owner() or { panic('account bound') } }
	mut denied := false
	open_owner() or { denied = true }
	assert denied
	for entry in owners { close_owner(entry) }
	assert snapshot().accounts == initial.accounts
}

fn assert_denial(before Snapshot, reason DenialReason, owner Owner, kind Kind, requested u64) {
	after := snapshot()
	assert after.denials == before.denials + 1
	for i in 0 .. denial_reasons {
		assert after.denied_by_reason[i] == before.denied_by_reason[i] + if i == int(reason) { u64(1) } else { u64(0) }
	}
	assert after.last_reason == int(reason) && after.last_owner == owner
	assert after.last_kind == kind && after.last_requested == requested
	assert after.last_global_bytes == before.bytes
	assert after.bytes == before.bytes && after.objects == before.objects && after.charged == before.charged
}

fn reject_reservation(owner Owner, kind Kind, bytes u64, reason DenialReason) {
	before := snapshot()
	mut denied := false
	reserve(owner, kind, bytes) or { denied = true }
	assert denied
	assert_denial(before, reason, owner, kind, bytes)
}

fn test_denial_evidence_survives_rollback_and_preserves_admission_order() {
	configure(64 * 1024 * 1024)
	initial := snapshot()
	a := open_owner() or { panic('first owner') }
	b := open_owner() or { panic('second owner') }
	c := open_owner() or { panic('third owner') }
	mut first := reserve(a, .mapping, initial.owner_limit) or { panic('owner ceiling') }
	reject_reservation(a, .mapping, 1, .owner)
	assert snapshot().last_owner_bytes == initial.owner_limit
	before_growth := snapshot()
	assert !grow(mut first, 1)
	assert_denial(before_growth, .owner, a, .mapping, 1)
	second := reserve(b, .mapping, initial.owner_limit) or { panic('global ceiling') }
	reject_reservation(a, .thread, 1, .global) // Global exhaustion precedes owner exhaustion.
	reject_reservation(c, .process, 1, .global)
	assert snapshot().last_owner_bytes == 0
	evidence := snapshot()
	release(first)
	release(second)
	assert snapshot().last_global_bytes == evidence.last_global_bytes
	assert snapshot().bytes == initial.bytes
	reject_reservation(c, .file, 0, .invalid)
	close_owner(a); close_owner(b); close_owner(c)
	reject_reservation(c, .file, 1, .invalid)
	assert snapshot().last_owner_bytes == 0
	assert snapshot().accounts == initial.accounts
}

fn test_object_and_account_denials_do_not_change_reservations() {
	configure(64 * 1024 * 1024)
	initial := snapshot()
	owner := open_owner() or { panic('owner') }
	mut charges := []Charge{cap: 512}
	for _ in 0 .. 512 { charges << reserve(owner, .scratch, 1) or { panic('object admission') } }
	reject_reservation(owner, .scratch, 1, .objects)
	assert grow(mut charges[0], 1) // Growing an existing object does not consume a slot.
	for charge in charges { release(charge) }
	close_owner(owner)
	mut owners := []Owner{cap: max_accounts}
	for _ in 0 .. max_accounts { owners << open_owner() or { panic('account admission') } }
	before := snapshot()
	mut denied := false
	open_owner() or { denied = true }
	assert denied
	assert_denial(before, .accounts, Owner{}, .process, 0)
	for account in owners { close_owner(account) }
	assert snapshot().bytes == initial.bytes && snapshot().accounts == initial.accounts
}

fn test_group_denials_preserve_both_controllers() {
	configure(64 * 1024 * 1024)
	initial := snapshot()
	mut group := cgcontrol.Group{memory_max: 64}
	owner := open_owner() or { panic('owner') }
	assert bind_group(owner, unsafe { &group }, 0)
	mut charge := reserve(owner, .socket, 64) or { panic('group admission') }
	reject_reservation(owner, .ipc, 1, .group)
	before := snapshot()
	assert !grow(mut charge, 1)
	assert_denial(before, .group, owner, .socket, 1)
	assert charge.bytes == 64 && cgcontrol.snapshot(unsafe { &group }).kernel == 64
	assert snapshot().last_owner_bytes == 64
	close_owner(owner)
	release(charge)
	assert cgcontrol.snapshot(unsafe { &group }).kernel == 0
	assert snapshot().bytes == initial.bytes && snapshot().accounts == initial.accounts
}
