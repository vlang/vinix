// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module fs

import errno
import devcore
import event.eventstruct
import file
import fs.smb2
import katomic
import klock
import krandom
import memory
import proc
import resource
import socket.inet
import socket.public as sockpub
import stat
import time

const smb2_sessions = 4

pub struct SMB2FS {
mut:
	box        &FileSystem = unsafe { nil }
	lock       klock.Lock
	client     smb2.Client
	socket     &sockpub.Socket  = unsafe { nil }
	stream     &inet.InetSocket = unsafe { nil }
	handle     file.Handle
	tx         [smb2.capacity]u8
	rx         [smb2.capacity]u8
	scratch    [smb2.capacity + 64]u8
	resources  [smb2.max_nodes]&SMB2Resource
	count      int
	dev        u64
	uid        u32
	source     [384]u8
	source_len int
	credential [16]u8
	guest      bool
	ro         bool
	serial     u64
	published  bool
}

__global (
	smb2_pool      [smb2_sessions]&SMB2FS
	smb2_pool_lock klock.Lock
)
struct SMB2Resource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
mut:
	backend     &SMB2FS            = unsafe { nil }
	box         &resource.Resource = unsafe { nil }
	node        &VFSNode           = unsafe { nil }
	path        [smb2.max_path]u8
	length      int
	seen        u64
	host        smb2.Attr
	publication int
}

fn (mut b SMB2FS) as_filesystem() &FileSystem {
	if b.box == unsafe { nil } { b.box = &FileSystem(b) }
	return b.box
}

fn (mut template SMB2FS) instantiate() &FileSystem {
	mut b := unsafe { &SMB2FS(memory.malloc_packed_fallible(sizeof(SMB2FS))) }
	if b == unsafe { nil } {
		errno.set(errno.enomem)
		return unsafe { nil }
	}
	unsafe {
		*b = SMB2FS{}
	}
	return b.as_filesystem()
}

fn (mut b SMB2FS) mount(_ &VFSNode, _ string, _ &VFSNode) ?&VFSNode {
	errno.set(errno.einval)
	return none
}

fn (mut b SMB2FS) error() {
	if b.client.diagnostic.len > 0 {
		C.kprintf(c'smb2: request failed errno=%d reason=%s\n', b.client.fault,
			b.client.diagnostic.str)
	}
	errno.set(if b.client.fault > 0 && b.client.fault < 4096 {
		u64(b.client.fault)
	} else {
		errno.eio
	})
}

fn smb2_transfer(context voidptr, p &u8, n int, sending bool) bool {
	mut b := unsafe { &SMB2FS(context) }
	mut done := 0
	// Nonblocking calls plus a bounded retry avoid losing an ACK/readiness
	// edge between a full TCP send queue and the generic socket's wait setup.
	// Sleeping yields to network progress; no global network lock is held.
	deadline := time.monotonic_ns() + u64(15_000_000_000)
	for done < n {
		if time.monotonic_ns() >= deadline {
			C.kprintf(c'smb2: TCP deadline sending=%d done=%d length=%d\n', int(sending), done, n)
			return false
		}
		amount := if sending {
			b.stream.sendto(unsafe { &b.handle }, unsafe { &p[done] }, u64(n - done),
				unsafe { nil }, 0) or {
				if errno.get() == errno.eagain {
					devcore.sleep_ms(1)
					continue
				}
				C.kprintf(c'smb2: TCP send failed errno=%lu done=%d length=%d\n', errno.get(),
					done, n)
				return false
			}
		} else {
			b.stream.recvfrom(unsafe { &b.handle }, unsafe { &p[done] }, u64(n - done),
				unsafe { nil }, unsafe { nil }) or {
				if errno.get() == errno.eagain {
					devcore.sleep_ms(1)
					continue
				}
				C.kprintf(c'smb2: TCP receive failed errno=%lu done=%d length=%d\n', errno.get(),
					done, n)
				return false
			}
		}
		if amount <= 0 || amount > n - done { return false }
		done += int(amount)
	}
	return true
}

