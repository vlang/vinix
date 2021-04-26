module resource

import vfs
import klock

interface Resource {
	st       vfs.Stat
	refcount int
	l        klock.Lock

	read(buf voidptr, loc i64, count u64) i64
}
