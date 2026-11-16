@[has_globals]
module errno

pub const einval = u64(22)
pub const enotty = u64(25)
pub const enomem = u64(12)
pub const emfile = u64(24)
pub const efault = u64(14)
pub const ebusy = u64(16)
pub const ebadf = u64(9)
__global last_error = u64(0)
pub fn set(value u64) { last_error = value }
pub fn get() u64 { return last_error }
