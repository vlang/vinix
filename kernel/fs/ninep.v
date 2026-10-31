// SPDX-License-Identifier: GPL-2.0-or-later
// Mission16-A: bounded, synchronous 9P2000.L VFS facade.
// Data/attributes are fetched remotely; namespace conflicts fail closed.
// Namespace nodes follow the VFS's permanent mount-cache lifetime. One bounded
// superblock/session per transport tag is pinned for this boot, including across ordinary detach:
// copied namespaces and nsfs descriptions can retain routes invisible here.
// Remount makes a fresh root view without resetting another view's live FIDs.
@[has_globals]
module fs

import dev.virtio_9p
import errno
import event.eventstruct
import fs.ninep
import katomic
import klock
import memory
import proc
import resource
import stat
import time

pub struct NinePFS {
mut:
	session &NinePSession = unsafe { nil }
	session_value NinePSession
	box &FileSystem = unsafe { nil }
	filesystem_value FileSystem
	published bool
}

// Mount adapters have distinct stable addresses. Only mounts of the same tag
// share the serialized wire session/FID budget; another tag cannot mutate it.
struct NinePSession {
mut:
	channel         &virtio_9p.Channel = unsafe { nil }
	client          ninep.Client
	lock            klock.Lock
	resources       [ninep.max_nodes]&NinePResource
	root            &VFSNode = unsafe { nil }
	closed          bool
	serial          u64
	dev             u64
	tag             string
	requested_msize u32
	attach_uid      u32
}

__global (
	ninep_backends [32]&NinePFS
	ninep_cache_lock     klock.Lock
)

struct NinePResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
mut:
	filesystem       &NinePFS           = unsafe { nil }
	box              &resource.Resource = unsafe { nil }
	resource_value resource.Resource
	node             &VFSNode           = unsafe { nil }
	fid              u32                = ninep.nofid
	slot             int
	seen             u64
	host             ninep.Attr
	namespace_parent &VFSNode = unsafe { nil }
	namespace_name   [256]u8
	namespace_length int
	publication      int // 1: wait for adoption/publication, 2: wait for removal
}

fn (mut backend NinePFS) as_filesystem() &FileSystem {
	if backend.session == unsafe { nil } {
		backend.session = unsafe { &backend.session_value }
	}
	if backend.box == unsafe { nil } {
		backend.filesystem_value = FileSystem(unsafe { &backend })
		backend.box = unsafe { &backend.filesystem_value }
	}
	return backend.box
}

fn (mut template NinePFS) instantiate() &FileSystem {
	mut instance := unsafe { &NinePFS(memory.malloc_packed_fallible(sizeof(NinePFS))) }
	if instance == unsafe { nil } {
		errno.set(errno.enomem)
		return unsafe { nil }
	}
	unsafe { *instance = NinePFS{} }
	return instance.as_filesystem()
}

fn (mut backend NinePFS) mount(_ &VFSNode, _ string, _ &VFSNode) ?&VFSNode {
	errno.set(errno.einval)
	return none
}

fn (mut backend NinePFS) error() {
	errno.set(if backend.session.client.fault > 0 && backend.session.client.fault <= 4095 {
		u64(backend.session.client.fault)
	} else {
		errno.eio
	})
}

fn (mut backend NinePFS) live() ? {
	if backend.session.closed || backend.session.channel == unsafe { nil } || backend.session.client.dead {
		errno.set(errno.eio)
		return none
	}
}

