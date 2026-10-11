module vmstorage

import kbudget

fn test_storage_envelope_and_overflow() {
	assert allocation_bytes(0)? == 128
	assert allocation_bytes(136)? == 512
	assert allocation_bytes(752)? == 1024
	assert allocation_bytes(4096)? == 12288
	for page in [u64(4096), 16384]! {
		assert allocation_bytes_for(1920, page)? == 2048
		assert allocation_bytes_for(1921, page)? == page * 2
		assert allocation_bytes_for(2048, page)? == page * 2
		assert allocation_bytes_for(4096, page)? == page * (if page == 4096 {
			u64(3)
		} else {
			u64(2)
		})
		assert allocation_bytes_for(page - 128, page)? == page * 2
		assert allocation_bytes_for(page - 127, page)? == page * 3
		mut overflow := false
		allocation_bytes_for(~u64(0) - 128, page) or { overflow = true }
		assert overflow
	}
	mut denied := false
	allocation_bytes(~u64(0) - 127) or { denied = true }
	assert denied
	denied = false
	allocation_bytes_for(0, 0) or { denied = true }
	assert denied
}

fn test_real_array_peak_admission_rollback_reuse_and_owner_lifetime() {
	kbudget.configure(64 * 1024 * 1024)
	initial := kbudget.snapshot()
	owner := kbudget.open_owner() or { panic('owner') }
	mut values := []voidptr{}
	mut charge := kbudget.reserve(owner, .mapping, 128) or { panic('empty buffer') }
	ensure_capacity(mut values, mut charge, 2) or { panic('first growth') }
	assert values.cap == 2 && values.len == 0 && charge.bytes == 256
	values << voidptr(0x1234)
	values << voidptr(0x5678)
	before_data := values.data
	filler := kbudget.reserve(owner, .file, initial.owner_limit - charge.bytes - 16383) or { panic('quota') }
	mut denied := false
	ensure_capacity(mut values, mut charge, 1024) or { denied = true }
	assert denied && values.data == before_data && values.cap == 2 && values.len == 2
	assert values[0] == voidptr(0x1234) && values[1] == voidptr(0x5678)
	assert charge.bytes == 256 && kbudget.snapshot().last_requested == 16384
	kbudget.release(filler)
	ensure_capacity(mut values, mut charge, 1024) or { panic('retry') }
	assert values.cap == 1024 && charge.bytes == 16384
	assert values[0] == voidptr(0x1234) && values[1] == voidptr(0x5678)
	before := kbudget.snapshot()
	ensure_capacity(mut values, mut charge, 3) or { panic('capacity reuse') }
	assert kbudget.snapshot().bytes == before.bytes && kbudget.snapshot().denials == before.denials
	// A shared global may grow after its creator has exited.
	kbudget.close_owner(owner)
	ensure_capacity(mut values, mut charge, 1025) or { panic('surviving buffer') }
	assert values.cap == 2048 && charge.bytes == allocation_bytes(u64(values.cap) * sizeof(voidptr))?
	unsafe { values.free() }
	kbudget.release(charge)
	assert kbudget.snapshot().bytes == initial.bytes && kbudget.snapshot().accounts == initial.accounts
}
