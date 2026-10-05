// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module security

import errno
import katomic
import klock
import lib
import limine
import proc

// OpenBSD's securelevel(7), kern.securelevel here at
// /proc/sys/kernel/securelevel:
//
// -1  permanently insecure: as 0, and init will not raise it.
//  0  insecure: no more than the usual permissions apply.
//  1  secure: a set immutable or append-only bit cannot be cleared, even by
//     root, so a sealed file stays sealed as long as the machine is multi-user.
//  2  highly secure: userspace cannot open or write block disks for writing,
//     including descriptions opened before the level was raised. Filesystem
//     writeback uses Resource directly and remains available.
//
// It can always be raised. Once it is above 0, only init, pid 1, can lower
// it, as OpenBSD's init does on its way to single-user mode. At 0 or -1 it
// can be set to -1. Root with CAP_SYS_ADMIN sets it, as it does the hostname,
// in the initial user namespace, so that a container's root cannot. A
// vinix.securelevel boot option additionally sets a floor which even init
// cannot lower. The bootloader and command line are not authenticated here.
//
// One aligned word, read and written whole on both architectures.
__global (
	current_securelevel    i32
	boot_securelevel_floor = i32(-1)
	securelevel_lock       klock.Lock
)

pub const lowest_securelevel = -1
pub const highest_securelevel = 2

pub fn securelevel() int {
	return int(katomic.load(&current_securelevel))
}

pub fn securelevel_floor() int {
	return int(boot_securelevel_floor)
}

// Called once, after runtime/console initialization and before SMP or any
// userspace process. Consume bootloader storage now: it is not retained.
pub fn initialise_boot_policy() {
	kernel_file := limine.kernel_file()
	if kernel_file == unsafe { nil } || kernel_file.cmdline == unsafe { nil } {
		return
	}
	bytes := unsafe { &u8(kernel_file.cmdline) }
	mut length := 0
	for length < securelevel_cmdline_max && unsafe { bytes[length] } != 0 {
		length++
	}
	if length == securelevel_cmdline_max {
		lib.kpanic(unsafe { nil }, c'security: boot command line exceeds limit')
		return
	}
	text := unsafe { tos(bytes, length) }
	level, valid := parse_securelevel_boot(text)
	if !valid {
		lib.kpanic(unsafe { nil }, c'security: invalid or duplicate vinix.securelevel boot policy')
		return
	}
	if level >= lowest_securelevel {
		boot_securelevel_floor = i32(level)
		katomic.store(mut &current_securelevel, i32(level))
		C.kprintf(c'security: boot securelevel floor %d\n', i32(level))
	}
}

// sysctl kern.securelevel=`level`, by the calling process.
pub fn set_securelevel(level int) ? {
	if level < lowest_securelevel || level > highest_securelevel {
		errno.set(errno.einval)
		return none
	}
	if !permitted(system_securelevel_set) {
		errno.set(errno.eperm)
		return none
	}
	securelevel_lock.acquire()
	defer { securelevel_lock.release() }
	current := securelevel()
	if level < securelevel_floor()
		|| (current > 0 && level < current && proc.current_thread().process.pid != 1) {
		errno.set(errno.eperm)
		return none
	}
	katomic.store(mut &current_securelevel, i32(level))
}
