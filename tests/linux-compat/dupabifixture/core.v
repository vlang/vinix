// SPDX-License-Identifier: GPL-2.0-or-later
module dupabifixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_dev u64 st_ino u64 st_mode u32 st_uid u32 st_gid u32 st_nlink u64 st_size i64 }
struct Counts { mut: calls [6]u64 failures [6]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.fcntl(i32, i32, ...) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.dup3(i32, i32, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.unlink(&char) i32
fn C.pipe2(&i32, i32) i32
fn C.ioctl(i32, usize, ...) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.usleep(u32) i32
fn C.pause() i32
fn C._exit(i32)

fn equal(left &C.stat, right &C.stat) bool {
	return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode
		&& left.st_uid == right.st_uid && left.st_gid == right.st_gid && left.st_nlink == right.st_nlink && left.st_size == right.st_size
}
// The target is seeded with a different open description for each request.
// A refusal must retain that target and the source, including descriptor flags
// and cursors. Successful aliases must share the source's description.
fn probe(counts &Counts, kind i32, ordinary bool, operation i32, source i32, seed i32, old_word u64, new_word u64, flags u64, expected i32) bool {
	unsafe {
		mut tally := &Counts(counts); tally.calls[kind]++
		if C.dup3(seed, 63, C.O_CLOEXEC) != 63 { tally.failures[kind]++; return false }
		defer { C.close(63) }
		source_stat := &C.stat(C.alloca(usize(sizeof(C.stat)))); target_stat := &C.stat(C.alloca(usize(sizeof(C.stat)))); checked := &C.stat(C.alloca(usize(sizeof(C.stat))))
		if C.fstat(source, source_stat) != 0 || C.fstat(63, target_stat) != 0 { tally.failures[kind]++; return false }
		source_flags := C.fcntl(source, C.F_GETFD); status_flags := C.fcntl(source, C.F_GETFL)
		source_cursor := C.lseek(source, 0, C.SEEK_CUR); target_cursor := C.lseek(seed, 0, C.SEEK_CUR)
		error_slot := C.__errno_location(); *error_slot = 0
		mut ret := isize(-2)
		match operation {
			0 { ret = C.syscall(C.SYS_dup, old_word) }
			1 { ret = C.syscall(C.SYS_dup3, old_word, new_word, flags) }
			2 { $if amd64 { ret = C.syscall(C.SYS_dup2, old_word, new_word) } }
			3 { ret = isize(C.dup(i32(u32(old_word)))) }
			4 { ret = isize(C.dup3(i32(u32(old_word)), i32(u32(new_word)), i32(u32(flags)))) }
			5 { ret = isize(C.dup2(i32(u32(old_word)), i32(u32(new_word)))) }
			else {}
		}
		error_code := *error_slot
		automatic := operation == 0 || operation == 3
		defer { if automatic && ret >= 0 { C.close(i32(ret)) } }
		mut good := if expected == 0 { ret >= 0 && (automatic || ret == isize(u32(new_word))) } else { ret == -1 && error_code == expected }
		if expected == 0 && ret >= 0 {
			alias := i32(ret); same := (operation == 2 || operation == 5) && u32(old_word) == u32(new_word)
			wanted := if same { source_flags } else if (operation == 1 || operation == 4) && u32(flags) & u32(C.O_CLOEXEC) != 0 { C.FD_CLOEXEC } else { i32(0) }
			good = good && C.fstat(alias, checked) == 0 && equal(checked, source_stat) && C.fcntl(alias, C.F_GETFD) == wanted && C.fcntl(alias, C.F_GETFL) == status_flags
			if source_cursor >= 0 && alias != source {
				good = good && C.lseek(alias, 0, C.SEEK_CUR) == source_cursor
				good = good && C.lseek(alias, source_cursor + 1, C.SEEK_SET) == source_cursor + 1 && C.lseek(source, 0, C.SEEK_CUR) == source_cursor + 1
				if C.lseek(source, source_cursor, C.SEEK_SET) != source_cursor { good = false }
			}
		} else {
			good = good && C.fstat(63, checked) == 0 && equal(checked, target_stat) && C.fcntl(63, C.F_GETFD) == C.FD_CLOEXEC && C.lseek(63, 0, C.SEEK_CUR) == target_cursor
		}
		good = good && C.fstat(source, checked) == 0 && equal(checked, source_stat) && C.fcntl(source, C.F_GETFD) == source_flags && C.fcntl(source, C.F_GETFL) == status_flags
		if source_cursor >= 0 { good = good && C.lseek(source, 0, C.SEEK_CUR) == source_cursor }
		if !good { tally.failures[kind]++; if tally.failures[kind] <= 6 { C.printf(c'LINUX DUPABI DETAIL: ordinary=%d kind=%d op=%d old=%lx new=%lx flags=%lx ret=%ld errno=%d expected=%d\n', i32(ordinary), kind, operation, old_word, new_word, flags, ret, error_code, expected); C.fflush(nil) } }
		return good
	}
}
fn qualify(fds &i32, seed i32, ordinary bool, reference_run bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		mut counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
		for index in 0 .. 6 {
			fd := fds[index]
			for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { probe(counts, 0, ordinary, 0, fd, seed, upper | u64(u32(fd)), 0, 0, 0) }
			for old_upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for new_upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for flag_upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for flag in [u64(0), u64(C.O_CLOEXEC)]! {
				probe(counts, 1, ordinary, 1, fd, seed, old_upper | u64(u32(fd)), new_upper | 63, flag_upper | flag, 0)
			} } } }
			$if amd64 {
				for old_upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for new_upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
					probe(counts, 4, ordinary, 2, fd, seed, old_upper | u64(u32(fd)), new_upper | u64(u32(fd)), 0, 0)
					probe(counts, 4, ordinary, 2, fd, seed, old_upper | u64(u32(fd)), new_upper | 63, 0, 0)
				} }
			}
			probe(counts, 5, ordinary, 3, fd, seed, u64(u32(fd)), 0, 0, 0)
			for flag in [u64(0), u64(C.O_CLOEXEC)]! { probe(counts, 5, ordinary, 4, fd, seed, u64(u32(fd)), 63, flag, 0) }
			probe(counts, 5, ordinary, 5, fd, seed, u64(u32(fd)), 63, 0, 0)
			probe(counts, 5, ordinary, 5, fd, seed, u64(u32(fd)), u64(u32(fd)), 0, 0)
		}
		for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for bad in [u32(-1), u32(999999)]! {
			probe(counts, 0, ordinary, 0, fds[0], seed, upper | u64(bad), 0, 0, C.EBADF)
			for flag in [u64(0), u64(C.O_CLOEXEC)]! {
				probe(counts, 3, ordinary, 1, fds[0], seed, upper | u64(bad), upper | 63, upper | flag, C.EBADF)
				probe(counts, 3, ordinary, 1, fds[0], seed, upper | u64(u32(fds[0])), upper | u64(bad), upper | flag, C.EBADF)
			}
			$if amd64 {
				probe(counts, 4, ordinary, 2, fds[0], seed, upper | u64(bad), upper | 63, 0, C.EBADF)
				probe(counts, 4, ordinary, 2, fds[0], seed, upper | u64(u32(fds[0])), upper | u64(bad), 0, C.EBADF)
				for other_upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { probe(counts, 4, ordinary, 2, fds[0], seed, upper | u64(bad), other_upper | u64(bad), 0, C.EBADF) }
			}
		} }
		for old_upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for new_upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for flag_upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for flag in [u64(0), u64(C.O_CLOEXEC)]! {
			probe(counts, 3, ordinary, 1, fds[0], seed, old_upper | 63, new_upper | 63, flag_upper | flag, C.EINVAL)
		} } } }
		for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for flag in [u64(0), u64(C.O_CLOEXEC)]! { probe(counts, 3, ordinary, 1, fds[0], seed, upper | u64(u32(-1)), upper | u64(u32(-1)), upper | flag, C.EINVAL) } }
		for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for location in 0 .. 4 { for bit in 0 .. 32 {
			flag := u64(1) << bit; if flag == u64(C.O_CLOEXEC) { continue }
			old_word := upper | if location == 1 { u64(u32(-1)) } else if location == 2 { u64(63) } else { u64(u32(fds[0])) }
			new_word := upper | if location == 3 { u64(u32(-1)) } else { u64(63) }
			probe(counts, 2, ordinary, 1, fds[0], seed, old_word, new_word, upper | flag, C.EINVAL)
		} } }
		probe(counts, 5, ordinary, 4, fds[0], seed, u64(u32(fds[0])), 63, 1, C.EINVAL)
		probe(counts, 5, ordinary, 4, fds[0], seed, u64(u32(-1)), 63, 0, C.EBADF)
		probe(counts, 5, ordinary, 4, fds[0], seed, u64(u32(-1)), u64(u32(-1)), 0, C.EINVAL)
		probe(counts, 5, ordinary, 4, fds[0], seed, u64(u32(fds[0])), u64(u32(-1)), 0, C.EBADF)
		probe(counts, 5, ordinary, 5, fds[0], seed, u64(u32(fds[0])), u64(u32(-1)), 0, C.EBADF)
		mut good := true
		for kind in 0 .. 6 { C.printf(c'LINUX DUPABI CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		if good && !reference_run && !storage(fds[0], seed, ordinary) { good = false }
		return good
	}
}
fn storage_cycle(fd i32, seed i32) bool {
	unsafe {
		for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
			alias := C.syscall(C.SYS_dup, upper | u64(u32(fd))); if alias < 0 { return false }; if C.close(i32(alias)) != 0 { return false }
			for flags in [u64(0), u64(C.O_CLOEXEC)]! {
				if C.syscall(C.SYS_dup3, upper | u64(u32(fd)), upper | 63, upper | flags) != 63 || C.fcntl(63, C.F_GETFD) != if flags == 0 { 0 } else { C.FD_CLOEXEC } { C.close(63); return false }; C.close(63)
			}
			if C.dup3(seed, 63, C.O_CLOEXEC) != 63 { return false }; error_slot := C.__errno_location(); *error_slot = 0
			if C.syscall(C.SYS_dup3, upper | u64(u32(fd)), upper | 63, upper | 1) != -1 || *error_slot != C.EINVAL || C.fcntl(63, C.F_GETFD) != C.FD_CLOEXEC { C.close(63); return false }; C.close(63)
			*error_slot = 0; if C.syscall(C.SYS_dup3, upper | u64(u32(fd)), upper | u64(u32(fd)), upper) != -1 || *error_slot != C.EINVAL { return false }
			$if amd64 {
				if C.syscall(C.SYS_dup2, upper | u64(u32(fd)), upper | 63) != 63 || C.fcntl(63, C.F_GETFD) != 0 { C.close(63); return false }; C.close(63)
				if C.syscall(C.SYS_dup2, upper | u64(u32(fd)), u64(u32(fd))) != fd || C.fcntl(fd, C.F_GETFD) != C.FD_CLOEXEC { return false }
			}
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
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX DUPABI SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX DUPABI STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut fds := [6]i32{init: -1}; mut seed := i32(-1)
		defer { for fd in fds { if fd >= 0 { C.close(fd) } }; if seed >= 0 { C.close(seed) } }
		fds[0] = C.open(c'/tmp/linux-dupabi-source', C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, i32(0o644)); if fds[0] < 0 { return 1 }
		if C.write(fds[0], c'dupabi-data-ok!', 16) != 16 || C.lseek(fds[0], 3, C.SEEK_SET) != 3 { return 1 }
		fds[1] = C.open(c'/tmp/linux-dupabi-source', C.O_PATH | C.O_CLOEXEC); if fds[1] < 0 { return 1 }
		fds[2] = C.open(c'/tmp', C.O_PATH | C.O_DIRECTORY | C.O_CLOEXEC); if fds[2] < 0 { return 1 }
		fds[3] = C.open(c'/tmp/linux-dupabi-deleted', C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, i32(0o600)); if fds[3] < 0 || C.unlink(c'/tmp/linux-dupabi-deleted') != 0 { return 1 }
		if C.pipe2(&fds[4], C.O_NONBLOCK | C.O_CLOEXEC) != 0 || C.write(fds[5], c'AB', 2) != 2 { return 1 }
		seed = C.open(c'/tmp/linux-dupabi-seed', C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, i32(0o644)); if seed < 0 { return 1 }
		if C.write(seed, c'dupabi-seed-ok!', 16) != 16 || C.lseek(seed, 5, C.SEEK_SET) != 5 { return 1 }
		mut good := true
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { good = false; break }
			if child == 0 { C._exit(if qualify(&fds[0], seed, ordinary, reference_run) { 0 } else { 1 }) }
			mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false }
		}
		mut data := [16]char{}
		if C.lseek(fds[0], 0, C.SEEK_CUR) != 3 || C.pread(fds[0], &data[0], 16, 0) != 16 { good = false }
		for i in 0 .. 16 { if data[i] != c'dupabi-data-ok!'[i] { good = false } }
		if C.lseek(seed, 0, C.SEEK_CUR) != 5 || C.pread(seed, &data[0], 16, 0) != 16 { good = false }
		for i in 0 .. 16 { if data[i] != c'dupabi-seed-ok!'[i] { good = false } }
		mut queued := i32(-1); if C.ioctl(fds[4], usize(C.FIONREAD), &queued) != 0 || queued != 2 { good = false }
		if C.read(fds[4], &data[0], 2) != 2 || data[0] != char(65) || data[1] != char(66) { good = false }
		for fd in fds { if C.fcntl(fd, C.F_GETFD) != C.FD_CLOEXEC { good = false } }
		if !good { C.puts(c'LINUX DUPABI FAIL: errors, aliases, target/source state or retained storage'); C.fflush(nil); return 1 }
		if reference_run { C.puts(c'LINUX DUPABI REFERENCE: PASS') } else { C.puts(c'LINUX DUPABI: PASS') }; C.fflush(nil); for { C.pause() }
	}
	return 0
}
