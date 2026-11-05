// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module fs

import fs.nfs
import resource
import stat
import time
import errno
import memory
import klock
import katomic
import event.eventstruct
import file
import proc
import devcore
import socket.inet
import socket.public as sockpub

fn C.kprintf(&char, ...) i32
fn C.memset(voidptr, i32, usize) voidptr

const nfs_sessions = 4
const nfs_nodes = 512

__global (
	nfs_pool [nfs_sessions]&NFSFS
	nfs_pool_lock klock.Lock
)

pub struct NFSFS {
mut:
	lock klock.Lock
	client nfs.Client
	box &FileSystem = unsafe { nil }
	stream &inet.InetSocket = unsafe { nil }
	socket &sockpub.Socket = unsafe { nil }
	io_handle file.Handle
	deadline u64
	address u32
	mount_port u16
	nfs_port u16
	export_path [1025]u8
	export_len int
	root_handle nfs.FileHandle
	root &VFSNode = unsafe { nil }
	dev u64
	mounted bool
	pool_slot int
	resources [nfs_nodes]&NfsResource
	node_count int
	name_max u32 = 255
	epoch u64
	listing &u8 = unsafe { nil }
	cookies &u64 = unsafe { nil }
}

@[heap]
struct NfsResource {
pub mut:
	stat stat.Stat
	refcount int
	l klock.Lock
	event eventstruct.Event
	status int
	can_mmap bool
mut:
	box &resource.Resource = unsafe { nil }
	backend &NFSFS = unsafe { nil }
	node &VFSNode = unsafe { nil }
	handle nfs.FileHandle
	parent_handle nfs.FileHandle
	name [256]u8
	name_len int
	removed bool
	seen u64
}

fn (mut template NFSFS) instantiate() &FileSystem {
	nfs_pool_lock.acquire()
	defer { nfs_pool_lock.release() }
	mut slot := -1
	for i in 0 .. nfs_sessions { if nfs_pool[i] == unsafe { nil } { slot = i; break } }
	if slot < 0 { errno.set(errno.enospc); return unsafe { nil } }
	mut b := unsafe { &NFSFS(memory.malloc_packed_fallible(sizeof(NFSFS))) }
	if b == unsafe { nil } { errno.set(errno.enomem); return unsafe { nil } }
	// Avoid a large initializer on the kernel stack.
	C.memset(b, 0, sizeof(NFSFS))
	b.pool_slot = slot
	b.client.xid = 1; b.client.rsize = nfs.io_max; b.client.wsize = nfs.io_max
	b.name_max = 255
	b.box = &FileSystem(b)
	nfs_pool[slot] = b
	return b.box
}

fn (mut b NFSFS) mount(_ &VFSNode, _ string, _ &VFSNode) ?&VFSNode {
	b.destroy_failed()
	errno.set(errno.einval)
	return none
}

fn (mut b NFSFS) failure() { errno.set(u64(if b.client.fault != 0 { b.client.fault } else { 5 })) }

fn (mut b NFSFS) identity() {
	current := proc.current_thread()
	if current == unsafe { nil } || current.process == unsafe { nil } { return }
	p := current.process
	// setgroups replaces and frees the supplementary array under this lock.
	// Copy credentials only; never retain the array or lock across wire I/O.
	proc.lock_table()
	defer { proc.unlock_table() }
	b.client.uid = p.euid; b.client.gid = p.egid
	b.client.group_count = if p.groups.len < 16 { p.groups.len } else { 16 }
	for i in 0 .. b.client.group_count { b.client.groups[i] = p.groups[i] }
}

fn (mut b NFSFS) usable() bool {
	if b.client.dead { b.failure(); return false }
	b.identity()
	return true
}

fn nfs_res(node &VFSNode) &NfsResource {
	if node == unsafe { nil } || node.resource == unsafe { nil } { return unsafe { nil } }
	mut r := node.resource
	if mut r is NfsResource { return unsafe { r } }
	return unsafe { nil }
}

