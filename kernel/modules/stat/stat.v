// stat.v: Stat implementation.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module stat

import time

pub const (
	ifmt   = 0xf000
	ifblk  = 0x6000
	ifchr  = 0x2000
	ififo  = 0x1000
	ifreg  = 0x8000
	ifdir  = 0x4000
	iflnk  = 0xa000
	ifsock = 0xc000
	ifpipe = 0x3000
)

pub fn isblk(mode int) bool {
	return (mode & stat.ifmt) == stat.ifblk
}

pub fn ischr(mode int) bool {
	return (mode & stat.ifmt) == stat.ifchr
}

pub fn isifo(mode int) bool {
	return (mode & stat.ifmt) == stat.ififo
}

pub fn isreg(mode int) bool {
	return (mode & stat.ifmt) == stat.ifreg
}

pub fn isdir(mode int) bool {
	return (mode & stat.ifmt) == stat.ifdir
}

pub fn islnk(mode int) bool {
	return (mode & stat.ifmt) == stat.iflnk
}

pub fn issock(mode int) bool {
	return (mode & stat.ifmt) == stat.ifsock
}

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
	atim    time.TimeSpec
	mtim    time.TimeSpec
	ctim    time.TimeSpec
	blksize u64
	blocks  u64
}

pub const (
	dt_unknown = 0
	dt_fifo    = 1
	dt_chr     = 2
	dt_dir     = 4
	dt_blk     = 6
	dt_reg     = 8
	dt_lnk     = 10
	dt_sock    = 12
	dt_wht     = 14
)

pub struct Dirent {
pub mut:
	ino    u64
	off    u64
	reclen u16
	@type  u8
	name   [1024]u8
}
