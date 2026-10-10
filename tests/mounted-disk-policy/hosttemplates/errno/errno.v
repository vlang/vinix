@[has_globals]
module errno
__global ( saved int )
pub const eperm = 1
pub const enodev = 19
pub const ebusy = 16
pub const eoverflow = 75
pub fn set(value int) { saved = value }
pub fn get() int { return saved }
