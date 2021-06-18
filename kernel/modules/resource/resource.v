module resource

import stat
import klock

pub const o_accmode = 0x0007
pub const o_exec    = 1
pub const o_rdonly  = 2
pub const o_rdwr    = 3
pub const o_search  = 4
pub const o_wronly  = 5

pub const o_append    = 0x0008
pub const o_creat     = 0x0010
pub const o_directory = 0x0020
pub const o_excl      = 0x0040
pub const o_noctty    = 0x0080
pub const o_nofollow  = 0x0100
pub const o_trunc     = 0x0200
pub const o_nonblock  = 0x0400
pub const o_dsync     = 0x0800
pub const o_rsync     = 0x1000
pub const o_sync      = 0x2000
pub const o_cloexec   = 0x4000

pub const file_creation_flags_mask = o_creat | o_directory | o_excl | o_noctty |
									 o_nofollow | o_trunc

pub const file_descriptor_flags_mask = o_cloexec

pub const file_status_flags_mask = ~(file_creation_flags_mask | file_descriptor_flags_mask)

interface Resource {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock

	read(buf voidptr, loc u64, count u64) i64
	write(buf voidptr, loc u64, count u64) i64
}

pub struct Dummy {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
}

fn (this Dummy) read(buf voidptr, loc u64, count u64) i64 {
	return -1
}

fn (this Dummy) write(buf voidptr, loc u64, count u64) i64 {
	return -1
}

__global (
	dev_id_counter = u64(1)
)

pub fn create_dev_id() u64 {
	return dev_id_counter++
}
