module fs

import katomic
import klock
import proc
import stat
import time

// ── Freeing what a name leaves behind ──────────────────────────────
// A regular file, symlink or socket whose name is unlinked, and a memfd, is
// reachable only through its open-file descriptions once it has no name.
// When the last of those goes, its node was still never freed, and with it
// its name: 200 bytes for every temporary file ever made.
//
// It is not freed at once. Path lookups run without the VFS lock and may
// still hold a node from before the unlink; and a process keeps the node of
// the program it runs for /proc/<pid>/exe even when nothing maps it any more,
// as when it has exited. So each waits here for removed_grace_ns, far longer
// than a lookup takes, and is freed then only if no process runs it.
//
// Directories are not freed: a file still open, or a directory still someone's
// cwd, keeps a removed directory as its parent.
const removed_grace_ns = u64(5_000_000_000)
// Reaping scans the process table, so it is not done more often than this.
const removed_reap_interval_ns = u64(1_000_000_000)

// A node, or memory for free_after_grace(), and when it was retired.
struct RetiredItem {
	node  &VFSNode = unsafe { nil }
	bytes &u8      = unsafe { nil }
	at    u64
}

__global (
	removed_lock      klock.Lock
	removed_items     []RetiredItem
	removed_last_reap u64
)

// orphan_node marks a node that no name leads to any more, and retires it
// once no open-file description does either. `mode` is read before the name's
// reference is dropped, which may free the resource.
fn orphan_node(mut node VFSNode, mode u32) {
	if !(stat.isreg(mode) || stat.islnk(mode) || stat.issock(mode)) || pinned(node) {
		return
	}
	node.orphan = true
	if katomic.load(&node.handles) == 0 {
		retire_node(mut node)
	}
}

// Whether something holds `node` without a count, so that it is never freed:
// an overlay built on it, or a mount on it or of it, now or once, here or in
// another mount namespace.
fn pinned(node &VFSNode) bool {
	return node.overlaid || node.mount_covered || node.mount_root || node.ns_mounts > 0
		|| node.mountpoint != unsafe { nil }
}

// Called with a handle's node as the handle is freed.
fn release_handle_node(node voidptr) {
	mut n := unsafe { &VFSNode(node) }
	if !katomic.dec(mut &n.handles) && n.orphan {
		retire_node(mut n)
	}
}

fn retire_node(mut node VFSNode) {
	// The last handle and the unlink can both find the node unreachable; only
	// one of them hands it over.
	if !katomic.cas(mut &node.retired, u32(0), u32(1)) {
		return
	}
	retire(RetiredItem{
		node: unsafe { node }
	})
}

// free_after_grace frees `ptr` after the grace period, for memory another CPU
// may still be using: a socket just looked up by name, say.
pub fn free_after_grace(ptr voidptr) {
	if ptr == unsafe { nil } {
		return
	}
	retire(RetiredItem{
		bytes: unsafe { &u8(ptr) }
	})
}

fn retire(item RetiredItem) {
	removed_lock.acquire()
	// Nothing slices the list, so growing it frees the buffer it outgrew.
	removed_items.flags |= .noslices
	removed_items << RetiredItem{
		node:  item.node
		bytes: item.bytes
		at:    time.monotonic_ns()
	}
	removed_lock.release()
	reap_removed()
}

// reap_removed frees what has waited out its grace period. The writeback
// thread calls it as well, so the last few do not wait for more to come.
pub fn reap_removed() {
	now := time.monotonic_ns()
	removed_lock.acquire()
	if now - removed_last_reap < removed_reap_interval_ns || removed_items.len == 0 {
		removed_lock.release()
		return
	}
	removed_last_reap = now
	mut due := 0
	for due < removed_items.len && now - removed_items[due].at >= removed_grace_ns {
		due++
	}
	if due == 0 {
		removed_lock.release()
		return
	}
	// Taken off the front, oldest first, and dealt with outside the lock.
	mut items := []RetiredItem{cap: due} @[freed]
	for i in 0 .. due {
		items << removed_items[i]
	}
	removed_items.delete_many(0, due)
	removed_lock.release()

	mut nodes := []voidptr{cap: due} @[freed]
	for item in items {
		if item.node != unsafe { nil } {
			nodes << voidptr(item.node)
		}
	}
	mut running := []bool{len: nodes.len} @[freed]
	proc.mark_programs_in_use(nodes, mut running)

	mut index := 0
	for item in items {
		if item.node == unsafe { nil } {
			unsafe { free(item.bytes) }
			continue
		}
		mut node := item.node
		in_use := running[index]
		index++
		if pinned(node) {
			// Mounted, overlaid or linked from /proc since it was retired: it
			// stays.
			continue
		}
		if in_use {
			// A process runs it still: another round.
			retire(RetiredItem{
				node: node
			})
			continue
		}
		if katomic.load(&node.handles) != 0 {
			// Opened again, through a lookup that began before the unlink. Its
			// last handle retires it anew.
			katomic.store(mut &node.retired, u32(0))
			if katomic.load(&node.handles) == 0 {
				retire_node(mut node)
			}
			continue
		}
		free_node(node)
	}
	unsafe {
		items.free()
		nodes.free()
		running.free()
	}
}

fn free_node(node &VFSNode) {
	// A watch added through /proc/self/fd/N was never forgotten by name.
	inotify_forget(node)
	unsafe {
		node.name.free()
		node.symlink_target.free()
		free(node)
	}
}