fn (mut backend NinePFS) mount_specifier(parent &VFSNode, name string, source string, flags u64, options string) ?&VFSNode {
	// Serialize discovery/publication, including same-tag simultaneous mounts.
	// No template state is changed and every mount keeps its own adapter.
	ninep_cache_lock.acquire()
	defer { ninep_cache_lock.release() }
	backend.as_filesystem()
	mut free_slot := -1
	for i, cached in ninep_backends {
		if cached == unsafe { nil } {
			if free_slot < 0 { free_slot = i }
		} else if !backend.published && cached.session.tag == source {
			backend.session = cached.session
			break
		}
	}
	mut opts := ninep.Options{}
	// A published superblock is never destroyed by a subsequent mount failure.
	// Each attachment owns a new, bounded namespace view; all share the serialized
	// connection. This avoids both stale remount trees and unsafe alias teardown.
	if backend.session.root != unsafe { nil } {
		mut attached := false
		defer {
			if !attached && !backend.published { memory.free(backend) }
		}
		backend.session.lock.acquire()
		defer { backend.session.lock.release() }
		if !ninep.parse_options(options, unsafe { &opts }) {
			errno.set(errno.einval)
			return none
		}
		if source != backend.session.tag {
			errno.set(errno.enodev)
			return none
		}
		if opts.msize != backend.session.requested_msize || proc.current_thread().process.euid != backend.session.attach_uid {
			errno.set(errno.ebusy)
			return none
		}
		backend.live()?
		root_resource := ninep_resource(backend.session.root)
		fid := backend.session.client.walk(root_resource.fid, '') or {
			backend.error()
			return none
		}
		mut attr := unsafe { &ninep.Attr(C.vinix_stack_alloc(sizeof(ninep.Attr))) }
		unsafe { *attr = ninep.Attr{} }
		backend.session.client.getattr(fid, attr) or {
			backend.session.client.release(fid)
			backend.error()
			return none
		}
		if !stat.isdir(attr.mode) {
			backend.session.client.release(fid)
			errno.set(errno.enotdir)
			return none
		}
		mut root := backend.make_node(parent, name, fid, attr) or {
			backend.session.client.release(fid)
			return none
		}
		root.create_dotentries(parent)
		backend.published = true
		attached = true
		return root
	}
	mut success := false
	defer {
		if !success {
			if backend.session.channel != unsafe { nil } { backend.session.channel.close() }
			// Failed construction is private; no node/name ownership escaped.
			for ptr in backend.session.resources {
				mut res := unsafe { ptr }
				if res == unsafe { nil } { continue }
				mut node := res.node
				if node != unsafe { nil } {
					if node.children != unsafe { nil } {
						unsafe {
							node.children.free()
							free(node.children)
						}
					}
					// The root's name is borrowed until mount succeeds.
					if voidptr(node) != voidptr(backend.session.root) { unsafe { node.name.free() } }
					memory.free(node)
				}
				memory.free(res)
			}
			memory.free(backend)
		}
	}
	if !ninep.parse_options(options, unsafe { &opts }) {
		errno.set(errno.einval)
		return none
	}
	if free_slot < 0 {
		errno.set(errno.enodev)
		return none
	}
	backend.session.channel = virtio_9p.connect(source) or {
		errno.set(errno.enodev)
		return none
	}
	backend.session.client = ninep.Client{
		context:  voidptr(backend.session.channel)
		exchange: virtio_9p.exchange
		tx:       backend.session.channel.tx
		rx:       backend.session.channel.rx
		msize:    opts.msize
	}
	backend.session.dev = resource.create_dev_id()
	backend.session.client.negotiate() or {
		backend.error()
		return none
	}
	attach_uid := proc.current_thread().process.euid
	fid := backend.session.client.attach(attach_uid) or {
		backend.error()
		return none
	}
	mut attr := unsafe { &ninep.Attr(C.vinix_stack_alloc(sizeof(ninep.Attr))) }
	unsafe { *attr = ninep.Attr{} }
	backend.session.client.getattr(fid, attr) or {
		backend.error()
		return none
	}
	if !stat.isdir(attr.mode) {
		errno.set(errno.enotdir)
		return none
	}
	mut root := backend.make_node(parent, name, fid, attr) or { return none }
	backend.session.root = root
	// Root publication is all-or-nothing. Population is lazy through the
	// existing permission/open capabilities, rather than a whole-share crawl.
	root.create_dotentries(parent)
	// Retained once per boot, not per operation. The node/FID budgets cap all
	// later mount views; incompatible remount credentials/options are refused.
	backend.session.tag = source.clone()
	backend.session.requested_msize = opts.msize
	backend.session.attach_uid = attach_uid
	ninep_backends[free_slot] = backend
	backend.published = true
	success = true
	_ = flags // VFS attachment enforces readonly/noexec/etc on every use.
	return root
}

