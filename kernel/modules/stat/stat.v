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

pub fn isblk(mode u32) bool {
	return (mode & stat.ifmt) == stat.ifblk
}

pub fn ischr(mode u32) bool {
	return (mode & stat.ifmt) == stat.ifchr
}

pub fn isifo(mode u32) bool {
	return (mode & stat.ifmt) == stat.ififo
}

pub fn isreg(mode u32) bool {
	return (mode & stat.ifmt) == stat.ifreg
}

pub fn isdir(mode u32) bool {
	return (mode & stat.ifmt) == stat.ifdir
}

pub fn islnk(mode u32) bool {
	return (mode & stat.ifmt) == stat.iflnk
}

pub fn issock(mode u32) bool {
	return (mode & stat.ifmt) == stat.ifsock
}

pub struct Stat {
pub mut:
	dev     u64
	ino     u64
	nlink   u64
	mode    u32
	uid     u32
	gid     u32
	pad0    u32
	rdev    u64
	size    i64
	blksize i64
	blocks  i64
	atim    time.TimeSpec
	mtim    time.TimeSpec
	ctim    time.TimeSpec
	pad1    [3]i64
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