fn (mut b SMB2FS) destroy_private() {
	// InetSocket.unref owns its resource.Resource box and concrete socket.
	// This adapter's separate sockpub.Socket interface box is ours to free.
	if b.socket != unsafe { nil } {
		b.socket.unref(unsafe { &b.handle }) or {}
		memory.free(b.socket)
	}
	krandom.explicit_bzero(unsafe { &b.credential[0] }, sizeof(b.credential))
	krandom.explicit_bzero(unsafe { &b.client.key[0] }, sizeof(b.client.key))
	krandom.explicit_bzero(unsafe { &b.tx[0] }, sizeof(b.tx))
	krandom.explicit_bzero(unsafe { &b.rx[0] }, sizeof(b.rx))
	krandom.explicit_bzero(unsafe { &b.scratch[0] }, sizeof(b.scratch))
	memory.free(b.box)
	memory.free(b)
}

fn (mut b SMB2FS) mount_specifier(parent &VFSNode, name string, source string, flags u64, options string) ?&VFSNode {
	mut opts := smb2.Options{}
	defer { krandom.explicit_bzero(unsafe { &opts }, sizeof(opts)) }
	mut address := u32(0)
	mut share := ''
	mut host := ''
	if !smb2.parse_options(options, unsafe { &opts })
		|| !smb2.parse_source(source, unsafe { &address }, unsafe { &share }, unsafe { &host }) {
		b.destroy_private()
		errno.set(errno.einval)
		return none
	}
	mut credential := [16]u8{}
	defer { krandom.explicit_bzero(unsafe { &credential[0] }, sizeof(credential)) }
	if !opts.guest
		&& !smb2.ntlmv2_hash(opts.user, opts.domain, opts.password, unsafe { &credential[0] }) {
		b.destroy_private()
		errno.set(errno.einval)
		return none
	}
	// Pool lock is never held during connect or wire I/O. Slot reservation
	// prevents concurrent mount attempts from exceeding the hard boot budget.
	smb2_pool_lock.acquire()
	mut slot := -1
	for i in 0 .. smb2_sessions {
		mut cached := smb2_pool[i]
		if cached == unsafe { nil } {
			if slot < 0 { slot = i }
			continue
		}
		if !cached.published { continue
		 }
		if cached.source_len != source.len || cached.uid != proc.current_thread().process.euid || cached.guest != opts.guest || cached.ro != (opts.ro || flags & 1 != 0) { continue
		 }
		mut same := true
		for j in 0 .. source.len {
			if cached.source[j] != source[j] {
				same = false
				break
			}
		}
		for j in 0 .. 16 {
			if cached.credential[j] != credential[j] {
				same = false
				break
			}
		}
		if same {
			smb2_pool_lock.release()
			b.destroy_private()
			cached.lock.acquire()
			defer { cached.lock.release() }
			return cached.make_root(parent, name)
		}
	}
	if slot < 0 {
		smb2_pool_lock.release()
		b.destroy_private()
		errno.set(errno.enospc)
		return none
	}
	smb2_pool[slot] = b
	smb2_pool_lock.release()
	mut success := false
	defer {
		if !success {
			smb2_pool_lock.acquire()
			smb2_pool[slot] = unsafe { nil }
			smb2_pool_lock.release()
			b.destroy_private()
		}
	}
	b.stream = inet.create(sockpub.sock_stream, 6) or { return none }
	b.stream.set_timeout(true, 5_000_000_000)
	b.stream.set_timeout(false, 5_000_000_000)
	b.socket = &sockpub.Socket(b.stream)
	mut endpoint := inet.SockaddrIn{
		sin_family: 2
		sin_port:   0xbd01
		sin_addr:   address
	}
	b.socket.connect(unsafe { &b.handle }, unsafe { &endpoint }, u32(sizeof(inet.SockaddrIn)))?
	// Connect remains bounded/blocking; framed traffic is retried explicitly.
	b.handle.flags = resource.o_nonblock
	b.client = smb2.Client{
		context:  voidptr(b)
		transfer: smb2_transfer
		tx:       unsafe { &b.tx[0] }
		rx:       unsafe { &b.rx[0] }
		scratch:  unsafe { &b.scratch[0] }
	}
	mut random := [24]u8{}
	defer { krandom.explicit_bzero(unsafe { &random[0] }, sizeof(random)) }
	if !krandom.fill(unsafe { &random[0] }, 24, false) {
		errno.set(errno.eagain)
		return none
	}
	b.client.negotiate(unsafe { &random[0] }) or {
		b.error()
		return none
	}
	b.client.login(opts.user, opts.domain, opts.password, opts.guest, unsafe { &random[16] }) or {
		if b.client.diagnostic.len > 0 { C.kprintf(c'smb2: %s\n', b.client.diagnostic.str) }
		b.error()
		return none
	}
	mut unc := [512]u8{}
	unc[0] = `\\`
	unc[1] = `\\`
	smb2.move(unsafe { &unc[2] }, host.str, host.len)
	unc[2 + host.len] = `\\`
	smb2.move(unsafe { &unc[3 + host.len] }, share.str, share.len)
	b.client.tree_connect(unsafe { tos(&unc[0], 3 + host.len + share.len) }) or {
		b.error()
		return none
	}
	volume_ro := b.client.volume_readonly() or {
		b.error()
		return none
	}
	b.client.readonly = b.client.readonly || volume_ro
	b.ro = opts.ro || flags & 1 != 0
	b.client.readonly = b.client.readonly || b.ro
	b.uid = proc.current_thread().process.euid
	b.dev = resource.create_dev_id()
	root := b.make_root(parent, name)?
	b.source_len = source.len
	smb2.move(unsafe { &b.source[0] }, source.str, source.len)
	smb2.move(unsafe { &b.credential[0] }, unsafe { &credential[0] }, 16)
	b.guest = opts.guest
	smb2_pool_lock.acquire()
	b.published = true
	smb2_pool_lock.release()
	success = true
	return root
}

