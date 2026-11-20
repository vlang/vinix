// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

import errno
import file
import posixtimer
import proc
import resource
import usercopy

pub fn syscall_pidfd_open(_ voidptr, pid i32, flags u32) (u64, u64) {
	if pid <= 0 || flags & ~u32(resource.o_nonblock) != 0 {
		return errno.err, errno.einval
	}
	mut res := proc.pin_pidfd(int(pid)) or { return errno.err, errno.get() }
	defer { resource.release_resource(mut res) }
	fd := file.fdnum_create_from_resource(unsafe { nil }, mut res,
		resource.o_rdwr | resource.o_cloexec | int(flags), 0, false) or {
		return errno.err, errno.get()
	}
	return u64(fd), 0
}

fn may_signal_pidfd(caller &proc.Process, target &proc.Process, signal int) bool {
	if !proc.mac_peer_allowed(caller, target) { return false }
	user_ns := proc.user_namespace_id(caller)
	target_ns := proc.user_namespace_id(target)
	if user_ns == target_ns && (caller.uid == target.uid || caller.uid == target.suid
		|| caller.euid == target.uid || caller.euid == target.suid) { return true }
	if signal == sigcont && caller.sid == target.sid { return true }
	return proc.has_capability(caller, proc.cap_kill)
		&& (user_ns == u64(4026531837) || user_ns == target_ns)
}

pub fn syscall_pidfd_send_signal(_ voidptr, fdnum i32, signal i32, info u64, flags u32) (u64, u64) {
	if flags != 0 || signal < 0 || signal > 64 { return errno.err, errno.einval }
	mut fd := file.fd_from_fdnum(unsafe { nil }, int(fdnum)) or { return errno.err, errno.ebadf }
	defer { fd.unref() }
	mut res := fd.handle.resource
	mut record := &proc.PidFile(unsafe { nil })
	if mut res is proc.PidFile { record = res } else { return errno.err, errno.ebadf }
	if info != 0 {
		mut supplied := [128]u8{}
		if !usercopy.copy_from_user(voidptr(&supplied[0]), info, u64(supplied.len)) {
			return errno.err, errno.efault
		}
		// Queued siginfo metadata needs a real signal-queue implementation.
		return errno.err, errno.enosys
	}
	// fd_from_fdnum has already released the descriptor-table lock. Keep the
	// lookup reference through authorization/delivery and drop it after both
	// these locks: final Resource release may itself take the process table.
	mut notify := &proc.Process(unsafe { nil })
	defer {
		if notify != unsafe { nil } { notify_signal_parent(notify); proc.unpin_process(notify) }
	}
	posixtimer.lock_signal_info()
	proc.lock_table()
	defer { proc.unlock_table(); posixtimer.unlock_signal_info() }
	mut target := proc.pidfd_target_locked(record)
	if target == unsafe { nil } { return errno.err, errno.esrch }
	caller := proc.current_thread().process
	if proc.pid_in(target, caller.numbered_in) == 0 { return errno.err, errno.einval }
	if !may_signal_pidfd(caller, target, int(signal)) { return errno.err, errno.eperm }
	if signal != 0 {
		_, changed := signal_process_locked(mut target, int(signal))
		if changed { proc.pin_process(target); notify = target }
	}
	// An unreaped zombie still has this identity, even with no thread left.
	return 0, 0
}

// pidfd_getfd(pidfd, targetfd, flags): a close-on-exec duplicate of another
// process's descriptor, sharing its open-file description. Linux requires
// ptrace's ATTACH_REALCREDS access, which without Yama is the credential and
// dumpability check READ_REALCREDS makes (kcmp's). Errors follow Linux:
// EINVAL for flags, EBADF for anything but a pidfd, ESRCH for a gone process,
// EPERM, ESRCH for an exiting one, then EBADF for the target and EMFILE.
pub fn syscall_pidfd_getfd(_ voidptr, pidfd_word u64, target_word u64, flags_word u64) (u64, u64) {
	if u32(flags_word) != 0 { return errno.err, errno.einval }
	mut fd := file.fd_from_fdnum(unsafe { nil }, int(i32(u32(pidfd_word)))) or {
		return errno.err, errno.ebadf
	}
	defer { fd.unref() }
	mut res := fd.handle.resource
	mut record := &proc.PidFile(unsafe { nil })
	if mut res is proc.PidFile { record = res } else { return errno.err, errno.ebadf }
	// A negative descriptor is a huge unsigned one, which no table has.
	target_fd := u32(target_word)
	for attempt := 0; attempt < kcmp_attempts; attempt++ {
		if attempt > 0 { kcmp_relax() }
		proc.lock_table()
		target := proc.pidfd_target_locked(record)
		if target == unsafe { nil } {
			proc.unlock_table()
			return errno.err, errno.esrch
		}
		// Linux checks access first, then reports a task whose descriptors are
		// gone, as an exiting one's are, as ESRCH.
		if !proc.may_inspect_realcreds_locked(target) {
			proc.unlock_table()
			return errno.err, errno.eperm
		}
		if target.exiting {
			proc.unlock_table()
			return errno.err, errno.esrch
		}
		mut taken, busy := kcmp_try_take(target, target_fd)
		proc.unlock_table()
		if busy { continue }
		if taken == unsafe { nil } { return errno.err, errno.ebadf }
		received := file.fdnum_receive(taken) or {
			// The last reference's release may set errno itself.
			code := errno.get()
			taken.unref()
			return errno.err, code
		}
		taken.unref()
		return u64(received), 0
	}
	return errno.err, errno.eagain
}
