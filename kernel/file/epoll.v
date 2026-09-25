@[has_globals]
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
	fd     int
	events u32
	data   u64
	ready  u32
	// A retained reference to the open-file description being watched, which
	// keeps the resource alive for as long as it is in the set. It is counted
	// in the file's epoll_refs, and when those are all that is left the file
	// leaves the set (epoll_forget): an epoll registration is against the open
	// file, and goes with it, as on Linux. Kept for good, it stayed after its
	// last descriptor was closed, and a descriptor that later got the same
	// number could not be added: nginx adds one end of a socketpair to test
	// EPOLLRDHUP and closes it without deleting it, and a connection accepted
	// as the same number failed with EEXIST and was never answered.
	handle     &Handle = unsafe { nil }
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

// Every epoll set, for epoll_forget() to find the ones watching a file.
__global (
	epoll_sets      []&EpollResource
	epoll_sets_lock klock.Lock
)

// Take `handle`, whose last descriptor has been closed, out of every set that
// watches it, and give back their references. Called with no set's lock
// held: the set's is taken here, after epoll_sets_lock.
fn epoll_forget(handle &Handle) {
	mut dropped := 0
	epoll_sets_lock.acquire()
	for mut set in epoll_sets {
		set.l.acquire()
		mut i := 0
		for i < set.entries.len {
			if voidptr(set.entries[i].handle) == voidptr(handle) {
				set.entries.delete(i)
				dropped++
				continue
			}
			i++
		}
		set.l.release()
	}
	epoll_sets_lock.release()
	if dropped == 0 {
		return
	}
	mut watched := unsafe { handle }
	for _ in 0 .. dropped {
		katomic.dec(mut &watched.epoll_refs)
	}
	for _ in 0 .. dropped {
		watched.unref()
	}
}

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

fn (mut this EpollResource) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this EpollResource) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this EpollResource) ioctl(_handle voidptr, _request u64, _argp voidptr) ?int {
	errno.set(errno.einval)
	return none
}

fn (mut this EpollResource) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) {
		return
	}
	epoll_sets_lock.acquire()
	for i := 0; i < epoll_sets.len; i++ {
		if voidptr(epoll_sets[i]) == voidptr(this) {
			epoll_sets.delete(i)
			break
		}
	}
	epoll_sets_lock.release()
	// Give back the reference every entry held on its watched open file.
	for entry in this.entries {
		if entry.handle != unsafe { nil } {
			mut watched_handle := entry.handle
			katomic.dec(mut &watched_handle.epoll_refs)
			watched_handle.unref()
		}
	}
	unsafe {
		this.entries.free()
		free(voidptr(this))
	}
}

fn (mut this EpollResource) link(_handle voidptr) ? {
	katomic.inc(mut &this.refcount)
}

fn (mut this EpollResource) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this EpollResource) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this EpollResource) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

