// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <fcntl.h>
#include <sys/stat.h>

fn C.open(&char, int, ...int) int
fn C.shm_open(&char, i32, u32) i32
fn C.shm_unlink(&char) i32
fn C.ftruncate(i32, u64) i32
fn C.close(int) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.lseek(int, i64, int) i64
fn C.ios_open()
fn C.mlock(voidptr, usize) i32
fn C.munlock(voidptr, usize) i32
fn C.ios_stat_info(&char, i32, i32, &u64) i32
fn C.ios_mkdir(&char, u32) i32
fn C.access(&char, int) int
fn C.rmdir(&char) i32
fn C.getcwd(&char, usize) &char
fn C.chmod(&char, u32) int
fn C.fchmod(int, u32) int

fn darwin_file_result(result int) int {
	if result < 0 { darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() })) }
	return result
}

// Darwin mode_t is 16 bits; the Linux syscall/libc interface uses 32 bits.
fn darwin_chmod(path &char, mode u16) int {
	return darwin_file_result(C.chmod(path, u32(mode)))
}

fn darwin_fchmod(fd int, mode u16) int {
	return darwin_file_result(C.fchmod(fd, u32(mode)))
}

fn darwin_stat_result(path &char, fd i32, kind i32, output u64) i32 {
	if output == 0 { darwin_set_errno(14); return -1 }
	mut fields := [20]u64{}
	result := C.ios_stat_info(path, fd, kind, unsafe { &fields[0] })
	if result != 0 { return result }
	unsafe { C.memset(voidptr(output), 0, 144) }
	write32(output, u32(fields[0]))
	unsafe { *(&u16(output + 4)) = u16(fields[1]); *(&u16(output + 6)) = u16(fields[2]); *(&u64(output + 8)) = fields[3] }
	write32(output + 16, u32(fields[4]))
	write32(output + 20, u32(fields[5]))
	write32(output + 24, u32(fields[6]))
	for i in 0 .. 8 { unsafe { *(&u64(output + 32 + u64(i) * 8)) = fields[i + 7] } }
	unsafe { *(&u64(output + 96)) = fields[15]; *(&u64(output + 104)) = fields[16] }
	for i in 0 .. 3 { write32(output + 112 + u64(i) * 4, u32(fields[i + 17])) }
	return 0
}

fn darwin_stat(path &char, output u64) i32 { return darwin_stat_result(path, -1, 0, output) }
fn darwin_lstat(path &char, output u64) i32 { return darwin_stat_result(path, -1, 1, output) }
fn darwin_fstat(fd i32, output u64) i32 { return darwin_stat_result(unsafe { nil }, fd, 2, output) }

fn darwin_open_flags(flags i32) !i32 {
	$if linux {
		if flags & ~i32(3 | 4 | 8 | 0x80 | 0x100 | 0x200 | 0x400 | 0x800 | 0x20000 | 0x100000 | 0x1000000) != 0 { return error('unsupported Darwin open flags') }
		mut native := flags & 3
		for pair in [[i32(4), C.O_NONBLOCK]!, [i32(8), C.O_APPEND]!, [i32(0x80), C.O_SYNC]!,
			[i32(0x100), C.O_NOFOLLOW]!, [i32(0x200), C.O_CREAT]!, [i32(0x400), C.O_TRUNC]!,
			[i32(0x800), C.O_EXCL]!, [i32(0x20000), C.O_NOCTTY]!, [i32(0x100000), C.O_DIRECTORY]!, [i32(0x1000000), C.O_CLOEXEC]!]! {
			if flags & pair[0] != 0 { native |= pair[1] }
		}
		return native
	}
	return flags
}

@[export: 'ios_open_stack']
fn darwin_open(path &char, flags i32, stack u64) i32 {
	native := darwin_open_flags(flags) or { darwin_set_errno(45); return -1 }
	mode := if flags & 0x200 != 0 { i32(read32(stack)) } else { i32(0) }
	return i32(C.open(path, native, mode))
}

fn darwin_shm_open(path &char, flags i32, mode u32) i32 {
	native := darwin_open_flags(flags) or { darwin_set_errno(45); return -1 }
	$if linux {
		// musl uses the host's tmpfs directory, with ordinary POSIX lifetime:
		// unlink removes its name while open descriptors/mappings remain valid.
		os.mkdir_all('/dev/shm') or { darwin_set_errno(2); return -1 }
	}
	return C.shm_open(path, native, mode)
}

fn darwin_mmap(address voidptr, size usize, protection i32, flags i32, file i32, offset i64) voidptr {
	$if linux {
		if flags & ~i32(1 | 2 | 0x10 | 0x40 | 0x1000) != 0 || protection & ~i32(7) != 0 {
			darwin_set_errno(45)
			return unsafe { voidptr(-1) }
		}
		mut native := flags & (1 | 2 | 0x10)
		if flags & 0x1000 != 0 { native |= C.MAP_ANONYMOUS }
		if flags & 0x40 != 0 { native |= C.MAP_NORESERVE }
		return C.mmap(address, size, protection, native, file, offset)
	}
	return C.mmap(address, size, protection, flags, file, offset)
}

fn files_symbol(symbol string) ?u64 {
	return match symbol {
		'_fcntl' { u64(unsafe { voidptr(C.ios_fcntl) }) }
		'_ioctl' { u64(unsafe { voidptr(C.ios_ioctl) }) }
		'_fsync' { u64(unsafe { voidptr(darwin_fsync) }) }
		'_chmod' { u64(unsafe { voidptr(darwin_chmod) }) }
		'_fchmod' { u64(unsafe { voidptr(darwin_fchmod) }) }
		'_stat', '_stat$INODE64' { u64(unsafe { voidptr(darwin_stat) }) }
		'_pread' { u64(unsafe { voidptr(C.pread) }) }
		'_pwrite' { u64(unsafe { voidptr(C.pwrite) }) }
		'_lstat', '_lstat$INODE64' { u64(unsafe { voidptr(darwin_lstat) }) }
		'_fstat', '_fstat$INODE64' { u64(unsafe { voidptr(darwin_fstat) }) }
		'_mkdir' { u64(unsafe { voidptr(C.ios_mkdir) }) }
		'_access' { u64(unsafe { voidptr(C.access) }) }
		'_rmdir' { u64(unsafe { voidptr(C.rmdir) }) }
		'_getcwd' { u64(unsafe { voidptr(C.getcwd) }) }
		'_open' { u64(unsafe { voidptr(C.ios_open) }) }
		'_shm_open' { u64(unsafe { voidptr(darwin_shm_open) }) }
		'_shm_unlink' { u64(unsafe { voidptr(C.shm_unlink) }) }
		'_ftruncate' { u64(unsafe { voidptr(C.ftruncate) }) }
		'_close' { u64(unsafe { voidptr(C.close) }) }
		'_read' { u64(unsafe { voidptr(C.read) }) }
		'_write' { u64(unsafe { voidptr(C.write) }) }
		'_lseek' { u64(unsafe { voidptr(C.lseek) }) }
		'_mmap' { u64(unsafe { voidptr(darwin_mmap) }) }
		'_munmap' { u64(unsafe { voidptr(C.munmap) }) }
		'_mprotect' { u64(unsafe { voidptr(C.mprotect) }) }
		'_mlock' { u64(unsafe { voidptr(C.mlock) }) }
		'_munlock' { u64(unsafe { voidptr(C.munlock) }) }
		else { return none }
	}
}
