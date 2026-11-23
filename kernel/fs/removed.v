module fs

import event
import kbudget
import katomic
import klock
import proc
import resource
import sched
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
	// An overlay pointer removed from a still-live entry, released after grace.
	overlay_backing &VFSNode = unsafe { nil }
	bytes &u8      = unsafe { nil }
	text string
	// Keep the complete V array header: data may follow managed metadata and
	// need not be the allocator's original pointer.
	lower_nodes []&VFSNode
	lower_resources []&resource.Resource
	directory_busy bool
	at    u64
}

__global (
	removed_lock      klock.Lock
	removed_items     []RetiredItem
	removed_last_reap u64
	// Batches with a disk-changing release (see wait_queued_releases) that
	// reap_removed() has taken off the queue and not yet dealt with.
	removed_in_flight u32
)

// orphan_node marks a node that no name leads to any more, and retires it
// once no open-file description does either. `mode` is read before the name's
// reference is dropped, which may free the resource.
fn orphan_node(mut node VFSNode, mode u32) {
	if !(stat.isdir(mode) || stat.isreg(mode) || stat.islnk(mode) || stat.issock(mode) || stat.ischr(mode) || stat.isblk(mode) || stat.isifo(mode)) {
		return
	}
	if stat.isdir(mode) { overlay_detach_work(mut node) }
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

// Mounts retain their existing permanent pins. Overlay ownership is counted
// separately so releasing the last alias can retire an unlinked backing node.
fn pinned(node &VFSNode) bool {
	return node.mount_covered || node.mount_root || node.ns_mounts > 0
		|| node.mountpoint != unsafe { nil }
}

fn retain_handle_node(node voidptr) {
	mut n := unsafe { &VFSNode(node) }
	katomic.inc(mut &n.handles)
}

// Called when a handle or executable mapping drops its node.
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
		overlay_backing: item.overlay_backing
		bytes: item.bytes
		charge: item.charge
		resource: item.resource
		text: item.text
		lower_nodes: item.lower_nodes
		lower_resources: item.lower_resources
		directory_busy: item.directory_busy
		at:    time.monotonic_ns()
	}
	removed_lock.release()
}

// Only the maintenance thread reaps. Retiring can happen under VFS/resource
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
	mut items := []RetiredItem{} @[freed]
	if due == removed_items.len {
		// Move the whole buffer when drained. Retiring and callbacks use a new
		// queue after unlock; the detached batch owns and frees the old buffer.
		items = unsafe { removed_items }
		removed_items = []RetiredItem{}
	} else {
		items = []RetiredItem{len: due} @[freed]
		// Transfer the original owned strings. V deep-clones a string-bearing
		// struct pushed directly from an array index, losing the original names.
		unsafe { C.memcpy(items.data, removed_items.data, uint(due) * sizeof(RetiredItem)) }
		removed_items.delete_many(0, due)
	}
	mut disk_batch := false
	for i in 0 .. items.len {
		if release_changes_disk(unsafe { &items[i] }) { disk_batch = true; break }
	}
	if disk_batch { removed_in_flight++ }
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
			if item.overlay_backing != unsafe { nil } { overlay_release_node(item.overlay_backing) }
			unsafe { free(item.bytes) }
			unsafe { item.text.free() }
			mut lower_nodes := unsafe { item.lower_nodes }
			mut lower_resources := unsafe { item.lower_resources }
			unsafe { lower_nodes.free(); lower_resources.free() }
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
			// Mounted or linked from /proc since it was retired: it
			// stays.
			continue
		}
		if katomic.load(&node.overlay_refs) != 0 {
			// A final overlay release will requeue it. Reset first, then
			// recheck so a concurrent final release cannot lose retirement.
			katomic.store(mut &node.retired, u32(0))
			if katomic.load(&node.overlay_refs) == 0 { retire_node(mut node) }
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
	if disk_batch {
		removed_lock.acquire()
		removed_in_flight--
		removed_lock.release()
	}
	unsafe {
		items.free()
		nodes.free()
		running.free()
	}
}

