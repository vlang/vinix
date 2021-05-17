module resource

import stat
import klock

interface Resource {
	stat     stat.Stat
	refcount int
	l        klock.Lock

	read(buf voidptr, loc i64, count u64) i64
}

pub struct Dummy {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
}

fn (this Dummy) read(buf voidptr, loc i64, count u64) i64 {
	return 0
}
