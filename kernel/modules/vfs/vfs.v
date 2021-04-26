module vfs

struct TimeSpec {
pub:
	tv_sec  i64
	tv_nsec i64
}

struct Stat {
pub:
	st_dev     u64
	st_ino     u64
	st_mode    int
	st_nlink   int
	st_uid     int
	st_gid     int
	st_rdev    u64
	st_size    i64
	st_atim    TimeSpec
	st_mtim    TimeSpec
	st_ctim    TimeSpec
	st_blksize i64
	st_blocks  i64
}
