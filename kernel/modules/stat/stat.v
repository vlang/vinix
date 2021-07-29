module stat

struct TimeSpec {
pub mut:
	tv_sec  i64
	tv_nsec i64
}

pub const ifmt   = 0xf000
pub const ifblk  = 0x6000
pub const ifchr  = 0x2000
pub const ififo  = 0x1000
pub const ifreg  = 0x8000
pub const ifdir  = 0x4000
pub const iflnk  = 0xa000
pub const ifsock = 0xc000
pub const ifpipe = 0x3000

pub fn isblk(mode int) bool { return (mode & ifmt) == ifblk }
pub fn ischr(mode int) bool { return (mode & ifmt) == ifchr }
pub fn isifo(mode int) bool { return (mode & ifmt) == ififo }
pub fn isreg(mode int) bool { return (mode & ifmt) == ifreg }
pub fn isdir(mode int) bool { return (mode & ifmt) == ifdir }
pub fn islnk(mode int) bool { return (mode & ifmt) == iflnk }
pub fn issock(mode int) bool { return (mode & ifmt) == ifsock }

pub struct Stat {
pub mut:
	dev     u64
	ino     u64
	mode    int
	nlink   int
	uid     int
	gid     int
	rdev    u64
	size    u64
	atim    TimeSpec
	mtim    TimeSpec
	ctim    TimeSpec
	blksize u64
	blocks  u64
}

pub const dt_unknown = 0
pub const dt_fifo = 1
pub const dt_chr = 2
pub const dt_dir = 4
pub const dt_blk = 6
pub const dt_reg = 8
pub const dt_lnk = 10
pub const dt_sock = 12
pub const dt_wht = 14

pub struct Dirent {
pub mut:
	ino    u64
	off    u64
	reclen u16
	@type  byte
	name   [1024]byte
}