fn (mut backend NinePFS) make_node(parent &VFSNode, name string, fid u32, attr &ninep.Attr) ?&VFSNode {
	mut slot := -1
	for i in 0 .. ninep.max_nodes {
		if backend.session.resources[i] == unsafe { nil } {
			slot = i
			break
		}
	}
	if slot < 0 {
		errno.set(errno.enospc)
		return none
	}
	mut res := unsafe { &NinePResource(memory.malloc_packed_fallible(sizeof(NinePResource))) }
	if res == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	unsafe { *res = NinePResource{ filesystem: backend, refcount: 1, fid: fid, slot: slot } }
	res.set_stat(attr)
	mut node := create_node(backend.as_filesystem(), parent, name, stat.isdir(attr.mode))
	res.node = node
	res.remember_name(parent, name)
	// refcount is already initialized in the stable owner before conversion.
	res.resource_value = resource.Resource(res)
	res.box = unsafe { &res.resource_value }
	node.resource = res.box
	backend.session.resources[slot] = res
	return node
}

fn (mut res NinePResource) set_stat(attr &ninep.Attr) {
	res.host = *attr
	res.stat.dev = res.filesystem.session.dev
	res.stat.ino = attr.qid.path
	res.stat.mode = attr.mode
	res.stat.uid = attr.uid
	res.stat.gid = attr.gid
	res.stat.nlink = attr.nlink
	res.stat.rdev = attr.rdev
	res.stat.size = i64(attr.size)
	res.stat.blksize = i64(attr.blksize)
	res.stat.blocks = i64(attr.blocks)
	res.stat.atim = time.TimeSpec{i64(attr.atime_sec), i64(attr.atime_nsec)}
	res.stat.mtim = time.TimeSpec{i64(attr.mtime_sec), i64(attr.mtime_nsec)}
	res.stat.ctim = time.TimeSpec{i64(attr.ctime_sec), i64(attr.ctime_nsec)}
}

fn ninep_resource(node &VFSNode) &NinePResource {
	if node == unsafe { nil } || node.resource == unsafe { nil } { return unsafe { nil } }
	mut res := node.resource
	if mut res is NinePResource { return unsafe { res } }
	return unsafe { nil }
}

fn (mut res NinePResource) refresh_locked() ? {
	mut backend := res.filesystem
	backend.live()?
	// Legacy VFS metadata callers edit stat before persist_metadata(). A
	// concurrent refresh must not erase that staged change in the gap.
	if res.stat.mode != res.host.mode || res.stat.uid != res.host.uid || res.stat.gid != res.host.gid
		|| res.stat.atim.tv_sec != i64(res.host.atime_sec) || res.stat.atim.tv_nsec != i64(res.host.atime_nsec)
		|| res.stat.mtim.tv_sec != i64(res.host.mtime_sec) || res.stat.mtim.tv_nsec != i64(res.host.mtime_nsec) {
		errno.set(errno.ebusy)
		return none
	}
	mut attr := ninep.Attr{}
	backend.session.client.getattr(res.fid, unsafe { &attr }) or {
		backend.error()
		return none
	}
	// Never mutate a cached node's kind/identity in place under lockless VFS
	// readers. Directory reconciliation replaces a changed host inode.
	if attr.qid.path != res.stat.ino || attr.mode & stat.ifmt != res.stat.mode & stat.ifmt {
		errno.set(errno.eio)
		return none
	}
	res.set_stat(&attr)
}

// Parent integration for direct fstat/fstatat(AT_EMPTY_PATH): call this before
// copying Resource.stat. Existing VFS has no general stat-refresh callback.
// Other resource kinds are a no-op. This API does not consume a reference.
pub fn ninep_refresh_stat(mut res resource.Resource) ? {
	if mut res is NinePResource {
		res.filesystem.session.lock.acquire()
		defer { res.filesystem.session.lock.release() }
		res.refresh_locked()?
	}
}

fn (mut res NinePResource) remember_name(parent &VFSNode, name string) {
	res.namespace_parent = unsafe { parent }
	// A mountpoint name is local, not a protocol component. It is never a
	// pending child operation and need not fit our remote-name scratch.
	if name.len > ninep.max_name {
		res.namespace_length = 0
		return
	}
	res.namespace_length = name.len
	for i in 0 .. name.len { res.namespace_name[i] = name[i] }
}