// Removal is atomic with the identity check. Published pointers are never freed
// or handed to the generic orphan queue: the boot pool retains their storage.
fn nfs_retire_child(parent &VFSNode, mut r NfsResource) {
	children_lock.acquire()
	mut directory := unsafe { parent }
	if voidptr(lookup_child(parent, r.node.name)) == voidptr(r.node) { directory.children.delete(r.node.name) }
	children_lock.release()
	r.removed = true
	r.node.removed = true
}

fn (mut b NFSFS) destroy_failed() {
	saved := errno.get()
	b.close_stream()
	for i in 0 .. nfs_nodes {
		mut r := b.resources[i]
		if r == unsafe { nil } { continue }
		mut node := r.node
		if node != unsafe { nil } {
			if node.children != unsafe { nil } {
				// Only dots are private map-owned nodes. Looking them up directly
				// avoids V's heap-cloned string keys in a map iteration. map.free
				// below still owns and frees the stored keys exactly once.
				memory.free(lookup_child(node, '.'))
				memory.free(lookup_child(node, '..'))
				unsafe { node.children.free(); free(node.children) }
			}
			if voidptr(node) != voidptr(b.root) { unsafe { node.name.free() } }
			memory.free(node)
		}
		memory.free(r.box); memory.free(r)
	}
	memory.free(b.client.tx); memory.free(b.client.rx)
	memory.free(b.listing); memory.free(b.cookies)
	nfs_pool_lock.acquire()
	if voidptr(nfs_pool[b.pool_slot]) == voidptr(b) { nfs_pool[b.pool_slot] = unsafe { nil } }
	nfs_pool_lock.release()
	memory.free(b.box); memory.free(b)
	errno.set(saved)
}

// Hosts-only resolution. Scratch is fallible and released before mount returns;
// the stack Handle is borrowed by Resource.read, never published or closed.
fn nfs_resolve_host(host string) ?u32 {
	node := get_node(vfs_root, '/etc/hosts', true) or { return none }
	if node.resource == unsafe { nil } || !stat.isreg(node.resource.stat.mode) { errno.set(errno.einval); return none }
	mut r := node.resource
	if nfs_res(node) != unsafe { nil } { errno.set(errno.eopnotsupp); return none }
	buffer := memory.malloc_packed_fallible(nfs.hosts_max + 1)
	if buffer == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(buffer) }
	katomic.inc(mut &r.refcount)
	defer { r.unref(unsafe { nil }) or {} }
	mut handle := file.Handle{resource: r, flags: resource.o_rdonly}
	mut used := 0
	for used <= nfs.hosts_max {
		n := r.read(unsafe { &handle }, unsafe { &u8(buffer) + used }, u64(used), u64(nfs.hosts_max + 1 - used)) or { return none }
		if n < 0 || n > nfs.hosts_max + 1 - used { errno.set(errno.eio); return none }
		if n == 0 {
			mut address := u32(0)
			if !nfs.resolve_hosts(unsafe { tos(buffer, used) }, host, unsafe { &address }) { errno.set(errno.enoent); return none }
			return address
		}
		used += int(n)
	}
	errno.set(errno.efbig)
	return none
}

