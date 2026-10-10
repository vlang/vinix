module fs

import kbudget
import katomic
import klock
import proc
import resource
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
// Removed directories retain their dot entries and resource while a cwd/root,
// descriptor or unlinked child still needs them. Each orphan pins its parent,
// so a removed subtree is reclaimed from its leaves without dangling parents.
const removed_grace_ns = u64(5_000_000_000)
// Reaping scans the process table, so it is not done more often than this.
const removed_reap_interval_ns = u64(1_000_000_000)

// A node, or memory for free_after_grace(), and when it was retired.
struct RetiredItem {
	charge kbudget.Charge
	resource &resource.Resource = unsafe { nil }
	node  &VFSNode = unsafe { nil }
	bytes &u8      = unsafe { nil }
	text string
	directory_busy bool
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
	if !(stat.isdir(mode) || stat.isreg(mode) || stat.islnk(mode) || stat.issock(mode) || stat.ischr(mode) || stat.isblk(mode) || stat.isifo(mode)) {
		return
	}
	hold_parent(mut node)
	if pinned(node) { return }
	// CGroup.node is a permanent controller identity, also read by asynchronous
	// accounting. Its existing mount-lifetime charge owns this directory.
	if stat.isdir(mode) && is_cgroup_resource(node.resource) { return }

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
	hold_parent(mut node)
	retire(RetiredItem{
		node: unsafe { node }
	})
}

fn hold_parent(mut node VFSNode) {
	if node.parent != unsafe { nil } && voidptr(node.parent) != voidptr(node)
		&& katomic.cas(mut &node.parent_held, u32(0), u32(1)) {
		mut parent := node.parent
		katomic.inc(mut &parent.parent_refs)
	}
}

// A rename publishes another owned name; lockless path readers may still be
// using the old one. String.free also knows to leave literal names alone.
fn free_string_after_grace(value string) {
	if value.len != 0 { retire(RetiredItem{text: value}) }
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
		charge: item.charge
		resource: item.resource
		text: item.text
		directory_busy: item.directory_busy
		at:    time.monotonic_ns()
	}
	removed_lock.release()
}

// Only the writeback worker reaps. Retiring can happen under VFS/resource
// locks, while a final retained device release can acquire those same locks.
// Queueing never runs such callbacks synchronously.
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
	mut items := []RetiredItem{len: due} @[freed]
	// Transfer the original owned strings. V deep-clones a string-bearing
	// struct pushed directly from an array index, losing the original names.
	unsafe { C.memcpy(items.data, removed_items.data, usize(due) * sizeof(RetiredItem)) }
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
			unsafe { item.text.free() }
			if item.resource != unsafe { nil } {
				mut res := item.resource
				resource.release_resource(mut res)
			}
			kbudget.release(item.charge)
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
		if katomic.load(&node.handles) != 0 {
			// fchdir publishes cwd while its description still pins the node.
			// Check that pin before scanning owners, so a final close cannot
			// turn a completed owner scan into permission to free the new cwd.
			katomic.store(mut &node.retired, u32(0))
			if katomic.load(&node.handles) == 0 { retire_node(mut node) }
			continue
		}
		if in_use || katomic.load(&node.parent_refs) != 0 {
			// A child can hand its cwd to this parent through "..". Check that
			// durable source pin before scanning the newly published owners.
			retire(RetiredItem{node: node, directory_busy: item.directory_busy})
			continue
		}
		directory_busy := node.removed && proc.directory_in_use(voidptr(node))
		if directory_busy {
			retire(RetiredItem{
				node: node
				directory_busy: directory_busy
			})
			continue
		}
		if item.directory_busy {
			// The last cwd/root was released since the previous scan. Give
			// lookups that used that reference a complete grace period too.
			retire(RetiredItem{node: node})
			continue
		}
		released := katomic.load(&node.directory_released)
		checked_at := time.monotonic_ns()
		if node.removed && (checked_at < released || checked_at - released < removed_grace_ns) {
			retire(RetiredItem{node: node})
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

// Called before a cwd/root owner drops its reference, under its own lock.
// Never wait on VFS/table locks here. Concurrent owners cannot move the last
// release time backwards, and no allocation is needed on this repeated path.
fn directory_releasing(pointer voidptr) {
	if pointer == unsafe { nil } { return }
	mut node := unsafe { &VFSNode(pointer) }
	now := time.monotonic_ns()
	mut before := katomic.load(&node.directory_released)
	for before < now {
		if katomic.cas(mut &node.directory_released, before, now) { break }
		before = katomic.load(&node.directory_released)
	}
}

fn free_node(node &VFSNode) {
	// A watch added through /proc/self/fd/N was never forgotten by name.
	if node.directory_resource {
		// Only dot redirects remain after rmdir. They are owned, rather than
		// aliases of the parent, and share the enclosing node's grace period.
		if node.children != unsafe { nil } {
			for _, dot in node.children { unsafe { free(dot) } }
			unsafe { node.children.free(); free(node.children) }
		}
		mut res := node.resource
		resource.release_resource(mut res)
	}
	kbudget.release(node.kernel_charge)
	inotify_forget(node)
 if node.overlay != unsafe { nil } {
  unsafe { node.overlay.lowers.free(); free(node.overlay) }
 }
	unsafe {
		node.name.free()
		node.symlink_target.free()
		if node.parent_held != 0 {
			mut parent := node.parent
			katomic.dec(mut &parent.parent_refs)
		}
		free(node)
	}
}

// Keep a reservation while lockless readers finish, just as the bytes remain.
pub fn free_charged_after_grace(ptr voidptr, charge kbudget.Charge) {
	if ptr == unsafe { nil } { kbudget.release(charge); return }
	retire(RetiredItem{bytes: unsafe { &u8(ptr) }, charge: charge})
}

// Return an already retained resource outside VFS locks after their readers
// finish; final device release may itself detach a pathname under vfs_lock.
pub fn release_resource_after_grace(res &resource.Resource) {
	if res != unsafe { nil } { retire(RetiredItem{resource: unsafe { res }}) }
}
