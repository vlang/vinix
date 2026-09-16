module fs

import errno
import event
import event.eventstruct
import file
import katomic
import klock
import proc
import resource
import stat
import usercopy

pub const in_access = u32(0x00000001)
pub const in_modify = u32(0x00000002)
pub const in_attrib = u32(0x00000004)
pub const in_close_write = u32(0x00000008)
pub const in_close_nowrite = u32(0x00000010)
pub const in_open = u32(0x00000020)
pub const in_moved_from = u32(0x00000040)
pub const in_moved_to = u32(0x00000080)
pub const in_create = u32(0x00000100)
pub const in_delete = u32(0x00000200)
pub const in_delete_self = u32(0x00000400)
pub const in_move_self = u32(0x00000800)
pub const in_q_overflow = u32(0x00004000)
pub const in_ignored = u32(0x00008000)
pub const in_onlydir = u32(0x01000000)
pub const in_dont_follow = u32(0x02000000)
pub const in_excl_unlink = u32(0x04000000)
pub const in_mask_create = u32(0x10000000)
pub const in_mask_add = u32(0x20000000)
pub const in_isdir = u32(0x40000000)
pub const in_oneshot = u32(0x80000000)

const in_event_mask = u32(0x00000fff)
const in_control_mask = in_onlydir | in_dont_follow | in_excl_unlink | in_mask_create | in_mask_add | in_oneshot
const in_cloexec = resource.o_cloexec
const in_nonblock = resource.o_nonblock
const max_inotify_queue = 1024 * 1024
const max_inotify_watches = 8192

struct InotifyWatch {
mut:
	wd   int
	node &VFSNode = unsafe { nil }
	mask u32
}

struct INotify {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	watches    []InotifyWatch
	queue      []u8
	next_wd    int = 1
	overflowed bool
}

__global (
	inotify_lock      klock.Lock
	inotify_instances []&INotify
	inotify_cookie    = u32(1)
)

pub fn inotify_next_cookie() u32 {
	inotify_lock.acquire()
	defer { inotify_lock.release() }
	ret := inotify_cookie
	inotify_cookie++
	if inotify_cookie == 0 {
		inotify_cookie = 1
	}
	return ret
}

fn append_u32(mut bytes []u8, value u32) {
	bytes << u8(value)
	bytes << u8(value >> 8)
	bytes << u8(value >> 16)
	bytes << u8(value >> 24)
}

fn queued_record_size(bytes []u8) u64 {
	if bytes.len < 16 {
		return 0
	}
	name_len := u32(bytes[12]) | (u32(bytes[13]) << 8) | (u32(bytes[14]) << 16) | (u32(bytes[15]) << 24)
	return 16 + u64(name_len)
}

fn (mut this INotify) enqueue_locked(wd int, mask u32, cookie u32, name string) {
	mut name_len := 0
	if name.len != 0 {
		name_len = (name.len + 1 + 3) & ~3
	}
	record_size := 16 + name_len
	if this.queue.len + record_size > max_inotify_queue {
		if this.overflowed {
			return
		}
		this.overflowed = true
		if this.queue.len + 16 > max_inotify_queue {
			this.queue.delete_many(0, this.queue.len)
		}
		this.enqueue_locked(-1, in_q_overflow, 0, '')
		return
	}
	append_u32(mut this.queue, u32(wd))
	append_u32(mut this.queue, mask)
	append_u32(mut this.queue, cookie)
	append_u32(mut this.queue, u32(name_len))
	for i := 0; i < name_len; i++ {
		this.queue << if i < name.len { name[i] } else { u8(0) }
	}
	this.status |= file.pollin
	event.trigger(mut &this.event, false)
}

// Called only after a VFS operation has committed.
pub fn inotify_emit(node &VFSNode, name string, mask u32, cookie u32) {
	if unsafe { node == nil } {
		return
	}
	inotify_lock.acquire()
	defer { inotify_lock.release() }
	for mut instance in inotify_instances {
		instance.l.acquire()
		mut remove := []int{}
		for i, watch in instance.watches {
			if voidptr(watch.node) != voidptr(node) || watch.mask & mask == 0 {
				continue
			}
			instance.enqueue_locked(watch.wd, mask, cookie, name)
			if watch.mask & in_oneshot != 0 { remove << i }
		}
		for i := remove.len - 1; i >= 0; i-- {
			index := remove[i]
			instance.enqueue_locked(instance.watches[index].wd, in_ignored, 0, '')
			instance.watches.delete(index)
		}
		unsafe { remove.free() }
		instance.l.release()
	}
}

pub fn inotify_forget(node &VFSNode) {
	if unsafe { node == nil } {
		return
	}
	inotify_lock.acquire()
	defer { inotify_lock.release() }
	for mut instance in inotify_instances {
		instance.l.acquire()
		for i := instance.watches.len - 1; i >= 0; i-- {
			watch := instance.watches[i]
			if voidptr(watch.node) != voidptr(node) {
				continue
			}
			instance.enqueue_locked(watch.wd, in_ignored, 0, '')
			instance.watches.delete(i)
		}
		instance.l.release()
	}
}

