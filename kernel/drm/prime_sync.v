// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.gem
import drm.ioctl
import drm.syncobj
import errno
import event.eventstruct
import file
import katomic
import memory
import proc
import resource
import sched
import usercopy

const prime_access = ioctl.dma_buf_sync_read | ioctl.dma_buf_sync_write

struct PrimePoll {
mut:
	fence &syncobj.DmaFence = unsafe { nil }
	event syncobj.FenceEvent
	generation u64
}

fn (mut this GemPrimeResource) poll_requested(requested int) resource.PollState {
	if this.obj == unsafe { nil } || !this.obj.file_scoped {
		return resource.PollState{status: this.status, generation: this.event.generation}
	}
	mut object := unsafe { this.obj }
	object.lock.acquire()
	defer { object.lock.release() }
	mut status := 0
	if requested & file.pollout != 0 && prime_poll_ready(mut object, mut this.poll_write, unsafe { &this.event }, true) {
		status |= file.pollout
	}
	if requested & file.pollin != 0 && prime_poll_ready(mut object, mut this.poll_read, unsafe { &this.event }, false) {
		status |= file.pollin
	}
	return resource.PollState{status: status, directional: true,
		generation: katomic.load(&this.poll_read.generation),
		write_generation: katomic.load(&this.poll_write.generation)}
}

// The GEM lock serializes each open description's two subscription slots.
// Leaves are retained independently of their reservation records. Completion
// takes the leaf and event locks only and can run while we scan.
fn prime_poll_ready(mut object gem.GemObject, mut watch PrimePoll, target &eventstruct.Event, write bool) bool {
	if watch.fence != unsafe { nil } {
		if !katomic.load(&watch.fence.signaled) { return false }
		syncobj.cancel_fence_event(watch.fence, unsafe { &watch.event })
		watch.fence = unsafe { nil }
	}
	for {
		pending := prime_pending_locked(mut object, write)
		if pending == unsafe { nil } { return true }
		if !syncobj.poll_leaf_event(pending, unsafe { &watch.event }, target, unsafe { &watch.generation }) {
			watch.fence = unsafe { pending }
			return false
		}
	}
	return false
}

fn prime_import_sync_file(object &gem.GemObject, address u64) int {
	mut request := ioctl.DmaBufImportSyncFile{}
	if !usercopy.copy_from_user(unsafe { &request }, address, sizeof(request)) { return -14 }
	if request.flags == 0 || u64(request.flags) & ~prime_access != 0 { return -22 }
	mut fd := file.fd_from_fdnum(unsafe { nil }, request.fd) or { return -22 }
	defer { fd.unref() }
	fence := sync_file_fence(fd) or { return -22 }
	return add_prime_fences(object, fence, u64(request.flags) & ioctl.dma_buf_sync_write != 0)
}

fn prime_export_sync_file(object &gem.GemObject, address u64) int {
	mut request := ioctl.DmaBufExportSyncFile{}
	if !usercopy.copy_from_user(unsafe { &request }, address, sizeof(request)) { return -14 }
	if request.flags == 0 || u64(request.flags) & ~prime_access != 0 { return -22 }
	mut reservation := file.FdReservation{}
	number := file.reserve_fd(unsafe { nil }, unsafe { &reservation }) or { return -int(errno.get()) }
	defer { file.cancel_fd_reservation(unsafe { &reservation }) }

	snapshot := capture_prime_fences(object, u64(request.flags) & ioctl.dma_buf_sync_write != 0) or { return -12 }
	mut fd := new_sync_file_fd(snapshot.fence, snapshot.owned, unsafe { nil }) or { return -int(errno.get()) }
	request.fd = i32(number)
	return publish_sync_file_fd(mut fd, unsafe { &reservation }, address, unsafe { &request }, sizeof(request))
}

struct PrimeSnapshot {
	fence &syncobj.DmaFence = unsafe { nil }
	owned bool
}

// Snapshot membership and access modes under the GEM lock. Any leaf that
// signals once selected stays in this snapshot with its completed status.
fn capture_prime_fences(object &gem.GemObject, write bool) ?PrimeSnapshot {
	mut source := unsafe { object }
	source.lock.acquire()
	defer { source.lock.release() }
	single := prime_pending_locked(mut source, write)
	if single == unsafe { nil } { return PrimeSnapshot{fence: syncobj.shared_timeline_stub()} }
	mut count := u32(0)
	mut entry := unsafe { source.prime_fences }
	for entry != unsafe { nil } {
		if write || entry.write {
			if count == u32(0x7fff_ffff) { return none }
			count++
		}
		entry = unsafe { entry.next }
	}
	if count == 1 { return PrimeSnapshot{fence: single} }
	storage := memory.malloc_packed_fallible(u64(count) * sizeof(voidptr))
	if storage == unsafe { nil } { return none }
	items := unsafe { &&syncobj.DmaFence(storage) }
	mut index := u32(0)
	entry = unsafe { source.prime_fences }
	for entry != unsafe { nil } {
		if write || entry.write {
			unsafe { items[index] = &syncobj.DmaFence(entry.source) }
			index++
		}
		entry = unsafe { entry.next }
	}
	array := syncobj.new_sync_file_snapshot(items, count) or {
		memory.free(storage)
		return none
	}
	return PrimeSnapshot{fence: array, owned: true}
}

// Prepare every pending leaf before changing the reservation. The caller
// pins the sync-file root during traversal. Only published leaves, which
// have a retained lifetime, remain in the GEM reservation.
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