fn (mut b NFSFS) mount_specifier(parent &VFSNode, name string, source string, flags u64, options string) ?&VFSNode {
	mut success := false
	defer { if !success { b.destroy_failed() } }
	mut opts := nfs.Options{}
	mut path := ''; mut host := ''
	if !nfs.parse_options(options, unsafe { &opts }) || !nfs.parse_host_source(source, unsafe { &host }, unsafe { &path }) {
		errno.set(errno.einval); return none
	}
	if !nfs.parse_ipv4(host, unsafe { &b.address }) { b.address = nfs_resolve_host(host) or { return none } }
	b.export_len = path.len
	nfs.copy_bytes(unsafe { &b.export_path[0] }, path.str, path.len)
	b.client.tx = memory.malloc_packed_fallible(nfs.capacity + 4)
	b.client.rx = memory.malloc_packed_fallible(nfs.capacity)
	b.listing = memory.malloc_packed_fallible(nfs.capacity)
	b.cookies = unsafe { &u64(memory.malloc_packed_fallible(nfs.max_entries * sizeof(u64))) }
	if b.client.tx == unsafe { nil } || b.client.rx == unsafe { nil } || b.listing == unsafe { nil } || b.cookies == unsafe { nil } {
		errno.set(errno.enomem); return none
	}
	b.client.context = voidptr(b); b.client.transfer = nfs_transfer; b.client.begin = nfs_begin_call
	b.client.ro = opts.ro || flags & ms_rdonly != 0
	b.client.rsize = opts.rsize; b.client.wsize = opts.wsize
	b.identity()
	b.connect_port(111) or { return none }
	b.nfs_port = b.client.getport(100003, 3) or { b.failure(); return none }
	b.mount_port = b.client.getport(100005, 3) or { b.failure(); return none }
	b.connect_port(b.mount_port) or { return none }
	b.client.mount_export(path, unsafe { &b.root_handle }) or {
		saved := b.client.fault
		C.kprintf(c'nfs: MNT denied errno=%d; server exports follow (AUTH_SYS only)\n', saved)
		if !b.client.dead { b.log_exports() }
		errno.set(u64(saved)); return none
	}
	b.mounted = true
	defer {
		if !success && b.mounted {
			saved := errno.get()
			b.connect_port(b.mount_port) or {}
			if !b.client.dead { b.client.unmount_export(path) or {} }
			errno.set(saved)
		}
	}
	b.connect_port(b.nfs_port) or { return none }
	b.client.null() or { b.failure(); return none }
	mut attr := nfs.Attr{}
	b.client.getattr(unsafe { &b.root_handle }, unsafe { &attr }) or { b.failure(); return none }
	if attr.kind != 2 { errno.set(errno.enotdir); return none }
	mut conf := nfs.PathConf{}
	b.client.pathconf(unsafe { &b.root_handle }, unsafe { &conf }) or { b.failure(); return none }
	b.name_max = if conf.namemax < 255 { conf.namemax } else { 255 }
	mut info := nfs.FsInfo{}
	b.client.fsstat(unsafe { &b.root_handle }, unsafe { &info }) or { b.failure(); return none }
	b.dev = resource.create_dev_id()
	b.root = b.make_node(parent, name, b.root_handle, b.root_handle, attr, true) or { return none }
	b.refresh_locked(b.root) or { return none }
	success = true
	return b.root
}

fn (mut r NfsResource) set_stat(a nfs.Attr) {
	r.stat.dev = r.backend.dev; r.stat.ino = a.fileid
	r.stat.mode = u32(if a.kind == 2 { stat.ifdir } else { stat.ifreg }) | (a.mode & 0o7777)
	r.stat.uid = a.uid; r.stat.gid = a.gid; r.stat.nlink = a.nlink
	r.stat.size = i64(a.size); r.stat.blocks = i64(a.used / 512 + u64(a.used % 512 != 0)); r.stat.blksize = 4096
	r.stat.atim = time.TimeSpec{i64(a.atime.sec), i64(a.atime.nsec)}
	r.stat.mtim = time.TimeSpec{i64(a.mtime.sec), i64(a.mtime.nsec)}
	r.stat.ctim = time.TimeSpec{i64(a.ctime.sec), i64(a.ctime.nsec)}
}

// owned names come from VFS mount/create; only borrowed enumeration names are
// cloned here. The VFS creates dots for its own nodes after successful return.
fn (mut b NFSFS) make_node(parent &VFSNode, name string, h nfs.FileHandle, ph nfs.FileHandle, a nfs.Attr, owned bool) ?&VFSNode {
	if b.node_count >= nfs_nodes { errno.set(errno.enospc); return none }
	mut r := &NfsResource{backend: b, handle: h, parent_handle: ph, refcount: 1, status: if b.client.ro { 1 } else { 5 }}
	r.set_stat(a)
	// Successful resources are boot-retained. Do not suppress their allocation
	// warning as "freed"; only unpublished mount failures reclaim this box.
	r.box = &resource.Resource(r)
	owned_name := if owned { name } else { name.clone() }
	mut node := create_node(b.box, parent, owned_name, a.kind == 2)
	node.resource = r.box; node.read_only = b.client.ro
	// Existing permanent pin understood by removed.v (same as SMB). Otherwise
	// generic unlink would free this node behind the retained resource registry.
	node.mount_covered = true
	r.node = node
	if name.len <= 255 { r.name_len = name.len; nfs.copy_bytes(unsafe { &r.name[0] }, name.str, name.len) }
	if a.kind == 2 && !owned { node.create_dotentries(parent) }
	b.resources[b.node_count] = r; b.node_count++
	return node
}