fn (mut this INotify) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn inotify_wait(mut this INotify, handle_ptr voidptr) bool {
	mut handle := unsafe { &file.Handle(handle_ptr) }
	this.l.release()
	if handle != unsafe { nil } { handle.l.release() }
	mut events := [&this.event]
	event.await(mut events, true) or {
		unsafe { events.free() }
		if handle != unsafe { nil } { handle.l.acquire() }
		this.l.acquire()
		return false
	}
	unsafe { events.free() }
	if handle != unsafe { nil } { handle.l.acquire() }
	this.l.acquire()
	return true
}

fn (mut this INotify) read(handle_ptr voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if buf == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}
	handle := unsafe { &file.Handle(handle_ptr) }
	this.l.acquire()
	defer { this.l.release() }
	for this.queue.len == 0 {
		if handle != unsafe { nil } && handle.flags & resource.o_nonblock != 0 {
			errno.set(errno.eagain)
			return none
		}
		if !inotify_wait(mut this, handle_ptr) {
			errno.set(errno.eintr)
			return none
		}
	}
	first := queued_record_size(this.queue)
	if first == 0 {
		errno.set(errno.eio)
		return none
	}
	if count < first {
		errno.set(errno.einval)
		return none
	}
	mut amount := u64(0)
	for amount < u64(this.queue.len) {
		record := queued_record_size(this.queue[int(amount)..])
		if record == 0 || amount + record > count {
			break
		}
		amount += record
	}
	if !usercopy.copy_to_user(u64(buf), voidptr(&this.queue[0]), amount) {
		errno.set(errno.efault)
		return none
	}
	this.queue.delete_many(0, int(amount))
	if this.queue.len == 0 {
		this.status &= ~file.pollin
		this.overflowed = false
	}
	return i64(amount)
}

fn (mut this INotify) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.ebadf)
	return none
}

fn (mut this INotify) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this INotify) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) {
		return
	}
	inotify_lock.acquire()
	for i, instance in inotify_instances {
		if voidptr(instance) == voidptr(this) {
			inotify_instances.delete(i)
			break
		}
	}
	inotify_lock.release()
	unsafe {
		this.watches.free()
		this.queue.free()
		free(voidptr(this))
	}
}

fn (mut this INotify) link(_handle voidptr) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this INotify) unlink(_handle voidptr) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this INotify) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.einval)
	return none
}

pub fn syscall_inotify_init(_ voidptr, flags int) (u64, u64) {
	if flags & ~(in_cloexec | in_nonblock) != 0 {
		return errno.err, errno.einval
	}
	// The descriptor's Handle owns the resource reference.  The registry is
	// only an index protected by inotify_lock, so it must not keep a closed
	// instance alive indefinitely.
	mut inotify := &INotify{}
	inotify.stat.mode = stat.ifchr | 0o600
	inotify.stat.blksize = 1
	inotify_lock.acquire()
	inotify_instances << inotify
	inotify_lock.release()
	mut res := &resource.Resource(unsafe { inotify })
	fdnum := file.fdnum_create_from_resource(unsafe { nil }, mut res, flags, 0, false) or {
		return errno.err, errno.get()
	}
	return u64(fdnum), 0
}

pub fn syscall_inotify_add_watch(_ voidptr, fdnum int, _path charptr, mask u32) (u64, u64) {
	if mask & (in_event_mask | in_control_mask) == 0
		|| mask & ~(in_event_mask | in_control_mask) != 0 {
		return errno.err, errno.einval
	}
	path := user_path(_path) or { return errno.err, errno.get() }
	if path.len == 0 {
		return errno.err, errno.enoent
	}
	follow := mask & in_dont_follow == 0
	node := get_node(proc.current_thread().process.current_directory, path, follow) or {
		return errno.err, errno.get()
	}
	if mask & in_onlydir != 0 && !stat.isdir(node.resource.stat.mode) {
		return errno.err, errno.enotdir
	}
	if !check_access(node, access_read, true) {
		return errno.err, errno.eacces
	}
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer { fd.unref() }
	mut res := fd.handle.resource
	if mut res is INotify {
		res.l.acquire()
		defer { res.l.release() }
		for mut watch in res.watches {
			if voidptr(watch.node) != voidptr(node) {
				continue
			}
			if mask & in_mask_create != 0 {
				return errno.err, errno.eexist
			}
			watch.mask = if mask & in_mask_add != 0 { watch.mask | mask } else { mask }
			return u64(watch.wd), 0
		}
		if res.watches.len >= max_inotify_watches {
			return errno.err, errno.enospc
		}
		wd := res.next_wd
		res.next_wd++
		if res.next_wd <= 0 {
			res.next_wd = 1
		}
		res.watches << InotifyWatch{ wd: wd, node: unsafe { node }, mask: mask }
		return u64(wd), 0
	}
	return errno.err, errno.einval
}

pub fn syscall_inotify_rm_watch(_ voidptr, fdnum int, wd int) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer { fd.unref() }
	mut res := fd.handle.resource
	if mut res is INotify {
		res.l.acquire()
		defer { res.l.release() }
		for i, watch in res.watches {
			if watch.wd != wd {
				continue
			}
			res.enqueue_locked(wd, in_ignored, 0, '')
			res.watches.delete(i)
			return 0, 0
		}
		return errno.err, errno.einval
	}
	return errno.err, errno.einval
}
