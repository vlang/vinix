module stat
pub const ifblk = u32(0o60000)
pub struct Stat { pub mut: size i64 blksize i64 blocks i64 mode u32 rdev u64 nlink u64 }
pub fn isblk(mode u32) bool { return mode & 0o170000 == ifblk }
