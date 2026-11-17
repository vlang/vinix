// SPDX-License-Identifier: GPL-2.0-or-later
module submission

import memory
import drm.syncobj

// Input lists borrow fence snapshots. Outputs own syncobj references and
// may own private chain reservations until publication transfers them.
pub fn release_sync_array(array SyncArray) {
	for index := u32(0); index < array.count; index++ {
		// Taking this by-value array's address for item() boxes the whole inline
		// record in V's manual-free C. Read the scalar directly instead.
		chain := if array.items != unsafe { nil } { unsafe { array.items[index].chain } } else { array.chains[index] }
		syncobj.release_chain_reservation(chain)
		if array.owns_objects {
			object := if array.items != unsafe { nil } { unsafe { array.items[index].object } } else { array.objects[index] }
			syncobj.release_syncobj(object)
		}
	}
	if array.items != unsafe { nil } { memory.free(voidptr(array.items)) }
}

// Copy input dependencies only (never output chain reservations). Pending work
// must not borrow the syscall's temporary dynamic record buffer.
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
