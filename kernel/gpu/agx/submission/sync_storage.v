// SPDX-License-Identifier: GPL-2.0-or-later
module submission

import memory

// Inline lists borrow retained syncobj/fence pointers and need no allocation.
// Dynamic lists own only their record buffer, never the pointed-to metadata.
pub fn release_sync_array(array SyncArray) {
	if array.items != unsafe { nil } { memory.free(voidptr(array.items)) }
}

// Pending work must not borrow the syscall's temporary dynamic record buffer.
// Return one independent owner; the caller releases it on failure or transfers
// it to the pending worker, which releases it after its final dependency read.
pub fn copy_sync_array(array &SyncArray) (int, SyncArray) {
	if array.items == unsafe { nil } { return 0, *array }
	bytes := u64(array.count) * sizeof(SyncItem)
	storage := memory.malloc_packed_fallible(bytes) @[freed]
	if storage == unsafe { nil } { return -12, SyncArray{} }
	unsafe { C.memcpy(storage, array.items, bytes) }
	return 0, SyncArray{ count: array.count, items: unsafe { &SyncItem(storage) } }
}
