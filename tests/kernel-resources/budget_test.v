module kbudget

fn test_budget_and_surviving_owner() {
	configure(64 * 1024 * 1024)
	initial := snapshot()
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
