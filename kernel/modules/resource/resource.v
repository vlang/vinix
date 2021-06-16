module resource

import stat
import klock

interface Resource {
mut:
	null     bool
	stat     stat.Stat
	refcount int
	l        klock.Lock

	read(buf voidptr, loc u64, count u64) i64
	write(buf voidptr, loc u64, count u64) i64
}

pub struct Dummy {
pub mut:
	null     bool
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
	null_resource Dummy
)

pub fn null() &Resource {
	null_resource.null = true
	return &null_resource
}

__global (
	dev_id_counter = u64(1)
)

pub fn create_dev_id() u64 {
	return dev_id_counter++
}