// Backend RPC completion precedes VFS map publication. Do not discover a
// second node for an unpublished create/rename, or republish an unlink.
// Names here are fixed owned bytes, never the name adopt() frees outside our
// lock. We never retire cached nodes, so observing the map before adopt() is
// safe: reconciliation only refreshes attributes or adds unrelated names.
fn (mut backend NinePFS) publication_ready_locked() bool {
	mut ready := true
	for ptr in backend.session.resources {
		mut res := unsafe { ptr }
		if res == unsafe { nil } || res.publication == 0 { continue }
		name := unsafe { tos(&res.namespace_name[0], res.namespace_length) }
		current := lookup_child_synced(res.namespace_parent, name)
		if (res.publication == 1 && voidptr(current) == voidptr(res.node))
			|| (res.publication == 2 && voidptr(current) != voidptr(res.node)) {
			res.publication = 0
		} else {
			ready = false
		}
	}
	return ready
}

fn (mut backend NinePFS) populate_locked(mut directory NinePResource) ? {
	backend.live()?
	if !backend.publication_ready_locked() {
		errno.set(errno.ebusy)
		return none
	}
	if !stat.isdir(directory.stat.mode) { return }
	if directory.node.removed {
		errno.set(errno.enoent)
		return none
	}
	fid := backend.session.client.walk(directory.fid, '') or {
		backend.error()
		return none
	}
	defer { backend.session.client.release(fid) }
	unit := backend.session.client.lopen(fid, 0x10000) or {
		backend.error()
		return none
	}
	if unit < 280 {
		errno.set(errno.eio)
		return none
	}
	backend.session.serial++
	if backend.session.serial == 0 { backend.session.serial++ }
	epoch := backend.session.serial
	mut cookie := u64(0)
	mut entry := unsafe { &ninep.DirEntry(C.vinix_stack_alloc(sizeof(ninep.DirEntry))) }
	unsafe { *entry = ninep.DirEntry{} }
	mut complete := false
	// Bounds malicious cookie cycles and dot-only streams independently of
	// the number of allocated nodes; no count controls a dynamic allocation.
	for _ in 0 .. ninep.max_nodes * 4 {
		has_entry := backend.session.client.readdir_one(fid, cookie, unit, entry) or {
			backend.error()
			return none
		}
		if !has_entry {
			complete = true
			break
		}
		cookie = entry.offset
		name := unsafe { tos(&entry.name[0], int(entry.length)) }
		if name == '.' || name == '..' { continue }
		// This milestone exposes regular files and directories only. Ignore
		// other d_types rather than manufacturing broken symlink/device nodes.
		if entry.kind != 0 && entry.kind != 4 && entry.kind != 8 { continue }
		mut existing := ninep_resource(lookup_child_synced(directory.node, name))
		if existing != unsafe { nil } && existing.stat.ino == entry.qid.path {
			existing.refresh_locked()?
			existing.seen = epoch
			continue
		}
		// Host replacement cannot safely retire VFS nodes from this callback:
		// readers and a VFS transaction may still own the entire subtree.
		if existing != unsafe { nil } {
			errno.set(errno.ebusy)
			return none
		}
		fresh := backend.session.client.walk(directory.fid, name) or {
			backend.error()
			return none
		}
		mut attr := ninep.Attr{}
		backend.session.client.getattr(fresh, unsafe { &attr }) or {
			backend.session.client.release(fresh)
			backend.error()
			return none
		}
		if !stat.isreg(attr.mode) && !stat.isdir(attr.mode) {
			backend.session.client.release(fresh)
			continue
		}
		owned_name := name.clone() @[freed]
		mut node := backend.make_node(directory.node, owned_name, fresh, unsafe { &attr }) or {
			backend.session.client.release(fresh)
			unsafe { owned_name.free() }
			return none
		}
		mut child := ninep_resource(node)
		child.seen = epoch
		if stat.isdir(attr.mode) { node.create_dotentries(directory.node) }
		publish_child(directory.node, node.name, node)
	}
	if !complete {
		errno.set(errno.eoverflow)
		return none
	}
	// Removal/replacement requires a VFS transaction API unavailable here.
	// Retain the complete cached subtree and refuse conflicting lookups.
	for ptr in backend.session.resources {
		mut child := unsafe { ptr }
		if child == unsafe { nil } || child.node == unsafe { nil } || voidptr(child.namespace_parent) != voidptr(directory.node)
			|| child.node.orphan || child.node.removed || child.seen == epoch {
			continue
		}
		errno.set(errno.ebusy)
		return none
	}
}

