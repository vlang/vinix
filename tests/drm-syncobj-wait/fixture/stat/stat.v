module stat
pub const ifchr = 0x2000
pub struct Stat {
pub mut:
	mode int
	blksize int
}
