module stat
pub struct Stat {
pub mut:
 mode u32
 rdev u64
 size i64
}
pub fn isblk(mode u32) bool { return mode & 0o170000 == 0o060000 }