fn (mut backend NinePFS) populate(node &VFSNode) {
	mut res := ninep_resource(node)
	if res == unsafe { nil } { return }
	backend.session.lock.acquire()
	defer { backend.session.lock.release() }
	backend.populate_locked(mut res) or {}
}

fn (mut res NinePResource) snapshot_permissions(mut acl []u8) ?resource.PermissionMetadata {
	res.filesystem.session.lock.acquire()
	defer { res.filesystem.session.lock.release() }
	res.refresh_locked()?
	if stat.isdir(res.stat.mode) { res.filesystem.populate_locked(mut res)? }
	_ = acl // No remote ACL/xattr support in this subset.
	return resource.PermissionMetadata{res.stat.mode, res.stat.uid, res.stat.gid}
}

fn (mut res NinePResource) open(flags int) ?&resource.Resource {
	res.filesystem.session.lock.acquire()
	defer { res.filesystem.session.lock.release() }
	res.refresh_locked()?
	if stat.isdir(res.stat.mode) { res.filesystem.populate_locked(mut res)? }
	if flags & resource.o_path == 0 {
		fid := res.filesystem.session.client.walk(res.fid, '') or {
			res.filesystem.error()
			return none
		}
		defer { res.filesystem.session.client.release(fid) }
		mode := if stat.isdir(res.stat.mode) { u32(0x10000) } else { u32(flags & 3) }
		res.filesystem.session.client.lopen(fid, mode) or {
			res.filesystem.error()
			return none
		}
	}
	return res.box
}

fn (mut backend NinePFS) create(parent &VFSNode, name string, mode u32) &VFSNode {
	backend.session.lock.acquire()
	defer { backend.session.lock.release() }
	backend.live() or { return unsafe { nil } }
	mut dir := ninep_resource(parent)
	if dir == unsafe { nil } || !ninep.valid_name(name) {
		errno.set(errno.einval)
		return unsafe { nil }
	}
	if !backend.publication_ready_locked() {
		errno.set(errno.ebusy)
		return unsafe { nil }
	}
	if lookup_child_synced(parent, name) != unsafe { nil } {
		errno.set(errno.eexist)
		return unsafe { nil }
	}
	if !stat.isdir(mode) && !stat.isreg(mode) {
		errno.set(errno.enotsup)
		return unsafe { nil }
	}
	// Reserve a resource slot before mutating the host namespace.
	mut available := false
	for res in backend.session.resources {
		if res == unsafe { nil } {
			available = true
			break
		}
	}
	if !available {
		errno.set(errno.enospc)
		return unsafe { nil }
	}
	gid := proc.current_thread().process.egid
	if stat.isdir(mode) {
		backend.session.client.mkdir(dir.fid, name, mode, gid) or {
			backend.error()
			return unsafe { nil }
		}
	} else {
		fid := backend.session.client.walk(dir.fid, '') or {
			backend.error()
			return unsafe { nil }
		}
		defer { backend.session.client.release(fid) }
		backend.session.client.lcreate(fid, name, mode, gid) or {
			backend.error()
			return unsafe { nil }
		}
	}
	fresh := backend.session.client.walk(dir.fid, name) or {
		backend.error()
		return unsafe { nil }
	}
	mut attr := unsafe { &ninep.Attr(C.vinix_stack_alloc(sizeof(ninep.Attr))) }
	unsafe { *attr = ninep.Attr{} }
	backend.session.client.getattr(fresh, attr) or {
		backend.session.client.release(fresh)
		backend.error()
		return unsafe { nil }
	}
	mut node := backend.make_node(parent, name, fresh, attr) or {
		backend.session.client.release(fresh)
		backend.session.client.unlinkat(dir.fid, name, stat.isdir(mode)) or {}
		return unsafe { nil }
	}
	mut created := ninep_resource(node)
	created.publication = 1
	return node
}

