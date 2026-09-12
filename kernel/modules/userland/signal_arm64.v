// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

// Linux signal syscalls: disposition, masking, and the two ways a thread can
// wait for a signal (rt_sigsuspend, rt_sigtimedwait) plus the alternate stack
// handlers can run on.

import errno
import event
import event.eventstruct
import katomic
import posixtimer
import proc
import time
import usercopy

// Signal N occupies bit N-1 of the pending and blocked words, so all 64 of them
// fit in a u64.
const max_signal = 64

// A sigset_t is one 64-bit word on aarch64; the kernel rejects any other size.
const sigset_size = u64(8)

// struct k_sigaction as the raw syscall sees it: handler, flags, restorer, mask.
const sa_handler_offset = u64(0)

const sa_flags_offset = u64(8)

const sa_restorer_offset = u64(16)

const sa_mask_offset = u64(24)

const k_sigaction_size = u64(32)

// stack_t: void *ss_sp; int ss_flags; size_t ss_size.
const stack_t_size = u64(24)

const ss_onstack = 1

const ss_disable = 2

// Small enough to accept whatever a libc hands us, large enough that a handler
// has somewhere to stand.
const min_sigstack_size = u64(2048)

// Signals that can never be blocked, caught or ignored.
fn unblockable_mask() u64 {
	return signal_bit(sigkill) | signal_bit(sigstop)
}

fn signal_bit(signum int) u64 {
	return u64(1) << u64(signum - 1)
}

fn valid_signal(signum int) bool {
	return signum > 0 && signum <= max_signal
}

// ── disposition and masking ──────────────────────────────────────────────────

// rt_sigaction(signum, act, oldact, sigsetsize).
pub fn syscall_rt_sigaction(_ voidptr, signum int, act_ptr u64, oldact_ptr u64, sigsetsize u64) (u64, u64) {
	if !valid_signal(signum) || signum == sigkill || signum == sigstop {
		return errno.err, errno.einval
	}
	if sigsetsize != sigset_size {
		return errno.err, errno.einval
	}

	mut current_thread := proc.current_thread()

	// Read the new disposition before publishing the old one, so a faulting
	// `act` leaves the disposition untouched.
	mut incoming := proc.SigAction{}
	if act_ptr != 0 {
		mut raw := [4]u64{}
		if !usercopy.copy_from_user(voidptr(&raw[0]), act_ptr, k_sigaction_size) {
			return errno.err, errno.efault
		}
		incoming = proc.SigAction{
			sa_sigaction: voidptr(raw[0])
			sa_flags:     int(raw[1])
			sa_restorer:  voidptr(raw[2])
			sa_mask:      raw[3] & ~unblockable_mask()
		}
	}

	if oldact_ptr != 0 {
		previous := current_thread.sigactions[signum]
		mut raw := [4]u64{}
		raw[0] = u64(previous.sa_sigaction)
		raw[1] = u64(u32(previous.sa_flags))
		// The restorer has to survive a save/restore round trip: it is the only
		// way back out of a Linux-style handler, so dropping it here would
		// wedge the next signal the caller re-installs this action for.
		raw[2] = u64(previous.sa_restorer)
		raw[3] = previous.sa_mask
		if !usercopy.copy_to_user(oldact_ptr, voidptr(&raw[0]), k_sigaction_size) {
			return errno.err, errno.efault
		}
	}

	if act_ptr != 0 {
		// Linux shares signal dispositions across every thread in a process.
		// Musl installs its dynamic-TLS barrier handler after worker threads may
		// already exist, so updating only the caller deadlocks GTK applications.
		mut process := current_thread.process
		process.threads_lock.acquire()
		for mut target_thread in process.threads {
			target_thread.sigactions[signum] = incoming
		}
		process.threads_lock.release()
	}

	return 0, 0
}

// rt_sigprocmask(how, set, oldset, sigsetsize).
pub fn syscall_rt_sigprocmask(_ voidptr, how int, set_ptr u64, oldset_ptr u64, sigsetsize u64) (u64, u64) {
	if sigsetsize != sigset_size {
		return errno.err, errno.einval
	}

	mut current_thread := proc.current_thread()

	mut incoming := u64(0)
	if set_ptr != 0 {
		if !usercopy.copy_from_user(voidptr(&incoming), set_ptr, sigset_size) {
			return errno.err, errno.efault
		}
		if how != sig_block && how != sig_unblock && how != sig_setmask {
			return errno.err, errno.einval
		}
	}

	if oldset_ptr != 0 {
		previous := current_thread.masked_signals
		if !usercopy.copy_to_user(oldset_ptr, voidptr(&previous), sigset_size) {
			return errno.err, errno.efault
		}
	}

	if set_ptr != 0 {
		mut mask := current_thread.masked_signals
		match how {
			sig_block { mask |= incoming }
			sig_unblock { mask &= ~incoming }
			else { mask = incoming }
		}
		// SIGKILL and SIGSTOP are never blockable, whatever was asked for.
		current_thread.masked_signals = mask & ~unblockable_mask()
	}

	return 0, 0
}

