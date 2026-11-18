module stat
pub const ifchr = 0x2000
pub const ifreg = 0x8000
pub struct Stat {
pub mut:
	mode int
	blksize i64
	size i64
	blocks i64
}