fn (mut backend NinePFS) symlink(_ &VFSNode, _ string, _ string) &VFSNode {
	errno.set(errno.enotsup)
	return unsafe { nil }
}

fn (mut backend NinePFS) link(_ &VFSNode, _ string, mut _ VFSNode) ?&VFSNode {
	errno.set(errno.enotsup)
	return none
}

fn (mut backend NinePFS) rename(old_parent &VFSNode, old_name string, new_parent &VFSNode, new_name string, flags int) ? {
	if flags != 0 {
		errno.set(errno.enotsup)
		return none
	}
	backend.session.lock.acquire()
	defer { backend.session.lock.release() }
	backend.live()?
	old := ninep_resource(old_parent)
	new := ninep_resource(new_parent)
	if old == unsafe { nil } || new == unsafe { nil } || voidptr(old.filesystem) != voidptr(backend) || voidptr(new.filesystem) != voidptr(backend) {
		errno.set(errno.exdev)
		return none
	}
	if !backend.publication_ready_locked() {
		errno.set(errno.ebusy)
		return none
	}
	mut source := ninep_resource(lookup_child_synced(old_parent, old_name))
	if source == unsafe { nil } {
		errno.set(errno.enoent)
		return none
	}
	// Replacing a destination captured by VFS before our callback is unsafe
	// without a shared transaction lock. This subset permits absent targets.
	if lookup_child_synced(new_parent, new_name) != unsafe { nil } {
		errno.set(errno.ebusy)
		return none
	}
	backend.session.client.renameat(old.fid, old_name, new.fid, new_name) or {
		backend.error()
		return none
	}
	source.remember_name(new_parent, new_name)
	source.publication = 1
}

fn (mut res NinePResource) read(_ voidptr, buf voidptr, offset u64, count u64) ?i64 {
	res.filesystem.session.lock.acquire()
	defer { res.filesystem.session.lock.release() }
	return res.read_locked(buf, offset, count, false)
}

fn (mut res NinePResource) read_locked(buf voidptr, offset u64, count u64, strict bool) ?i64 {
	res.refresh_locked()?
	if !stat.isreg(res.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}
	if !ninep.valid_range(offset, count) {
		errno.set(errno.eoverflow)
		return none
	}
	if count == 0 { return 0 }
	if buf == unsafe { nil } || count > u64(-1) - u64(buf) {
		errno.set(errno.efault)
		return none
	}
	mut backend := res.filesystem
	fid := backend.session.client.walk(res.fid, '') or {
		backend.error()
		return none
	}
	defer { backend.session.client.release(fid) }
	unit := backend.session.client.lopen(fid, 0) or {
		backend.error()
		return none
	}
	mut done := u64(0)
	for done < count {
		chunk := u32(if count - done < unit { count - done } else { unit })
		n := backend.session.client.read(fid, offset + done, unsafe { &u8(u64(buf) + done) }, chunk) or {
			backend.error()
			if done != 0 { return i64(done) }
			return none
		}
		done += n
		if n < chunk { break }
	}
	return i64(done)
}

fn (mut res NinePResource) write_locked(buf voidptr, offset u64, count u64) ?i64 {
	mut backend := res.filesystem
	backend.live()?
	if !stat.isreg(res.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}
	if !ninep.valid_range(offset, count) {
		errno.set(errno.eoverflow)
		return none
	}
	if count == 0 { return 0 }
	if buf == unsafe { nil } || count > u64(-1) - u64(buf) {
		errno.set(errno.efault)
		return none
	}
	fid := backend.session.client.walk(res.fid, '') or {
		backend.error()
		return none
	}
	defer { backend.session.client.release(fid) }
	unit := backend.session.client.lopen(fid, 1) or {
		backend.error()
		return none
	}
	mut done := u64(0)
	for done < count {
		chunk := u32(if count - done < unit { count - done } else { unit })
		n := backend.session.client.write(fid, offset + done, unsafe { &u8(u64(buf) + done) }, chunk) or {
			backend.error()
			if done != 0 { break }
			return none
		}
		done += n
		if n < chunk { break }
	}
	// Preserve a successful write count even when a following getattr fails.
	if done != 0 {
		end := offset + done
		if end > u64(res.stat.size) { res.stat.size = i64(end) }
		res.refresh_locked() or {}
	}
	return i64(done)
}