// sync(2) promises that a file removed before it is gone from the disk as
// well. Its name's reference is dropped only after the grace period
// (release_resource_after_grace), and on a filesystem without a journal only
// that release frees the inode and its blocks: a sync and then a power cut
// left them allocated with no owner. Wait for such releases already queued,
// and for a batch being dealt with, so the flush that follows writes the
// result. Only releases that change the disk are waited for: a removed tmpfs
// file, or one still open, costs sync nothing. A resource release is never
// requeued, so this waits at most one grace period and a reap interval.
// A removed directory is released with its node, which cwd/root owners may
// keep requeueing, so it is not waited for; nor is a file whose final
// reference belongs to its mapped pages or a transient writeback pin. The
// caller holds no lock.
pub fn wait_queued_releases() {
	start := time.monotonic_ns()
	for releases_pending(start) {
		mut timer := time.new_timer(time.TimeSpec{tv_nsec: 50_000_000})
		// Ordinary signals wait for the syscall to finish, as Linux's sync
		// does; they must not turn this into a spin. A thread told to exit
		// stops waiting.
		mut stopped := false
		mut early := false
		_ := event.await_one_masked(mut timer.event, 0) or {
			stopped = katomic.load(&proc.current_thread().must_exit)
			early = true
			u64(0)
		}
		timer.disarm()
		unsafe { free(timer) }
		if stopped { return }
		// A full listener array also ends the wait at once.
		if early { sched.yield(true) }
	}
}

fn releases_pending(start u64) bool {
	removed_lock.acquire()
	defer { removed_lock.release() }
	if removed_in_flight != 0 { return true }
	// Retired in time order: `at` is read under the lock.
	for i in 0 .. removed_items.len {
		item := unsafe { &removed_items[i] }
		if item.at > start { break }
		if !release_changes_disk(item) { continue }
		// Pending if only queued references remain: each hard link's name
		// holds its own. An open description or mapping keeps the file, and
		// its own final release frees it, outside this wait.
		mut res := unsafe { item.resource }
		refs := katomic.load(&res.refcount)
		if refs <= 1 || refs <= queued_references(item.resource) { return true }
	}
	return false
}

// A queued release that will free its removed file on disk once it is the
// last reference. The batch flag ignores the count: a close may still make
// the release final while the batch is being dealt with.
fn release_changes_disk(item &RetiredItem) bool {
	if item.node != unsafe { nil } || item.resource == unsafe { nil } { return false }
	mut res := unsafe { item.resource }
	return resource.release_changes_disk(mut res)
}

fn queued_references(res &resource.Resource) int {
	mut count := 0
	for i in 0 .. removed_items.len {
		queued := unsafe { &removed_items[i] }
		if voidptr(queued.resource) == voidptr(res) && queued.node == unsafe { nil } {
			count++
		}
	}
	return count
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
	if node.directory_resource || (node.overlay != unsafe { nil } && node.removed) {
		// Only dot redirects remain after rmdir. They are owned, rather than
		// aliases of the parent, and share the enclosing node's grace period.
		if node.children != unsafe { nil } {
			for _, dot in node.children { unsafe { free(dot) } }
			unsafe { node.children.free(); free(node.children) }
		}
		if node.directory_resource {
			mut res := node.resource
			resource.release_resource(mut res)
		}
	}
	kbudget.release(node.kernel_charge)
	inotify_forget(node)
 if node.overlay != unsafe { nil } {
  overlay_release_entry(node.overlay)
  unsafe { node.overlay.lowers.free(); node.overlay.lower_resources.free(); free(node.overlay) }
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

fn overlay_release_after_grace(node &VFSNode, res &resource.Resource) {
	retire(RetiredItem{overlay_backing: unsafe { node }, resource: unsafe { res }})
}

fn overlay_retire_lower_arrays(nodes []&VFSNode, resources []&resource.Resource) {
	if nodes.data != unsafe { nil } || resources.data != unsafe { nil } {
		retire(RetiredItem{lower_nodes: nodes, lower_resources: resources})
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
