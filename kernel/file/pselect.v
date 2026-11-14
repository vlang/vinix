// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module file

// pselect6(2), and through it select(2), which musl implements on top of it on
// aarch64, where there is no select or poll syscall of its own. x86-64 has
// select(2) as well; its table builds it from this too.

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

// Select rejects closed slots before polling any resource or publishing any
// output. Borrow only the table's slot values under its lock; ppoll retains
// its own references afterwards. An open O_PATH slot is valid at this stage.
fn select_fds_open(process &proc.Process, polls []PollFD) bool {
	mut target := unsafe { process }
	target.fds_lock.acquire()
	defer { target.fds_lock.release() }
	for poll in polls {
		if poll.fd < 0 || int(poll.fd) >= target.fds.len
			|| target.fds[int(poll.fd)] == unsafe { nil } {
			return false
		}
	}
	return true
}

// pselect6(nfds, readfds, writefds, exceptfds, timeout, sigmask).
//
// The descriptors are gathered into the same PollFD list ppoll() works on, so
// there is one readiness path rather than two. Unlike select(2), the timeout is
// not written back: pselect6 leaves it alone, and musl's select() copies it.
pub fn syscall_pselect6(_ voidptr, nfds_word int, readfds u64, writefds u64, exceptfds u64, timeout u64, sigmask u64) (u64, u64) {
	// Linux declares nfds as signed int; the upper register word is ignored.
	nfds := int(i32(nfds_word))
	// Import the pselect argument pack before the timeout. Validate its mask
	// after the timeout, but before nfds and the descriptor bitmaps.
	mut arg := SigmaskArg{}
	if sigmask != 0 && !usercopy.copy_from_user(voidptr(&arg), sigmask, sizeof(SigmaskArg)) {
		return errno.err, errno.efault
	}
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
	if arg.mask != 0 {
		if arg.size != sizeof(u64) {
			return errno.err, errno.einval
		}
		mut wanted := u64(0)
		if !usercopy.copy_from_user(voidptr(&wanted), arg.mask, sizeof(u64)) {
			return errno.err, errno.efault
		}
		mut masked_thread := proc.current_thread()
		proc.begin_wait_mask(mut masked_thread, wanted)
	}
	return do_select(nfds, readfds, writefds, exceptfds, timed, deadline)
}

// select(nfds, readfds, writefds, exceptfds, timeout), the x86-64 call: the
// same as pselect6 with a struct timeval for the timeout and no signal mask.
// The time left is not written back; musl hands the kernel a copy anyway.
pub fn syscall_select(_ voidptr, nfds_word int, readfds u64, writefds u64, exceptfds u64, timeout u64) (u64, u64) {
	nfds := int(i32(nfds_word))
	mut deadline := time.TimeSpec{}
	mut timed := false
	if timeout != 0 {
		// struct timeval: seconds and microseconds.
		mut tv := [2]i64{}
		if !usercopy.copy_from_user(voidptr(&tv[0]), timeout, 16) {
			return errno.err, errno.efault
		}
		if tv[0] < 0 || tv[1] < 0 || tv[1] >= 1000000 {
			return errno.err, errno.einval
		}
		deadline = time.TimeSpec{tv[0], tv[1] * 1000}
		timed = true
	}
	return do_select(nfds, readfds, writefds, exceptfds, timed, deadline)
}

fn do_select(nfds int, readfds u64, writefds u64, exceptfds u64, timed bool, deadline time.TimeSpec) (u64, u64) {
	mut current_thread := proc.current_thread()

	if nfds < 0 || nfds > fd_set_bits {
		return errno.err, errno.einval
	}

	words := u64((nfds + 63) / 64)

	mut want_read := read_fd_set(readfds, words) or { return errno.err, errno.get() }
	mut want_write := read_fd_set(writefds, words) or { return errno.err, errno.get() }
	mut want_except := read_fd_set(exceptfds, words) or { return errno.err, errno.get() }

	mut polls := []PollFD{}
	mut indexes := []int{}
	// Nothing slices them, so growing can free each outgrown block.
	polls.flags |= .noslices
	indexes.flags |= .noslices
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

	if polls.len != 0 && !select_fds_open(current_thread.process, polls) {
		return errno.err, errno.ebadf
	}

	if polls.len == 0 {
		// Nothing to watch: this is select() being used purely as a sleep.
		if !timed {
			// An absent timeout is an interruptible, indefinite sleep. Reuse
			// ppoll's synchronous stack event without replacing a pselect mask.
			return ppoll(unsafe { nil }, 0, unsafe { nil }, unsafe { nil })
		}
		if deadline.tv_sec != 0 || deadline.tv_nsec != 0 {
			mut timer := time.new_timer(deadline)
			defer {
				timer.disarm()
				unsafe { free(timer) }
			}
			event.await_one(mut timer.event, true) or { return errno.err, errno.eintr }
		}
		// The imported last word can contain bits beyond nfds. A successful
		// empty wait still publishes zero words, including those ignored bits.
		mut empty_result := [fd_set_words]u64{}
		if readfds != 0 && !usercopy.copy_to_user(readfds, voidptr(&empty_result[0]), words * sizeof(u64)) {
			return errno.err, errno.efault
		}
		if writefds != 0 && !usercopy.copy_to_user(writefds, voidptr(&empty_result[0]), words * sizeof(u64)) {
			return errno.err, errno.efault
		}
		if exceptfds != 0 && !usercopy.copy_to_user(exceptfds, voidptr(&empty_result[0]), words * sizeof(u64)) {
			return errno.err, errno.efault
		}
		return 0, 0
	}

	mut remaining := unsafe { &time.TimeSpec(C.vinix_stack_alloc(sizeof(time.TimeSpec))) }
	unsafe { *remaining = deadline }
	mut timeout_ptr := &time.TimeSpec(unsafe { nil })
	if timed {
		// ppoll consumes this synchronously. An ordinary local whose address
		// escapes is heap-promoted by V even through unsafe, losing 16 bytes.
		timeout_ptr = remaining
	}

	ready, err := ppoll(unsafe { &polls[0] }, u64(polls.len), timeout_ptr, unsafe { nil })
	if err != 0 {
		return ready, err
	}

	mut got_read := [fd_set_words]u64{}
	mut got_write := [fd_set_words]u64{}
	mut got_except := [fd_set_words]u64{}
	mut count := u64(0)

	// Linux counts ready bits across all three sets, including when one
	// descriptor appears in more than one returned set.
	// An open O_PATH handle, or a close after slot validation, can produce
	// POLLNVAL from ppoll. Linux select reports it in every requested set.
	for i := 0; i < polls.len; i++ {
		revents := polls[i].revents
		fd := indexes[i]

		// An error or a hangup makes a descriptor readable as far as select is
		// concerned, so that the caller goes and finds out what happened.
		if revents & i16(pollin | pollhup | pollerr | pollnval) != 0 && is_set(want_read, fd) {
			set_bit(mut got_read, fd)
			count++
		}
		if revents & i16(pollout | pollerr | pollnval) != 0 && is_set(want_write, fd) {
			set_bit(mut got_write, fd)
			count++
		}
		if revents & i16(pollpri | pollnval) != 0 && is_set(want_except, fd) {
			set_bit(mut got_except, fd)
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