fn (mut res NinePResource) write(_ voidptr, buf voidptr, offset u64, count u64) ?i64 {
	res.filesystem.session.lock.acquire()
	defer { res.filesystem.session.lock.release() }
	res.refresh_locked()?
	return res.write_locked(buf, offset, count)
}

fn (mut res NinePResource) append_data(_ voidptr, buf voidptr, count u64, limit u64, end &u64) ?i64 {
	res.filesystem.session.lock.acquire()
	defer { res.filesystem.session.lock.release() }
	res.refresh_locked()?
	location := u64(res.stat.size)
	if count != 0 && location >= limit {
		errno.set(errno.efbig)
		return none
	}
	allowed := if count != 0 && count > limit - location { limit - location } else { count }
	n := res.write_locked(buf, location, allowed)?
	unsafe { *end = location + u64(n) }
	return n
}

fn (mut res NinePResource) grow(_ voidptr, size u64) ? {
	res.filesystem.session.lock.acquire()
	defer { res.filesystem.session.lock.release() }
	res.filesystem.live()?
	if !stat.isreg(res.stat.mode) || size > 0x7fffffffffffffff {
		errno.set(errno.einval)
		return none
	}
	attr := ninep.Attr{ size: size }
	res.filesystem.session.client.setattr(res.fid, 8, &attr) or {
		res.filesystem.error()
		return none
	}
	res.stat.size = i64(size)
	res.refresh_locked()?
}

fn (mut res NinePResource) persist_metadata() ? {
	res.filesystem.session.lock.acquire()
	defer { res.filesystem.session.lock.release() }
	res.filesystem.live()?
	if res.stat.atim.tv_sec < 0 || res.stat.mtim.tv_sec < 0
		|| res.stat.atim.tv_nsec < 0 || res.stat.mtim.tv_nsec < 0 {
		errno.set(errno.einval)
		return none
	}
	mut attr := ninep.Attr{
		mode:       res.stat.mode
		uid:        res.stat.uid
		gid:        res.stat.gid
		atime_sec:  u64(res.stat.atim.tv_sec)
		atime_nsec: u64(res.stat.atim.tv_nsec)
		mtime_sec:  u64(res.stat.mtim.tv_sec)
		mtime_nsec: u64(res.stat.mtim.tv_nsec)
	}
	previous := res.host
	mut mask := u32(0)
	if attr.mode != previous.mode { mask |= 1 }
	if attr.uid != previous.uid { mask |= 2 }
	if attr.gid != previous.gid { mask |= 4 }
	if attr.atime_sec != previous.atime_sec || attr.atime_nsec != previous.atime_nsec {
		mask |= 16 | 128
	}
	if attr.mtime_sec != previous.mtime_sec || attr.mtime_nsec != previous.mtime_nsec {
		mask |= 32 | 256
	}
	if mask == 0 { return }
	mut fresh := ninep.Attr{}
	res.filesystem.session.client.getattr(res.fid, unsafe { &fresh }) or {
		res.filesystem.error()
		return none
	}
	if fresh.qid.path != previous.qid.path || fresh.mode & stat.ifmt != previous.mode & stat.ifmt {
		errno.set(errno.eio)
		return none
	}
	// Only fields actually edited by the caller may be sent. If that field
	// also changed remotely since its snapshot, refuse the stale update.
	if (mask & 1 != 0 && fresh.mode != previous.mode && fresh.mode != attr.mode)
		|| (mask & 2 != 0 && fresh.uid != previous.uid && fresh.uid != attr.uid)
		|| (mask & 4 != 0 && fresh.gid != previous.gid && fresh.gid != attr.gid)
		|| (mask & 16 != 0 && (fresh.atime_sec != previous.atime_sec || fresh.atime_nsec != previous.atime_nsec)
			&& (fresh.atime_sec != attr.atime_sec || fresh.atime_nsec != attr.atime_nsec))
		|| (mask & 32 != 0 && (fresh.mtime_sec != previous.mtime_sec || fresh.mtime_nsec != previous.mtime_nsec)
			&& (fresh.mtime_sec != attr.mtime_sec || fresh.mtime_nsec != attr.mtime_nsec)) {
		errno.set(errno.ebusy)
		return none
	}
	res.filesystem.session.client.setattr(res.fid, mask, &attr) or {
		res.filesystem.error()
		return none
	}
	if mask & 1 != 0 { fresh.mode = attr.mode }
	if mask & 2 != 0 { fresh.uid = attr.uid }
	if mask & 4 != 0 { fresh.gid = attr.gid }
	if mask & 16 != 0 {
		fresh.atime_sec = attr.atime_sec
		fresh.atime_nsec = attr.atime_nsec
	}
	if mask & 32 != 0 {
		fresh.mtime_sec = attr.mtime_sec
		fresh.mtime_nsec = attr.mtime_nsec
	}
	res.set_stat(&fresh)
}

