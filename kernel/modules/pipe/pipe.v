// pipe.v: pipe implementation.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module pipe

import resource
import stat
import klock
import event
import event.eventstruct
import errno
import file
import katomic
import proc

// A pipe is a circular buffer
pub const pipe_buf = 4096

pub struct Pipe {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	status   int
	can_mmap bool

	data      &u8
	read_ptr  u64
	write_ptr u64
	capacity  u64
	used      u64
	event     eventstruct.Event
}

pub fn initialise() {}

pub fn create() ?&Pipe {
	mut p := &Pipe{
		data:     unsafe { C.malloc(pipe.pipe_buf) }
		capacity: pipe.pipe_buf
	}
	p.stat.mode = stat.ifpipe

	return p
}

pub fn syscall_pipe(_ voidptr, pipefds &int, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: pipe(0x%llx, 0x%x)\n', process.name.str, voidptr(pipefds),
		flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut new_pipe := create() or { return errno.err, errno.get() }

	rd_fd := file.fdnum_create_from_resource(unsafe { nil }, mut new_pipe, flags, 0, false) or {
		return errno.err, errno.get()
	}

	wr_fd := file.fdnum_create_from_resource(unsafe { nil }, mut new_pipe, flags, 0, false) or {
		return errno.err, errno.get()
	}

	unsafe {
		pipefds[0] = rd_fd
		pipefds[1] = wr_fd
	}
	return 0, 0
}

fn (mut this Pipe) mmap(page u64, flags int) voidptr {
	return 0
}

fn (mut this Pipe) read(_handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	mut count := _count

	this.l.acquire()
	defer {
		this.l.release()
	}

	handle := unsafe { &file.Handle(_handle) }

	// If pipe is empty, block or return if nonblock
	for katomic.load(&this.used) == 0 {
		// Return EOF if the pipe was closed
		if this.refcount <= 1 {
			return 0
		}
		if handle.flags & resource.o_nonblock != 0 {
			return 0
		}
		this.l.release()
		mut events := [&this.event]
		event.await(mut events, true) or {
			unsafe { events.free() }
			errno.set(errno.eintr)
			return none
		}
		unsafe { events.free() }
		this.l.acquire()
	}

	if this.used < count {
		count = this.used
	}

	// Calculate sizes before and after wrap-around and new ptr location
	mut before_wrap := u64(0)
	mut after_wrap := u64(0)
	mut new_ptr_loc := u64(0)
	if this.read_ptr + count > this.capacity {
		before_wrap = this.capacity - this.read_ptr
		after_wrap = count - before_wrap
		new_ptr_loc = after_wrap
	} else {
		before_wrap = count
		after_wrap = 0
		new_ptr_loc = this.read_ptr + count
		if new_ptr_loc == this.capacity {
			new_ptr_loc = 0
		}
	}

	unsafe { C.memcpy(buf, &this.data[this.read_ptr], before_wrap) }
	if after_wrap != 0 {
		unsafe { C.memcpy(voidptr(u64(buf) + before_wrap), this.data, after_wrap) }
	}

	this.read_ptr = new_ptr_loc
	this.used -= count

	if this.used == 0 {
		this.status &= ~file.pollin
	}
	if this.used < this.capacity {
		this.status |= file.pollout
	}
	event.trigger(mut this.event, false)

	return i64(count)
}

fn (mut this Pipe) write(handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	mut count := _count

	this.l.acquire()
	defer {
		this.l.release()
	}

	// If pipe is full, block or return if nonblock
	for katomic.load(&this.used) == this.capacity {
		// We don't do nonblock yet
		this.l.release()
		mut events := [&this.event]
		event.await(mut events, true) or {
			unsafe { events.free() }
			errno.set(errno.eintr)
			return none
		}
		unsafe { events.free() }
		this.l.acquire()
	}

	if this.used + count > this.capacity {
		count = this.capacity - this.used
	}

	// Calculate sizes before and after wrap-around and new ptr location
	mut before_wrap := u64(0)
	mut after_wrap := u64(0)
	mut new_ptr_loc := u64(0)
	if this.write_ptr + count > this.capacity {
		before_wrap = this.capacity - this.write_ptr
		after_wrap = count - before_wrap
		new_ptr_loc = after_wrap
	} else {
		before_wrap = count
		after_wrap = 0
		new_ptr_loc = this.write_ptr + count
		if new_ptr_loc == this.capacity {
			new_ptr_loc = 0
		}
	}

	unsafe { C.memcpy(&this.data[this.write_ptr], buf, before_wrap) }
	if after_wrap != 0 {
		unsafe { C.memcpy(this.data, voidptr(u64(buf) + before_wrap), after_wrap) }
	}

	this.write_ptr = new_ptr_loc
	this.used += count

	if this.used == this.capacity {
		this.status &= ~file.pollout
	}
	this.status |= file.pollin
	event.trigger(mut this.event, false)

	return i64(count)
}

fn (mut this Pipe) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this Pipe) unref(handle voidptr) ? {
	katomic.dec(mut &this.refcount)
	event.trigger(mut this.event, false)
}

fn (mut this Pipe) unlink(handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this Pipe) link(handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Pipe) grow(handle voidptr, new_size u64) ? {
	return none
}
