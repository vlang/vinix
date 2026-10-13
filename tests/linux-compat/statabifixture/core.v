// SPDX-License-Identifier: GPL-2.0-or-later
module statabifixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_mode u32 st_ino u64 st_uid u32 st_gid u32 st_nlink u64 st_size i64 st_blocks i64 st_blksize i64 }
struct Counts { mut: calls [5]u64 failures [5]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.fstatat(i32, &char, &C.stat, i32) i32
fn C.stat(&char, &C.stat) i32
fn C.lstat(&char, &C.stat) i32
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.mkdir(&char, u32) i32
fn C.symlink(&char, &char) i32
fn C.unlink(&char) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.usleep(u32) i32
fn C.pause() i32
fn C._exit(i32)

fn probe(counts &Counts, kind i32, ordinary bool, operation i32, fd u64, path &char, flags u64, destination i32, expected i32, reference &C.stat) bool {
	unsafe {
		length := int(sizeof(C.stat)); guard := &u8(C.alloca(usize(length + 16))); C.memset(guard, 0xa5, usize(length + 16))
		output := if destination == 0 { voidptr(guard + 8) } else if destination == 1 { voidptr(usize(0)) } else { voidptr(usize(1)) }
		error_slot := C.__errno_location(); *error_slot = 0
		mut ret := isize(-2)
		match operation {
			0 { ret = C.syscall(C.SYS_fstat, fd, output) }
			1 { ret = C.syscall(C.SYS_newfstatat, fd, path, output, flags) }
			2 { $if amd64 { ret = C.syscall(C.SYS_stat, path, output) } }
			3 { $if amd64 { ret = C.syscall(C.SYS_lstat, path, output) } }
			4 { ret = isize(C.fstat(i32(u32(fd)), &C.stat(output))) }
			5 { ret = isize(C.fstatat(i32(u32(fd)), path, &C.stat(output), i32(u32(flags)))) }
			6 { ret = isize(C.stat(path, &C.stat(output))) }
			7 { ret = isize(C.lstat(path, &C.stat(output))) }
			else {}
		}
		error_code := *error_slot
		mut good := if expected == 0 { ret == 0 } else { ret == -1 && error_code == expected }
		for i in 0 .. 8 { if guard[i] != 0xa5 || guard[i + length + 8] != 0xa5 { good = false } }
		if expected != 0 { for i in 8 .. length + 8 { if guard[i] != 0xa5 { good = false } } }
		else if ret == 0 && reference != nil {
			value := &C.stat(guard + 8)
			good = good && value.st_mode == reference.st_mode && value.st_ino == reference.st_ino
				&& value.st_uid == reference.st_uid && value.st_gid == reference.st_gid && value.st_nlink == reference.st_nlink
				&& value.st_size == reference.st_size && value.st_blocks == reference.st_blocks && value.st_blksize == reference.st_blksize
		}
		mut tally := &Counts(counts); tally.calls[kind]++
		if !good { tally.failures[kind]++; if tally.failures[kind] <= 6 { C.printf(c'LINUX STATABI DETAIL: ordinary=%d kind=%d op=%d fd=%lx flags=%lx destination=%d ret=%ld errno=%d expected=%d\n', i32(ordinary), kind, operation, fd, flags, destination, ret, error_code, expected); C.fflush(nil) } }
		return good
	}
}
fn qualify(dirfd i32, filefd i32, linkfd i32, deleted i32, pipefd i32, ordinary bool, reference_run bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		mut counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
		file_stat := &C.stat(C.alloca(usize(sizeof(C.stat)))); link_stat := &C.stat(C.alloca(usize(sizeof(C.stat))))
		if C.fstat(filefd, file_stat) != 0 || C.fstat(linkfd, link_stat) != 0 { return false }
		descriptor_stat := &C.stat(C.alloca(usize(sizeof(C.stat))))
		for fd in [filefd, linkfd, deleted, pipefd]! {
			if C.fstat(fd, descriptor_stat) != 0 { return false }
			for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for destination in 0 .. 3 {
				probe(counts, 0, ordinary, 0, upper | u64(u32(fd)), nil, 0, i32(destination), if destination == 0 { 0 } else { C.EFAULT }, descriptor_stat)
			} }
			probe(counts, 4, ordinary, 4, u64(u32(fd)), nil, 0, 0, 0, descriptor_stat)
			for sync in [u64(0), 0x2000, 0x4000, 0x6000]! { for automount in [u64(0), 0x800]! { for nofollow in [u64(0), 0x100]! { for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
				flags := upper | 0x1000 | sync | automount | nofollow
				probe(counts, 1, ordinary, 1, upper | u64(u32(fd)), c'', flags, 0, 0, descriptor_stat)
				// Unlike statabi, Linux 6.12 fstatat's NULL fast path requires exactly AT_EMPTY_PATH.
				plain := sync == 0 && automount == 0 && nofollow == 0
				probe(counts, if plain { 1 } else { 2 }, ordinary, 1, upper | u64(u32(fd)), nil, flags, 0, if plain { 0 } else { C.EFAULT }, descriptor_stat)
			} } } }
		}
		for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for fd in [u32(-1), u32(999999)]! { for destination in 0 .. 3 {
			probe(counts, 0, ordinary, 0, upper | u64(fd), nil, 0, i32(destination), C.EBADF, nil)
		} } }
		for sync in [u64(0), 0x2000, 0x4000, 0x6000]! { for automount in [u64(0), 0x800]! { for nofollow in [u64(0), 0x100]! { for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
			flags := upper | sync | automount | nofollow
			probe(counts, 1, ordinary, 1, upper | u64(u32(-1)), c'/tmp/linux-statabi/file', flags, 0, 0, file_stat)
			probe(counts, 1, ordinary, 1, upper | u64(u32(dirfd)), c'file', flags, 0, 0, file_stat)
			probe(counts, 1, ordinary, 1, upper | u64(u32(dirfd)), c'link', flags, 0, 0, if nofollow == 0 { file_stat } else { link_stat })
		} } } }
		for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for location in 0 .. 4 { for destination in 0 .. 3 {
			path := if location == 0 { &char(c'/tmp/linux-statabi/file') } else if location == 1 { &char(usize(1)) } else if location == 2 { &char(c'/tmp/linux-statabi/absent') } else { &char(c'') }
			for bit in 0 .. 32 {
				flag := u64(1) << bit; if flag & 0x7900 != 0 { continue }
				probe(counts, 2, ordinary, 1, upper | u64(u32(-1)), path, upper | flag, i32(destination), C.EINVAL, nil)
			}
		} } }
		for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for destination in 0 .. 3 {
			probe(counts, 3, ordinary, 1, upper | u64(u32(-1)), c'/tmp/linux-statabi/absent', upper, i32(destination), C.ENOENT, nil)
			probe(counts, 3, ordinary, 1, upper | u64(u32(-1)), c'', upper | 0x1000, i32(destination), C.EBADF, nil)
			probe(counts, 3, ordinary, 1, upper | u64(u32(-1)), nil, upper | 0x1000, i32(destination), C.EFAULT, nil)
			probe(counts, 3, ordinary, 1, upper | 999999, nil, upper | 0x1000, i32(destination), C.EBADF, nil)
			probe(counts, 3, ordinary, 1, upper | u64(u32(C.AT_FDCWD)), nil, upper | 0x1000, i32(destination), C.EFAULT, nil)
			probe(counts, 3, ordinary, 1, upper | u64(u32(dirfd)), c'', upper, i32(destination), C.ENOENT, nil)
			probe(counts, 3, ordinary, 1, upper | u64(u32(filefd)), c'file', upper, i32(destination), C.ENOTDIR, nil)
			probe(counts, 3, ordinary, 1, upper | u64(u32(filefd)), nil, upper, i32(destination), C.EFAULT, nil)
			probe(counts, 3, ordinary, 1, upper | u64(u32(filefd)), nil, upper | 0x1100, i32(destination), C.EFAULT, nil)
			probe(counts, 3, ordinary, 1, upper | u64(u32(dirfd)), &char(usize(1)), upper, i32(destination), C.EFAULT, nil)
			if destination != 0 { probe(counts, 3, ordinary, 1, upper | u64(u32(dirfd)), c'file', upper, i32(destination), C.EFAULT, nil) }
		} }
		$if amd64 {
			for operation in [i32(2), 3]! { for destination in 0 .. 3 {
				probe(counts, 3, ordinary, operation, 0, c'/tmp/linux-statabi/link', 0, i32(destination), if destination == 0 { 0 } else { C.EFAULT }, if operation == 2 { file_stat } else { link_stat })
				probe(counts, 3, ordinary, operation, 0, c'/tmp/linux-statabi/file', 0, i32(destination), if destination == 0 { 0 } else { C.EFAULT }, file_stat)
				probe(counts, 3, ordinary, operation, 0, c'/tmp/linux-statabi/absent', 0, i32(destination), C.ENOENT, nil)
				probe(counts, 3, ordinary, operation, 0, c'', 0, i32(destination), C.ENOENT, nil)
				probe(counts, 3, ordinary, operation, 0, nil, 0, i32(destination), C.EFAULT, nil)
				probe(counts, 3, ordinary, operation, 0, &char(usize(1)), 0, i32(destination), C.EFAULT, nil)
			} }
		}
		probe(counts, 4, ordinary, 5, u64(u32(dirfd)), c'file', 0, 0, 0, file_stat)
		probe(counts, 4, ordinary, 5, u64(u32(dirfd)), c'link', 0, 0, 0, file_stat)
		probe(counts, 4, ordinary, 5, u64(u32(dirfd)), c'link', 0x100, 0, 0, link_stat)
		probe(counts, 4, ordinary, 5, u64(u32(filefd)), c'', 0x1000, 0, 0, file_stat)
		probe(counts, 4, ordinary, 5, u64(u32(dirfd)), c'file', 1, 0, C.EINVAL, nil)
		probe(counts, 4, ordinary, 5, u64(u32(dirfd)), c'absent', 0, 0, C.ENOENT, nil)
		probe(counts, 4, ordinary, 6, 0, c'/tmp/linux-statabi/link', 0, 0, 0, file_stat)
		probe(counts, 4, ordinary, 7, 0, c'/tmp/linux-statabi/link', 0, 0, 0, link_stat)
		mut good := true
		for kind in 0 .. 5 { C.printf(c'LINUX STATABI CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		if good && !reference_run && !storage(dirfd, filefd, ordinary) { good = false }
		return good
	}
}
fn storage_cycle(dirfd i32, filefd i32) bool {
	unsafe {
		buffer := C.alloca(usize(sizeof(C.stat))); error_slot := C.__errno_location()
		for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
			if C.syscall(C.SYS_fstat, upper | u64(u32(filefd)), buffer) != 0 || C.syscall(C.SYS_newfstatat, upper | u64(u32(dirfd)), c'file', buffer, upper | 0x6000) != 0 { return false }
			if C.syscall(C.SYS_newfstatat, upper | u64(u32(filefd)), c'', buffer, upper | 0x7900) != 0 || C.syscall(C.SYS_newfstatat, upper | u64(u32(filefd)), voidptr(usize(0)), buffer, upper | 0x1000) != 0 { return false }
			*error_slot = 0; if C.syscall(C.SYS_newfstatat, upper | u64(u32(dirfd)), c'file', buffer, upper | 1) != -1 || *error_slot != C.EINVAL { return false }
			*error_slot = 0; if C.syscall(C.SYS_newfstatat, upper | u64(u32(filefd)), voidptr(usize(0)), buffer, upper | 0x1800) != -1 || *error_slot != C.EFAULT { return false }
			*error_slot = 0; if C.syscall(C.SYS_fstat, upper | u64(u32(-1)), voidptr(usize(1))) != -1 || *error_slot != C.EBADF { return false }
		}
		return true
	}
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination); *counts = Slabs{}; mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0); if length <= 0 || length >= 4096 { return false }; data[int(length)] = 0
		mut position := 0; mut large := false
		for position < int(length) {
			mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }; counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}
		return counts.rows > 0 && large
	}
}
fn storage(dirfd i32, filefd i32, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !storage_cycle(dirfd, filefd) { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(observer, before) { return false }; for _ in 0 .. 200 { if !storage_cycle(dirfd, filefd) { return false } }; C.usleep(13000000)
		if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX STATABI SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX STATABI STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		if C.mkdir(c'/tmp/linux-statabi', u32(0o755)) != 0 { return 1 }
		filefd := C.open(c'/tmp/linux-statabi/file', C.O_RDWR | C.O_CREAT | C.O_EXCL, i32(0o644)); if filefd < 0 { return 1 }; defer { C.close(filefd) }
		if C.write(filefd, c'statabi-data-ok!', 16) != 16 || C.lseek(filefd, 3, C.SEEK_SET) != 3 || C.symlink(c'file', c'/tmp/linux-statabi/link') != 0 { return 1 }
		linkfd := C.open(c'/tmp/linux-statabi/link', C.O_PATH | C.O_NOFOLLOW); if linkfd < 0 { return 1 }; defer { C.close(linkfd) }
		dirfd := C.open(c'/tmp/linux-statabi', C.O_PATH | C.O_DIRECTORY); if dirfd < 0 { return 1 }; defer { C.close(dirfd) }
		deleted := C.open(c'/tmp/linux-statabi/deleted', C.O_RDWR | C.O_CREAT | C.O_EXCL, i32(0o600)); if deleted < 0 { return 1 }; defer { C.close(deleted) }
		if C.unlink(c'/tmp/linux-statabi/deleted') != 0 { return 1 }
		mut pipe := [2]i32{}; if C.pipe(&pipe[0]) != 0 { return 1 }; defer { C.close(pipe[0]); C.close(pipe[1]) }
		mut good := true
		for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { good = false; break }; if child == 0 { C._exit(if qualify(dirfd, filefd, linkfd, deleted, pipe[0], ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		mut bytes := [16]char{}
		if C.lseek(filefd, 0, C.SEEK_CUR) != 3 || C.pread(filefd, &bytes[0], 16, 0) != 16 { good = false }
		for i in 0 .. 16 { if bytes[i] != c'statabi-data-ok!'[i] { good = false } }
		if !good { C.puts(c'LINUX STATABI FAIL: metadata, errors, output or retained storage'); C.fflush(nil); return 1 }
		if reference_run { C.puts(c'LINUX STATABI REFERENCE: PASS') } else { C.puts(c'LINUX STATABI: PASS') }; C.fflush(nil); for { C.pause() }
	}
	return 0
}
