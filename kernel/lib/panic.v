@[has_globals]
module lib

import katomic as _
import klock

__global (
	kpanic_lock klock.Lock
)

fn C.printf_panic(charptr, ...voidptr)
