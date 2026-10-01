module file

import resource
import proc
import klock
import katomic
import errno
import stat
import event
import event.eventstruct
import memory
import memory.mmap
import time
import usercopy

pub const f_dupfd = 0
pub const f_dupfd_cloexec = 1030
pub const f_setpipe_sz = 1031
pub const f_getpipe_sz = 1032
pub const f_getfd = 1
pub const f_setfd = 2
pub const f_getfl = 3
pub const f_setfl = 4

// close_range(2) flags.
pub const close_range_cloexec = u32(1) << 2
pub const f_add_seals = 1033
pub const f_get_seals = 1034
pub const f_ofd_getlk = 36
pub const f_ofd_setlk = 37
pub const f_ofd_setlkw = 38
pub const f_getlk = 5
pub const f_setlk = 6
pub const f_setlkw = 7
pub const f_getown = 8
pub const f_setown = 9
pub const f_setsig = 10
pub const f_getsig = 11
pub const f_setown_ex = 15
pub const f_getown_ex = 16

const f_owner_tid = 0
const f_owner_pid = 1
const f_owner_pgrp = 2

const f_rdlck = i16(0)
const f_wrlck = i16(1)
const f_unlck = i16(2)

struct Flock {
mut:
	l_type   i16
	l_whence i16
	l_start  i64
	l_len    i64
	l_pid    i32
}

pub const fd_cloexec = 1

pub struct Handle {
pub mut:
	l             klock.Lock
	resource      &resource.Resource = unsafe { nil }
	node          voidptr
	refcount      int
	loc           i64
	flags         int
	dirlist_valid bool
	dirlist       []stat.Dirent
	dirlist_index u64
	// Who F_SETOWN made the file's owner, a F_OWNER_* kind and an id, and the
	// signal F_SETSIG chose. They are recorded, so that a program reads back
	// what it set; I/O readiness raises no SIGIO here.
	owner_type int
	owner_id   int
	signal     int
	// How many of `refcount` are epoll sets' registrations of it.
	epoll_refs int
}

__global (
	handle_released fn (voidptr)
)

// on_handle_released has `f` called with a handle's node as the handle is
// freed: the VFS counts the handles that lead to each node.
pub fn on_handle_released(f fn (voidptr)) {
	handle_released = f
}

// A Handle is the open-file description shared by dup() and fork(). Its
// resource reference must therefore be released exactly once, after both the
// final descriptor and every in-flight lookup have dropped their references.
fn (mut this Handle) unref() {
	if katomic.dec(mut &this.refcount) {
		// Only epoll sets hold it now: its last descriptor is closed, and, as
		// on Linux, it leaves every set that watches it.
		watches := katomic.load(&this.epoll_refs)
		if watches != 0 && katomic.load(&this.refcount) == watches {
			epoll_forget(this)
		}
		return
	}

	release_flock(this)
	mut res := this.resource
	res.unref(voidptr(this)) or {}
	if this.node != unsafe { nil } && voidptr(handle_released) != unsafe { nil } {
		handle_released(this.node)
	}
	unsafe {
		this.dirlist.free()
		free(voidptr(this))
	}
}

fn retain_mmap_handle(handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	mut open_handle := unsafe { &Handle(handle) }
	katomic.inc(mut &open_handle.refcount)
}

fn release_mmap_handle(handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	mut open_handle := unsafe { &Handle(handle) }
	open_handle.unref()
}

struct PollFD {
mut:
	// Linux and mlibc expose pollfd.fd as a signed 32-bit C int. V3's plain
	// `int` is pointer-width, so spelling this field explicitly keeps the
	// userspace ABI at its required eight-byte layout on 64-bit kernels.
	fd      i32
	events  i16
	revents i16
}

pub const pollin = 0x01
pub const pollout = 0x04
pub const pollpri = 0x02
pub const pollhup = 0x10
pub const pollerr = 0x08
pub const pollrdhup = 0x2000
pub const pollnval = 0x20
pub const pollwrnorm = 0x100

// POLLERR and POLLHUP are reported even when userspace did not ask for them.
// In particular, readers use POLLHUP to notice that the final writer of a
// pipe has gone away and drain it to EOF.
fn poll_revents(status int, requested i16) i16 {
	return (i16(status) & requested) | (i16(status) & i16(pollerr | pollhup))
}

