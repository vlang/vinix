// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module file

// Linux eventfd(2): a pollable 64-bit counter used by runtimes and event
// loops for cheap cross-thread notifications.

import errno
import event
import event.eventstruct
import katomic
import klock
import resource
import stat

const efd_semaphore = 1

const efd_nonblock = 0o4000

const efd_cloexec = 0o2000000

// Userspace writes stop one short of the kernel-only overflow value.
const eventfd_counter_max = ~u64(0) - 1

pub struct EventFD {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int = pollout
	can_mmap bool

	counter   u64
	semaphore bool
	// The interface box its descriptors share, freed with the counter.
	box &resource.Resource = unsafe { nil }
}

pub fn retain_eventfd(number int) ?&EventFD {
	mut fd := fd_from_fdnum(unsafe { nil }, number) or {
		errno.set(errno.ebadf)
		return none
	}
	mut res := fd.handle.resource
	if mut res is EventFD {
		katomic.inc(mut &res.refcount)
		fd.unref()
		return unsafe { res }
	}
	fd.unref()
	errno.set(errno.einval)
	return none
}

fn (mut this EventFD) counter_changed_locked() {
	mut status := if this.counter != 0 { pollin } else { 0 }
	if this.counter < eventfd_counter_max { status |= pollout }
	if this.counter > eventfd_counter_max { status |= pollerr }
	katomic.store(mut &this.status, status)
	event.trigger(mut this.event, false)
}

pub fn (mut this EventFD) poll_status(_ int) int {
	return katomic.load(&this.status)
}

// A retained counter can be signaled even after its last descriptor closes.
// Kernel notification saturates and never waits for a userspace reader.
pub fn (mut this EventFD) notify() {
	this.l.acquire()
	if this.counter != ~u64(0) { this.counter++ }
	this.counter_changed_locked()
	this.l.release()
}

fn (mut this EventFD) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

// Character-device I/O bypasses the open-description lock. Snapshot the
// counter event before unlocking to catch notifications before enrollment.
fn eventfd_wait(mut this EventFD) bool {
	generation := event.generation(mut this.event)
	this.l.release()
	event.await_one_from_generation(mut this.event, true, generation) or {
		this.l.acquire()
		return false
	}
	this.l.acquire()
	return true
}

fn (mut this EventFD) read(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count < sizeof(u64) {
		errno.set(errno.einval)
		return none
	}
	if buf == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}

	handle := unsafe { &Handle(_handle) }
	this.l.acquire()
	defer {
		this.l.release()
	}

	for this.counter == 0 {
		if handle != unsafe { nil } && handle.flags & resource.o_nonblock != 0 {
			errno.set(errno.eagain)
			return none
		}
		if !eventfd_wait(mut this) {
			errno.set(errno.eintr)
			return none
		}
	}

	value := if this.semaphore { u64(1) } else { this.counter }
	unsafe { C.memcpy(buf, voidptr(&value), sizeof(u64)) }

	this.counter -= value
	this.counter_changed_locked()

	return i64(sizeof(u64))
}

fn (mut this EventFD) write(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count < sizeof(u64) {
		errno.set(errno.einval)
		return none
	}
	if buf == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}

	mut value := u64(0)
	unsafe { C.memcpy(voidptr(&value), buf, sizeof(u64)) }
	if value == ~u64(0) {
		errno.set(errno.einval)
		return none
	}

	handle := unsafe { &Handle(_handle) }
	this.l.acquire()
	defer {
		this.l.release()
	}

	for this.counter > eventfd_counter_max || value > eventfd_counter_max - this.counter {
		if handle != unsafe { nil } && handle.flags & resource.o_nonblock != 0 {
			errno.set(errno.eagain)
			return none
		}
		if !eventfd_wait(mut this) {
			errno.set(errno.eintr)
			return none
		}
	}

	this.counter += value
	this.counter_changed_locked()

	return i64(sizeof(u64))
}

fn (mut this EventFD) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this EventFD) unref(_handle voidptr) ? {
	this.release()
}

pub fn (mut this EventFD) release() {
	if katomic.dec(mut &this.refcount) {
		return
	}
	unsafe {
		free(voidptr(this.box))
		free(voidptr(this))
	}
}

fn (mut this EventFD) link(_handle voidptr) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this EventFD) unlink(_handle voidptr) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this EventFD) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.einval)
	return none
}

pub fn syscall_eventfd2(_ voidptr, initial u32, flags int) (u64, u64) {
	if flags & ~(efd_semaphore | efd_nonblock | efd_cloexec) != 0 {
		return errno.err, errno.einval
	}

	mut counter := &EventFD{
		counter:   u64(initial)
		semaphore: flags & efd_semaphore != 0
	}
	counter.stat.mode = stat.ifchr | 0o600
	counter.stat.blksize = 8
	if initial != 0 {
		counter.status |= pollin
	}

	// The eventfd flags are not open flags: EFD_SEMAPHORE shares its bit with
	// O_WRONLY, so passing them straight through made a semaphore eventfd
	// unreadable and an ordinary one unwritable. Translate them, and say that
	// the descriptor is open both ways, which is what an eventfd is for.
	mut open_flags := resource.o_rdwr
	if flags & efd_nonblock != 0 {
		open_flags |= resource.o_nonblock
	}
	if flags & efd_cloexec != 0 {
		open_flags |= resource.o_cloexec
	}

	counter.box = &resource.Resource(unsafe { counter }) @[freed]
	mut res := counter.box
	fdnum := fdnum_create_from_resource(unsafe { nil }, mut res, open_flags, 0, false) or {
		return errno.err, errno.get()
	}

	return u64(fdnum), 0
}