fn smb2_res(node &VFSNode) &SMB2Resource {
	if node == unsafe { nil } || node.resource == unsafe { nil } { return unsafe { nil } }
	mut r := node.resource
	if mut r is SMB2Resource { return unsafe { r } }
	return unsafe { nil }
}

fn (r &SMB2Resource) remote_path() string {
	return unsafe { tos(&r.path[0], r.length) }
}

fn smb2_component(name string) bool {
	if name.len == 0 || name.len > 255 || name == '.' || name == '..' { return false }
	for ch in name {
		if ch == 0 || ch == `/` || ch == `\\` || ch == `:` { return false }
	}
	return true
}

fn smb2_path(parent &SMB2Resource, name string, out &u8) ?int {
	if !smb2_component(name) {
		errno.set(errno.einval)
		return none
	}
	separator := if parent.length > 0 { 1 } else { 0 }
	if !smb2.span(smb2.max_path, parent.length, separator + name.len) {
		errno.set(errno.enametoolong)
		return none
	}
	smb2.move(out, unsafe { &parent.path[0] }, parent.length)
	if separator > 0 {
		unsafe {
			out[parent.length] = `\\`
		}
	}
	smb2.move(unsafe { &out[parent.length + separator] }, name.str, name.len)
	return parent.length + separator + name.len
}

fn smb2_time(value u64) time.TimeSpec {
	if value < 116444736000000000 { return time.TimeSpec{} }
	ticks := value - u64(116444736000000000)
	return time.TimeSpec{i64(ticks / 10000000), i64(ticks % 10000000) * 100}
}

fn (mut r SMB2Resource) set_stat(a &smb2.Attr) {
	r.host = *a
	r.stat.dev = r.backend.dev
	r.stat.ino = a.ino
	r.stat.size = i64(a.size)
	r.stat.blocks = i64(a.allocation / 512)
	r.stat.blksize = smb2.io_size
	r.stat.uid = r.backend.uid
	r.stat.gid = 0
	r.stat.nlink = 1
	r.stat.mode = if a.attributes & 16 != 0 {
		u32(stat.ifdir | 0o755)
	} else {
		u32(stat.ifreg | 0o644)
	}
	if r.backend.client.readonly || a.attributes & 1 != 0 { r.stat.mode &= ~u32(0o222) }
	r.stat.atim = smb2_time(a.accessed)
	r.stat.mtim = smb2_time(a.written)
	r.stat.ctim = smb2_time(a.changed)
}

