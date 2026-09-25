// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module userland

// signalfd(2): signals a program blocks, read from a descriptor instead of
// taken by a handler, so an event loop waits for them with everything else.
// systemd's sd-event takes every signal it handles this way.

import errno
import event
import event.eventstruct
import file
import katomic
import klock
import posixtimer
import proc
import resource
import stat
import usercopy

// The signalfd4 flags are the open(2) bits of the same names.
const sfd_nonblock = resource.o_nonblock

const sfd_cloexec = resource.o_cloexec

// One struct signalfd_siginfo per signal read.
const signalfd_siginfo_size = u64(128)

struct SignalFD {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	mask u64
	// The process whose signals make it readable: the one that made it, or
	// last set its mask.
	owner int
	// Raised each time a signal makes it readable, so that a look at what is
	// pending that raced with one does not clear what it set.
	notifications u64
}

__global (
	signalfds       []&SignalFD
	signalfds_lock  klock.Lock
	signalfds_count = u64(0)
)

fn (mut this SignalFD) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

// Take one signal in `wanted` for the calling thread: its own first, then one
// another thread of its process holds and blocks. A signal sent to a process
// waits on one of its threads here, not on the process, and the thread that
// reads the descriptor is seldom that one. Fills in `info` as a
// signalfd_siginfo; 0 when there is none.
fn take_for_signalfd(current &proc.Thread, wanted u64, mut info [16]u64) int {
	mut own := unsafe { current }
	if signum := take_pending(mut own, wanted) {
		fill_signalfd_info(mut info, current, signum)
		posixtimer.acknowledge_signal(mut own, signum)
		return signum
	}
	mut process := current.process
	mut holder := &proc.Thread(unsafe { nil })
	mut taken := 0
	process.threads_lock.acquire()
	for t in process.threads {
		if t.tid == current.tid || katomic.load(&t.is_dead) {
			continue
		}
		mut other := unsafe { t }
		// Only what that thread blocks: one it does not is on its way to its
		// handler.
		if signum := take_pending(mut other, wanted & katomic.load(&t.masked_signals)) {
			holder = t
			taken = signum
			proc.pin_thread(holder)
			break
		}
	}
	process.threads_lock.release()
	if taken == 0 {
		return 0
	}
	mut other := unsafe { holder }
	fill_signalfd_info(mut info, other, taken)
	posixtimer.acknowledge_signal(mut other, taken)
	proc.unpin_thread(holder)
	return taken
}

// struct signalfd_siginfo: ssi_signo, ssi_errno, ssi_code, then for a POSIX
// timer its overrun at 32 and value in ssi_int and ssi_ptr, at 44 and 48.
fn fill_signalfd_info(mut info [16]u64, holder &proc.Thread, signum int) {
	timer_info := posixtimer.signal_info(holder, signum)
	unsafe {
		mut words := &u32(&info[0])
		words[0] = u32(signum)
		words[2] = u32(timer_info.code)
		if timer_info.found {
			words[8] = u32(timer_info.overrun)
			words[11] = u32(timer_info.value)
			info[6] = timer_info.value
		}
	}
}

// The signals in `mask` some thread of process `pid` has pending.
fn process_pending(pid int, mask u64) u64 {
	if pid <= 0 || pid >= proc.max_pid {
		return 0
	}
	mut process := processes[pid]
	if process == unsafe { nil } {
		return 0
	}
	mut pending := u64(0)
	process.threads_lock.acquire()
	for t in process.threads {
		pending |= katomic.load(&t.pending_signals) & mask
	}
	process.threads_lock.release()
	return pending & mask
}

// Readable when its owner has one of its signals pending. The look at what is
// pending is made with no lock of this descriptor held; a signal that came
// meanwhile raised `notifications`, and keeps it readable.
fn (mut this SignalFD) refresh() {
	this.l.acquire()
	seen := this.notifications
	mask := this.mask
	owner := this.owner
	this.l.release()

	pending := process_pending(owner, mask)

	this.l.acquire()
	if pending != 0 || this.notifications != seen {
		this.status |= file.pollin
	} else {
		this.status &= ~file.pollin
	}
	this.l.release()
}

// sendsig() made `signal` pending on a thread of process `pid`: the
// descriptors of that process that read it are readable now.
fn notify_signalfds(pid int, signal int) {
	if katomic.load(&signalfds_count) == 0 {
		return
	}
	bit := signal_bit(signal)
	signalfds_lock.acquire()
	for mut sfd in signalfds {
		sfd.l.acquire()
		if sfd.owner != pid || sfd.mask & bit == 0 {
			sfd.l.release()
			continue
		}
		sfd.notifications++
		sfd.status |= file.pollin
		sfd.l.release()
		event.trigger(mut sfd.event, false)
	}
	signalfds_lock.release()
}

