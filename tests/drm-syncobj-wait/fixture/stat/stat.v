module stat
pub const ifmt = 0xf000
pub const ififo = 0x1000
pub const ifchr = 0x2000
pub const ifreg = 0x8000
pub const ifsock = 0xc000
pub const ifpipe = 0x3000
pub struct Stat {
pub mut:
	mode int
	blksize i64
	size i64
	blocks i64
}
