@[has_globals]
module ext2

import katomic
import klock
import pagecache
import memory

const mapped_writeback_batch = 16

__global (
	mapped_resources_first &EXT2Resource = unsafe { nil }
	mapped_resources_last  &EXT2Resource = unsafe { nil }
	mapped_resources_lock  klock.Lock
	mapped_resources_serial u64
	mapped_reclaim_cursor u64
	mapped_writeback_registered bool
)

fn register_mapped_writeback() bool {
	mapped_resources_lock.acquire()
	defer { mapped_resources_lock.release() }
	if mapped_writeback_registered { return true }
	if !pagecache.register_sync_hook(sync_mapped_resources) { return false }
	memory.register_file_pageout(reclaim_mapped_resources)
	mapped_writeback_registered = true
	return true
}

// Only sleepable pressure work enters this bridge. Registry pins survive
// unlink and concurrent unmap; every vnode callback runs outside its lock.
fn reclaim_mapped_resources(wanted u64, foreground bool) u64 {
	mapped_resources_lock.acquire()
	bound := mapped_resources_serial
	mut cursor := if foreground { u64(0) } else { mapped_reclaim_cursor }
	mapped_resources_lock.release()
	mut reclaimed := u64(0)
	for reclaimed < wanted {
		mut batch := unsafe { [mapped_writeback_batch]&EXT2Resource{} }
		mut count := 0
		mapped_resources_lock.acquire()
		mut entry := mapped_resources_first
		for entry != unsafe { nil } && count < mapped_writeback_batch {
			if entry.mapped_serial > cursor && entry.mapped_serial <= bound {
				katomic.inc(mut &entry.refcount)
				batch[count] = entry
				count++
				cursor = entry.mapped_serial
			}
			entry = entry.mapped_next
		}
		if !foreground { mapped_reclaim_cursor = if count == 0 { u64(0) } else { cursor } }
		mapped_resources_lock.release()
		if count == 0 { break }
		for i in 0 .. count {
			mut target := batch[i]
			if reclaimed < wanted { reclaimed += target.reclaim_mapped_pages(wanted - reclaimed, foreground) }
			target.unref(unsafe { nil }) or {}
		}
		if !foreground { break }
	}
	return reclaimed
}

// Caller holds the resource lock. The registry owns one strong reference
// while pages exist, including zero-mapping-ref pages whose writeback failed.
// This keeps an unlinked inode alive until retry has preserved its last data.
fn (mut this EXT2Resource) register_mapped_resource() {
	mapped_resources_lock.acquire()
	defer { mapped_resources_lock.release() }
	if this.mapped_registered { return }
	katomic.inc(mut &this.refcount)
	mapped_resources_serial++
	this.mapped_serial = mapped_resources_serial
	this.mapped_previous = mapped_resources_last
	this.mapped_next = unsafe { nil }
	if mapped_resources_last != unsafe { nil } {
		mapped_resources_last.mapped_next = this
	} else {
		mapped_resources_first = this
	}
	mapped_resources_last = this
	this.mapped_registered = true
}

// Caller holds the resource lock. Return the registry's reference to drop
// AFTER both resource and filesystem locks have been released. The caller
// must retain its own handle/mapping/sweep pin through that deferred drop.
fn (mut this EXT2Resource) unregister_empty_mapped_resource() bool {
	if this.mapped_pages.len != 0 { return false }
	mapped_resources_lock.acquire()
	defer { mapped_resources_lock.release() }
	if !this.mapped_registered { return false }
	if this.mapped_previous != unsafe { nil } {
		this.mapped_previous.mapped_next = this.mapped_next
	} else {
		mapped_resources_first = this.mapped_next
	}
	if this.mapped_next != unsafe { nil } {
		this.mapped_next.mapped_previous = this.mapped_previous
	} else {
		mapped_resources_last = this.mapped_previous
	}
	this.mapped_next = unsafe { nil }
	this.mapped_previous = unsafe { nil }
	this.mapped_registered = false
	return true
}

fn sync_mapped_resources() bool {
	mapped_resources_lock.acquire()
	bound := mapped_resources_serial
	mapped_resources_lock.release()
	mut cursor := u64(0)
	mut ok := true
	for {
		mut batch := unsafe { [mapped_writeback_batch]&EXT2Resource{} }
		mut count := 0
		// Pin a fixed batch, never acquire resource/filesystem locks or do
		// I/O under the registry lock. No raw cursor survives this lock.
		mapped_resources_lock.acquire()
		mut entry := mapped_resources_first
		for entry != unsafe { nil } && count < mapped_writeback_batch {
			if entry.mapped_serial > cursor && entry.mapped_serial <= bound {
				katomic.inc(mut &entry.refcount)
				batch[count] = entry
				count++
				cursor = entry.mapped_serial
			}
			entry = entry.mapped_next
		}
		mapped_resources_lock.release()
		if count == 0 { break }
		for i := 0; i < count; i++ {
			mut target := batch[i]
			target.write_mapped_pages(0, u64(-1)) or { ok = false }
			target.unref(unsafe { nil }) or { ok = false }
		}
	}
	return ok
}
