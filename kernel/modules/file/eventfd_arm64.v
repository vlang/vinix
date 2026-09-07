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
import usercopy

const efd_semaphore = 1

const efd_nonblock = 0o4000

const efd_cloexec = 0o2000000

// UINT64_MAX is reserved as an invalid value by Linux.  The largest counter
// value an eventfd may contain is therefore UINT64_MAX - 1.
const eventfd_counter_max = ~u64(0) - 1

struct EventFD {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int = pollout
	can_mmap bool

	counter   u64
	semaphore bool
}

fn (mut this EventFD) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

// Handle.read()/write() hold the open-description lock while calling into a
// resource.  A blocking counter must temporarily drop it as well as its own
// lock, otherwise a writer using a dup of this descriptor could never wake a
// reader (both descriptors share the same Handle).
fn eventfd_wait(mut this EventFD, handle_ptr voidptr) bool {
	mut handle := unsafe { &Handle(handle_ptr) }
	this.l.release()
	if handle != unsafe { nil } {
		handle.l.release()
	}

	mut events := [&this.event]
	event.await(mut events, true) or {
		unsafe { events.free() }
		if handle != unsafe { nil } {
			handle.l.acquire()
		}
		this.l.acquire()
		return false
	}
	unsafe { events.free() }

	if handle != unsafe { nil } {
		handle.l.acquire()
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
		if !eventfd_wait(mut this, _handle) {
			errno.set(errno.eintr)
			return none
		}
	}

	value := if this.semaphore { u64(1) } else { this.counter }
	if !usercopy.copy_to_user(u64(buf), voidptr(&value), sizeof(u64)) {
		errno.set(errno.efault)
		return none
	}

	this.counter -= value
	if this.counter == 0 {
		this.status &= ~pollin
	}
	this.status |= pollout
	event.trigger(mut this.event, false)

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
	if !usercopy.copy_from_user(voidptr(&value), u64(buf), sizeof(u64)) {
		errno.set(errno.efault)
		return none
	}
	if value == ~u64(0) {
		errno.set(errno.einval)
		return none
	}

	handle := unsafe { &Handle(_handle) }
	this.l.acquire()
	defer {
		this.l.release()
	}

	for value > eventfd_counter_max - this.counter {
		if handle != unsafe { nil } && handle.flags & resource.o_nonblock != 0 {
			errno.set(errno.eagain)
			return none
		}
		if !eventfd_wait(mut this, _handle) {
			errno.set(errno.eintr)
			return none
		}
	}

	this.counter += value
	if this.counter != 0 {
		this.status |= pollin
	}
	if this.counter == eventfd_counter_max {
		this.status &= ~pollout
	}
	event.trigger(mut this.event, false)

	return i64(sizeof(u64))
}

fn (mut this EventFD) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this EventFD) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) {
		return
	}
	unsafe { free(voidptr(this)) }
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

	mut res := &resource.Resource(unsafe { counter })
	fdnum := fdnum_create_from_resource(unsafe { nil }, mut res, flags, 0, false) or {
		return errno.err, errno.get()
	}

	return u64(fdnum), 0
}