fn ppoll(fds &PollFD, nfds u64, tmo_p &time.TimeSpec, sigmask &u64) (u64, u64) {
	if voidptr(sigmask) != unsafe { nil } {
		mut t := proc.current_thread()
		proc.begin_wait_mask(mut t, *sigmask)
	}
	if voidptr(tmo_p) != unsafe { nil }
		&& (tmo_p.tv_sec < 0 || tmo_p.tv_nsec < 0 || tmo_p.tv_nsec >= 1000000000) {
		return errno.err, errno.einval
	}

	// poll(NULL, 0, timeout) is a sleep used by glibc and UI event loops.
	// Keep a signal-interruptible event even without a timeout; returning
	// immediately here makes a supposedly sleeping loop spin at full speed.
	if nfds == 0 {
		if voidptr(tmo_p) != unsafe { nil } && tmo_p.tv_sec == 0 && tmo_p.tv_nsec == 0 {
			return 0, 0
		}
		mut sleeper := eventstruct.Event{}
		mut sleep_storage := [unsafe { &sleeper }]!
		mut timer := &time.Timer(unsafe { nil })
		if voidptr(tmo_p) != unsafe { nil } {
			timer = time.new_timer(*tmo_p)
			sleep_storage[0] = &timer.event
		}
		mut sleep_events := unsafe { event.stack_list(&sleep_storage[0], sleep_storage.len) }
		defer {
			if voidptr(timer) != unsafe { nil } {
				timer.disarm()
				unsafe { free(timer) }
			}
		}
		event.await(mut sleep_events, true) or { return errno.err, errno.eintr }
		return 0, 0
	}

	// Sized up front: growing them would leave each outgrown block behind.
	mut fdlist := []&FD{cap: int(nfds)} @[freed]
	mut fdnums := []u64{cap: int(nfds)} @[freed]
	mut events := []&eventstruct.Event{cap: int(nfds) + 1} @[freed]

	defer {
		for mut f in fdlist {
			f.unref()
		}
		unsafe {
			events.free()
			fdnums.free()
			fdlist.free()
		}
	}

	mut ret := u64(0)

	for i := u64(0); i < nfds; i++ {
		mut fdd := unsafe { &fds[i] }

		fdd.revents = 0

		if fdd.fd < 0 {
			continue
		}

		mut fd := fd_from_fdnum(unsafe { nil }, int(fdd.fd)) or {
			fdd.revents = pollnval
			ret++
			continue
		}

		mut resource_ := fd.handle.resource

		status := resource_.status

		revents := poll_revents(status, fdd.events)
		if revents != 0 {
			fdd.revents = revents
			ret++
			fd.unref()
			continue
		}

		fdlist << fd
		fdnums << i
		events << &resource_.event
	}

	if ret != 0 {
		return ret, 0
	}

	mut timer := &time.Timer(unsafe { nil })

	if voidptr(tmo_p) != unsafe { nil } {
		mut target_time := *tmo_p

		timer = time.new_timer(target_time)

		events << &timer.event
	}

	defer {
		if voidptr(timer) != unsafe { nil } {
			timer.disarm()
			unsafe { free(timer) }
		}
	}

	for {
		which := event.await(mut events, true) or { return errno.err, errno.eintr }

		if voidptr(timer) != unsafe { nil } {
			if which == u64(events.len) - 1 {
				return 0, 0
			}
		}

		status := fdlist[which].handle.resource.status

		mut fdd := unsafe { &fds[fdnums[which]] }

		revents := poll_revents(status, fdd.events)
		if revents != 0 {
			fdd.revents = revents
			ret++
			break
		}
	}

	return ret, 0
}

// ppoll may sleep while a socket or pipe becomes ready. Keep the poll array,
// timeout and signal mask in kernel memory across that wait: dereferencing the
// caller's virtual addresses after the scheduler has run can fault in EL1, and
// malformed userspace pointers must return EFAULT rather than crash the kernel.
pub fn syscall_ppoll(_ voidptr, user_fds u64, nfds u64, user_timeout u64, user_sigmask u64) (u64, u64) {
	if nfds > 4096 {
		return errno.err, errno.einval
	}
	pagemap := proc.current_thread().process.pagemap

	mut pollfds := []PollFD{len: int(nfds)} @[freed]
	defer {
		unsafe { pollfds.free() }
	}
	if nfds != 0
		&& !usercopy.copy_from_user(unsafe { voidptr(&pollfds[0]) }, user_fds, nfds * sizeof(PollFD)) {
		return errno.err, errno.efault
	}

	mut timeout_storage := [time.TimeSpec{}]!
	mut timeout_ptr := &time.TimeSpec(unsafe { nil })
	if user_timeout != 0 {
		if !usercopy.copy_from_user(unsafe { voidptr(&timeout_storage[0]) }, user_timeout, sizeof(time.TimeSpec)) {
			return errno.err, errno.efault
		}
		// In unsafe, so that timeout stays on the stack: see getdents64.
		timeout_ptr = unsafe { &timeout_storage[0] }
	}

	mut sigmask_storage := [u64(0)]!
	mut sigmask_ptr := &u64(unsafe { nil })
	if user_sigmask != 0 {
		if !usercopy.copy_from_user(unsafe { voidptr(&sigmask_storage[0]) }, user_sigmask, sizeof(u64)) {
			return errno.err, errno.efault
		}
		// In unsafe, so that sigmask stays on the stack: see getdents64.
		sigmask_ptr = unsafe { &sigmask_storage[0] }
	}
	ret, err := poll_user_fds(pagemap, user_fds, mut pollfds, nfds, timeout_ptr, sigmask_ptr)
	return ret, err
}

// poll(2), which x86-64 Linux programs call rather than ppoll: musl's DNS
// resolver among them. The timeout is in milliseconds, and negative for none.
pub fn syscall_poll(_ voidptr, user_fds u64, nfds u64, timeout_ms u64) (u64, u64) {
	if nfds > 4096 {
		return errno.err, errno.einval
	}
	pagemap := proc.current_thread().process.pagemap

	mut pollfds := []PollFD{len: int(nfds)} @[freed]
	defer {
		unsafe { pollfds.free() }
	}
	if nfds != 0
		&& !usercopy.copy_from_user(unsafe { voidptr(&pollfds[0]) }, user_fds, nfds * sizeof(PollFD)) {
		return errno.err, errno.efault
	}

	// The C int arrives in a 64-bit register; only its low half is defined.
	milliseconds := i64(i32(u32(timeout_ms)))
	timeout_storage := [time.TimeSpec{
		tv_sec: milliseconds / 1000
		tv_nsec: (milliseconds % 1000) * 1000000
	}]!
	mut timeout_ptr := &time.TimeSpec(unsafe { nil })
	if milliseconds >= 0 {
		// In unsafe, so that timeout stays on the stack: see getdents64.
		timeout_ptr = unsafe { &timeout_storage[0] }
	}
	ret, err := poll_user_fds(pagemap, user_fds, mut pollfds, nfds, timeout_ptr, unsafe { nil })
	return ret, err
}

