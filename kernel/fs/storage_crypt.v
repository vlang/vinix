// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import aesxts
import errno
import kbudget
import memory
import proc

// One native-sector workspace keeps each IRQ-masking critical section bounded.
// Copy/allocator admission occurs outside the volume lock; all key use and
// driver I/O serialize with removal. Caller plaintext is never encrypted in place.
fn (mut volume LogicalVolume) encrypted_transfer(buffer voidptr, offset u64, bytes u64, writing bool) ?i64 {
	volume.l.acquire()
	size := u64(volume.stat.size); sector := u64(volume.stat.blksize)
	removed := volume.removed; readonly := volume.readonly
	volume.l.release()
	if removed { errno.set(errno.enodev); return none }
	if writing && readonly { errno.set(errno.erofs); return none }
	if sector == 0 || offset > size || bytes > size - offset || offset % sector != 0 || bytes % sector != 0 { errno.set(errno.einval); return none }
	if bytes == 0 { return 0 }
	if buffer == unsafe { nil } { errno.set(errno.efault); return none }
	charge := proc.reserve_kernel(.file, sector)?; defer { kbudget.release(charge) }
	workspace := memory.malloc_packed_fallible(sector) @[freed]
	if workspace == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { aesxts.erase(workspace, usize(sector)); memory.free(workspace) }
	for done := u64(0); done < bytes; done += sector {
		if writing { unsafe { C.memcpy(workspace, &u8(buffer) + done, usize(sector)) } }
		volume.encrypted_sector(workspace, offset + done, sector, writing)?
		if !writing { unsafe { C.memcpy(&u8(buffer) + done, workspace, usize(sector)) } }
	}
	volume.metrics.completed(bytes, writing)
	return i64(bytes)
}

fn (mut volume LogicalVolume) encrypted_sector(workspace voidptr, offset u64, sector u64, writing bool) ? {
	volume.l.acquire(); defer { volume.l.release() }
	if volume.removed { errno.set(errno.enodev); return none }
	if writing && !aesxts.crypt(&volume.cipher, workspace, sector, sector, offset / sector, false) { errno.set(errno.eio); volume.metrics.failed(); return none }
	mut result := i64(0)
	if writing { result = volume.parent.write(unsafe { nil }, workspace, volume.parent_offset + offset, sector) or { volume.metrics.failed(); return none } }
	else { result = volume.parent.read(unsafe { nil }, workspace, volume.parent_offset + offset, sector) or { volume.metrics.failed(); return none } }
	if result != i64(sector) { errno.set(errno.eio); volume.metrics.failed(); return none }
	if !writing && !aesxts.crypt(&volume.cipher, workspace, sector, sector, offset / sector, true) { errno.set(errno.eio); volume.metrics.failed(); return none }
}