fn (mut r NfsResource) refresh_attr() ? {
	mut a := nfs.Attr{}
	r.backend.client.getattr(unsafe { &r.handle }, unsafe { &a }) or { r.backend.failure(); return none }
	// Do not morph an existing resource into an unsupported remote special file.
	if a.kind != 1 && a.kind != 2 { errno.set(errno.eopnotsupp); return none }
	if (a.kind == 2) != stat.isdir(r.stat.mode) {
		r.backend.client.poison(5); r.backend.failure(); return none
	}
	r.set_stat(a)
}

fn (mut b NFSFS) refresh_locked(node &VFSNode) ? {
	mut parent := nfs_res(node)
	if parent == unsafe { nil } || !stat.isdir(parent.stat.mode) { errno.set(errno.enotdir); return none }
	if parent.removed { errno.set(errno.enoent); return none }
	mut cookie := u64(0); mut verifier := u64(0); mut count := 0
	b.epoch++; if b.epoch == 0 { b.epoch = 1 }
	epoch := b.epoch
	for _ in 0 .. nfs.max_entries {
		mut eof := false
		page := b.client.readdirplus(unsafe { &parent.handle }, cookie, verifier, unsafe { &verifier }, unsafe { &eof }) or { b.failure(); return none }
		nfs.copy_bytes(b.listing, page.p, page.n)
		mut entries := nfs.Xdr{p: b.listing, n: page.n, at: page.at}
		mut e := nfs.Entry{}
		for entries.boolean() {
			entries.entry(unsafe { &e })
			if entries.bad || count >= nfs.max_entries { b.client.poison(5); b.failure(); return none }
			if !nfs.remember_cookie(b.cookies, count, e.cookie) { b.client.poison(5); b.failure(); return none }
			count++; cookie = e.cookie
			if e.name == '.' || e.name == '..' { continue }
			if !e.has_handle {
				b.client.lookup(unsafe { &parent.handle }, e.name, unsafe { &e.handle }, unsafe { &e.attr }) or {
					if b.client.fault == 2 || b.client.fault == 116 { continue }
					b.failure(); return none
				}
			} else if !e.has_attr {
				b.client.getattr(unsafe { &e.handle }, unsafe { &e.attr }) or {
					if b.client.fault == 2 || b.client.fault == 116 { continue }
					b.failure(); return none
				}
			}
			if e.attr.kind != 1 && e.attr.kind != 2 { continue }
			mut existing := &NfsResource(unsafe { nil })
			for i in 0 .. b.node_count {
				mut candidate := b.resources[i]
				if !candidate.removed && voidptr(candidate.node.parent) == voidptr(node) && candidate.node.name == e.name { existing = candidate; break }
			}
			if existing != unsafe { nil } {
				if existing.stat.ino == e.attr.fileid && nfs_handles_equal(unsafe { &existing.handle }, unsafe { &e.handle }) {
					if (e.attr.kind == 2) != stat.isdir(existing.stat.mode) {
						b.client.poison(5); b.failure(); return none
					}
					existing.set_stat(e.attr); existing.seen = epoch; continue
				}
				nfs_retire_child(node, mut existing)
			}
			child := b.make_node(node, e.name, e.handle, parent.handle, e.attr, false)?
			mut created := nfs_res(child); created.seen = epoch
			publish_child(node, child.name, child)
		}
		if eof {
			for i in 0 .. b.node_count {
				mut old := b.resources[i]
				if old.removed || voidptr(old.node) == voidptr(node) || voidptr(old.node.parent) != voidptr(node) || old.seen == epoch { continue }
				nfs_retire_child(node, mut old)
			}
			return
		}
	}
	errno.set(errno.eoverflow); return none
}