// Wait on a poll array already copied in from `pagemap`, then copy the
// results back out.
fn poll_user_fds(pagemap &memory.Pagemap, user_fds u64, mut pollfds []PollFD, nfds u64, timeout_ptr &time.TimeSpec, sigmask_ptr &u64) (u64, u64) {
	mut fds_ptr := &PollFD(unsafe { nil })
	if nfds != 0 {
		fds_ptr = unsafe { &pollfds[0] }
	}
	ret, err := ppoll(fds_ptr, nfds, timeout_ptr, sigmask_ptr)
	if err != 0 {
		return ret, err
	}
	if nfds != 0
		&& !usercopy.copy_to_pagemap(pagemap, user_fds, unsafe { voidptr(&pollfds[0]) }, nfds * sizeof(PollFD)) {
		return errno.err, errno.efault
	}
	return ret, 0
}

pub fn (mut this Handle) read(buf voidptr, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}
	ret := this.resource.read(voidptr(this), buf, u64(this.loc), count) or { return none }
	this.loc += ret
	return ret
}

// The largest piece of a read or write that goes through one kernel buffer.
const user_io_chunk = u64(64 * 1024)

// The most taken at once from what hands over a message: a socket or a pipe.
// No socket family takes a message longer than this (socket.unix.sock_buf).
const user_io_message_max = u64(1024 * 1024)

// A transfer this small uses a buffer on the stack.
const user_io_small = u64(512)

// A resource's read() and write() are given kernel memory, always. What a
// process reads or writes goes through a kernel buffer here, and to or from
// the process through usercopy, which is what tells a pointer that leads
// nowhere, or into the kernel, from one that is the process's own. A resource
// also must not touch a user page while it holds filesystem or device locks: a
// missing page faults in the middle of that critical section, and the fault
// handler may need the same resource to page it in.
pub fn (mut this Handle) read_to_user(address u64, count u64) ?i64 {
	if count == 0 {
		return this.read(unsafe { nil }, 0)
	}
	if !usercopy.user_range(address, count) {
		errno.set(errno.efault)
		return none
	}
	mode := this.resource.stat.mode
	// What a pipe, a socket or a device gives up is gone from it: find out
	// that there is nowhere to put it before taking it.
	if !stat.isreg(mode) && !usercopy.writable(address) {
		errno.set(errno.efault)
		return none
	}
	// A socket or a pipe gives what it has, once: asking again would wait for
	// more, and would run two messages together.
	once := stat.issock(mode) || stat.isifo(mode)
	limit := if once { user_io_message_max } else { user_io_chunk }
	size := if count < limit { count } else { limit }
	mut small := [512]u8{}
	buffer := if size <= user_io_small { unsafe { voidptr(&small[0]) } } else { unsafe { malloc(size) } }
	if buffer == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	defer {
		if size > user_io_small {
			unsafe { free(buffer) }
		}
	}
	// A file or a disk is read to the end of what was asked for. A device
	// gives its first piece as the caller's flags say, and more only if it has
	// more without waiting: /dev/zero always has, a terminal seldom.
	waits := stat.isreg(mode) || stat.isblk(mode)
	mut done := u64(0)
	for done < count {
		chunk := if count - done < size { count - done } else { size }
		read := if done == 0 || waits {
			this.read(buffer, chunk) or {
				if done != 0 { return i64(done) }
				return none
			}
		} else {
			this.read_without_waiting(buffer, chunk) or { return i64(done) }
		}
		if read <= 0 {
			return i64(done)
		}
		if !usercopy.copy_to_user(address + done, buffer, u64(read)) {
			errno.set(errno.efault)
			if done != 0 { return i64(done) }
			return none
		}
		done += u64(read)
		if once || u64(read) < chunk { break }
	}
	return i64(done)
}

// read(), as if the descriptor were O_NONBLOCK for this one call. The flag is
// set and cleared under the lock every read of this open file takes.
fn (mut this Handle) read_without_waiting(buf voidptr, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}
	waited := this.flags & resource.o_nonblock == 0
	this.flags |= resource.o_nonblock
	ret := this.resource.read(voidptr(this), buf, u64(this.loc), count) or {
		if waited {
			this.flags &= ~resource.o_nonblock
		}
		return none
	}
	if waited {
		this.flags &= ~resource.o_nonblock
	}
	this.loc += ret
	return ret
}

fn limited_write_count(res &resource.Resource, location u64, count u64) ?u64 {
	if !stat.isreg(res.stat.mode) || count == 0 {
		return count
	}
	limit := proc.soft_limit(proc.current_thread().process, proc.rlimit_fsize)
	if limit == proc.rlim_infinity {
		return count
	}
	if location >= limit {
		errno.set(errno.efbig)
		return none
	}
	return if count > limit - location { limit - location } else { count }
}

pub fn (mut this Handle) write(buf voidptr, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}
	// O_APPEND chooses the end of the file for every write, rather than only
	// setting the descriptor's initial offset. Go's builder relies on this when
	// it adds native objects to the archive produced by the compiler.
	if this.flags & resource.o_append != 0 {
		this.loc = this.resource.stat.size
	}
	allowed := limited_write_count(this.resource, u64(this.loc), count)?
	ret := this.resource.write(voidptr(this), buf, u64(this.loc), allowed) or { return none }
	this.loc += ret
	if this.flags & resource.o_dsync != 0 {
		mut res := this.resource
		resource.sync_resource(mut res, voidptr(this)) or { return none }
	}
	return ret
}

