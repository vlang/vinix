// SPDX-License-Identifier: GPL-2.0-or-later
module ext2host

import hosttest

#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#define vinix_ext2_stat stat
#define vinix_ext2_lstat lstat
#define vinix_ext2_fstat fstat

struct C.vinix_ext2_stat {
	st_dev              u64
	st_ino              u64
	st_mode             u32
	st_size             i64
	st_blocks           i64
	st_mtime            i64
	vinix_ext2_mtime_ns i64
	st_ctime            i64
	vinix_ext2_ctime_ns i64
}

fn C.vinix_ext2_lstat(&char, &C.vinix_ext2_stat) int
fn C.vinix_ext2_fstat(int, &C.vinix_ext2_stat) int
fn C.pread(int, voidptr, usize, i64) i64
fn C.pwrite(int, voidptr, usize, i64) i64
fn C.ftruncate(int, u64) int
fn C.fsync(int) int

pub struct FileInfo {
pub:
	identity []i64
	mode     u32
	mtime    i64
	blocks   i64
}

fn file_info(info C.vinix_ext2_stat) FileInfo {
	return FileInfo{[i64(info.st_dev), i64(info.st_ino), info.st_size,
		info.st_mtime * 1_000_000_000 + info.vinix_ext2_mtime_ns,
		info.st_ctime * 1_000_000_000 + info.vinix_ext2_ctime_ns], info.st_mode, info.st_mtime, info.st_blocks}
}

fn io_error(message string) IError {
	return error_with_code(message, if C.errno == 0 { int(C.EIO) } else { int(C.errno) })
}

pub fn inspect(path string) !FileInfo {
	mut info := C.vinix_ext2_stat{}
	if path.contains('\x00') || C.vinix_ext2_lstat(path.str, &info) != 0 {
		return io_error('Cannot inspect ' + path)
	}
	return file_info(info)
}

fn inspect_fd(fd int) !FileInfo {
	mut info := C.vinix_ext2_stat{}
	if C.vinix_ext2_fstat(fd, &info) != 0 { return io_error('Cannot inspect opened export source') }
	return file_info(info)
}

pub fn same_source(info FileInfo, recorded []i64) bool {
	return recorded.len == 5 && info.identity[1..] == recorded[1..]
}

fn read_at(fd int, offset i64, count int) ![]u8 {
	mut data := []u8{len: count}
	if count == 0 { return data }
	n := C.pread(fd, data.data, usize(count), offset)
	if n < 0 { return io_error('Cannot read export data') }
	return data[..int(n)].clone()
}

fn write_at(fd int, offset i64, data []u8) ! {
	mut at := 0
	for at < data.len {
		n := C.pwrite(fd, unsafe { &u8(data.data) + at }, usize(data.len - at), offset + at)
		if n <= 0 { return io_error('Short metadata write') }
		at += int(n)
	}
}

fn exclusive(path string, size i64) !int {
	fd := C.open(path.str, C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600)
	if fd < 0 { return io_error('Cannot create ' + path) }
	if C.ftruncate(fd, u64(size)) != 0 {
		failure := io_error('Cannot size ' + path)
		C.close(fd)
		return failure
	}
	return fd
}

pub fn put_le(mut data []u8, at int, value u64, width int) {
	for index in 0 .. width { data[at + index] = u8(value >> (index * 8)) }
}

pub fn put_be(mut data []u8, at int, value u64, width int) {
	for index in 0 .. width { data[at + index] = u8(value >> ((width - index - 1) * 8)) }
}

pub fn get_be(data []u8, at int, width int) u64 {
	mut value := u64(0)
	for index in 0 .. width { value = (value << 8) | data[at + index] }
	return value
}

pub const block = 4096
pub const group_blocks = 32768
pub const pointers = 1024
pub const max_request = 32 * 1024 * 1024
pub const nbd_magic = u64(0x4e42444d41474943)
pub const option_magic = u64(0x49484156454f5054)
pub const reply_magic = u64(0x3e889045565a9)
pub const request_magic = u32(0x25609513)

pub fn rounded(value i64, unit i64) i64 { return (value + unit - 1) / unit }

fn is_dir(info FileInfo) bool { return info.mode & 0o170000 == 0o040000 }

fn is_file(info FileInfo) bool { return info.mode & 0o170000 == 0o100000 }

fn is_link(info FileInfo) bool { return info.mode & 0o170000 == 0o120000 }

fn resolve(path string) !string { return hosttest.module_resolve(path)! }
