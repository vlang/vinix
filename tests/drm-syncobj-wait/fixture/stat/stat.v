module stat
pub const ifmt = 0xf000
pub const ififo = 0x1000
pub const ifchr = 0x2000
pub const ifreg = 0x8000
pub const ifsock = 0xc000
pub const ifpipe = 0x3000
pub const ifdir = 0x4000

pub fn isreg(mode int) bool { return (mode & ifmt) == ifreg }
pub fn isdir(mode int) bool { return (mode & ifmt) == ifdir }
pub struct Stat {
pub mut:
	dev u64
	ino u64
	mode int
	blksize i64
	size i64
	blocks i64
}