// write(2)'s side of read_to_user(). A long write goes in pieces, which is all
// a stream promises. A socket's pieces are one byte longer than the longest
// message any family takes: a stream takes them as it takes any, and a
// datagram too long to send is refused by its family, with EMSGSIZE, rather
// than cut in two here.
pub fn (mut this Handle) write_from_user(address u64, count u64) ?i64 {
	if count == 0 {
		return this.write(unsafe { nil }, 0)
	}
	if !usercopy.user_range(address, count) {
		errno.set(errno.efault)
		return none
	}
	limit := if stat.issock(this.resource.stat.mode) {
		user_io_message_max + 1
	} else {
		user_io_chunk
	}
	size := if count < limit { count } else { limit }
	mut small := [512]u8{}
	buffer := if size <= user_io_small { unsafe { voidptr(&small[0]) } } else { unsafe { malloc(size) } }
	if buffer == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	defer {
		if size > user_io_small {
			unsafe { free(buffer) }
		}
	}
	mut done := u64(0)
	for done < count {
		chunk := if count - done < size { count - done } else { size }
		if !usercopy.copy_from_user(buffer, address + done, chunk) {
			errno.set(errno.efault)
			if done != 0 { return i64(done) }
			return none
		}
		written := this.write(buffer, chunk) or {
			if done != 0 { return i64(done) }
			return none
		}
		if written <= 0 { return i64(done) }
		done += u64(written)
		if u64(written) < chunk { break }
	}
	return i64(done)
}

pub fn (mut this Handle) ioctl(request u64, argp voidptr) ?int {
	return this.resource.ioctl(voidptr(this), request, argp)
}

pub struct FD {
pub mut:
	handle &Handle = unsafe { nil }
	flags  int
	// The descriptor table's reference, plus one for every syscall that has
	// the descriptor from fd_from_fdnum(). close() drops the table's, so a
	// syscall still running on a descriptor another thread closed keeps what
	// it is using until it lets go.
	refcount int = 1
}

// Give back the reference fd_from_fdnum() took, on the descriptor and on the
// open file behind it. The descriptor goes once nothing holds it.
pub fn (mut this FD) unref() {
	mut handle := this.handle
	handle.unref()
	this.release_descriptor()
}

// Drop only the reference on the descriptor object, for a caller that keeps
// the open-file reference fd_from_fdnum() took -- a descriptor being passed
// over a socket.
pub fn (mut this FD) release_descriptor() {
	if !katomic.dec(mut &this.refcount) {
		unsafe { free(voidptr(this)) }
	}
}

pub fn fdnum_close(_process &proc.Process, fdnum int, do_lock bool) ? {
	mut process := &proc.Process(unsafe { nil })
	if voidptr(_process) == unsafe { nil } {
		process = proc.current_thread().process
	} else {
		process = unsafe { _process }
	}

	if fdnum < 0 || fdnum >= proc.max_fds {
		errno.set(errno.ebadf)
		return none
	}

	if do_lock {
		process.fds_lock.acquire()
	}
	mut fd := if fdnum < process.fds.len { unsafe { &FD(process.fds[fdnum]) } } else { unsafe { nil } }
	if fd == unsafe { nil } {
		if do_lock {
			process.fds_lock.release()
		}
		errno.set(errno.ebadf)
		return none
	}
	process.fds[fdnum] = unsafe { nil }
	// Out of the table, the descriptor is this call's alone, and what closing
	// it sets going -- a pipe or a socket torn down, a file's pages freed -- is
	// done without the table held. Exec and exit close descriptor after
	// descriptor, and /proc/<pid>/fd, which a runtime reads of every process it
	// starts, gives up on a table that stays held.
	if do_lock {
		process.fds_lock.release()
	}
	mut handle := fd.handle
	// POSIX record locks are process-owned and closing any descriptor for the
	// inode releases that process' locks, even when another dup remains open.
	release_posix_locks(handle.resource, process.pid)
	handle.unref()
	fd.release_descriptor()
}

pub fn fdnum_create_from_fd(_process &proc.Process, fd &FD, oldfd int, specific bool) ?int {
	mut process := &proc.Process(unsafe { nil })
	if voidptr(_process) == unsafe { nil } {
		process = proc.current_thread().process
	} else {
		process = unsafe { _process }
	}

	process.fds_lock.acquire()
	defer {
		process.fds_lock.release()
	}

	limit := if process.rlimits[proc.rlimit_nofile].cur < u64(proc.max_fds) {
		int(process.rlimits[proc.rlimit_nofile].cur)
	} else {
		proc.max_fds
	}
	if oldfd < 0 {
		errno.set(errno.einval)
		return none
	}
	if specific == false {
		// The lowest free number from oldfd up: in the table, or the first
		// one past its end, which the table grows to hold.
		mut i := oldfd
		for ; i < limit && i < process.fds.len; i++ {
			if process.fds[i] == unsafe { nil } {
				process.fds[i] = voidptr(fd)
				return i
			}
		}
		if i >= limit || !grow_fd_table(mut process, i) {
			errno.set(errno.emfile)
			return none
		}
		process.fds[i] = voidptr(fd)
		return i
	} else {
		if oldfd >= limit {
			errno.set(errno.ebadf)
			return none
		}
		if oldfd >= process.fds.len && !grow_fd_table(mut process, oldfd) {
			errno.set(errno.emfile)
			return none
		}
		fdnum_close(process, oldfd, false) or {}
		process.fds[oldfd] = voidptr(fd)
		return oldfd
	}
}

// Make room in a descriptor table for `fdnum`, doubling it until there is. The
// caller holds fds_lock, which everything that reads the table while another
// thread may make descriptors holds too.
fn grow_fd_table(mut process proc.Process, fdnum int) bool {
	if fdnum >= proc.max_fds {
		return false
	}
	mut length := if process.fds.len > 0 { process.fds.len } else { proc.initial_fds }
	for length <= fdnum {
		length *= 2
	}
	if length > proc.max_fds {
		length = proc.max_fds
	}
	mut bigger := unsafe { []voidptr{len: length} } @[freed]
	if bigger.len != length {
		return false
	}
	for i in 0 .. process.fds.len {
		bigger[i] = process.fds[i]
	}
	mut old := unsafe { process.fds }
	process.fds = bigger
	unsafe { old.free() }
	return true
}