fn nfs_handles_equal(a &nfs.FileHandle, b &nfs.FileHandle) bool {
	if a.len != b.len || a.len < 1 || a.len > 64 { return false }
	for i in 0 .. a.len { if a.bytes[i] != b.bytes[i] { return false } }
	return true
}

fn (mut b NFSFS) populate(node &VFSNode) {
	b.lock.acquire(); defer { b.lock.release() }
	if b.usable() { b.refresh_locked(node) or {} }
}

fn (mut b NFSFS) create(parent &VFSNode, name string, mode u32) &VFSNode {
	b.lock.acquire(); defer { b.lock.release() }
	if !b.usable() { return unsafe { nil } }
	p := nfs_res(parent)
	if p == unsafe { nil } || voidptr(p.backend) != voidptr(b) || p.removed || !nfs.component(name) || name.len > int(b.name_max) { errno.set(errno.einval); return unsafe { nil } }
	if mode & stat.ifmt != stat.ifreg && mode & stat.ifmt != stat.ifdir { errno.set(errno.eopnotsupp); return unsafe { nil } }
	if b.node_count >= nfs_nodes { errno.set(errno.enospc); return unsafe { nil } }
	mut h := nfs.FileHandle{}; mut a := nfs.Attr{}
	b.client.create(unsafe { &p.handle }, name, mode, stat.isdir(mode), unsafe { &h }, unsafe { &a }) or { b.failure(); return unsafe { nil } }
	return b.make_node(parent, name, h, p.handle, a, true) or { unsafe { nil } }
}

fn (mut b NFSFS) symlink(_ &VFSNode, _ string, _ string) &VFSNode { errno.set(errno.eopnotsupp); return unsafe { nil } }
fn (mut b NFSFS) link(_ &VFSNode, _ string, mut _ VFSNode) ?&VFSNode { errno.set(errno.eopnotsupp); return none }

fn (mut b NFSFS) rename(oldparent &VFSNode, old string, newparent &VFSNode, name string, flags int) ? {
	b.lock.acquire(); defer { b.lock.release() }
	b.rename_locked(oldparent, old, newparent, name, flags)?
}

fn (mut b NFSFS) rename_begin(oldparent &VFSNode, old string, source &VFSNode,
	newparent &VFSNode, name string, destination &VFSNode, flags int) ? {
	b.lock.acquire()
	mut success := false
	defer { if !success { b.lock.release() } }
	// Permission/path walks can refresh directories before reaching this hook.
	// Bind the validated identities again under the lock that excludes refresh.
	r := nfs_res(source)
	if r == unsafe { nil } || r.removed || voidptr(r.backend) != voidptr(b)
		|| voidptr(lookup_child(oldparent, old)) != voidptr(source) {
		errno.set(errno.enoent); return none
	}
	if voidptr(lookup_child(newparent, name)) != voidptr(destination) {
		errno.set(errno.eagain); return none
	}
	b.rename_locked(oldparent, old, newparent, name, flags)?
	success = true
}

fn (mut b NFSFS) rename_end() { b.lock.release() }

fn (mut b NFSFS) rename_locked(oldparent &VFSNode, old string, newparent &VFSNode, name string, flags int) ? {
	if !b.usable() { return none }
	if flags != 0 { errno.set(errno.eopnotsupp); return none }
	p := nfs_res(oldparent); q := nfs_res(newparent)
	if p == unsafe { nil } || q == unsafe { nil } || voidptr(p.backend) != voidptr(b) || voidptr(q.backend) != voidptr(b) { errno.set(errno.exdev); return none }
	if !nfs.component(old) || !nfs.component(name) || name.len > int(b.name_max) { errno.set(errno.einval); return none }
	b.client.rename(unsafe { &p.handle }, old, unsafe { &q.handle }, name) or { b.failure(); return none }
	for i in 0 .. b.node_count {
		mut r := b.resources[i]
		// VFS replaces this map slot itself after the hook returns. Retire the
		// destination identity without deleting that slot prematurely.
		if !r.removed && voidptr(r.node.parent) == voidptr(newparent) && r.node.name == name
			&& !(voidptr(oldparent) == voidptr(newparent) && old == name) {
			r.removed = true; r.node.removed = true
		}
		if !r.removed && voidptr(r.node.parent) == voidptr(oldparent) && r.node.name == old {
			r.parent_handle = q.handle; r.name_len = name.len
			nfs.copy_bytes(unsafe { &r.name[0] }, name.str, name.len)
		}
	}
}

