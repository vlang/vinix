// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module userland

// signalfd(2): signals a program blocks, read from a descriptor instead of
// taken by a handler, so an event loop waits for them with everything else.
// systemd's sd-event takes every signal it handles this way.
//
// Shared by both architectures; signal n is represented by bit n-1.


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

struct SignalFDReadInfo {
mut:
	words [16]u64
}

struct SignalFD {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	mask u64
	// The interface box its descriptor holds, freed with it.
	box &resource.Resource = unsafe { nil }
}

__global (
	signalfds       []&SignalFD
	signalfds_lock  klock.Lock
	signalfds_count = u64(0)
)

fn (mut this SignalFD) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

// Read only the caller's thread-directed signals and its process pool. A
// sibling's private pending signal must stay available to that sibling.
fn take_for_signalfd(current &proc.Thread, wanted u64, mut info [16]u64) int {
	mut own := unsafe { current }
	signum, shared := take_wait_signal(mut own, wanted)
	if signum == -1 { return 0 }
	fill_signalfd_info(mut info, current, signum, shared)
	if !shared { posixtimer.acknowledge_signal(mut own, signum) }
	return signum
}

// struct signalfd_siginfo: ssi_signo, ssi_errno, ssi_code, then for a POSIX
// timer its overrun at 32 and value in ssi_int and ssi_ptr, at 44 and 48.
fn fill_signalfd_info(mut info [16]u64, holder &proc.Thread, signum int, shared bool) {
	timer_info := if shared { posixtimer.SignalInfo{} } else { posixtimer.signal_info(holder, signum) }
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

// Readiness for the current reader follows the same private/shared ownership
// as read(), rather than advertising a sibling's private signal.
fn process_pending(mask u64) u64 {
	current := proc.current_thread()
	if current == unsafe { nil } { return 0 }
	return proc.pending_signals(current) & mask
}

fn (mut this SignalFD) poll_status() int {
	this.l.acquire()
	mask := this.mask
	this.l.release()
	return if process_pending(mask) != 0 { file.pollin } else { 0 }
}

// Matching descriptors receive a wake even after fork or descriptor passing.
// Their per-reader callback determines readiness from the current pool.
fn notify_signalfds(_pid int, signal int) {
	if katomic.load(&signalfds_count) == 0 {
		return
	}
	bit := signal_bit(signal)
	signalfds_lock.acquire()
	for mut sfd in signalfds {
		sfd.l.acquire()
		// A forked or passed descriptor observes the current reader's signals.
		// Broadcast a matching wake; per-reader readiness filters other pools.
		if sfd.mask & bit == 0 {
			sfd.l.release()
			continue
		}
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
	mut woken := true
	event.await_one(mut this.event, true) or { woken = false }
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
	// Passing a local fixed array by mutable reference makes V promote it to
	// the heap. This buffer is borrowed synchronously and stays in this frame.
	mut info := unsafe { &SignalFDReadInfo(C.__builtin_alloca(sizeof(SignalFDReadInfo))) }
	for done + signalfd_siginfo_size <= count {
		this.l.acquire()
		wanted := this.mask
		this.l.release()

		unsafe { *info = SignalFDReadInfo{} }
		signum := take_for_signalfd(current, wanted, mut info.words)
		if signum != 0 {
			unsafe {
				C.memcpy(voidptr(u64(buf) + done), voidptr(&info.words[0]), signalfd_siginfo_size)
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
		// Matching broadcasts from another process can keep the event pending.
		// Check cancellation before consuming another such spurious wake.
		if katomic.load(&current.must_exit)
			|| proc.pending_signals(current) & ~katomic.load(&current.masked_signals) != 0 {
			errno.set(errno.eintr)
			return none
		}
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
	unsafe {
		free(voidptr(this.box))
		free(voidptr(this))
	}
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
	return signalfd_set(fdnum, proc.sigset_from_user(mask) & ~unblockable_mask(), flags)
}

// Make a signalfd for `mask`, given in this kernel's layout, or give the one
// `fdnum` is that mask.
fn signalfd_set(fdnum int, mask u64, flags int) (u64, u64) {
	if fdnum != -1 {
		mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or {
			return errno.err, errno.get()
		}
		defer { fd.unref() }
		mut existing := &SignalFD(unsafe { nil })
		mut res := fd.handle.resource
		if mut res is SignalFD {
			existing = res
		}
		if existing == unsafe { nil } {
			return errno.err, errno.einval
		}
		existing.l.acquire()
		existing.mask = mask
		existing.l.release()
		event.trigger(mut &existing.event, false)
		return u64(fdnum), 0
	}

	mut sfd := &SignalFD{
		mask:  mask
	}
	sfd.stat.mode = stat.ifchr | 0o600
	// Listed before it has a descriptor, which, should making one fail, is
	// closed, and takes it off the list.
	signalfds_lock.acquire()
	signalfds << sfd
	katomic.inc(mut &signalfds_count)
	signalfds_lock.release()
	sfd.box = &resource.Resource(unsafe { sfd }) @[freed]
	mut res := sfd.box
	newfd := file.fdnum_create_from_resource(unsafe { nil }, mut res, flags | resource.o_rdwr,
		0, false) or { return errno.err, errno.get() }
	// poll_status also observes signals queued before descriptor creation.
	return u64(newfd), 0
}