// The descriptors a process has open, and their flags, read in one go under
// the table's lock: what fork copies into the child.
pub fn open_fdnums(process &proc.Process) []int {
	mut target := unsafe { process }
	target.fds_lock.acquire()
	defer {
		target.fds_lock.release()
	}
	mut count := 0
	for slot in target.fds {
		if slot != unsafe { nil } {
			count++
		}
	}
	// The caller frees it.
	mut open := []int{cap: count} @[freed]
	for i, slot in target.fds {
		if slot != unsafe { nil } {
			open << i
		}
	}
	return open
}

pub fn fd_create_from_resource(mut res resource.Resource, flags int) ?&FD {
	katomic.inc(mut &res.refcount)

	mut new_handle := &Handle{}
	new_handle.resource = unsafe { res }
	new_handle.refcount = 1
	new_handle.flags = flags & resource.file_status_flags_mask

	mut new_fd := &FD{}
	new_fd.handle = new_handle
	new_fd.flags = flags & resource.file_descriptor_flags_mask

	return new_fd
}

pub fn fdnum_create_from_resource(_process &proc.Process, mut res resource.Resource, flags int, oldfd int, specific bool) ?int {
	new_fd := fd_create_from_resource(mut res, flags) or { return none }
	return fdnum_create_from_fd(_process, new_fd, oldfd, specific) or {
		mut handle := new_fd.handle
		unsafe { free(voidptr(new_fd)) }
		handle.unref()
		return none
	}
}

pub fn fd_from_fdnum(_process &proc.Process, fdnum int) ?&FD {
	mut process := &proc.Process(unsafe { nil })
	if voidptr(_process) == unsafe { nil } {
		process = proc.current_thread().process
	} else {
		process = unsafe { _process }
	}

	if fdnum >= proc.max_fds || fdnum < 0 {
		errno.set(errno.ebadf)
		return none
	}

	process.fds_lock.acquire()
	defer {
		process.fds_lock.release()
	}

	if fdnum >= process.fds.len {
		errno.set(errno.ebadf)
		return none
	}
	mut ret := unsafe { &FD(process.fds[fdnum]) }
	if voidptr(ret) == unsafe { nil } {
		errno.set(errno.ebadf)
		return none
	}

	katomic.inc(mut &ret.handle.refcount)
	katomic.inc(mut &ret.refcount)

	return ret
}

pub fn fdnum_dup(_old_process &proc.Process, oldfdnum int, _new_process &proc.Process, newfdnum int, flags int, specific bool, cloexec bool) ?int {
	mut old_process := &proc.Process(unsafe { nil })
	if voidptr(_old_process) == unsafe { nil } {
		old_process = proc.current_thread().process
	} else {
		old_process = unsafe { _old_process }
	}

	mut new_process := &proc.Process(unsafe { nil })
	if voidptr(_new_process) == unsafe { nil } {
		new_process = proc.current_thread().process
	} else {
		new_process = unsafe { _new_process }
	}

	if specific && oldfdnum == newfdnum && voidptr(old_process) == voidptr(new_process) {
		errno.set(errno.einval)
		return none
	}

	mut oldfd := fd_from_fdnum(old_process, oldfdnum) or { return none }
	defer {
		oldfd.unref()
	}

	mut new_fd := unsafe { &FD(malloc(sizeof(FD))) }
	unsafe { C.memcpy(new_fd, oldfd, sizeof(FD)) }
	new_fd.refcount = 1
	katomic.inc(mut &oldfd.handle.refcount)

	new_fdnum := fdnum_create_from_fd(new_process, new_fd, newfdnum, specific) or {
		mut handle := new_fd.handle
		unsafe { free(voidptr(new_fd)) }
		handle.unref()
		return none
	}

	new_fd.flags = flags & resource.file_descriptor_flags_mask
	if cloexec {
		new_fd.flags |= resource.o_cloexec
	}

	return new_fdnum
}

pub fn syscall_dup3(_ voidptr, oldfdnum int, newfdnum int, flags int) (u64, u64) {
	mut t := proc.current_thread()
	mut process := t.process

	C.printf(c'\n\e[32m%s\e[m: dup3(%d, %d, %d)\n', process.name.str, oldfdnum, newfdnum, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	// dup2 quietly returns oldfd here; dup3 is required to refuse.
	if oldfdnum == newfdnum {
		return errno.err, errno.einval
	}

	new_fdnum := fdnum_dup(unsafe { nil }, oldfdnum, unsafe { nil }, newfdnum, flags, true, false) or { return errno.err, errno.get() }

	return u64(new_fdnum), 0
}

// close_range(first, last, flags): close every descriptor in the range, or mark
// it close-on-exec when CLOSE_RANGE_CLOEXEC is given. Used by libcs and daemons
// to shed inherited descriptors without walking /proc.
pub fn syscall_close_range(_ voidptr, first u32, last u32, flags u32) (u64, u64) {
	if first > last || flags & ~u32(close_range_cloexec) != 0 {
		return errno.err, errno.einval
	}

	mut process := proc.current_thread().process

	// No further than the table reaches; it only grows, and a descriptor
	// made past its end while this runs is not one it was asked to close.
	if process.fds.len == 0 {
		return 0, 0
	}
	mut top := u64(last)
	if top >= u64(process.fds.len) {
		top = u64(process.fds.len) - 1
	}

	for i := u64(first); i <= top; i++ {
		if flags & close_range_cloexec != 0 {
			mut fd := fd_from_fdnum(process, int(i)) or { continue }
			fd.flags |= resource.o_cloexec
			fd.unref()
			continue
		}
		fdnum_close(process, int(i), true) or { continue }
	}

	return 0, 0
}

// fsync/fdatasync flush dirty pages through the resource's optional sync hook.
// In-memory resources need no callback; streams cannot be synchronized.
pub fn syscall_fsync(_ voidptr, fdnum int) (u64, u64) {
	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }
	defer { fd.unref() }
	mut handle := fd.handle
	handle.l.acquire()
	defer { handle.l.release() }
	if handle.flags & resource.o_path != 0 {
		return errno.err, errno.ebadf
	}
	mut res := handle.resource
	mode := res.stat.mode
	if !stat.isreg(mode) && !stat.isdir(mode) && !stat.isblk(mode) {
		return errno.err, errno.einval
	}
	resource.sync_resource(mut res, voidptr(handle)) or { return errno.err, errno.get() }
	return 0, 0
}

