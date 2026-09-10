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
	readers   int
	writers   int
	event     eventstruct.Event
}

pub fn initialise() {}

pub fn create() ?&Pipe {
	mut p := &Pipe{
		data: unsafe { malloc(pipe_buf) }
		capacity: pipe_buf
		// A pipe starts with one read-side and one write-side open-file
		// description. dup() and fork() share those descriptions, so their
		// lifetime is already accounted for by file.Handle.refcount.
		readers: 1
		writers: 1
	}
	p.stat.mode = stat.ifpipe
	// An empty pipe is writable. pollout was only ever raised by read(), when
	// it freed space, so until something had been read a fresh pipe reported
	// itself unwritable and anything waiting for room to write blocked for good.
	p.status |= file.pollout

	return p
}

pub fn syscall_pipe(_ voidptr, pipefds &int, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: pipe(0x%llx, 0x%x)\n', process.name.str, voidptr(pipefds), flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut new_pipe := create() or { return errno.err, errno.get() }

	rd_fd := file.fdnum_create_from_resource(unsafe { nil }, mut new_pipe, flags | resource.o_rdonly, 0, false) or {
		return errno.err, errno.get()
	}

	wr_fd := file.fdnum_create_from_resource(unsafe { nil }, mut new_pipe, flags | resource.o_wronly, 0, false) or {
		return errno.err, errno.get()
	}

	unsafe {
		pipefds[0] = rd_fd
		pipefds[1] = wr_fd
	}
	return 0, 0
}

fn (mut this Pipe) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}

fn (mut this Pipe) read(_handle voidptr, buf voidptr, _loc u64, _count u64) ?i64 {
	mut count := _count

	this.l.acquire()
	defer {
		this.l.release()
	}

	handle := unsafe { &file.Handle(_handle) }

	// If pipe is empty, block or return if nonblock
	for katomic.load(&this.used) == 0 {
		// EOF begins only after the last write-side open-file description is
		// gone. The resource refcount also includes readers, so it cannot tell
		// this apart once shells have made more than one pipe endpoint.
		if this.writers == 0 {
			return 0
		}
		if handle.flags & resource.o_nonblock != 0 {
			errno.set(errno.eagain)
			return none
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

fn (mut this Pipe) write(handle voidptr, buf voidptr, _loc u64, _count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}

	open_handle := unsafe { &file.Handle(handle) }
	if _count == 0 {
		return 0
	}

	if this.readers == 0 {
		errno.set(errno.epipe)
		return none
	}

	mut written := u64(0)
	for written < _count {
		remaining := _count - written
		// Writes no larger than PIPE_BUF are atomic: wait for the complete
		// write to fit instead of exposing a partial record to the reader.
		// A larger blocking write may be consumed in chunks internally, but
		// write(2) still reports the full count once all chunks are queued.
		required_room := if remaining <= this.capacity { remaining } else { u64(1) }
		for this.capacity - katomic.load(&this.used) < required_room {
			if this.readers == 0 {
				if written != 0 {
					return i64(written)
				}
				errno.set(errno.epipe)
				return none
			}
			if open_handle.flags & resource.o_nonblock != 0 {
				if written != 0 {
					return i64(written)
				}
				errno.set(errno.eagain)
				return none
			}
			this.l.release()
			mut events := [&this.event]
			event.await(mut events, true) or {
				unsafe { events.free() }
				this.l.acquire()
				if written != 0 {
					return i64(written)
				}
				errno.set(errno.eintr)
				return none
			}
			unsafe { events.free() }
			this.l.acquire()
		}

		if this.readers == 0 {
			if written != 0 {
				return i64(written)
			}
			errno.set(errno.epipe)
			return none
		}

		mut count := remaining
		room := this.capacity - this.used
		if count > room {
			count = room
		}

		// Calculate sizes before and after wrap-around and new ptr location.
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

		unsafe { C.memcpy(&this.data[this.write_ptr], voidptr(u64(buf) + written), before_wrap) }
		if after_wrap != 0 {
			unsafe {
				C.memcpy(this.data, voidptr(u64(buf) + written + before_wrap), after_wrap)
			}
		}

		this.write_ptr = new_ptr_loc
		this.used += count
		written += count

		if this.used == this.capacity {
			this.status &= ~file.pollout
		}
		this.status |= file.pollin
		event.trigger(mut this.event, false)
	}

	return i64(written)
}

fn (mut this Pipe) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this Pipe) unref(handle voidptr) ? {
	open_handle := unsafe { &file.Handle(handle) }

	this.l.acquire()
	match open_handle.flags & resource.o_accmode {
		resource.o_rdonly {
			this.readers--
			if this.readers == 0 {
				this.status &= ~file.pollout
				this.status |= file.pollerr
			}
		}
		resource.o_wronly {
			this.writers--
			if this.writers == 0 {
				// EOF is a readiness condition. Wake poll/select/epoll waiters
				// after the final write-side open description disappears.
				this.status |= file.pollhup
			}
		}
		resource.o_rdwr {
			this.readers--
			this.writers--
			if this.readers == 0 {
				this.status &= ~file.pollout
				this.status |= file.pollerr
			}
			if this.writers == 0 {
				this.status |= file.pollhup
			}
		}
		else {}
	}
	katomic.dec(mut &this.refcount)
	this.l.release()
	event.trigger(mut this.event, false)
}

fn (mut this Pipe) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this Pipe) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Pipe) grow(_handle voidptr, _new_size u64) ? {
	return none
}

// Copy up to `count` bytes out of the pipe without consuming them, which is
// what tee(2) needs: the data has to stay readable for the original reader.
pub fn (mut this Pipe) peek(buf voidptr, count u64) u64 {
	this.l.acquire()
	defer {
		this.l.release()
	}

	mut to_copy := count
	if to_copy > this.used {
		to_copy = this.used
	}
	if to_copy == 0 {
		return 0
	}

	// The buffer is a ring, so a read that reaches the end wraps.
	before_wrap := this.capacity - this.read_ptr
	if to_copy <= before_wrap {
		unsafe { C.memcpy(buf, voidptr(u64(this.data) + this.read_ptr), to_copy) }
	} else {
		after_wrap := to_copy - before_wrap
		unsafe {
			C.memcpy(buf, voidptr(u64(this.data) + this.read_ptr), before_wrap)
			C.memcpy(voidptr(u64(buf) + before_wrap), this.data, after_wrap)
		}
	}

	return to_copy
}

// How much a pipe is holding, and how much room is left.
pub fn (this &Pipe) available() u64 {
	return this.used
}

pub fn (this &Pipe) room() u64 {
	return this.capacity - this.used
}