fn (mut b SMB2FS) make_node(parent &VFSNode, name string, path string, a &smb2.Attr) ?&VFSNode {
	if b.count >= smb2.max_nodes || path.len > smb2.max_path {
		errno.set(errno.enospc)
		return none
	}
	mut r := unsafe { &SMB2Resource(memory.malloc_packed_fallible(sizeof(SMB2Resource))) }
	if r == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	unsafe {
		*r = SMB2Resource{
			backend:  b
			refcount: 1
			length:   path.len
		}
	}
	smb2.move(unsafe { &r.path[0] }, path.str, path.len)
	r.set_stat(a)
	mut node := create_node(b.as_filesystem(), parent, name, stat.isdir(r.stat.mode))
	r.node = node
	r.box = &resource.Resource(r)
	node.resource = r.box
	node.read_only = b.client.readonly
	// The boot cache, rather than generic orphan teardown, owns this node.
	// mount_covered is the existing permanent-pin bit used by removed.v only.
	node.mount_covered = true
	b.resources[b.count] = r
	b.count++
	if stat.isdir(r.stat.mode) { node.create_dotentries(parent) }
	return node
}

fn (mut b SMB2FS) make_root(parent &VFSNode, name string) ?&VFSNode {
	id := b.client.create('', 0x80, 1, true) or {
		b.error()
		return none
	}
	defer { b.client.close(id) or {} }
	mut attr := unsafe { &smb2.Attr(C.vinix_stack_alloc(sizeof(smb2.Attr))) }
	unsafe {
		*attr = smb2.Attr{}
	}
	b.client.query_info(id, attr) or {
		b.error()
		return none
	}
	return b.make_node(parent, name, '', attr)
}

// Caller holds backend.lock. Validate THIS handle before any operation: a
// pathname can be replaced between a previous refresh and CREATE.
fn (mut r SMB2Resource) open_checked(access u32) ?smb2.FileId {
	id := r.backend.client.create(r.remote_path(), access | 0x80, 1, r.host.attributes & 16 != 0) or {
		// CREATE's directory constraint can detect a type replacement before
		// a handle exists to query; report the same fail-closed identity error.
		if r.backend.client.fault == 20 || r.backend.client.fault == 21 {
			errno.set(errno.ebusy)
		} else {
			r.backend.error()
		}
		return none
	}
	mut a := smb2.Attr{}
	r.backend.client.query_info(id, unsafe { &a }) or {
		r.backend.error()
		r.backend.client.close(id) or {}
		return none
	}
	if a.ino != r.host.ino || a.attributes & 16 != r.host.attributes & 16 {
		r.backend.client.close(id) or {}
		errno.set(errno.ebusy)
		return none
	}
	return id
}

fn (mut r SMB2Resource) refresh_locked() ? {
	id := r.open_checked(0x80)?
	defer { r.backend.client.close(id) or {} }
	mut a := smb2.Attr{}
	r.backend.client.query_info(id, unsafe { &a }) or {
		r.backend.error()
		return none
	}
	r.set_stat(unsafe { &a })
}

// Integration hook for fstat/fstatat; the current VFS has no generic callback.
pub fn smb2_refresh_stat(mut res resource.Resource) ? {
	if mut res is SMB2Resource {
		res.backend.lock.acquire()
		defer { res.backend.lock.release() }
		res.refresh_locked()?
	}
}

fn (mut b SMB2FS) populate_locked(mut r SMB2Resource) ? {
	if !stat.isdir(r.stat.mode) { return }
	id := r.open_checked(0x81)?
	defer { b.client.close(id) or {} }
	b.serial++
	epoch := b.serial
	mut entry := unsafe { &smb2.DirEntry(C.vinix_stack_alloc(sizeof(smb2.DirEntry))) }
	mut path := unsafe { &u8(C.vinix_stack_alloc(smb2.max_path)) }
	mut complete := false
	for batch in 0 .. smb2.max_nodes * 2 {
		has := b.client.directory(id, batch == 0) or {
			b.error()
			return none
		}
		if !has {
			complete = true
			break
		}
		off := int(smb2.get16(b.client.rx, 66))
		length := int(smb2.get32(b.client.rx, 68))
		mut at := 0
		for _ in 0 .. smb2.max_nodes {
			if !smb2.span(length, at, 104)
				|| !smb2.parse_entry(unsafe { &b.client.rx[off + at] }, length - at, entry) {
				errno.set(errno.eio)
				return none
			}
			name := unsafe { tos(&entry.name[0], entry.length) }
			if name != '.' && name != '..' && entry.attr.attributes & 0x400 == 0 {
				mut old := smb2_res(lookup_child_synced(r.node, name))
				if old != unsafe { nil } {
					if old.host.ino != entry.attr.ino
						|| old.host.attributes & 16 != entry.attr.attributes & 16 {
						errno.set(errno.ebusy)
						return none
					}
					old.set_stat(unsafe { &entry.attr })
					old.seen = epoch
				} else {
					n := smb2_path(r, name, path)?
					owned := name.clone()
					node := b.make_node(r.node, owned, unsafe { tos(path, n) },
						unsafe { &entry.attr }) or {
						unsafe { owned.free() }
						return none
					}
					mut child := smb2_res(node)
					child.seen = epoch
					publish_child(r.node, node.name, node)
				}
			}
			if entry.next == 0 {
				at = length
				break
			}
			at += entry.next
		}
		if at != length {
			errno.set(errno.eoverflow)
			return none
		}
	}
	if !complete {
		errno.set(errno.eoverflow)
		return none
	}
	// Keep cached nodes pinned. Remove only their name-map binding, so an
	// existing descriptor/cwd continues to own valid memory. Replacements
	// fail EBUSY above rather than changing an inode under a lockless walker.
	for i in 0 .. b.count {
		mut child := b.resources[i]
		if voidptr(child.node.parent) == voidptr(r.node) && child.length > 0 && child.seen != epoch
			&& !child.node.removed {
			remove_child(r.node, child.node.name)
			child.node.removed = true
		}
	}
}

