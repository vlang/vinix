// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module proc

import errno
import event
import event.eventstruct
import katomic
import klock
import resource
import stat

// A process owns its identity until reap, and each open description/epoll
// snapshot owns another reference. Static storage survives Process teardown
// and gives low-memory callers a deliberate bound rather than a dangling pid.
pub const max_pidfd_identities = 1024
const pidfd_pollin = 0x01 | 0x40 // POLLIN | POLLRDNORM
const pidfd_pollhup = 0x10
const initial_user_namespace_id = u64(4026531837)

pub struct PidFile {
pub mut:
	stat stat.Stat
	refcount int
	l klock.Lock
	event eventstruct.Event
	status int
	can_mmap bool
	global_pid int
	cookie u64
	slot int
	box &resource.Resource = unsafe { nil }
}

__global (
	pid_files [max_pidfd_identities]PidFile
	pid_file_boxes [max_pidfd_identities]resource.Resource
	pid_file_used [max_pidfd_identities]bool
	pid_file_cookie = u64(0)
)

// The returned resource owns a temporary operation reference. The caller
// must release it after installing its descriptor, including failure paths.
pub fn pin_pidfd(local_pid int) ?&resource.Resource {
	lock_table()
	defer { unlock_table() }
	mut target := process_in(current_thread().process.numbered_in, local_pid)
	if target == unsafe { nil } || target.pid <= 0 || !target.pidfd_openable {
		errno.set(errno.esrch)
		return none
	}
	if target.pidfd_slot >= 0 {
		mut record := &pid_files[target.pidfd_slot]
		katomic.inc(mut &record.refcount)
		return record.box
	}
	for i in 0 .. max_pidfd_identities {
		if pid_file_used[i] { continue }
		if pid_file_cookie == u64(-1) { break }
		pid_file_cookie++
		pid_files[i] = PidFile{
			stat: stat.Stat{mode: stat.ifreg | 0o600, blksize: 4096, ino: pid_file_cookie}
			refcount: 2 // process owner and this operation
			global_pid: target.pid
			cookie: pid_file_cookie
			slot: i
			status: if target.exit_published { pidfd_pollin } else { 0 }
		}
		pid_file_boxes[i] = resource.Resource(unsafe { &pid_files[i] })
		pid_files[i].box = &pid_file_boxes[i]
		pid_file_used[i] = true
		target.pidfd_slot = i
		target.pidfd_cookie = pid_file_cookie
		return &pid_file_boxes[i]
	}
	errno.set(errno.enfile)
	return none
}

// The table lock stays held through first enqueue, after parent bookkeeping
// and user-copy setup. A pidfd signal must not enqueue and free the new thread
// before its creator gets to enqueue it.
pub fn publish_pidfd_identity_locked(mut target Process) {
	target.pidfd_openable = true
}

// Caller holds the table lock and a descriptor/resource reference. A cookie
// check keeps an old fd from targeting a process that reused its numeric pid.
pub fn pidfd_target_locked(record &PidFile) &Process {
	target := process_at(record.global_pid)
	if target == unsafe { nil } || target.pidfd_slot != record.slot
		|| target.pidfd_cookie != record.cookie { return unsafe { nil } }
	return target
}

pub fn user_namespace_id(target &Process) u64 {
	if target.ns.user != unsafe { nil } { return target.ns.user.id }
	if target.exit_user_ns != 0 { return target.exit_user_ns }
	return initial_user_namespace_id
}

pub fn save_pidfd_exit_identity(mut target Process) {
	lock_table()
	target.exit_user_ns = user_namespace_id(target)
	unlock_table()
}

// Publish only once every sibling is gone and group teardown is complete.
// The process-owner reference protects the event while waiters are woken.
pub fn publish_pidfd_exit(mut target Process, status int) {
	lock_table()
	defer { unlock_table() }
	katomic.store(mut &target.status, status)
	target.exit_published = true
	if target.pidfd_slot >= 0 {
		mut record := &pid_files[target.pidfd_slot]
		katomic.store(mut &record.status, pidfd_pollin)
		event.trigger(mut record.event, false)
	}
}

fn reap_pidfd_locked(mut target Process) {
	if target.pidfd_slot < 0 { return }
	mut record := &pid_files[target.pidfd_slot]
	// Exit and reap are distinct edges. Descriptors remain readable after
	// waitpid, with HUP identifying that there is no longer a target task.
	katomic.store(mut &record.status, pidfd_pollin | pidfd_pollhup)
	event.trigger(mut record.event, false)
	target.pidfd_slot = -1
	target.pidfd_cookie = 0
	if !katomic.dec(mut &record.refcount) { pid_file_used[record.slot] = false }
}

fn (mut this PidFile) unref(_handle voidptr) ? {
	lock_table()
	if !katomic.dec(mut &this.refcount) {
		// Every poll waiter retains its FD or resource until after event
		// detachment. Zero therefore permits reuse of both event and box.
		pid_file_used[this.slot] = false
	}
	unlock_table()
}

fn (mut this PidFile) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}
fn (mut this PidFile) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}
fn (mut this PidFile) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}
fn (mut this PidFile) mmap(_handle voidptr, _page u64, _flags int) voidptr { return unsafe { nil } }
fn (mut this PidFile) grow(_handle voidptr, _size u64) ? { errno.set(errno.einval); return none }
fn (mut this PidFile) link(_handle voidptr) ? { errno.set(errno.eperm); return none }
fn (mut this PidFile) unlink(_handle voidptr) ? { errno.set(errno.eperm); return none }