// Sleep until a signal makes the descriptor readable. The open description's
// lock, which read() is called with, is let go meanwhile: another thread
// reading or polling a dup of it must not wait behind this one.
fn (mut this SignalFD) wait(_handle voidptr) bool {
	mut handle := unsafe { &file.Handle(_handle) }
	if handle != unsafe { nil } {
		handle.l.release()
	}
	mut events := [&this.event]
	mut woken := true
	event.await(mut events, true) or { woken = false }
	unsafe { events.free() }
	if handle != unsafe { nil } {
		handle.l.acquire()
	}
	return woken
}

fn (mut this SignalFD) read(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count < signalfd_siginfo_size {
		errno.set(errno.einval)
		return none
	}
	handle := unsafe { &file.Handle(_handle) }
	nonblocking := handle != unsafe { nil } && handle.flags & resource.o_nonblock != 0
	mut current := proc.current_thread()
	mut done := u64(0)
	defer {
		this.refresh()
	}
	for done + signalfd_siginfo_size <= count {
		this.l.acquire()
		wanted := this.mask
		this.l.release()

		mut info := [16]u64{}
		signum := take_for_signalfd(current, wanted, mut info)
		if signum != 0 {
			if !usercopy.copy_to_user(u64(buf) + done, voidptr(&info[0]), signalfd_siginfo_size) {
				// Hand the signal back rather than losing it.
				katomic.bts(mut &current.pending_signals, u8(signum - 1))
				if done != 0 {
					break
				}
				errno.set(errno.efault)
				return none
			}
			done += signalfd_siginfo_size
			continue
		}
		if done != 0 {
			break
		}
		if nonblocking {
			errno.set(errno.eagain)
			return none
		}
		// A signal the thread does not block, or its process going away, ends
		// the wait, as either ends any other.
		if !this.wait(_handle) {
			errno.set(errno.eintr)
			return none
		}
	}
	return i64(done)
}

fn (mut this SignalFD) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this SignalFD) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this SignalFD) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) {
		return
	}
	// Found by address. `==` on the two references compared the structs
	// field by field, a copy of each on the stack; with that, the image
	// tests froze or crashed the kernel right after postgres, the first
	// program here to read its signals this way, had exited.
	signalfds_lock.acquire()
	for i := 0; i < signalfds.len; i++ {
		if voidptr(signalfds[i]) == voidptr(this) {
			signalfds.delete(i)
			katomic.dec(mut &signalfds_count)
			break
		}
	}
	signalfds_lock.release()
	unsafe { free(voidptr(this)) }
}

fn (mut this SignalFD) link(_handle voidptr) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this SignalFD) unlink(_handle voidptr) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this SignalFD) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.einval)
	return none
}

// signalfd4(fd, mask, sizemask, flags): a new descriptor for the signals in
// `mask` when `fd` is -1, or a new mask for the signalfd `fd` is.
pub fn syscall_signalfd4(_ voidptr, fdnum int, mask_ptr u64, sizemask u64, flags int) (u64, u64) {
	if flags & ~(sfd_nonblock | sfd_cloexec) != 0 || sizemask != sigset_size {
		return errno.err, errno.einval
	}
	mut mask := u64(0)
	if !usercopy.copy_from_user(voidptr(&mask), mask_ptr, sigset_size) {
		return errno.err, errno.efault
	}
	mask &= ~unblockable_mask()
	pid := proc.current_thread().process.pid

	if fdnum != -1 {
		mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or {
			return errno.err, errno.get()
		}
		mut existing := &SignalFD(unsafe { nil })
		mut res := fd.handle.resource
		if mut res is SignalFD {
			existing = res
		}
		fd.unref()
		if existing == unsafe { nil } {
			return errno.err, errno.einval
		}
		existing.l.acquire()
		existing.mask = mask
		existing.owner = pid
		existing.l.release()
		existing.refresh()
		return u64(fdnum), 0
	}

	mut sfd := &SignalFD{
		mask:  mask
		owner: pid
	}
	sfd.stat.mode = stat.ifchr | 0o600
	// Listed before it has a descriptor, which, should making one fail, is
	// closed, and takes it off the list.
	signalfds_lock.acquire()
	signalfds << sfd
	katomic.inc(mut &signalfds_count)
	signalfds_lock.release()
	mut res := &resource.Resource(unsafe { sfd })
	newfd := file.fdnum_create_from_resource(unsafe { nil }, mut res, flags | resource.o_rdwr,
		0, false) or { return errno.err, errno.get() }
	// Signals it reads may be pending already.
	sfd.refresh()
	return u64(newfd), 0
}
