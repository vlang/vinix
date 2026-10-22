@[has_globals]
module errno

__global current_error u64

pub const einval = u64(22)
pub const eio = u64(5)
pub const enomem = u64(12)
pub const enodev = u64(19)
pub const enotdir = u64(20)
pub const enospc = u64(28)
pub const enoent = u64(2)
pub const eoverflow = u64(75)
pub const enotsup = u64(95)
pub const exdev = u64(18)
pub const eisdir = u64(21)
pub const efault = u64(14)
pub const efbig = u64(27)
pub const ebusy = u64(16)
pub const eexist = u64(17)

pub fn set(code u64) { current_error = code }

pub fn get() u64 { return current_error }