// ── waiting for a signal ─────────────────────────────────────────────────────

// True once a signal outside `mask` is pending, i.e. something that would be
// delivered as soon as we return to userspace.
fn deliverable_signal(t &proc.Thread, mask u64) bool {
	return katomic.load(&t.pending_signals) & ~mask != 0
}

// Sleep until a signal wakes us. Any sendsig() puts the thread back on the run
// queue and marks the wakeup as signal-driven, which is what ends the await.
fn sleep_for_signal(timeout &time.TimeSpec) bool {
	mut events := []&eventstruct.Event{}
	defer {
		unsafe { events.free() }
	}

	mut timer := &time.Timer(unsafe { nil })
	if timeout != unsafe { nil } {
		timer = time.new_timer(*timeout)
		events << &timer.event
	}

	defer {
		if timer != unsafe { nil } {
			timer.disarm()
			unsafe { free(timer) }
		}
	}

	// A signal makes await() report an interruption; the timer firing makes it
	// report which event woke it.
	event.await(mut events, true) or { return true }
	return false
}

// rt_sigsuspend(mask, sigsetsize): swap in a temporary mask, wait for something
// to get through it, and leave the original mask for the handler's sigreturn to
// put back.
pub fn syscall_rt_sigsuspend(_ voidptr, mask_ptr u64, sigsetsize u64) (u64, u64) {
	if sigsetsize != sigset_size {
		return errno.err, errno.einval
	}

	mut current_thread := proc.current_thread()

	mut temporary := u64(0)
	if !usercopy.copy_from_user(voidptr(&temporary), mask_ptr, sigset_size) {
		return errno.err, errno.efault
	}
	temporary &= ~unblockable_mask()

	original := current_thread.masked_signals
	current_thread.masked_signals = temporary

	for !deliverable_signal(current_thread, temporary) {
		sleep_for_signal(unsafe { nil })
	}

	// dispatch_a_signal() runs on the way out of this syscall and must record
	// the pre-suspend mask in the handler's frame. If nothing is going to be
	// dispatched after all, put the mask back here instead.
	current_thread.saved_mask = original
	current_thread.saved_mask_valid = true
	if !has_handler_for_pending(current_thread, temporary) {
		current_thread.masked_signals = original
		current_thread.saved_mask_valid = false
	}

	return errno.err, errno.eintr
}

// Whether the pending signal that got through `mask` has a real handler, as
// opposed to a default or ignored disposition that dispatch will drop.
fn has_handler_for_pending(t &proc.Thread, mask u64) bool {
	pending := katomic.load(&t.pending_signals) & ~mask
	for signum := 1; signum <= max_signal; signum++ {
		if pending & signal_bit(signum) == 0 {
			continue
		}
		handler := t.sigactions[signum].sa_sigaction
		if handler != sig_dfl && handler != sig_ign {
			return true
		}
	}
	return false
}

// rt_sigtimedwait(set, info, timeout, sigsetsize): consume one of `set`
// synchronously rather than letting it run a handler.
pub fn syscall_rt_sigtimedwait(_ voidptr, set_ptr u64, info_ptr u64, timeout_ptr u64, sigsetsize u64) (u64, u64) {
	if sigsetsize != sigset_size {
		return errno.err, errno.einval
	}

	mut current_thread := proc.current_thread()

	mut wanted := u64(0)
	if !usercopy.copy_from_user(voidptr(&wanted), set_ptr, sigset_size) {
		return errno.err, errno.efault
	}
	wanted &= ~unblockable_mask()

	mut deadline := time.TimeSpec{}
	mut timed := false
	if timeout_ptr != 0 {
		if !usercopy.copy_from_user(voidptr(&deadline), timeout_ptr, sizeof(time.TimeSpec)) {
			return errno.err, errno.efault
		}
		if deadline.tv_sec < 0 || deadline.tv_nsec < 0 || deadline.tv_nsec >= 1000000000 {
			return errno.err, errno.einval
		}
		timed = true
	}

	for {
		if which := take_pending(mut current_thread, wanted) {
			if info_ptr != 0 && !write_signal_info(info_ptr, current_thread, which) {
				// Hand the signal back rather than losing it.
				katomic.bts(mut &current_thread.pending_signals, u8(which - 1))
				return errno.err, errno.efault
			}
			posixtimer.acknowledge_signal(mut current_thread, which)
			return u64(which), 0
		}

		if timed && deadline.tv_sec == 0 && deadline.tv_nsec == 0 {
			return errno.err, errno.eagain
		}

		// Anything outside the requested set is a real interruption.
		if deliverable_signal(current_thread, current_thread.masked_signals | wanted) {
			return errno.err, errno.eintr
		}

		if timed {
			if sleep_for_signal(&deadline) == false {
				// The timer, not a signal, ended the wait.
				timed = true
				deadline = time.TimeSpec{}
				continue
			}
		} else {
			sleep_for_signal(unsafe { nil })
		}
	}

	return errno.err, errno.eagain
}