// ftruncate(fd, length): set the file's size, zero-filling when it grows.
pub fn syscall_ftruncate(_ voidptr, fdnum int, length i64) (u64, u64) {
	if length < 0 {
		return errno.err, errno.einval
	}

	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }
	defer {
		fd.unref()
	}

	mut handle := fd.handle
	mut res := handle.resource

	if stat.isdir(res.stat.mode) {
		return errno.err, errno.eisdir
	}
	if handle.flags & resource.o_accmode == resource.o_rdonly {
		return errno.err, errno.einval
	}
	// An immutable or append-only file cannot be truncated.
	if resource.is_protected(mut res) {
		return errno.err, errno.eperm
	}

	res.grow(voidptr(handle), u64(length)) or { return errno.err, errno.get() }

	return 0, 0
}

// pread64/pwrite64 operate at an explicit offset without changing the open
// file description's position.  Keeping the operation under Handle.l makes
// this atomic with ordinary read/write/lseek on a shared descriptor.
pub fn syscall_pread(_ voidptr, fdnum int, buf voidptr, count u64, offset i64) (u64, u64) {
	return pread(fdnum, buf, count, offset, true)
}

// pread(2) into the kernel's own buffer, for sendfile(2).
pub fn pread_to_kernel(fdnum int, buf voidptr, count u64, offset i64) (u64, u64) {
	return pread(fdnum, buf, count, offset, false)
}

fn pread(fdnum int, buf voidptr, count u64, offset i64, to_user bool) (u64, u64) {
	if offset < 0 || count > u64(0x7fffffffffffffff) - u64(offset) {
		return errno.err, errno.einval
	}
	if to_user && !usercopy.user_range(u64(buf), count) {
		return errno.err, errno.efault
	}

	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut handle := fd.handle

	mode := handle.resource.stat.mode
	if stat.ischr(mode) || stat.isifo(mode) || stat.issock(mode) || mode & stat.ifmt == stat.ifpipe {
		return errno.err, errno.espipe
	}
	if stat.isdir(mode) {
		return errno.err, errno.eisdir
	}
	access := handle.flags & resource.o_accmode
	if access != resource.o_rdonly && access != resource.o_rdwr {
		return errno.err, errno.ebadf
	}

	if count == 0 {
		return 0, 0
	}
	if !to_user {
		handle.l.acquire()
		read := handle.resource.read(voidptr(handle), buf, u64(offset), count) or {
			handle.l.release()
			return errno.err, errno.get()
		}
		handle.l.release()
		return u64(read), 0
	}
	buffer := unsafe { malloc(if count < user_io_chunk { count } else { user_io_chunk }) }
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer { unsafe { free(buffer) } }
	mut done := u64(0)
	for done < count {
		chunk := if count - done < user_io_chunk { count - done } else { user_io_chunk }
		handle.l.acquire()
		read := handle.resource.read(voidptr(handle), buffer, u64(offset) + done, chunk) or {
			handle.l.release()
			if done != 0 { return done, 0 }
			return errno.err, errno.get()
		}
		handle.l.release()
		if read <= 0 { break }
		if !usercopy.copy_to_user(u64(buf) + done, buffer, u64(read)) {
			if done != 0 { return done, 0 }
			return errno.err, errno.efault
		}
		done += u64(read)
		if u64(read) < chunk { break }
	}
	return done, 0
}

pub fn syscall_pwrite(_ voidptr, fdnum int, buf voidptr, count u64, offset i64) (u64, u64) {
	if offset < 0 || count > u64(0x7fffffffffffffff) - u64(offset) {
		return errno.err, errno.einval
	}
	if !usercopy.user_range(u64(buf), count) {
		return errno.err, errno.efault
	}

	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut handle := fd.handle

	mut res := handle.resource
	mode := res.stat.mode
	if stat.ischr(mode) || stat.isifo(mode) || stat.issock(mode) || mode & stat.ifmt == stat.ifpipe {
		return errno.err, errno.espipe
	}
	if stat.isdir(mode) {
		return errno.err, errno.eisdir
	}
	access := handle.flags & resource.o_accmode
	if access != resource.o_wronly && access != resource.o_rdwr {
		return errno.err, errno.ebadf
	}
	// pwrite names an offset, which an append-only file does not take, nor an
	// immutable one any write at all. An O_APPEND file would otherwise be
	// overwritten in place through this, past Handle.write's append.
	if resource.is_protected(mut res) {
		return errno.err, errno.eperm
	}

	allowed := limited_write_count(res, u64(offset), count) or {
		return errno.err, errno.get()
	}
	if allowed == 0 { return 0, 0 }
	buffer := unsafe { malloc(if allowed < user_io_chunk { allowed } else { user_io_chunk }) }
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer { unsafe { free(buffer) } }
	mut done := u64(0)
	for done < allowed {
		chunk := if allowed - done < user_io_chunk { allowed - done } else { user_io_chunk }
		if !usercopy.copy_from_user(buffer, u64(buf) + done, chunk) {
			if done != 0 { return done, 0 }
			return errno.err, errno.efault
		}
		handle.l.acquire()
		written := res.write(voidptr(handle), buffer, u64(offset) + done, chunk) or {
			handle.l.release()
			if done != 0 { return done, 0 }
			return errno.err, errno.get()
		}
		handle.l.release()
		if written <= 0 { break }
		done += u64(written)
		if u64(written) < chunk { break }
	}
	if handle.flags & resource.o_dsync != 0 {
		resource.sync_resource(mut res, voidptr(handle)) or { return errno.err, errno.get() }
	}
	return done, 0
}

