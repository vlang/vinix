module resource

import stat
import klock

interface Resource {
	st       stat.Stat
	refcount int
	l        klock.Lock

	read(buf voidptr, loc i64, count u64) i64
}
