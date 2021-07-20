module pipe

import resource
import stat
import klock
import event
import event.eventstruct
import errno
import file

// A pipe is a circular buffer

pub const pipe_buf = 4096

pub struct Pipe {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock

	data      &byte
	read_ptr  u64
	write_ptr u64
	capacity  u64
	used      u64
	event     eventstruct.Event
}

pub fn initialise() {}

pub fn create() ?&Pipe {
	mut pipe := &Pipe{
		data: unsafe { C.malloc(pipe_buf) }
		capacity: pipe_buf
	}
	pipe.stat.mode = stat.ifpipe

	return pipe
}

pub fn syscall_pipe(_ voidptr, pipefds &int, flags int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: pipe(0x%llx, 0x%x)\n', voidptr(pipefds), flags)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	new_pipe := create() or {
		return -1, errno.get()
	}

	rd_fd := file.fdnum_create_from_resource(voidptr(0), new_pipe, flags, 0, false) or {
		return -1, errno.get()
	}

	wr_fd := file.fdnum_create_from_resource(voidptr(0), new_pipe, flags, 0, false) or {
		return -1, errno.get()
	}

	unsafe {
		pipefds[0] = rd_fd
		pipefds[1] = wr_fd
	}

	return 0, 0
}

fn (mut this Pipe) read(buf voidptr, loc u64, _count u64) ?i64 {
	mut count := _count

	this.l.acquire()
	defer {
		this.l.release()
	}

	// If pipe is empty, block or return if nonblock
	for this.used == 0 {
		// Return EOF if the pipe was closed
		if this.refcount == 1 {
			return 0
		}
		// We don't do nonblock yet
		this.l.release()
		mut which := u64(0)
		event.await([&this.event], &which, true)
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
		unsafe { C.memcpy(voidptr(u64(buf) + before_wrap), &this.data[0], after_wrap) }
	}

	this.read_ptr = new_ptr_loc
	this.used -= count

	event.trigger(this.event, true)

	return i64(count)
}

fn (mut this Pipe) write(buf voidptr, loc u64, _count u64) ?i64 {
	mut count := _count

	this.l.acquire()
	defer {
		this.l.release()
	}

	// If pipe is full, block or return if nonblock
	for this.used == this.capacity {
		// We don't do nonblock yet
		this.l.release()
		mut which := u64(0)
		event.await([&this.event], &which, true)
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
		unsafe { C.memcpy(&this.data[0], voidptr(u64(buf) + before_wrap), after_wrap) }
	}

	this.write_ptr = new_ptr_loc
	this.used += count

	event.trigger(this.event, true)

	return i64(count)
}

fn (mut this Pipe) ioctl(request u64, argp voidptr) ?int {
	return resource.default_ioctl(request, argp)
}
