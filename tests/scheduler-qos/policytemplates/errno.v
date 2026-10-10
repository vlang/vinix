@[has_globals]
module errno
pub const edeadlk = 35
pub const eagain = 11
__global (last_error int)
pub fn set(value int) { last_error = value }
pub fn get() int { return last_error }
