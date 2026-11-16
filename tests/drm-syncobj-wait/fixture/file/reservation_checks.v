// SPDX-License-Identifier: GPL-2.0-or-later
module file

import errno
import proc

pub fn run_fd_reservation_checks() {
	mut checks := 0
	for _ in 0 .. 200 {
		proc.reset()
		mut process := proc.current_thread().process
		mut nodes := [8]FdReservation{}
		for index in 0 .. 8 {
			assert (reserve_fd(process, unsafe { &nodes[index] }) or { panic('reserve') }) == index; checks++
			if _ := fd_from_fdnum(process, index) { assert false }; checks++
			if _ := fdnum_close(process, index, true) { assert false }; checks++
			assert errno.get() == errno.ebadf
		}
		assert_reservations(8)
		if _ := reserve_fd(process, unsafe { &nodes[0] }) { assert false }; checks++
		assert errno.get() == errno.ebusy
		// These stack descriptions are borrowed fixture values. They exercise
		// table adoption only; clear the slots before leaving their scope.
		mut first := FD{ handle: unsafe { nil } }
		mut second := FD{ handle: unsafe { nil } }
		mut blocked := FD{ handle: unsafe { nil }, blocked: true }
		assert (fdnum_create_from_fd(process, unsafe { &first }, 0, false) or { panic('create') }) == 8; checks++
		if _ := fdnum_create_from_fd(process, unsafe { &second }, 2, true) { assert false }; checks++
		assert errno.get() == errno.ebusy && process.fds[2] == unsafe { nil }
		mut pair := [i32(-1), -1]!
		assert fdnum_create_pair(process, unsafe { &first }, unsafe { &second }, unsafe { &pair[0] }); checks++
		assert pair == [i32(9), 10]!
		for index in [3, 7, 0]! { cancel_fd_reservation(unsafe { &nodes[index] }); checks++ }
		assert_reservations(5)
		assert (reserve_fd(process, unsafe { &nodes[3] }) or { panic('reuse') }) == 0; checks++
		assert (fdnum_install_reserved_fd(unsafe { &nodes[2] }, unsafe { &second }) or { panic('install') }) == 2; checks++
		assert nodes[2].process == unsafe { nil } && nodes[2].next == unsafe { nil } && nodes[2].number == -1
		if _ := fdnum_install_reserved_fd(unsafe { &nodes[4] }, unsafe { &blocked }) { assert false }; checks++
		assert errno.get() == errno.ebusy
		assert_reservations(5)
		for index in 0 .. 8 { cancel_fd_reservation(unsafe { &nodes[index] }); cancel_fd_reservation(unsafe { &nodes[index] }); checks++ }
		assert_reservations(0)
		for index, value in process.fds {
			if value != unsafe { nil } { assert value == voidptr(unsafe { &first }) || value == voidptr(unsafe { &second }) }
			process.fds[index] = unsafe { nil }
		}
		// Growth failure cannot publish a node. Exhaustion counts invisible
		// reservations, and a later lowered limit cannot revoke an owned slot.
		proc.reset(); process = proc.current_thread().process
		mut all := [32]FdReservation{}
		for index in 0 .. 4 { assert (reserve_fd(process, unsafe { &all[index] }) or { panic('initial') }) == index; checks++ }
		fail_growth()
		if _ := reserve_fd(process, unsafe { &all[4] }) { assert false }; checks++
		assert errno.get() == errno.enomem && all[4].process == unsafe { nil }
		assert_reservations(4)
		for index in 4 .. 32 { assert (reserve_fd(process, unsafe { &all[index] }) or { panic('exhaust') }) == index; checks++ }
		mut overflow := FdReservation{}
		if _ := reserve_fd(process, unsafe { &overflow }) { assert false }; checks++
		assert errno.get() == errno.emfile
		if _ := fdnum_create_from_fd(process, unsafe { &first }, 0, false) { assert false }; checks++
		assert errno.get() == errno.emfile
		pair = [i32(-1), -1]!
		assert !fdnum_create_pair(process, unsafe { &first }, unsafe { &second }, unsafe { &pair[0] }); checks++
		assert pair == [i32(-1), -1]!
		process.rlimits[proc.rlimit_nofile].cur = 1
		assert (fdnum_install_reserved_fd(unsafe { &all[31] }, unsafe { &first }) or { panic('lowered limit') }) == 31; checks++
		for index in 0 .. 32 { cancel_fd_reservation(unsafe { &all[index] }) }
		assert_reservations(0)
		process.fds[31] = unsafe { nil }
		proc.reset()
	}
	println('FD reservations: ${checks} checks; invisible slots, head/middle/tail unlink, active-node rejection, reuse/install/cancel, competing create/dup/pair, growth failure, exhaustion and lowered-limit installation passed')
}