fn (mut b SMB2FS) populate(node &VFSNode) {
	mut r := smb2_res(node)
	if r == unsafe { nil } { return }
	b.lock.acquire()
	defer { b.lock.release() }
	b.populate_locked(mut r) or {}
}

fn (mut r SMB2Resource) snapshot_permissions(mut _ []u8) ?resource.PermissionMetadata {
	r.backend.lock.acquire()
	defer { r.backend.lock.release() }
	r.refresh_locked()?
	if stat.isdir(r.stat.mode) { r.backend.populate_locked(mut r)? }
	return resource.PermissionMetadata{r.stat.mode, r.stat.uid, r.stat.gid}
}

fn (r &SMB2Resource) read_only_backend() bool {
	return r.backend.client.readonly
}

fn (mut r SMB2Resource) open(flags int) ?&resource.Resource {
	r.backend.lock.acquire()
	defer { r.backend.lock.release() }
	r.refresh_locked()?
	if flags & 3 != 0 && r.backend.client.readonly {
		errno.set(errno.erofs)
		return none
	}
	if stat.isdir(r.stat.mode) { r.backend.populate_locked(mut r)? }
	return r.box
}

fn (mut b SMB2FS) create(parent &VFSNode, name string, mode u32) &VFSNode {
	b.lock.acquire()
	defer { b.lock.release() }
	mut p := smb2_res(parent)
	if p == unsafe { nil } {
		errno.set(errno.einval)
		return unsafe { nil }
	}
	mut path := unsafe { &u8(C.vinix_stack_alloc(smb2.max_path)) }
	n := smb2_path(p, name, path) or { return unsafe { nil } }
	remote := unsafe { tos(path, n) }
	id := b.client.create(remote, 0x0012019f, 2, stat.isdir(mode)) or {
		b.error()
		return unsafe { nil }
	}
	defer { b.client.close(id) or {} }
	mut attr := unsafe { &smb2.Attr(C.vinix_stack_alloc(sizeof(smb2.Attr))) }
	unsafe {
		*attr = smb2.Attr{}
	}
	b.client.query_info(id, attr) or {
		b.error()
		return unsafe { nil }
	}
	return b.make_node(parent, name, remote, attr) or { unsafe { nil } }
}

fn (mut b SMB2FS) symlink(_ &VFSNode, _ string, _ string) &VFSNode {
	errno.set(errno.enotsup)
	return unsafe { nil }
}

fn (mut b SMB2FS) link(_ &VFSNode, _ string, mut _ VFSNode) ?&VFSNode {
	errno.set(errno.enotsup)
	return none
}

