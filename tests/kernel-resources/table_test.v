module memory

import kbudget

fn test_denied_lazy_root_preserves_its_owner_until_disposal() {
	kbudget.configure(64 * 1024 * 1024)
	initial := kbudget.snapshot()
	owner := kbudget.open_owner() or { panic('owner') }
	mut shadow := Pagemap{ kernel_owner: owner }
	account_pagemap(mut shadow, owner) or { panic('base charge') }
	mut absent := false
	shadow.lookup_root(false) or { absent = true }
	assert absent && live_pages == 0 && shadow.kernel_charge.bytes == 128
	filler := kbudget.reserve(owner, .file, initial.owner_limit - shadow.kernel_charge.bytes) or { panic('quota') }
	mut failed := false
	shadow.lookup_root(true) or { failed = true }
	assert failed && shadow.top_level == unsafe { nil }
	assert shadow.kernel_charge.bytes == 128 && live_pages == 0
	kbudget.close_owner(owner)
	assert kbudget.owned_bytes(owner) == initial.owner_limit
	kbudget.release(filler)
	root := shadow.lookup_root(true) or { panic('retry after freeing quota') }
	assert root != unsafe { nil }
	assert live_pages == 1 && shadow.kernel_charge.bytes == 128 + page_size
	read_only := shadow.lookup_root(false) or { panic('existing root lookup') }
	assert voidptr(read_only) == voidptr(shadow.top_level)
	assert live_pages == 1
	dispose_pagemap_tables(mut shadow)
	assert live_pages == 0 && kbudget.owned_bytes(owner) == 0
	assert kbudget.snapshot().bytes == initial.bytes
	assert kbudget.snapshot().accounts == initial.accounts
}
