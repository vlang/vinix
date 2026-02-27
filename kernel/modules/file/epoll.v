module file

import resource
import stat as statmod
import klock
import proc
import katomic
import errno
import event
import event.eventstruct
import time

// epoll_event struct — on aarch64, NOT packed (unlike x86)
// Layout: events (u32) + padding (u32) + data (u64) = 16 bytes
struct EpollEvent {
mut:
	events u32
	data   u64
}

// Watched fd entry
struct EpollEntry {
mut:
	fd     int
	events u32
	data   u64
}

// epoll constants
pub const epoll_cloexec = 0x80000
pub const epoll_ctl_add = 1
pub const epoll_ctl_del = 2
pub const epoll_ctl_mod = 3

pub const epollin = 0x001
pub const epollout = 0x004
pub const epollpri = 0x002
pub const epollerr = 0x008
pub const epollhup = 0x010
pub const epollrdhup = 0x2000
pub const epollet = u32(0x80000000)
pub const epolloneshot = u32(0x40000000)

@[heap]
struct EpollResource {
mut:
	stat     statmod.Stat
	refcount int = 1
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	entries []EpollEntry
}

fn (mut this EpollResource) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this EpollResource) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this EpollResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	errno.set(errno.einval)
	return none
}

fn (mut this EpollResource) unref(handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this EpollResource) link(handle voidptr) ? {
	katomic.inc(mut &this.refcount)
}

fn (mut this EpollResource) unlink(handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this EpollResource) grow(handle voidptr, new_size u64) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this EpollResource) mmap(page u64, flags int) voidptr {
	return unsafe { nil }
}

pub fn syscall_epoll_create1(_ voidptr, flags int) (u64, u64) {
	mut res := &EpollResource{}
	res.stat.mode = 0o600

	mut r := &resource.Resource(unsafe { res })

	open_flags := if flags & epoll_cloexec != 0 { resource.o_cloexec } else { 0 }

	fdnum := fdnum_create_from_resource(unsafe { nil }, mut r, open_flags, 0, false) or {
		return errno.err, errno.get()
	}

	return u64(fdnum), 0
}

pub fn syscall_epoll_ctl(_ voidptr, epfd int, op int, fd int, _event &EpollEvent) (u64, u64) {
	// Get the epoll fd
	mut epoll_fd := fd_from_fdnum(unsafe { nil }, epfd) or {
		return errno.err, errno.ebadf
	}
	defer {
		epoll_fd.unref()
	}

	// V interface struct layout: { union { void* _object; ... }; u32 _typ; field_ptrs... }
	// The object pointer is at offset 0 of the interface struct.
	// Cannot simply cast &Resource to &EpollResource — must extract the object pointer.
	mut epoll_res := unsafe { &EpollResource(*&voidptr(epoll_fd.handle.resource)) }

	match op {
		epoll_ctl_add {
			// Check if fd already exists
			for entry in epoll_res.entries {
				if entry.fd == fd {
					return errno.err, errno.eexist
				}
			}
			ev := unsafe { *_event }
			epoll_res.entries << EpollEntry{
				fd:     fd
				events: ev.events
				data:   ev.data
			}
		}
		epoll_ctl_del {
			mut found := false
			for i, entry in epoll_res.entries {
				if entry.fd == fd {
					epoll_res.entries.delete(i)
					found = true
					break
				}
			}
			if !found {
				return errno.err, errno.enoent
			}
		}
		epoll_ctl_mod {
			mut found := false
			ev := unsafe { *_event }
			for mut entry in epoll_res.entries {
				if entry.fd == fd {
					entry.events = ev.events
					entry.data = ev.data
					found = true
					break
				}
			}
			if !found {
				return errno.err, errno.enoent
			}
		}
		else {
			return errno.err, errno.einval
		}
	}

	return 0, 0
}

