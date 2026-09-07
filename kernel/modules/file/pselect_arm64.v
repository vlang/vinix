// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module file

// pselect6(2), and through it select(2), which musl implements on top of it.
// aarch64 has no select or poll syscall of its own: both are built from
// pselect6 and ppoll.

import errno
import event
import proc
import time
import usercopy

// An fd_set is a flat bitmap of `fd_set_bits` descriptors.
const fd_set_bits = 1024

const fd_set_words = fd_set_bits / 64

// The sixth argument is a pointer to this, not to a mask directly, because the
// syscall ABI has only six registers and pselect6 wanted seven arguments.
struct SigmaskArg {
mut:
	mask u64
	size u64
}

fn read_fd_set(address u64, words u64) ?[fd_set_words]u64 {
	mut set := [fd_set_words]u64{}
	if address == 0 {
		return set
	}
	if !usercopy.copy_from_user(voidptr(&set[0]), address, words * sizeof(u64)) {
		errno.set(errno.efault)
		return none
	}
	return set
}

fn is_set(set [fd_set_words]u64, fd int) bool {
	return set[fd / 64] & (u64(1) << u64(fd % 64)) != 0
}

fn set_bit(mut set [fd_set_words]u64, fd int) {
	set[fd / 64] |= u64(1) << u64(fd % 64)
}

// pselect6(nfds, readfds, writefds, exceptfds, timeout, sigmask).
//
// The descriptors are gathered into the same PollFD list ppoll() works on, so
// there is one readiness path rather than two. Unlike select(2), the timeout is
// not written back: pselect6 leaves it alone, and musl's select() copies it.
pub fn syscall_pselect6(_ voidptr, nfds int, readfds u64, writefds u64, exceptfds u64, timeout u64, sigmask u64) (u64, u64) {
	mut current_thread := proc.current_thread()

	if nfds < 0 || nfds > fd_set_bits {
		return errno.err, errno.einval
	}

	words := u64((nfds + 63) / 64)

	mut want_read := read_fd_set(readfds, words) or { return errno.err, errno.get() }
	mut want_write := read_fd_set(writefds, words) or { return errno.err, errno.get() }
	mut want_except := read_fd_set(exceptfds, words) or { return errno.err, errno.get() }

	mut deadline := time.TimeSpec{}
	mut timed := false
	if timeout != 0 {
		if !usercopy.copy_from_user(voidptr(&deadline), timeout, sizeof(time.TimeSpec)) {
			return errno.err, errno.efault
		}
		if deadline.tv_sec < 0 || deadline.tv_nsec < 0 || deadline.tv_nsec >= 1000000000 {
			return errno.err, errno.einval
		}
		timed = true
	}

	// pselect6 swaps in a signal mask for the duration of the wait, the same
	// way ppoll does.
	old_mask := current_thread.masked_signals
	mut masked := false
	if sigmask != 0 {
		mut arg := SigmaskArg{}
		if !usercopy.copy_from_user(voidptr(&arg), sigmask, sizeof(SigmaskArg)) {
			return errno.err, errno.efault
		}
		if arg.mask != 0 {
			if arg.size != sizeof(u64) {
				return errno.err, errno.einval
			}
			mut wanted := u64(0)
			if !usercopy.copy_from_user(voidptr(&wanted), arg.mask, sizeof(u64)) {
				return errno.err, errno.efault
			}
			current_thread.masked_signals = wanted
			masked = true
		}
	}
	defer {
		if masked {
			current_thread.masked_signals = old_mask
		}
	}

	mut polls := []PollFD{}
	mut indexes := []int{}
	defer {
		unsafe {
			polls.free()
			indexes.free()
		}
	}

	for fd := 0; fd < nfds; fd++ {
		mut events := i16(0)
		if is_set(want_read, fd) {
			events |= i16(pollin)
		}
		if is_set(want_write, fd) {
			events |= i16(pollout)
		}
		if is_set(want_except, fd) {
			events |= i16(pollpri)
		}
		if events == 0 {
			continue
		}
		polls << PollFD{
			fd:      fd
			events:  events
			revents: 0
		}
		indexes << fd
	}

	if polls.len == 0 {
		// Nothing to watch: this is select() being used purely as a sleep.
		if !timed {
			return errno.err, errno.einval
		}
		if deadline.tv_sec != 0 || deadline.tv_nsec != 0 {
			mut timer := time.new_timer(deadline)
			mut sleep_events := [&timer.event]
			defer {
				timer.disarm()
				unsafe {
					free(timer)
					sleep_events.free()
				}
			}
			event.await(mut sleep_events, true) or { return errno.err, errno.eintr }
		}
		return 0, 0
	}

	mut timeout_ptr := &time.TimeSpec(unsafe { nil })
	if timed {
		timeout_ptr = &deadline
	}

	ready, err := ppoll(unsafe { &polls[0] }, u64(polls.len), timeout_ptr, unsafe { nil })
	if err != 0 {
		return ready, err
	}

	mut got_read := [fd_set_words]u64{}
	mut got_write := [fd_set_words]u64{}
	mut got_except := [fd_set_words]u64{}
	mut count := u64(0)

	for i := 0; i < polls.len; i++ {
		revents := polls[i].revents
		fd := indexes[i]
		mut hit := false

		// An error or a hangup makes a descriptor readable as far as select is
		// concerned, so that the caller goes and finds out what happened.
		if revents & i16(pollin | pollhup | pollerr) != 0 && is_set(want_read, fd) {
			set_bit(mut got_read, fd)
			hit = true
		}
		if revents & i16(pollout | pollerr) != 0 && is_set(want_write, fd) {
			set_bit(mut got_write, fd)
			hit = true
		}
		if revents & i16(pollpri) != 0 && is_set(want_except, fd) {
			set_bit(mut got_except, fd)
			hit = true
		}

		if hit {
			count++
		}
	}

	if readfds != 0 && !usercopy.copy_to_user(readfds, voidptr(&got_read[0]), words * sizeof(u64)) {
		return errno.err, errno.efault
	}
	if writefds != 0
		&& !usercopy.copy_to_user(writefds, voidptr(&got_write[0]), words * sizeof(u64)) {
		return errno.err, errno.efault
	}
	if exceptfds != 0
		&& !usercopy.copy_to_user(exceptfds, voidptr(&got_except[0]), words * sizeof(u64)) {
		return errno.err, errno.efault
	}

	return count, 0
}
