// SPDX-License-Identifier: GPL-2.0-or-later
module accessflagsfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_dev u64 st_ino u64 st_mode u32 st_size i64 st_nlink u64 st_uid u32 st_gid u32 }
struct Counts { mut: calls [3]u64 failures [3]u64 }
struct Bank { mut: fds [12]i32 meta [4]C.stat status [4]i32 writer i32 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fstat(i32, &C.stat) i32
fn C.fchmod(i32, u32) i32
fn C.mkdir(&char, u32) i32
fn C.chdir(&char) i32
fn C.chown(&char, u32, u32) i32
fn C.unlink(&char) i32
fn C.symlink(&char, &char) i32
fn C.pipe2(&i32, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.ioctl(i32, u64, ...) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.usleep(u32) i32
fn C.sscanf(&char, &char, ...) i32
fn C.strcmp(&char, &char) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C._exit(i32)

fn fatal() { C.puts(c'LINUX ACCESSFLAGS FAIL: setup or child protocol'); C.fflush(unsafe { nil }); C._exit(1) }
fn root_path(ordinary bool) &char { return if ordinary { c'/tmp/accessflags-u' } else { c'/tmp/accessflags-r' } }
fn absolute(ordinary bool) &char { return if ordinary { c'/tmp/accessflags-u/file' } else { c'/tmp/accessflags-r/file' } }
fn record(counts &Counts, kind i32, good bool, ordinary bool) {
	unsafe { mut value := &Counts(counts); value.calls[kind]++; if !good { value.failures[kind]++; if value.failures[kind] <= 3 { C.printf(c'LINUX ACCESSFLAGS DETAIL: ordinary=%d namespace=0 kind=%d call=%lu\n', i32(ordinary), kind, value.calls[kind]); C.fflush(nil) } } }
}
fn prepare(bank &Bank, ordinary bool) {
	unsafe { mut value := &Bank(bank); for index in 0 .. 12 { value.fds[index] = -1 }
		if C.mkdir(root_path(ordinary), 0o755) != 0 || (ordinary && C.chown(root_path(ordinary), 1000, 1000) != 0) || C.chdir(root_path(ordinary)) != 0 { fatal() }
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { fatal() }
		value.fds[0] = C.open(c'file', C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, 0o600)
		if value.fds[0] < 0 || C.write(value.fds[0], c'XYZ', 3) != 3 || C.lseek(value.fds[0], 1, C.SEEK_SET) != 1 || C.fchmod(value.fds[0], 0o400) != 0 || C.symlink(c'file', c'link') != 0 { fatal() }
		value.fds[3] = C.open(c'.', C.O_PATH | C.O_DIRECTORY | C.O_CLOEXEC)
		temporary := C.open(c'retired', C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, 0o600)
		if temporary < 0 || C.write(temporary, c'XYZ', 3) != 3 || C.fchmod(temporary, 0o400) != 0 { fatal() }
		value.fds[6] = C.open(c'retired', C.O_PATH | C.O_CLOEXEC)
		if value.fds[6] < 0 || C.close(temporary) != 0 || C.unlink(c'retired') != 0 { fatal() }
		pipe := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(pipe, C.O_CLOEXEC) != 0 { fatal() }; value.fds[9] = pipe[0]; value.writer = pipe[1]
		if C.write(value.writer, c'AB', 2) != 2 { fatal() }
		for group in 0 .. 4 { index := group * 3; if value.fds[index] < 0 || C.fstat(value.fds[index], &value.meta[group]) != 0 { fatal() }
			value.status[group] = C.fcntl(value.fds[index], C.F_GETFL); value.fds[index + 1] = C.dup(value.fds[index]); value.fds[index + 2] = C.fcntl(value.fds[index], C.F_DUPFD_CLOEXEC, 40)
			if value.status[group] < 0 || value.fds[index + 1] < 0 || value.fds[index + 2] < 0 { fatal() }
		}
	}
}
fn query(bank &Bank, target i32, mode u32, flags u32, upper u64, ordinary bool) bool {
	unsafe { mut fd := i32(C.AT_FDCWD); mut path := &char(c''); mut expected := i32(0)
		if target < 8 {
			match target {
				0 { path = absolute(ordinary) }
				1 { fd = bank.fds[3 + int((upper >> 32) % 3)]; path = c'file' }
				2 { fd = bank.fds[3]; path = c'.' }
				3 { fd = bank.fds[3]; path = c'link' }
				4 { fd = bank.fds[3]; path = c'missing'; expected = C.ENOENT }
				5 { fd = -1; path = c'file'; expected = C.EBADF }
				6 { fd = bank.fds[0]; path = c'file'; expected = C.ENOTDIR }
				else { path = &char(1); expected = C.EFAULT }
			}
			if ordinary && mode & u32(C.W_OK) != 0 && (target in [0, 1] || (target == 3 && flags & u32(C.AT_SYMLINK_NOFOLLOW) == 0)) { expected = C.EACCES }
		} else {
			index := target - 8; fd = bank.fds[index]
			if ordinary && mode & u32(C.W_OK) != 0 && index / 3 in [0, 2] { expected = C.EACCES }
		}
		if mode & ~u32(7) != 0 || flags & ~u32(0x1300) != 0 { expected = C.EINVAL }
		slot := C.__errno_location(); *slot = 0
		result := C.syscall(C.SYS_faccessat2, u64(u32(fd)) | upper, path, u64(mode) | upper, u64(flags) | upper)
		return if expected == 0 { result == 0 && *slot == 0 } else { result == -1 && *slot == expected }
	}
}
fn same(left &C.stat, right &C.stat) bool { return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode && left.st_size == right.st_size && left.st_nlink == right.st_nlink && left.st_uid == right.st_uid && left.st_gid == right.st_gid }
fn state(counts &Counts, bank &Bank, ordinary bool) {
	unsafe { data := &C.stat(C.alloca(usize(sizeof(C.stat)))); for index in 0 .. 12 {
		owner := if ordinary { u32(1000) } else { u32(0) }
		good := C.fstat(bank.fds[index], data) == 0 && same(data, &bank.meta[index / 3]) && data.st_uid == owner && data.st_gid == owner && C.fcntl(bank.fds[index], C.F_GETFL) == bank.status[index / 3] && C.fcntl(bank.fds[index], C.F_GETFD) == if index % 3 == 1 { i32(0) } else { i32(C.FD_CLOEXEC) }
		record(counts, 2, good, ordinary)
	}; mut bytes := [4]char{}; record(counts, 2, C.lseek(bank.fds[0], 0, C.SEEK_CUR) == 1 && C.pread(bank.fds[0], &bytes[0], 3, 0) == 3 && bytes[0] == char(`X`) && bytes[1] == char(`Y`) && bytes[2] == char(`Z`), ordinary)
	mut available := i32(-1); record(counts, 2, C.ioctl(bank.fds[9], C.FIONREAD, &available) == 0 && available == 2, ordinary)
	record(counts, 2, C.read(bank.fds[9], &bytes[0], 2) == 2 && bytes[0] == char(`A`) && bytes[1] == char(`B`), ordinary)
	}
}
fn qualify(counts &Counts, ordinary bool, reference_run bool) bool {
	unsafe { C.alarm(180); bank := &Bank(C.alloca(usize(sizeof(Bank)))); prepare(bank, ordinary)
		for flags in [u32(0), C.AT_EACCESS, C.AT_SYMLINK_NOFOLLOW, C.AT_EACCESS | C.AT_SYMLINK_NOFOLLOW, C.AT_EMPTY_PATH, C.AT_EMPTY_PATH | C.AT_EACCESS, C.AT_EMPTY_PATH | C.AT_SYMLINK_NOFOLLOW, C.AT_EMPTY_PATH | C.AT_EACCESS | C.AT_SYMLINK_NOFOLLOW]! {
			for upper in [u64(0), 0x100000000, 0x8000000000000000, 0xffffffff00000000, 0x1234567800000000]! { for mode in [u32(0), C.R_OK, C.W_OK, C.R_OK | C.W_OK, 8]! {
				for target in 0 .. if flags & u32(C.AT_EMPTY_PATH) != 0 { 20 } else { 8 } { record(counts, 0, query(bank, i32(target), mode, flags, upper, ordinary), ordinary) }
			} }
		}
		for flags in [u32(1), 0x400, 0x2000, 0xffffffff]! { for upper in [u64(0), 0x100000000, 0x8000000000000000, 0xffffffff00000000, 0x1234567800000000]! { for target in 0 .. 20 { record(counts, 1, query(bank, i32(target), 0, flags, upper, ordinary), ordinary) } } }
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0
		if good && !reference_run && !storage(bank, ordinary) { good = false }; state(counts, bank, ordinary)
		for kind in 0 .. 3 { C.printf(c'LINUX ACCESSFLAGS CASES: ordinary=%d namespace=0 kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }
		for index in 0 .. 12 { if C.close(bank.fds[index]) != 0 { good = false } }; if C.close(bank.writer) != 0 { good = false }; C.alarm(0); C.fflush(nil); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe { reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0; mut good := true
		for ordinary in [true, false]! { pipe := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(pipe, C.O_CLOEXEC) != 0 { return 1 }; child := C.fork(); if child < 0 { return 1 }
			if child == 0 { C.close(pipe[0]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; passed := qualify(counts, ordinary, reference_run); sent := C.write(pipe[1], counts, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(pipe[1]); C._exit(if passed && sent { 0 } else { 1 }) }
			C.close(pipe[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); received := C.read(pipe[0], counts, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(pipe[0]); mut status := i32(-1); completed := C.waitpid(child, &status, 0) == child && status == 0
			if !received || !completed { good = false }; if received { for kind in 0 .. 3 { C.printf(c'LINUX ACCESSFLAGS FINAL: ordinary=%d namespace=0 kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } } }; C.fflush(nil)
		}
		if !good { C.puts(c'LINUX ACCESSFLAGS FAIL: native flags or retained state'); C.fflush(nil); return 1 }; C.puts(if reference_run { c'LINUX ACCESSFLAGS REFERENCE: PASS' } else { c'LINUX ACCESSFLAGS: PASS' }); C.fflush(nil); for { C.pause() }
	}; return 0
}
fn snapshot(fd i32, destination &Slabs) bool {
	unsafe { mut counts := &Slabs(destination); *counts = Slabs{}; mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0); if length <= 0 || length >= 4096 { return false }; data[int(length)] = 0; mut position := 0; mut large := false
		for position < int(length) { mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 { if counts.rows >= 32 || size != duplicate { return false }; counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++ }
			else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }; for position < int(length) && data[position] != char(10) { position++ }; position++
		}; return counts.rows > 0 && large
	}
}
fn cycle(bank &Bank, ordinary bool) bool {
	unsafe { for upper in [u64(0), 0x100000000, 0x8000000000000000, 0xffffffff00000000, 0x1234567800000000]! {
		if !query(bank, 8, C.R_OK, u32(C.AT_EMPTY_PATH | C.AT_EACCESS), upper, ordinary) || !query(bank, 8, C.W_OK, C.AT_EMPTY_PATH, upper, ordinary) || !query(bank, 4, 0, 0, upper, ordinary) || !query(bank, 7, 0, C.AT_EMPTY_PATH, upper, ordinary) || !query(bank, 8, 0, 1, upper, ordinary) { return false }
		alias := C.dup(bank.fds[3]); if alias < 0 { return false }; data := &C.stat(C.alloca(usize(sizeof(C.stat)))); valid := C.fstat(alias, data) == 0 && same(data, &bank.meta[1]); closed := C.close(alias) == 0; if !valid || !closed { return false }
	}; return true }
}
fn storage(bank &Bank, ordinary bool) bool {
	unsafe { observer := C.open(c'/proc/slabinfo', C.O_RDONLY | C.O_CLOEXEC); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(bank, ordinary) { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(bank, ordinary) { return false } }; C.usleep(13000000); if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for index in 0 .. int(before.rows) { if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }; C.printf(c'LINUX ACCESSFLAGS SLAB: ordinary=%d namespace=0 size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index]) }
		C.printf(c'LINUX ACCESSFLAGS STORAGE: ordinary=%d namespace=0 cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