fn (mut r NfsResource) open(flags int) ?&resource.Resource {
	mut b := r.backend
	b.lock.acquire(); defer { b.lock.release() }
	if !b.usable() { return none }
	if b.client.ro && flags & 3 != resource.o_rdonly { errno.set(errno.erofs); return none }
	r.refresh_attr()?
	// VFS mode checks and actual READ/WRITE are authoritative. ACCESS may omit
	// MODIFY/EXTEND on RO exports: do not turn server WRITE->EROFS into EACCES.
	if flags & 0o10000000 == 0 && stat.isdir(r.stat.mode) { b.refresh_locked(r.node)? }
	return r.box
}

fn (mut r NfsResource) snapshot_permissions(mut _ []u8) ?resource.PermissionMetadata {
	mut b := r.backend
	b.lock.acquire(); defer { b.lock.release() }
	if !b.usable() { return none }
	r.refresh_attr()?
	if stat.isdir(r.stat.mode) { b.refresh_locked(r.node)? }
	return resource.PermissionMetadata{r.stat.mode, r.stat.uid, r.stat.gid}
}

fn (r &NfsResource) read_only_backend() bool { return r.backend.client.ro }

fn (mut r NfsResource) read(_ voidptr, buf voidptr, offset u64, count u64) ?i64 {
	mut b := r.backend
	b.lock.acquire(); defer { b.lock.release() }
	if !b.usable() { return none }
	if !stat.isreg(r.stat.mode) { errno.set(errno.eisdir); return none }
	if count > u64(0x7fffffff) || offset > u64(0x7fffffffffffffff) - count { errno.set(errno.einval); return none }
	r.refresh_attr()?
	mut done := u64(0)
	for done < count {
		n := int(if count-done < u64(b.client.rsize) { count-done } else { u64(b.client.rsize) })
		got := b.client.read(unsafe { &r.handle }, offset+done, unsafe { &u8(buf) + done }, n) or { b.failure(); if done > 0 { return i64(done) }; return none }
		done += u64(got); if got < n { break }
	}
	return i64(done)
}

fn (mut r NfsResource) write_locked(buf voidptr, offset u64, count u64) ?i64 {
	mut b := r.backend
	if !b.usable() { return none }
	if !stat.isreg(r.stat.mode) { errno.set(errno.eisdir); return none }
	if count > u64(0x7fffffff) || offset > u64(0x7fffffffffffffff) - count { errno.set(errno.einval); return none }
	mut done := u64(0)
	for done < count {
		n := int(if count-done < u64(b.client.wsize) { count-done } else { u64(b.client.wsize) })
		got := b.client.write(unsafe { &r.handle }, offset+done, unsafe { &u8(buf) + done }, n) or { b.failure(); if done > 0 { return i64(done) }; return none }
		done += u64(got); if offset+done > u64(r.stat.size) { r.stat.size = i64(offset+done) }
	}
	return i64(done)
}

fn (mut r NfsResource) write(_ voidptr, buf voidptr, offset u64, count u64) ?i64 {
	r.backend.lock.acquire(); defer { r.backend.lock.release() }
	return r.write_locked(buf, offset, count)
}

fn (mut r NfsResource) append_data(_ voidptr, buf voidptr, count u64, limit u64, end &u64) ?i64 {
	r.backend.lock.acquire(); defer { r.backend.lock.release() }
	if !r.backend.usable() { return none }
	r.refresh_attr()?
	start := u64(r.stat.size)
	if count > 0 && start >= limit { errno.set(errno.efbig); return none }
	allowed := if count == 0 { u64(0) } else if count > limit-start { limit-start } else { count }
	written := r.write_locked(buf, start, allowed)?
	unsafe { *end = start + u64(written) }
	return written
}