// fallocate(mode=0) guarantees that the requested range exists.  Vinix has no
// delayed allocation or hole-punching yet, so extending the resource provides
// that guarantee; unsupported Linux mode bits are rejected explicitly.
pub fn syscall_fallocate(_ voidptr, fdnum int, mode int, offset i64, length i64) (u64, u64) {
	if mode != 0 {
		return errno.err, errno.eopnotsupp
	}
	if offset < 0 || length <= 0 || u64(length) > u64(0x7fffffffffffffff) - u64(offset) {
		return errno.err, errno.einval
	}

	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut handle := fd.handle
	access := handle.flags & resource.o_accmode
	if access != resource.o_wronly && access != resource.o_rdwr {
		return errno.err, errno.ebadf
	}
	mut res := handle.resource
	if !stat.isreg(res.stat.mode) {
		if stat.isdir(res.stat.mode) {
			return errno.err, errno.eisdir
		}
		if stat.isifo(res.stat.mode) || res.stat.mode & stat.ifmt == stat.ifpipe {
			return errno.err, errno.espipe
		}
		return errno.err, errno.enodev
	}
	// An immutable or append-only file is not grown this way either; Linux's
	// vfs_fallocate refuses both.
	if resource.is_protected(mut res) {
		return errno.err, errno.eperm
	}

	end := u64(offset) + u64(length)
	if end > u64(res.stat.size) {
		res.grow(voidptr(handle), end) or { return errno.err, errno.get() }
	}
	return 0, 0
}

// Dispatch cache advice when supported; other resources may ignore hints.
pub fn syscall_fadvise64(_ voidptr, fdnum int, offset i64, length i64, advice int) (u64, u64) {
	if offset < 0 || length < 0 || advice < 0 || advice > 5 {
		return errno.err, errno.einval
	}

	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut handle := fd.handle
	if handle.flags & resource.o_path != 0 {
		return errno.err, errno.ebadf
	}
	mut res := handle.resource
	mode := res.stat.mode
	if stat.isifo(mode) || stat.issock(mode) || mode & stat.ifmt == stat.ifpipe {
		return errno.err, errno.espipe
	}
	resource.advise_resource(mut res, voidptr(handle), u64(offset), u64(length), advice) or {
		return errno.err, errno.get()
	}
	return 0, 0
}

pub fn syscall_sync_file_range(_ voidptr, fdnum int, offset i64, count i64, flags u32) (u64, u64) {
	if offset < 0 || count < 0 || flags & ~u32(0x7) != 0
		|| u64(count) > u64(0x7fffffffffffffff) - u64(offset) {
		return errno.err, errno.einval
	}

	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	access := fd.handle.flags & resource.o_accmode
	if access != resource.o_wronly && access != resource.o_rdwr {
		return errno.err, errno.ebadf
	}
	if !stat.isreg(fd.handle.resource.stat.mode) {
		return errno.err, errno.espipe
	}
	// A synchronous whole-resource flush is a conservative implementation of
	// range writeback until resources expose independent writeback ranges.
	if flags != 0 {
		mut res := fd.handle.resource
		resource.sync_resource(mut res, voidptr(fd.handle)) or { return errno.err, errno.get() }
	}
	return 0, 0
}

