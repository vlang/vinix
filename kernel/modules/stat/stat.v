module stat

import time

pub const ifmt   = 0o170000

pub const ifblk  = 0o060000
pub const ifchr  = 0o020000
pub const ififo  = 0o010000
pub const ifreg  = 0o100000
pub const ifdir  = 0o040000
pub const iflnk  = 0o120000
pub const ifsock = 0o140000

pub fn isblk(mode int) bool { return (mode & ifmt) == ifblk }
pub fn ischr(mode int) bool { return (mode & ifmt) == ifchr }
pub fn isfifo(mode int) bool { return (mode & ifmt) == ififo }
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
	pad1    u64
	size    u64
	blksize u64
	blocks  u64
	atim    time.TimeSpec
	mtim    time.TimeSpec
	ctim    time.TimeSpec
	pad2    int
	pad3    int
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