fn (mut r NfsResource) grow(_ voidptr, size u64) ? {
	r.backend.lock.acquire(); defer { r.backend.lock.release() }
	if !r.backend.usable() { return none }
	if size > u64(0x7fffffffffffffff) { errno.set(errno.efbig); return none }
	a := nfs.SetAttr{size_set: true, size: size}
	r.backend.client.setattr(unsafe { &r.handle }, unsafe { &a }) or { r.backend.failure(); return none }
	r.refresh_attr()?
}

fn (mut r NfsResource) unlink(_ voidptr) ? {
	mut b := r.backend
	b.lock.acquire(); defer { b.lock.release() }
	if !b.usable() { return none }
	if r.removed { errno.set(errno.enoent); return none }
	name := unsafe { tos(&r.name[0], r.name_len) }
	b.client.remove(unsafe { &r.parent_handle }, name, stat.isdir(r.stat.mode)) or { b.failure(); return none }
	r.removed = true
}

fn (mut r NfsResource) persist_metadata() ? {
	r.backend.lock.acquire(); defer { r.backend.lock.release() }
	if !r.backend.usable() { return none }
	if r.stat.atim.tv_sec < 0 || r.stat.mtim.tv_sec < 0 || u64(r.stat.atim.tv_sec) > 0xffffffff || u64(r.stat.mtim.tv_sec) > 0xffffffff { errno.set(errno.eoverflow); return none }
	a := nfs.SetAttr{mode_set: true, mode: r.stat.mode, uid_set: true, uid: r.stat.uid, gid_set: true, gid: r.stat.gid, atime_set: true, atime: nfs.Stamp{u32(r.stat.atim.tv_sec),u32(r.stat.atim.tv_nsec)}, mtime_set: true, mtime: nfs.Stamp{u32(r.stat.mtim.tv_sec),u32(r.stat.mtim.tv_nsec)}}
	r.backend.client.setattr(unsafe { &r.handle }, unsafe { &a }) or { r.backend.failure(); return none }
	r.refresh_attr()?
}

fn (mut r NfsResource) chmod_mode(mode u32) ? {
	r.backend.lock.acquire(); defer { r.backend.lock.release() }
	if !r.backend.usable() { return none }
	a := nfs.SetAttr{mode_set: true, mode: mode}
	r.backend.client.setattr(unsafe { &r.handle }, unsafe { &a }) or { r.backend.failure(); return none }
	r.refresh_attr()?
}

fn (mut r NfsResource) try_filesystem_stat() ?resource.FileSystemStat {
	r.backend.lock.acquire(); defer { r.backend.lock.release() }
	mut info := nfs.FsInfo{}
	if !r.backend.usable() { return none }
	r.backend.client.fsstat(unsafe { &r.handle }, unsafe { &info }) or { r.backend.failure(); return none }
	return resource.FileSystemStat{@type: 0x6969, bsize: 4096, frsize: 4096, blocks: info.total/4096, bfree: info.free/4096, bavail: info.available/4096, files: info.files, ffree: info.ffree, namelen: r.backend.name_max, flags: u64(r.backend.client.ro)}
}

fn (mut r NfsResource) sync(_ voidptr) ? { if r.backend.client.dead { r.backend.failure(); return none } }
fn (mut r NfsResource) link(_ voidptr) ? { errno.set(errno.eopnotsupp); return none }
fn (mut r NfsResource) ioctl(handle voidptr, request u64, arg voidptr) ?int { return resource.default_ioctl(handle, request, arg) }
fn (mut r NfsResource) mmap(_ voidptr, _ u64, _ int) voidptr { return unsafe { nil } }

// Boot-lifetime storage: reference changes never free boxes, nodes, or slots.
fn (mut r NfsResource) unref(_ voidptr) ? { katomic.dec(mut &r.refcount) }