fn (mut res NinePResource) chmod_mode(mode u32) ? {
	res.filesystem.session.lock.acquire()
	defer { res.filesystem.session.lock.release() }
	res.refresh_locked()?
	attr := ninep.Attr{ mode: (res.stat.mode & stat.ifmt) | (mode & 0o7777) }
	res.filesystem.session.client.setattr(res.fid, 1, &attr) or {
		res.filesystem.error()
		return none
	}
	res.stat.mode = attr.mode
	res.host.mode = attr.mode
}

fn (mut res NinePResource) unlink(handle voidptr) ? {
	mut node := unsafe { &VFSNode(handle) }
	if node == unsafe { nil } || voidptr(node) != voidptr(res.node) {
		errno.set(errno.einval)
		return none
	}
	res.filesystem.session.lock.acquire()
	defer { res.filesystem.session.lock.release() }
	res.filesystem.live()?
	dir := ninep_resource(node.parent)
	if dir == unsafe { nil } {
		errno.set(errno.einval)
		return none
	}
	res.filesystem.session.client.unlinkat(dir.fid, node.name, stat.isdir(res.stat.mode)) or {
		res.filesystem.error()
		return none
	}
	if res.stat.nlink != 0 { res.stat.nlink-- }
	res.publication = 2
}

fn (mut res NinePResource) link(_ voidptr) ? {
	errno.set(errno.enotsup)
	return none
}

fn (mut res NinePResource) ioctl(handle voidptr, request u64, arg voidptr) ?int {
	return resource.default_ioctl(handle, request, arg)
}

fn (mut res NinePResource) mmap(_ voidptr, _ u64, _ int) voidptr { return unsafe { nil } }

fn (mut res NinePResource) sync(_ voidptr) ? {
	res.filesystem.session.lock.acquire()
	defer { res.filesystem.session.lock.release() }
	res.filesystem.live()?
	fid := res.filesystem.session.client.walk(res.fid, '') or {
		res.filesystem.error()
		return none
	}
	defer { res.filesystem.session.client.release(fid) }
	res.filesystem.session.client.lopen(fid, if stat.isdir(res.stat.mode) { u32(0x10000) } else { u32(0) }) or {
		res.filesystem.error()
		return none
	}
	res.filesystem.session.client.fsync(fid) or {
		res.filesystem.error()
		return none
	}
}

fn (mut res NinePResource) unref(_ voidptr) ? {
	if katomic.dec(mut &res.refcount) { return }
	mut backend := res.filesystem
	backend.session.lock.acquire()
	if !backend.session.closed && res.fid != ninep.nofid { backend.session.client.release(res.fid) }
	backend.session.resources[res.slot] = unsafe { nil }
	backend.session.lock.release()
	memory.free(res)
}

// The VFS checks attachment-specific busy paths/descriptions before detaching.
// Never shut down a shared superblock here: another namespace or an nsfs
// description can retain it. The fixed boot cache owns this bounded session.
fn (mut backend NinePFS) check_unmount() ? {}
