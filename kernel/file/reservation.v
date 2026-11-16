// SPDX-License-Identifier: GPL-2.0-or-later
module file

import errno
import proc
import resource

// A caller owns this node until installation or cancellation. Keep it at a
// stable address and defer cancel_fd_reservation before returning. Only that
// caller may install/cancel/reuse the node; other table users see its number
// under fds_lock, never the caller's stack through a descriptor lookup.
pub struct FdReservation {
mut:
	process &proc.Process = unsafe { nil }
	number int = -1
	next &FdReservation = unsafe { nil }
}

fn fd_number_reserved_locked(process &proc.Process, number int) bool {
	mut node := unsafe { &FdReservation(process.fds_reserved) }
	for node != unsafe { nil } {
		if node.number == number { return true }
		node = unsafe { node.next }
	}
	return false
}

pub fn reserve_fd(_process &proc.Process, reservation &FdReservation) ?int {
	if reservation == unsafe { nil } { errno.set(errno.einval); return none }
	mut node := unsafe { reservation }
	if node.process != unsafe { nil } { errno.set(errno.ebusy); return none }
	mut process := if _process == unsafe { nil } { proc.current_thread().process } else { unsafe { _process } }
	process.fds_lock.acquire()
	defer { process.fds_lock.release() }
	limit := if process.rlimits[proc.rlimit_nofile].cur < u64(proc.max_fds) {
		int(process.rlimits[proc.rlimit_nofile].cur)
	} else { proc.max_fds }
	for number in 0 .. limit {
		if number < process.fds.len && process.fds[number] != unsafe { nil } { continue }
		if fd_number_reserved_locked(process, number) { continue }
		if number >= process.fds.len && !grow_fd_table(mut process, number) {
			errno.set(errno.enomem); return none
		}
		node.process = process
		node.number = number
		node.next = unsafe { &FdReservation(process.fds_reserved) }
		process.fds_reserved = voidptr(reservation)
		return number
	}
	errno.set(errno.emfile)
	return none
}

// Caller holds the owning table lock. Clear every borrowed link before the
// caller can leave its scope. Installation and cancellation share this path.
fn remove_fd_reservation_locked(process &proc.Process, reservation &FdReservation) bool {
	mut target := unsafe { process }
	mut node := unsafe { &FdReservation(target.fds_reserved) }
	mut previous := &FdReservation(unsafe { nil })
	for node != unsafe { nil } {
		if voidptr(node) == voidptr(reservation) {
			if previous == unsafe { nil } { target.fds_reserved = voidptr(node.next) }
			else { previous.next = node.next }
			node.process = unsafe { nil }; node.number = -1; node.next = unsafe { nil }
			return true
		}
		previous = node; node = unsafe { node.next }
	}
	return false
}

pub fn cancel_fd_reservation(reservation &FdReservation) {
	if reservation == unsafe { nil } || reservation.process == unsafe { nil } { return }
	mut process := unsafe { reservation.process }
	process.fds_lock.acquire()
	defer { process.fds_lock.release() }
	remove_fd_reservation_locked(process, reservation)
}

// Success adopts the caller's FD reference; failure leaves both the FD and
// reservation owned by the caller. No number search or allocation occurs here.
pub fn fdnum_install_reserved_fd(reservation &FdReservation, fd &FD) ?int {
	if reservation == unsafe { nil } || reservation.process == unsafe { nil } || fd == unsafe { nil } {
		errno.set(errno.einval); return none
	}
	mut process := unsafe { reservation.process }
	process.fds_lock.acquire()
	defer { process.fds_lock.release() }
	number := reservation.number
	if number < 0 || number >= process.fds.len || process.fds[number] != unsafe { nil }
		|| !fd_number_reserved_locked(process, number) { errno.set(errno.einval); return none }
	if !descriptor_mount_admitted(fd) { errno.set(errno.ebusy); return none }
	if !remove_fd_reservation_locked(process, reservation) { errno.set(errno.einval); return none }
	process.fds[number] = voidptr(fd)
	return number
}

pub fn fdnum_create_from_reserved_resource(reservation &FdReservation, mut res resource.Resource, flags int) ?int {
	mut fd := fd_create_from_resource(mut res, flags) or { return none }
	return fdnum_install_reserved_fd(reservation, fd) or { fd.unref(); return none }
}