fn (mut b SMB2FS) rename(old_parent &VFSNode, old_name string, new_parent &VFSNode, new_name string, flags int) ? {
	b.lock.acquire()
	defer { b.lock.release() }
	if flags & ~1 != 0 {
		errno.set(errno.einval)
		return none
	}
	mut r := smb2_res(lookup_child_synced(old_parent, old_name))
	p := smb2_res(new_parent)
	if r == unsafe { nil } || p == unsafe { nil } {
		errno.set(errno.enoent)
		return none
	}
	mut path := unsafe { &u8(C.vinix_stack_alloc(smb2.max_path)) }
	n := smb2_path(p, new_name, path)?
	// Cached mounts have separate namespace nodes. Until rename publication
	// is shared across them, reject a known alias rather than leave stale paths.
	for i in 0 .. b.count {
		other := b.resources[i]
		if voidptr(other) != voidptr(r) && other.remote_path() == r.remote_path() {
			errno.set(errno.ebusy)
			return none
		}
	}
	// Descendant paths are updated only if they fit, before mutating the server.
	for i in 0 .. b.count {
		child := b.resources[i]
		if child.length > r.length && child.path[r.length] == `\\` {
			mut prefix := true
			for j in 0 .. r.length {
				if child.path[j] != r.path[j] {
					prefix = false
					break
				}
			}
			if prefix && child.length - r.length > smb2.max_path - n {
				errno.set(errno.enametoolong)
				return none
			}
		}
	}
	id := r.open_checked(0x10080)?
	defer { b.client.close(id) or {} }
	b.client.rename(id, unsafe { tos(path, n) }, flags & 1 == 0) or {
		b.error()
		return none
	}
	for i in 0 .. b.count {
		mut child := b.resources[i]
		if child.length > r.length && child.path[r.length] == `\\` {
			mut prefix := true
			for j in 0 .. r.length {
				if child.path[j] != r.path[j] {
					prefix = false
					break
				}
			}
			if prefix {
				tail := child.length - r.length
				mut tmp := unsafe { &u8(C.vinix_stack_alloc(smb2.max_path)) }
				smb2.move(tmp, unsafe { &child.path[r.length] }, tail)
				smb2.move(unsafe { &child.path[0] }, path, n)
				smb2.move(unsafe { &child.path[n] }, tmp, tail)
				child.length = n + tail
			}
		}
	}
	smb2.move(unsafe { &r.path[0] }, path, n)
	r.length = n
}

fn (mut r SMB2Resource) read(_ voidptr, buf voidptr, offset u64, count u64) ?i64 {
	r.backend.lock.acquire()
	defer { r.backend.lock.release() }
	if offset > u64(0x7fffffffffffffff) {
		errno.set(errno.eoverflow)
		return none
	}
	// Linux's maximum signed file offset is an EOF boundary for reads.
	if offset == u64(0x7fffffffffffffff) { return 0 }
	id := r.open_checked(0x00120089)?
	defer { r.backend.client.close(id) or {} }
	mut done := u64(0)
	for done < count {
		if done > u64(0x7fffffffffffffff) || offset > u64(0x7fffffffffffffff) - done {
			errno.set(errno.eoverflow)
			return none
		}
		remaining := u64(0x7fffffffffffffff) - offset - done
		if remaining == 0 { break
		 }
		mut n := if count - done > r.backend.client.max_read {
			int(r.backend.client.max_read)
		} else {
			int(count - done)
		}
		if u64(n) > remaining { n = int(remaining) }
		got := r.backend.client.read(id, offset + done, unsafe { &u8(u64(buf) + done) }, n) or {
			r.backend.error()
			if done > 0 { return i64(done) }
			return none
		}
		done += u64(got)
		if got < n { break
		 }
	}
	return i64(done)
}

fn (mut r SMB2Resource) write_locked(buf voidptr, offset u64, count u64) ?i64 {
	id := r.open_checked(0x0012019f)?
	defer { r.backend.client.close(id) or {} }
	mut done := u64(0)
	for done < count {
		if done > u64(0x7fffffffffffffff) || offset > u64(0x7fffffffffffffff) - done {
			errno.set(errno.eoverflow)
			return none
		}
		remaining := u64(0x7fffffffffffffff) - offset - done
		if remaining == 0 {
			if done > 0 { return i64(done) }
			errno.set(errno.efbig)
			return none
		}
		mut n := if count - done > r.backend.client.max_write {
			int(r.backend.client.max_write)
		} else {
			int(count - done)
		}
		if u64(n) > remaining { n = int(remaining) }
		got := r.backend.client.write(id, offset + done, unsafe { &u8(u64(buf) + done) }, n) or {
			r.backend.error()
			if done > 0 { return i64(done) }
			return none
		}
		done += u64(got)
	}
	r.refresh_locked()?
	return i64(done)
}

