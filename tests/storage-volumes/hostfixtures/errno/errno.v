@[has_globals]
module errno
__global host_errno_code int
pub const eperm=1
pub const eintr=4
pub const eio=5
pub const ebadf=9
pub const enomem=12
pub const efault=14
pub const ebusy=16
pub const eexist=17
pub const enodev=19
pub const einval=22
pub const enotty=25
pub const enospc=28
pub const erofs=30
pub const eoverflow=75
pub const eopnotsupp=95
pub fn set(value int) { host_errno_code=value }
pub fn get() int { return host_errno_code }