fn (mut b NFSFS) check_unmount() ? {
	b.lock.acquire(); defer { b.lock.release() }
	if b.client.dead { return }
	// UMNT is advisory. Preserve the live stream for bind/namespace aliases.
	old_stream := b.stream; old_socket := b.socket; old_flags := b.io_handle.flags
	b.stream = unsafe { nil }; b.socket = unsafe { nil }
	defer {
		b.close_stream()
		b.stream = unsafe { old_stream }; b.socket = unsafe { old_socket }; b.io_handle.flags = old_flags
		b.client.dead = false; b.client.fault = 0
	}
	b.connect_port(b.mount_port) or { return }
	b.identity()
	b.client.unmount_export(unsafe { tos(&b.export_path[0], b.export_len) }) or {}
}

fn nfs_begin_call(context voidptr) {
	mut b := unsafe { &NFSFS(context) }
	b.deadline = time.monotonic_ns() + u64(5_000_000_000)
}

fn nfs_transfer(context voidptr, p &u8, n int, sending bool) bool {
	mut b := unsafe { &NFSFS(context) }
	mut at := 0
	for at < n {
		if time.monotonic_ns() >= b.deadline { return false }
		amount := if sending {
			b.stream.sendto(unsafe { &b.io_handle }, unsafe { p + at }, u64(n-at), unsafe { nil }, 0) or {
				if errno.get() == errno.eagain { devcore.sleep_ms(1); continue }; return false
			}
		} else {
			b.stream.recvfrom(unsafe { &b.io_handle }, unsafe { p + at }, u64(n-at), unsafe { nil }, unsafe { nil }) or {
				if errno.get() == errno.eagain { devcore.sleep_ms(1); continue }; return false
			}
		}
		if amount <= 0 || amount > n-at { return false }
		at += int(amount)
	}
	return true
}

fn (mut b NFSFS) close_stream() {
	if b.socket == unsafe { nil } { return }
	b.socket.unref(unsafe { &b.io_handle }) or {}
	memory.free(b.socket)
	b.socket = unsafe { nil }; b.stream = unsafe { nil }
}

fn (mut b NFSFS) connect_port(port u16) ? {
	b.close_stream()
	for _ in 0 .. 2 {
		b.stream = inet.create(sockpub.sock_stream, 6) or { return none }
		b.stream.refcount = 1
		b.socket = &sockpub.Socket(b.stream) @[freed]
		b.io_handle.flags = resource.o_nonblock
		mut address := inet.SockaddrIn{sin_family: 2, sin_port: (port << 8) | (port >> 8), sin_addr: b.address}
		mut connecting := false
		b.socket.connect(unsafe { &b.io_handle }, unsafe { &address }, u32(sizeof(inet.SockaddrIn))) or {
			connecting = errno.get() == errno.einprogress
			if !connecting { b.close_stream(); continue }
		}
		deadline := time.monotonic_ns() + u64(5_000_000_000)
		if connecting {
			for time.monotonic_ns() < deadline {
				error_code := b.socket.getsockopt(unsafe { &b.io_handle }, sockpub.sol_socket, sockpub.so_error) or { break }
				if error_code != 0 { break }
				b.stream.sendto(unsafe { &b.io_handle }, b.client.tx, 0, unsafe { nil }, 0) or { devcore.sleep_ms(1); continue }
				connecting = false; break
			}
		}
		if !connecting { b.client.dead = false; b.client.fault = 0; return }
		b.close_stream()
	}
	b.client.poison(110); errno.set(errno.etimedout); return none
}

fn (mut b NFSFS) log_exports() {
	mut r := b.client.exports() or { return }
	mut exports := 0; mut groups := 0
	for r.boolean() {
		if r.bad || exports >= 128 { r.bad = true; break }
		path := r.opaque(1024)
		if !r.bad { C.kprintf(c'nfs: export %.*s\n', path.len, path.str) }; exports++
		for r.boolean() {
			if r.bad || groups >= 1024 { r.bad = true; break }
			group := r.opaque(255)
			if !r.bad { C.kprintf(c'nfs:   allowed group %.*s\n', group.len, group.str) }; groups++
		}
		if r.bad { break }
	}
	b.client.finish(unsafe { &r }, 0) or {}
}