fn (mut r SMB2Resource) write(_ voidptr, buf voidptr, offset u64, count u64) ?i64 {
	r.backend.lock.acquire()
	defer { r.backend.lock.release() }
	return r.write_locked(buf, offset, count)
}

fn (mut r SMB2Resource) append_data(_ voidptr, buf voidptr, count u64, limit u64, end &u64) ?i64 {
	r.backend.lock.acquire()
	defer { r.backend.lock.release() }
	r.refresh_locked()?
	offset := u64(r.stat.size)
	if offset > limit || count > limit - offset {
		errno.set(errno.efbig)
		return none
	}
	n := r.write_locked(buf, offset, count)?
	unsafe {
		*end = offset + u64(n)
	}
	return n
}

fn (mut r SMB2Resource) grow(_ voidptr, size u64) ? {
	r.backend.lock.acquire()
	defer { r.backend.lock.release() }
	if size > u64(0x7fffffffffffffff) {
		errno.set(errno.efbig)
		return none
	}
	id := r.open_checked(0x0012019f)?
	defer { r.backend.client.close(id) or {} }
	mut data := [8]u8{}
	smb2.put64(unsafe { &data[0] }, 0, size)
	r.backend.client.set_info(id, 20, unsafe { &data[0] }, 8) or {
		r.backend.error()
		return none
	}
	r.refresh_locked()?
}

fn (mut r SMB2Resource) unlink(_ voidptr) ? {
	r.backend.lock.acquire()
	defer { r.backend.lock.release() }
	id := r.open_checked(0x10080)?
	defer { r.backend.client.close(id) or {} }
	mut data := u8(1)
	r.backend.client.set_info(id, 13, unsafe { &data }, 1) or {
		r.backend.error()
		return none
	}
	r.stat.nlink = 0
}

fn (mut r SMB2Resource) persist_metadata() ? {
	r.backend.lock.acquire()
	defer { r.backend.lock.release() }
	id := r.open_checked(0x00120180)?
	defer { r.backend.client.close(id) or {} }
	mut data := [40]u8{}
	if r.stat.uid != r.backend.uid || r.stat.gid != 0 {
		errno.set(errno.enotsup)
		return none
	}
	smb2.put64(unsafe { &data[0] }, 8, smb2_filetime(r.stat.atim))
	smb2.put64(unsafe { &data[0] }, 16, smb2_filetime(r.stat.mtim))
	smb2.put32(unsafe { &data[0] }, 32, if r.stat.mode & 0o222 == 0 {
		r.host.attributes | 1
	} else {
		r.host.attributes & ~u32(1)
	})
	r.backend.client.set_info(id, 4, unsafe { &data[0] }, 40) or {
		r.backend.error()
		return none
	}
	r.refresh_locked()?
}

fn smb2_filetime(t time.TimeSpec) u64 {
	if t.tv_sec < 0 || t.tv_sec > i64(0x7fffffffffffffff / 10000000) - 11644473600 { return 0 }
	return u64(t.tv_sec) * 10000000 + 116444736000000000 + u64(t.tv_nsec / 100)
}

fn (mut r SMB2Resource) chmod_mode(mode u32) ? {
	r.stat.mode = (r.stat.mode & stat.ifmt) | (mode & 0o777)
	r.persist_metadata()?
}

fn (mut r SMB2Resource) sync(_ voidptr) ? {
	r.backend.lock.acquire()
	defer { r.backend.lock.release() }
	id := r.open_checked(0x80)?
	defer { r.backend.client.close(id) or {} }
	r.backend.client.flush(id) or {
		r.backend.error()
		return none
	}
}

fn (mut r SMB2Resource) link(_ voidptr) ? {
	errno.set(errno.enotsup)
	return none
}

fn (mut r SMB2Resource) ioctl(handle voidptr, request u64, arg voidptr) ?int {
	return resource.default_ioctl(handle, request, arg)
}

fn (mut r SMB2Resource) mmap(_ voidptr, _ u64, _ int) voidptr {
	return unsafe { nil }
}

// Boot pool owns resource boxes/nodes; generic VFS teardown must never free
// these behind another namespace. Count is bounded and never recycled.
fn (mut r SMB2Resource) unref(_ voidptr) ? {
	katomic.dec(mut &r.refcount)
}

fn (mut b SMB2FS) check_unmount() ? {}