pub fn syscall_epoll_create1(_ voidptr, flags int) (u64, u64) {
	if flags & ~epoll_cloexec != 0 {
		return errno.err, errno.einval
	}

	mut res := &EpollResource{}
	res.stat.mode = 0o600

	mut r := &resource.Resource(unsafe { res })

	open_flags := resource.o_rdwr |
		if flags & epoll_cloexec != 0 { resource.o_cloexec } else { 0 }

	epoll_sets_lock.acquire()
	epoll_sets << res
	epoll_sets_lock.release()
	// A set that gets no descriptor is closed, which takes it off the list.
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

	// The set's own lock, held only for the list mutation, keeps a concurrent
	// epoll_pwait on another thread from scanning entries as they move. No
	// reference is given back while it is held: the last one on a file takes
	// the file out of every set, this one's too, with their locks.
	mut failure := u64(0)
	mut keep_lookup := false
	mut removed := &Handle(unsafe { nil })
	epoll_res.l.acquire()
	match op {
		epoll_ctl_add {
			for entry in epoll_res.entries {
				if entry.fd == fd {
					failure = errno.eexist
					break
				}
			}
			if failure == 0 {
				// The lookup reference is handed to the entry, which holds it
				// until the fd is removed, its file closed, or the set destroyed.
				epoll_res.entries << EpollEntry{
					fd:     fd
					events: requested.events
					data:   requested.data
					handle: watched_fd.handle
				}
				katomic.inc(mut &watched_fd.handle.epoll_refs)
				keep_lookup = true
			}
		}
		epoll_ctl_del {
			failure = errno.enoent
			for i, entry in epoll_res.entries {
				if entry.fd == fd {
					removed = epoll_res.entries[i].handle
					epoll_res.entries.delete(i)
					failure = 0
					break
				}
			}
		}
		epoll_ctl_mod {
			failure = errno.enoent
			for mut entry in epoll_res.entries {
				if entry.fd == fd {
					entry.events = requested.events
					entry.data = requested.data
					// EPOLL_CTL_MOD rearms EPOLLONESHOT and establishes a new
					// baseline for edge-triggered readiness.
					entry.ready = 0
					entry.generation = 0
					entry.disabled = false
					failure = 0
					break
				}
			}
		}
		else {
			failure = errno.einval
		}
	}
	epoll_res.l.release()

	if keep_lookup {
		watched_fd.release_descriptor()
	} else {
		watched_fd.unref()
	}
	if removed != unsafe { nil } {
		katomic.dec(mut &removed.epoll_refs)
		removed.unref()
	}
	if failure != 0 {
		return errno.err, failure
	}

	// A thread already blocked in epoll_pwait on this set has to look at the
	// descriptor just added or rearmed.
	if op == epoll_ctl_add || op == epoll_ctl_mod {
		event.trigger(mut epoll_res.event, false)
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
		// SIGKILL and SIGSTOP can never be blocked, not even for the wait.
		t.masked_signals = incoming_mask & ~((u64(1) << 8) | (u64(1) << 18))
	}
	defer {
		t.masked_signals = oldmask
	}

	// First pass: check if any fds are already ready.
	mut ret := u64(0)
	if events := epoll_res.collect_ready(maxevents) {
		for out_event in events {
			if !usercopy.copy_to_user(events_buf + ret * sizeof(EpollEvent),
				voidptr(&out_event), sizeof(EpollEvent)) {
				unsafe { events.free() }
				return errno.err, errno.efault
			}
			ret++
		}
		unsafe { events.free() }
	}
	if ret > 0 {
		return ret, 0
	}

	if timeout == 0 {
		// Non-blocking, and nothing is ready.
		return 0, 0
	}

	mut timer := &time.Timer(unsafe { nil })
	if timeout > 0 {
		ts := time.TimeSpec{
			tv_sec:  i64(timeout / 1000)
			tv_nsec: i64((timeout % 1000) * 1000000)
		}
		timer = time.new_timer(ts)
	}
	// timeout < 0 means block indefinitely
	defer {
		if voidptr(timer) != unsafe { nil } {
			timer.disarm()
			unsafe { free(timer) }
		}
	}

	for {
		// Sleep on the events of what the set watches right now, and on the
		// set's own event, which epoll_ctl raises when the set changes: Go adds
		// descriptors to its poller while a thread is already blocked here.
		// The wait pins the watched resources so their events outlive it, but
		// not the open files. A file watched here must still go away when its
		// last descriptor is closed -- a pipe reader is waiting for exactly
		// that to see end of file -- and Linux never keeps one open either.
		// Holding the file instead left runc's log pipe with a writer for as
		// long as its poller slept, so runc waited forever for the EOF.
		mut watched := epoll_res.snapshot_watched()
		mut ev_list := []&eventstruct.Event{cap: watched.len + 2}
		ev_list << &epoll_res.event
		for i in 0 .. watched.len {
			mut watched_res := watched[i]
			ev_list << &watched_res.event
		}
		timer_index := u64(ev_list.len)
		if voidptr(timer) != unsafe { nil } {
			ev_list << &timer.event
		}

		result := event.await(mut ev_list, true)
		for i in 0 .. watched.len {
			mut watched_res := watched[i]
			resource.release_resource(mut watched_res)
		}
		unsafe {
			watched.free()
			ev_list.free()
		}
		which := result or { return errno.err, errno.eintr }

		// Readiness is read from the set as it is now; the entries may have
		// moved while this slept.
		if events := epoll_res.collect_ready(maxevents) {
			ret = 0
			for out_event in events {
				if !usercopy.copy_to_user(events_buf + ret * sizeof(EpollEvent),
					voidptr(&out_event), sizeof(EpollEvent)) {
					unsafe { events.free() }
					return errno.err, errno.efault
				}
				ret++
			}
			unsafe { events.free() }
			if ret > 0 {
				return ret, 0
			}
		}
		if voidptr(timer) != unsafe { nil } && which == timer_index {
			return 0, 0
		}
		// A wake with nothing ready: the set changed, or a watched resource
		// did in a way that is not being waited for. Look again -- unless a
		// signal is waiting to be taken, which only the way out delivers, as
		// Linux's ep_poll() looks before every pass. An event that kept firing
		// with nothing ready kept postgres's processes looping here with a
		// SIGTERM pending for good, and a shutdown never finished.
		if t.pending_signals & ~t.masked_signals != 0 {
			return errno.err, errno.eintr
		}
	}

	return 0, 0
}

// The events that are ready right now, up to `maxevents`, computed with the
// set locked so a concurrent epoll_ctl cannot move the entries mid-scan.
fn (mut this EpollResource) collect_ready(maxevents int) ?[]EpollEvent {
	this.l.acquire()
	defer {
		this.l.release()
	}
	// Sized up front: an array that grows leaves its old buffer behind in
	// this kernel, and a Go runtime polls several times a millisecond.
	limit := if maxevents < this.entries.len { maxevents } else { this.entries.len }
	mut events := []EpollEvent{cap: limit}
	for mut entry in this.entries {
		if events.len >= maxevents {
			break
		}
		if entry.handle == unsafe { nil } {
			continue
		}
		mut watched := entry.handle.resource
		revents := epoll_ready_events(mut entry, watched.status, watched.event.generation)
		if revents != 0 {
			events << EpollEvent{
				events: revents
				data:   entry.data
			}
		}
	}
	if events.len == 0 {
		unsafe { events.free() }
		return none
	}
	return events
}

// The resources currently watched, each retained so that a blocking wait can
// sleep on its event without the resource being freed underneath it.
fn (mut this EpollResource) snapshot_watched() []&resource.Resource {
	this.l.acquire()
	defer {
		this.l.release()
	}
	mut resources := []&resource.Resource{cap: this.entries.len}
	for entry in this.entries {
		if entry.handle == unsafe { nil } {
			continue
		}
		mut watched := entry.handle.resource
		resource.retain_resource(mut watched)
		resources << watched
	}
	return resources
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
