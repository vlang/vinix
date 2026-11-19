@[has_globals]
module errno

pub const einval = u64(22)
pub const enodev = u64(19)
pub const enomem = u64(12)
pub const efault = u64(14)
pub const eexist = u64(17)
pub const enotdir = u64(20)

__global last_error = u64(0)

pub fn set(value u64) { last_error = value }

pub fn get() u64 { return last_error }
