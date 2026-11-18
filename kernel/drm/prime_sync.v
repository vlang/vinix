// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.gem
import drm.ioctl
import drm.syncobj
import katomic
import memory
import proc
import sched
import usercopy

const prime_access = ioctl.dma_buf_sync_read | ioctl.dma_buf_sync_write

fn prime_import_sync_file(object &gem.GemObject, address u64) int {
	mut request := ioctl.DmaBufImportSyncFile{}
	if !usercopy.copy_from_user(unsafe { &request }, address, sizeof(request)) { return -14 }
	if request.flags == 0 || u64(request.flags) & ~prime_access != 0 { return -22 }
	fence := sync_file_fence_from_fd(request.fd) or { return -22 }
	return add_prime_fences(object, fence, u64(request.flags) & ioctl.dma_buf_sync_write != 0)
}

// Prepare every pending leaf before changing the reservation. The sync-file
// source and its leaves have the same retained lifetime as other published
// fences, including after the source fd is closed.
fn add_prime_fences(object &gem.GemObject, root &syncobj.DmaFence, write bool) int {
	mut staged := &gem.PrimeFence(unsafe { nil })
	mut cursor := syncobj.FenceUnwrap{}
	mut fence := syncobj.unwrap_first(root, unsafe { &cursor })
	for fence != unsafe { nil } {
		if !syncobj.is_signaled(fence) {
			storage := memory.malloc_packed_fallible(sizeof(gem.PrimeFence))
			if storage == unsafe { nil } {
				gem.free_prime_fences(staged)
				return -12
			}
			mut entry := unsafe { &gem.PrimeFence(storage) }
			unsafe { *entry = gem.PrimeFence{source: voidptr(fence), write: write, next: staged} }
			staged = entry
		}
		fence = syncobj.unwrap_next(unsafe { &cursor })
	}
	mut source := unsafe { object }
	source.lock.acquire()
	defer { source.lock.release() }
	prime_pending_locked(mut source, true)
	for staged != unsafe { nil } {
		next := staged.next
		candidate := unsafe { &syncobj.DmaFence(staged.source) }
		if katomic.load(&candidate.signaled) {
			memory.free(voidptr(staged))
			staged = next
			continue
		}
		mut existing := unsafe { source.prime_fences }
		for existing != unsafe { nil } && existing.source != staged.source {
			existing = unsafe { existing.next }
		}
		if existing == unsafe { nil } {
			staged.next = unsafe { source.prime_fences }
			source.prime_fences = staged
		} else {
			existing.write = existing.write || staged.write
			memory.free(voidptr(staged))
		}
		staged = next
	}
	return 0
}

// Holding the GEM lock protects the list. The returned fence survives any
// removal of its record. Leaves can be checked without completion callbacks.
fn prime_pending_locked(mut object gem.GemObject, write bool) &syncobj.DmaFence {
	mut pending := &syncobj.DmaFence(unsafe { nil })
	mut link := unsafe { &object.prime_fences }
	for unsafe { *link } != unsafe { nil } {
		mut entry := unsafe { *link }
		fence := unsafe { &syncobj.DmaFence(entry.source) }
		if katomic.load(&fence.signaled) {
			unsafe { *link = entry.next }
			memory.free(voidptr(entry))
		} else {
			if pending == unsafe { nil } && (write || entry.write) { pending = fence }
			link = unsafe { &entry.next }
		}
	}
	return pending
}

fn prime_cpu_access(object &gem.GemObject, address u64) int {
	mut flags := u64(0)
	if !usercopy.copy_from_user(unsafe { &flags }, address, sizeof(flags)) { return -14 }
	if flags & ~(prime_access | ioctl.dma_buf_sync_end) != 0 || flags & prime_access == 0 { return -22 }
	if flags & ioctl.dma_buf_sync_end != 0 { return 0 }
	write := flags & ioctl.dma_buf_sync_write != 0
	mut source := unsafe { object }
	for {
		source.lock.acquire()
		pending := prime_pending_locked(mut source, write)
		source.lock.release()
		if pending == unsafe { nil } { return 0 }
		for !syncobj.is_signaled(pending) {
			task := proc.current_thread()
			if katomic.load(&task.must_exit) || proc.pending_signals(task) & ~task.masked_signals != 0 {
				return -proc.interrupted_errno
			}
			sched.reschedule()
		}
	}
	return 0
}