// Claim the lowest-numbered pending signal that is in `wanted`.
fn take_pending(mut t proc.Thread, wanted u64) ?int {
	for signum := 1; signum <= max_signal; signum++ {
		if wanted & signal_bit(signum) == 0 {
			continue
		}
		if katomic.btr(mut &t.pending_signals, u8(signum - 1)) == true {
			return signum
		}
	}
	return none
}

// The 128-byte siginfo_t for a synchronously accepted signal. Ordinary signals
// use SI_USER; POSIX timers retain SI_TIMER, their value, and overrun count.
fn write_signal_info(info_ptr u64, thrd &proc.Thread, signum int) bool {
	mut raw := [16]u64{}
	timer_info := posixtimer.signal_info(thrd, signum)
	unsafe {
		mut words := &u32(&raw[0])
		words[0] = u32(signum) // si_signo
		words[1] = 0 // si_errno
		words[2] = u32(timer_info.code) // SI_USER or SI_TIMER
		if timer_info.found {
			words[5] = u32(timer_info.overrun) // si_overrun
			*&u64(u64(&raw[0]) + 24) = timer_info.value // si_value
		}
	}
	return usercopy.copy_to_user(info_ptr, voidptr(&raw[0]), 128)
}

// ── alternate signal stack ───────────────────────────────────────────────────

// sigaltstack(ss, old_ss).
pub fn syscall_sigaltstack(_ voidptr, ss_ptr u64, old_ss_ptr u64) (u64, u64) {
	mut current_thread := proc.current_thread()

	// Read the new stack first: a faulting `ss` must leave the old one in place.
	mut incoming_sp := u64(0)
	mut incoming_size := u64(0)
	mut disabling := false
	if ss_ptr != 0 {
		// Changing the alternate stack while running on it would pull the rug
		// out from under the handler.
		if current_thread.on_sigaltstack {
			return errno.err, errno.eperm
		}

		mut raw := [3]u64{}
		if !usercopy.copy_from_user(voidptr(&raw[0]), ss_ptr, stack_t_size) {
			return errno.err, errno.efault
		}
		flags := int(u32(raw[1]))
		if flags & ~ss_disable != 0 {
			return errno.err, errno.einval
		}

		disabling = flags & ss_disable != 0
		if !disabling {
			if raw[2] < min_sigstack_size {
				return errno.err, errno.enomem
			}
			incoming_sp = raw[0]
			incoming_size = raw[2]
		}
	}

	if old_ss_ptr != 0 {
		mut raw := [3]u64{}
		raw[0] = current_thread.sigaltstack_sp
		raw[1] = if current_thread.on_sigaltstack {
			u64(ss_onstack)
		} else if current_thread.sigaltstack_size == 0 {
			u64(ss_disable)
		} else {
			u64(0)
		}
		raw[2] = current_thread.sigaltstack_size
		if !usercopy.copy_to_user(old_ss_ptr, voidptr(&raw[0]), stack_t_size) {
			return errno.err, errno.efault
		}
	}

	if ss_ptr != 0 {
		if disabling {
			current_thread.sigaltstack_sp = 0
			current_thread.sigaltstack_size = 0
		} else {
			current_thread.sigaltstack_sp = incoming_sp
			current_thread.sigaltstack_size = incoming_size
		}
	}

	return 0, 0
}

// Kept so the arm64 build still has a definition for the mlibc-shaped entry
// point the Vinix-native table used; the Linux table routes 134/135 to the
// rt_ variants above.
pub fn syscall_sigaction(_ voidptr, signum int, act &proc.SigAction, oldact &proc.SigAction) (u64, u64) {
	if !valid_signal(signum) || signum == sigkill || signum == sigstop {
		return errno.err, errno.einval
	}

	mut current_thread := proc.current_thread()

	if oldact != unsafe { nil } {
		unsafe {
			*oldact = current_thread.sigactions[signum]
		}
	}
	if act != unsafe { nil } {
		mut process := current_thread.process
		process.threads_lock.acquire()
		for mut target_thread in process.threads {
			target_thread.sigactions[signum] = *act
		}
		process.threads_lock.release()
	}

	return 0, 0
}