pub fn syscall_fcntl(_ voidptr, fdnum int, cmd int, arg u64) (u64, u64) {
	mut t := proc.current_thread()
	mut process := t.process

	C.printf(c'\n\e[32m%s\e[m: fcntl(%d, %d, %lld)\n', process.name.str, fdnum, cmd, arg)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }

	mut handle := fd.handle

	mut ret := u64(0)

	match cmd {
		f_dupfd {
			ret = u64(fdnum_dup(unsafe { nil }, fdnum, unsafe { nil }, int(arg), 0, false, false) or {
				fd.unref()
				return errno.err, errno.get()
			})
			// fd_from_fdnum() retained the source open-file description for
			// this syscall. The duplicate has its own descriptor reference;
			// release the temporary lookup just as the other fcntl paths do.
			fd.unref()
		}
		f_dupfd_cloexec {
			ret = u64(fdnum_dup(unsafe { nil }, fdnum, unsafe { nil }, int(arg), 0, false, true) or {
				fd.unref()
				return errno.err, errno.get()
			})
			fd.unref()
		}
		f_getpipe_sz {
			if !stat.isifo(handle.resource.stat.mode) {
				fd.unref()
				return errno.err, errno.einval
			}
			mut res := handle.resource
			ret = resource.pipe_capacity(mut res) or {
				fd.unref()
				return errno.err, errno.einval
			}
			fd.unref()
		}
		f_setpipe_sz {
			if !stat.isifo(handle.resource.stat.mode) {
				fd.unref()
				return errno.err, errno.einval
			}
			mut res := handle.resource
			ret = resource.set_pipe_capacity(mut res, arg) or {
				saved_errno := errno.get()
				fd.unref()
				return errno.err, saved_errno
			}
			fd.unref()
		}
		f_getfd {
			ret = if fd.flags & resource.o_cloexec != 0 { u64(fd_cloexec) } else { 0 }
			fd.unref()
		}
		f_setfd {
			fd.flags = if arg & fd_cloexec != 0 { resource.o_cloexec } else { 0 }
			fd.unref()
		}
		f_getfl {
			ret = u64(handle.flags)
			fd.unref()
		}
		f_setfl {
			// Only the status flags are settable. Taking the argument whole
			// would drop the access mode the file was opened with, leaving a
			// writable handle looking read-only.
			handle.flags = (handle.flags & ~resource.file_settable_flags_mask) | (int(arg) & resource.file_settable_flags_mask)
			fd.unref()
		}
		f_add_seals {
			mut res := handle.resource
			resource.add_seals(mut res, u32(arg)) or {
				saved := errno.get()
				fd.unref()
				return errno.err, if saved == 0 { errno.einval } else { saved }
			}
			fd.unref()
		}
		f_get_seals {
			mut res := handle.resource
			ret = u64(resource.get_seals(mut res) or {
				fd.unref()
				return errno.err, errno.einval
			})
			fd.unref()
		}
		f_ofd_getlk, f_ofd_setlk, f_ofd_setlkw {
			// Open-file-description locks are served by the per-process record
			// locks: every lock a process holds is on one of its descriptions,
			// and Vinix threads never contend for one against each other.
			posix_cmd := match cmd {
				f_ofd_getlk { f_getlk }
				f_ofd_setlk { f_setlk }
				else { f_setlkw }
			}
			lock_ret, lock_errno := fcntl_lock(mut handle, posix_cmd, arg)
			fd.unref()
			if lock_errno != 0 {
				return lock_ret, lock_errno
			}
			ret = lock_ret
		}
		// nginx gives its master's channel to each worker this way.
		f_setown {
			// A negative id names a process group.
			id := int(i32(u32(arg)))
			handle.owner_type = if id < 0 { f_owner_pgrp } else { f_owner_pid }
			handle.owner_id = if id < 0 { -id } else { id }
			fd.unref()
		}
		f_getown {
			ret = if handle.owner_type == f_owner_pgrp {
				u64(-i64(handle.owner_id))
			} else {
				u64(handle.owner_id)
			}
			fd.unref()
		}
		f_setown_ex, f_getown_ex {
			// struct f_owner_ex: an int kind, then a pid_t.
			mut owner := [2]i32{}
			if cmd == f_setown_ex {
				if !usercopy.copy_from_user(voidptr(&owner[0]), arg, 8) {
					fd.unref()
					return errno.err, errno.efault
				}
				if owner[0] < f_owner_tid || owner[0] > f_owner_pgrp {
					fd.unref()
					return errno.err, errno.einval
				}
				handle.owner_type = int(owner[0])
				handle.owner_id = int(owner[1])
			} else {
				owner[0] = i32(handle.owner_type)
				owner[1] = i32(handle.owner_id)
				if !usercopy.copy_to_user(arg, voidptr(&owner[0]), 8) {
					fd.unref()
					return errno.err, errno.efault
				}
			}
			fd.unref()
		}
		f_setsig {
			if arg > 64 {
				fd.unref()
				return errno.err, errno.einval
			}
			handle.signal = int(arg)
			fd.unref()
		}
		f_getsig {
			ret = u64(handle.signal)
			fd.unref()
		}
		f_getlk, f_setlk, f_setlkw {
			lock_ret, lock_errno := fcntl_lock(mut handle, cmd, arg)
			fd.unref()
			if lock_errno != 0 {
				return lock_ret, lock_errno
			}
			ret = lock_ret
		}
		else {
			C.kprintf(c'\nfcntl: Unhandled command: %lld\n', i64(cmd))
			fd.unref()
			return errno.err, errno.einval
		}
	}

	return ret, 0
}

pub fn syscall_mmap(_ voidptr, addr voidptr, length u64, prot_and_flags u64, fdnum int, offset i64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: mmap(0x%llx, 0x%llx, 0x%llx, %d, %lld)\n', process.name.str, addr, length, prot_and_flags, fdnum, offset)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut resource_ := &resource.Resource(unsafe { nil })
	mut fd := &FD(unsafe { nil })

	if fdnum != -1 {
		fd = fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
		resource_ = fd.handle.resource
	}

	defer {
		if fdnum != -1 {
			fd.unref()
		}
	}

	prot := int((prot_and_flags >> 32) & 0xffffffff)
	flags := int(prot_and_flags & 0xffffffff)
	sharing := flags & (mmap.map_shared | mmap.map_private)
	if sharing != mmap.map_shared && sharing != mmap.map_private {
		return errno.err, errno.einval
	}

	if flags & mmap.map_anonymous == 0 && voidptr(resource_) == unsafe { nil } {
		return errno.err, errno.ebadf
	}
	mut map_flags := flags & ~mmap.map_no_write
	if flags & mmap.map_anonymous == 0 {
		// O_PATH opens a file without any permission to it, and so lent its
		// contents to anyone mapping it, as Linux does not.
		if fd.handle.flags & resource.o_path != 0 {
			return errno.err, errno.ebadf
		}
		access := fd.handle.flags & resource.o_accmode
		if access == resource.o_wronly {
			return errno.err, errno.eacces
		}
		if flags & mmap.map_shared != 0 && access != resource.o_rdwr {
			if prot & mmap.prot_write != 0 {
				return errno.err, errno.eacces
			}
			// Nor may mprotect() make it writable later.
			map_flags |= mmap.map_no_write
		}
	}

	mut mapping_handle := voidptr(0)
	if fdnum != -1 {
		mapping_handle = voidptr(fd.handle)
	}
	ret := mmap.mmap(process.pagemap, addr, length, prot, map_flags, resource_, offset, mapping_handle, retain_mmap_handle, release_mmap_handle) or {
		return errno.err, errno.get()
	}

	return u64(ret), 0
}

// Apply descriptor and status flags to an already-open fd. accept4(2) and
// pipe2(2) take them alongside the operation itself rather than needing a
// separate fcntl.
pub fn set_fd_flags(fdnum int, flags int) {
	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return }
	defer {
		fd.unref()
	}

	if flags & resource.o_cloexec != 0 {
		fd.flags |= resource.o_cloexec
	}
	if flags & resource.o_nonblock != 0 {
		mut handle := fd.handle
		handle.flags |= resource.o_nonblock
	}
}
