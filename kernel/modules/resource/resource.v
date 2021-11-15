module resource

import stat
import klock
import ioctl
import errno
import event.eventstruct

pub const (
	o_accmode = 0x0007
	o_exec = 1
	o_rdonly = 2
	o_rdwr = 3
	o_search = 4
	o_wronly = 5
	o_append = 0x0008
	o_creat = 0x0010
	o_directory = 0x0020
	o_excl = 0x0040
	o_noctty = 0x0080
	o_nofollow = 0x0100
	o_trunc = 0x0200
	o_nonblock = 0x0400
	o_dsync = 0x0800
	o_rsync = 0x1000
	o_sync = 0x2000
	o_cloexec = 0x4000

	file_creation_flags_mask = o_creat | o_directory | o_excl | o_noctty | o_nofollow | o_trunc
	file_descriptor_flags_mask = o_cloexec
	file_status_flags_mask = ~(file_creation_flags_mask | file_descriptor_flags_mask)
)

pub interface Resource {
mut:
	stat stat.Stat
	refcount int
	l klock.Lock
	event eventstruct.Event
	status int
	can_mmap bool
	grow(handle voidptr, new_size u64) ?
	read(handle voidptr, buf voidptr, loc u64, count u64) ?i64
	write(handle voidptr, buf voidptr, loc u64, count u64) ?i64
	ioctl(handle voidptr, request u64, argp voidptr) ?int
	unref(handle voidptr) ?
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