pub fn syscall_epoll_pwait(_ voidptr, epfd int, events_buf &EpollEvent, maxevents int, timeout int, sigmask &u64) (u64, u64) {
	mut t := proc.current_thread()

	if maxevents <= 0 {
		return errno.err, errno.einval
	}

	// Get the epoll fd
	mut epoll_fd := fd_from_fdnum(unsafe { nil }, epfd) or {
		return errno.err, errno.ebadf
	}
	defer {
		epoll_fd.unref()
	}

	mut epoll_res := unsafe { &EpollResource(*&voidptr(epoll_fd.handle.resource)) }

	oldmask := t.masked_signals
	if voidptr(sigmask) != unsafe { nil } {
		t.masked_signals = *sigmask
	}
	defer {
		t.masked_signals = oldmask
	}

	// First pass: check if any fds are already ready
	mut ret := u64(0)
	for entry in epoll_res.entries {
		if ret >= u64(maxevents) {
			break
		}

		mut fd_obj := fd_from_fdnum(unsafe { nil }, entry.fd) or {
			continue
		}

		status := fd_obj.handle.resource.status

		// Map resource status to epoll events
		mut revents := u32(0)
		if status & pollin != 0 && entry.events & epollin != 0 {
			revents |= epollin
		}
		if status & pollout != 0 && entry.events & epollout != 0 {
			revents |= epollout
		}
		if status & pollhup != 0 {
			revents |= epollhup
		}
		if status & pollerr != 0 {
			revents |= epollerr
		}
		if status & pollrdhup != 0 && entry.events & epollrdhup != 0 {
			revents |= epollrdhup
		}

		if revents != 0 {
			mut out_event := unsafe { &events_buf[ret] }
			out_event.events = revents
			out_event.data = entry.data
			ret++
		}

		fd_obj.unref()
	}

	if ret > 0 {
		return ret, 0
	}

	// No fds ready — need to block
	// Collect events from all watched resources
	mut ev_list := []&eventstruct.Event{}
	mut fd_objs := []&FD{}
	mut entry_indices := []int{}

	defer {
		for mut f in fd_objs {
			f.unref()
		}
		unsafe {
			ev_list.free()
			fd_objs.free()
			entry_indices.free()
		}
	}

	for i, entry in epoll_res.entries {
		mut fd_obj := fd_from_fdnum(unsafe { nil }, entry.fd) or {
			continue
		}
		ev_list << &fd_obj.handle.resource.event
		fd_objs << fd_obj
		entry_indices << i
	}

	if ev_list.len == 0 {
		// No valid fds to wait on
		if timeout == 0 {
			return 0, 0
		}
		// With timeout, just sleep
		if timeout > 0 {
			ts := time.TimeSpec{
				tv_sec:  i64(timeout / 1000)
				tv_nsec: i64((timeout % 1000) * 1000000)
			}
			mut timer := time.new_timer(ts)
			mut timer_events := [&timer.event]
			event.await(mut timer_events, true) or {}
			timer.disarm()
			unsafe { free(timer) }
		}
		return 0, 0
	}

	// Add a timer if timeout > 0
	mut timer := &time.Timer(unsafe { nil })
	if timeout > 0 {
		ts := time.TimeSpec{
			tv_sec:  i64(timeout / 1000)
			tv_nsec: i64((timeout % 1000) * 1000000)
		}
		timer = time.new_timer(ts)
		ev_list << &timer.event
	} else if timeout == 0 {
		// Non-blocking — we already checked, nothing ready
		return 0, 0
	}
	// timeout < 0 means block indefinitely

	defer {
		if voidptr(timer) != unsafe { nil } {
			timer.disarm()
			unsafe { free(timer) }
		}
	}

	// Wait for any event
	for {
		which := event.await(mut ev_list, true) or { return errno.err, errno.eintr }

		// Check if timer expired
		if voidptr(timer) != unsafe { nil } && which == u64(ev_list.len) - 1 {
			return 0, 0
		}

		// Check all fds for events (not just the one that triggered)
		ret = 0
		for i, entry_idx in entry_indices {
			if ret >= u64(maxevents) {
				break
			}
			entry := epoll_res.entries[entry_idx]
			status := fd_objs[i].handle.resource.status

			mut revents := u32(0)
			if status & pollin != 0 && entry.events & epollin != 0 {
				revents |= epollin
			}
			if status & pollout != 0 && entry.events & epollout != 0 {
				revents |= epollout
			}
			if status & pollhup != 0 {
				revents |= epollhup
			}
			if status & pollerr != 0 {
				revents |= epollerr
			}

			if revents != 0 {
				mut out_event := unsafe { &events_buf[ret] }
				out_event.events = revents
				out_event.data = entry.data
				ret++
			}
		}

		if ret > 0 {
			return ret, 0
		}

		// Spurious wakeup, try again
	}

	return 0, 0
}
