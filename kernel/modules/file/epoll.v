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
import usercopy

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
	fd         int
	events     u32
	data       u64
	ready      u32
	generation u64
	disabled   bool
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
	refcount int
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
	if katomic.dec(mut &this.refcount) {
		return
	}
	unsafe {
		this.entries.free()
		free(voidptr(this))
	}
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

fn (mut this EpollResource) mmap(_handle voidptr, page u64, flags int) voidptr {
	return unsafe { nil }
}

pub fn syscall_epoll_create1(_ voidptr, flags int) (u64, u64) {
	if flags & ~epoll_cloexec != 0 {
		return errno.err, errno.einval
	}

	mut res := &EpollResource{}
	res.stat.mode = 0o600

	mut r := &resource.Resource(unsafe { res })

	open_flags := if flags & epoll_cloexec != 0 { resource.o_cloexec } else { 0 }

	fdnum := fdnum_create_from_resource(unsafe { nil }, mut r, open_flags, 0, false) or {
		return errno.err, errno.get()
	}

	return u64(fdnum), 0
}

pub fn syscall_epoll_ctl(_ voidptr, epfd int, op int, fd int, event_ptr u64) (u64, u64) {
	mut requested := EpollEvent{}
	if op == epoll_ctl_add || op == epoll_ctl_mod {
		if !usercopy.copy_from_user(voidptr(&requested), event_ptr, sizeof(EpollEvent)) {
			return errno.err, errno.efault
		}
	}

	// Get the epoll fd
	mut epoll_fd := fd_from_fdnum(unsafe { nil }, epfd) or {
		return errno.err, errno.ebadf
	}
	defer {
		epoll_fd.unref()
	}

	// Reach the concrete resource through V's own type test. Reading the
	// interface's first word by hand, as this used to, assumed a layout this
	// compiler does not use: it picked up the type tag instead of the object
	// pointer, so every access landed near address zero. It also let any
	// descriptor at all be treated as an epoll set.
	mut res := epoll_fd.handle.resource
	mut epoll_res := &EpollResource(unsafe { nil })
	if mut res is EpollResource {
		epoll_res = res
	} else {
		return errno.err, errno.einval
	}
	if epfd == fd {
		return errno.err, errno.einval
	}
	mut watched_fd := fd_from_fdnum(unsafe { nil }, fd) or {
		return errno.err, errno.ebadf
	}
	watched_fd.unref()

	match op {
		epoll_ctl_add {
			// Check if fd already exists
			for entry in epoll_res.entries {
				if entry.fd == fd {
					return errno.err, errno.eexist
				}
			}
			epoll_res.entries << EpollEntry{
				fd:     fd
				events: requested.events
				data:   requested.data
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
			for mut entry in epoll_res.entries {
				if entry.fd == fd {
					entry.events = requested.events
					entry.data = requested.data
					// EPOLL_CTL_MOD rearms EPOLLONESHOT and establishes a new
					// baseline for edge-triggered readiness.
					entry.ready = 0
					entry.generation = 0
					entry.disabled = false
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

// Translate a resource's poll status and apply the delivery mode requested by
// this registration. EPOLLET reports only newly-ready bits, while
// EPOLLONESHOT remains disabled until an EPOLL_CTL_MOD rearms it.
fn epoll_ready_events(mut entry EpollEntry, status int, generation u64) u32 {
	if entry.disabled {
		return 0
	}

	mut current := u32(0)
	if status & pollin != 0 && entry.events & epollin != 0 {
		current |= epollin
	}
	if status & pollout != 0 && entry.events & epollout != 0 {
		current |= epollout
	}
	if status & pollhup != 0 {
		current |= epollhup
	}
	if status & pollerr != 0 {
		current |= epollerr
	}
	if status & pollrdhup != 0 && entry.events & epollrdhup != 0 {
		current |= epollrdhup
	}

	mut deliverable := current
	if entry.events & epollet != 0 {
		deliverable &= ~entry.ready
		// A resource may become not-ready and ready again between two
		// epoll waits. Its event generation preserves that intervening edge
		// even when the sampled status bits are identical.
		if current != 0 && generation != entry.generation {
			deliverable = current
		}
		entry.ready = current
		entry.generation = generation
	}
	if deliverable != 0 && entry.events & epolloneshot != 0 {
		entry.disabled = true
	}
	return deliverable
}

pub fn syscall_epoll_pwait(_ voidptr, epfd int, events_buf u64, maxevents int, timeout int, sigmask u64, sigsetsize u64) (u64, u64) {
	mut t := proc.current_thread()

	if maxevents <= 0 || timeout < -1 {
		return errno.err, errno.einval
	}
	if sigmask != 0 && sigsetsize != sizeof(u64) {
		return errno.err, errno.einval
	}

	// Get the epoll fd
	mut epoll_fd := fd_from_fdnum(unsafe { nil }, epfd) or {
		return errno.err, errno.ebadf
	}
	defer {
		epoll_fd.unref()
	}

	mut res := epoll_fd.handle.resource
	mut epoll_res := &EpollResource(unsafe { nil })
	if mut res is EpollResource {
		epoll_res = res
	} else {
		return errno.err, errno.einval
	}
	oldmask := t.masked_signals
	if sigmask != 0 {
		mut incoming_mask := u64(0)
		if !usercopy.copy_from_user(voidptr(&incoming_mask), sigmask, sizeof(u64)) {
			return errno.err, errno.efault
		}
		t.masked_signals = incoming_mask
	}
	defer {
		t.masked_signals = oldmask
	}

	// First pass: check if any fds are already ready
	mut ret := u64(0)
	for mut entry in epoll_res.entries {
		if ret >= u64(maxevents) {
			break
		}

		mut fd_obj := fd_from_fdnum(unsafe { nil }, entry.fd) or {
			continue
		}

		status := fd_obj.handle.resource.status
		generation := fd_obj.handle.resource.event.generation

		revents := epoll_ready_events(mut entry, status, generation)

		if revents != 0 {
			out_event := EpollEvent{
				events: revents
				data:   entry.data
			}
			if !usercopy.copy_to_user(events_buf + ret * sizeof(EpollEvent),
				voidptr(&out_event), sizeof(EpollEvent)) {
				return errno.err, errno.efault
			}
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
		which := event.await(mut ev_list, true) or {
			return errno.err, errno.eintr
		}

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
			mut entry := epoll_res.entries[entry_idx]
			status := fd_objs[i].handle.resource.status
			generation := fd_objs[i].handle.resource.event.generation
			revents := epoll_ready_events(mut entry, status, generation)
			epoll_res.entries[entry_idx] = entry

			if revents != 0 {
				out_event := EpollEvent{
					events: revents
					data:   entry.data
				}
				if !usercopy.copy_to_user(events_buf + ret * sizeof(EpollEvent),
					voidptr(&out_event), sizeof(EpollEvent)) {
					return errno.err, errno.efault
				}
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

// epoll_pwait2 is epoll_pwait with a nanosecond timespec instead of a
// millisecond integer.  The event core currently schedules at millisecond
// granularity, so round a non-zero fractional millisecond up rather than
// returning before the requested deadline.
pub fn syscall_epoll_pwait2(gpr_state voidptr, epfd int, events_buf u64, maxevents int, timeout_ptr u64, sigmask u64, sigsetsize u64) (u64, u64) {
	mut timeout := -1
	if timeout_ptr != 0 {
		mut requested := time.TimeSpec{}
		if !usercopy.copy_from_user(voidptr(&requested), timeout_ptr, sizeof(time.TimeSpec)) {
			return errno.err, errno.efault
		}
		if requested.tv_sec < 0 || requested.tv_nsec < 0 || requested.tv_nsec >= 1000000000 {
			return errno.err, errno.einval
		}

		seconds := u64(requested.tv_sec)
		mut milliseconds := u64(0x7fffffff)
		if seconds <= u64(0x7fffffff) / 1000 {
			milliseconds = seconds * 1000 + u64(requested.tv_nsec + 999999) / 1000000
			if milliseconds > u64(0x7fffffff) {
				milliseconds = u64(0x7fffffff)
			}
		}
		timeout = int(milliseconds)
	}

	return syscall_epoll_pwait(gpr_state, epfd, events_buf, maxevents, timeout, sigmask,
		sigsetsize)
}
