// resource.v: Default resource management.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module resource

import stat
import klock
import ioctl
import errno
import event.eventstruct

pub const o_path = 0o10000000

pub const o_accmode = (0o03 | o_path)
pub const o_exec = o_path
pub const o_rdonly = 0o00
pub const o_rdwr = 0o02
pub const o_search = o_path
pub const o_wronly = 0o01
pub const o_append = 0o2000
pub const o_creat = 0o100
pub const o_directory = 0o200000
pub const o_excl = 0o200
pub const o_noctty = 0o400
pub const o_nofollow = 0o400000
pub const o_trunc = 0o1000
pub const o_nonblock = 0o4000
pub const o_dsync = 0o10000
pub const o_rsync = 0o4010000
pub const o_sync = 0o4010000
pub const o_cloexec = 0o2000000

pub const file_creation_flags_mask = o_creat | o_directory | o_excl | o_noctty | o_nofollow | o_trunc
pub const file_descriptor_flags_mask = o_cloexec
pub const file_status_flags_mask = ~(file_creation_flags_mask | file_descriptor_flags_mask)

pub interface Resource {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	grow(handle voidptr, new_size u64) ?
	read(handle voidptr, buf voidptr, loc u64, count u64) ?i64
	write(handle voidptr, buf voidptr, loc u64, count u64) ?i64
	ioctl(handle voidptr, request u64, argp voidptr) ?int
	unref(handle voidptr) ?
	link(handle voidptr) ?
	unlink(handle voidptr) ?
	mmap(page u64, flags int) voidptr
}

__global (
	dev_id_counter = u64(1)
)

pub fn create_dev_id() u64 {
	return dev_id_counter++
}

pub fn default_ioctl(handle voidptr, request u64, _ voidptr) ?int {
	match request {
		ioctl.tcgets, ioctl.tcsets, ioctl.tiocsctty, ioctl.tiocgwinsz {
			errno.set(errno.enotty)
			return none
		}
		else {
			errno.set(errno.einval)
			return none
		}
	}
}
