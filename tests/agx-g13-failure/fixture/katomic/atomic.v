@[has_globals]
module katomic

__global barrier_count = u32(0)

pub fn load[T](value &T) T { return unsafe { *value } }

pub fn store[T](mut target T, value T) { target = value }

pub fn sync() { barrier_count++ }

pub fn barriers() u32 { return barrier_count }
