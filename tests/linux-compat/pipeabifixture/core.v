// SPDX-License-Identifier: GPL-2.0-or-later
module pipeabifixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_dev u64 st_ino u64 st_mode u32 st_size i64 st_uid u32 st_gid u32 }
struct Counts { mut: calls [4]u64 failures [4]u64 }
struct Bank { mut: fds [9]i32 meta [3]C.stat status [3]i32 slots [64]i32 mapping &u8 page u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fstat(i32, &C.stat) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.ioctl(i32, u64, ...) i32
fn C.pipe2(&i32, i32) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) i64
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
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

fn fatal() { C.puts(c'LINUX PIPEABI FAIL: setup or child protocol'); C.fflush(unsafe { nil }); C._exit(1) }
fn record(counts &Counts, kind i32, good bool, ordinary bool) {
	unsafe { mut value := &Counts(counts); value.calls[kind]++; if !good { value.failures[kind]++; if value.failures[kind] <= 3 { C.printf(c'LINUX PIPEABI DETAIL: ordinary=%d namespace=0 kind=%d call=%lu\n', i32(ordinary), kind, value.calls[kind]); C.fflush(nil) } } }
}
fn same(left &C.stat, right &C.stat) bool { return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode && left.st_size == right.st_size && left.st_uid == right.st_uid && left.st_gid == right.st_gid }
fn prepare(bank &Bank, ordinary bool) {
	unsafe { mut value := &Bank(bank); for index in 0 .. 9 { value.fds[index] = -1 }
		value.page = u64(C.sysconf(C._SC_PAGESIZE)); if value.page < 4096 || value.page > 65536 { fatal() }
		value.mapping = &u8(C.mmap(nil, usize(value.page * 3), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		if isize(value.mapping) == -1 { fatal() }; C.memset(value.mapping, 0xa5, usize(value.page * 3))
		if C.mprotect(value.mapping + value.page, usize(value.page), C.PROT_NONE) != 0 || C.mprotect(value.mapping + value.page * 2, usize(value.page), C.PROT_READ) != 0 { fatal() }
		value.fds[0] = C.open(if ordinary { c'/tmp/pipeabi-u' } else { c'/tmp/pipeabi-r' }, C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, 0o600)
		if value.fds[0] < 0 || C.write(value.fds[0], c'XYZ', 3) != 3 || C.lseek(value.fds[0], 1, C.SEEK_SET) != 1 { fatal() }
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { fatal() }
		ends := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(ends, C.O_NONBLOCK | C.O_CLOEXEC) != 0 { fatal() }; value.fds[3] = ends[0]; value.fds[6] = ends[1]
		if C.write(value.fds[6], c'AB', 2) != 2 { fatal() }
		for group in 0 .. 3 { index := group * 3; if C.fstat(value.fds[index], &value.meta[group]) != 0 { fatal() }; value.status[group] = C.fcntl(value.fds[index], C.F_GETFL)
			value.fds[index + 1] = C.dup(value.fds[index]); value.fds[index + 2] = C.fcntl(value.fds[index], C.F_DUPFD_CLOEXEC, 40)
			if value.status[group] < 0 || value.fds[index + 1] < 0 || value.fds[index + 2] < 0 { fatal() }
		}; for fd in 0 .. 64 { value.slots[fd] = C.fcntl(i32(fd), C.F_GETFD) }
	}
}
fn pair_good(ends &i32, flags u32, ordinary bool) bool {
	unsafe { fds := &i32(C.alloca(usize(6 * sizeof(i32)))); for index in 0 .. 6 { fds[index] = -1 }; fds[0] = ends[0]; fds[3] = ends[1]; mut good := ends[0] >= 0 && ends[1] >= 0 && ends[0] != ends[1]
		data := &C.stat(C.alloca(usize(sizeof(C.stat)))); original := &C.stat(C.alloca(usize(sizeof(C.stat)))); owner := if ordinary { u32(1000) } else { u32(0) }
		for end in 0 .. 2 { *original = C.stat{}; index := end * 3; fds[index + 1] = C.dup(fds[index]); fds[index + 2] = C.fcntl(fds[index], C.F_DUPFD_CLOEXEC, 40)
			if fds[index + 1] < 0 || fds[index + 2] < 0 || C.fstat(fds[index], original) != 0 { good = false }
			for alias in 0 .. 3 { fd := fds[index + alias]; expected_status := u64(if end == 0 { i32(C.O_RDONLY) } else { i32(C.O_WRONLY) }) | u64(flags & u32(C.O_NONBLOCK)); expected_descriptor := if alias == 1 { i32(0) } else if alias == 2 || flags & u32(C.O_CLOEXEC) != 0 { i32(C.FD_CLOEXEC) } else { i32(0) }
				if fd < 0 || C.fstat(fd, data) != 0 || !same(data, original) || data.st_uid != owner || data.st_gid != owner || data.st_mode & u32(C.S_IFMT | 0o777) != u32(C.S_IFIFO | 0o600) || C.fcntl(fd, C.F_GETFD) != expected_descriptor || C.fcntl(fd, C.F_GETFL) != i32(expected_status) || u64(C.syscall(C.SYS_fcntl, fd, C.F_GETFL, 0)) != expected_status { good = false }
			}
		}
		mut bytes := [4]char{}; if good {
			if flags & u32(C.O_NONBLOCK) != 0 { slot := C.__errno_location(); *slot = 0; if C.read(fds[0], &bytes[0], 1) != -1 || *slot != C.EAGAIN { good = false } }
			if C.write(fds[3], c'ABC', 3) != 3 || C.read(fds[1], &bytes[0], 1) != 1 || bytes[0] != char(`A`) || C.read(fds[2], &bytes[0], 2) != 2 || bytes[0] != char(`B`) || bytes[1] != char(`C`) { good = false }
		}
		for index in 3 .. 6 { if fds[index] >= 0 && C.close(fds[index]) != 0 { good = false } }; if good && C.read(fds[0], &bytes[0], 1) != 0 { good = false }
		for index in 0 .. 3 { if fds[index] >= 0 && C.close(fds[index]) != 0 { good = false } }; return good
	}
}
fn query(bank &Bank, flags u64, destination i32, expected i32, ordinary bool) bool {
	unsafe { C.memset(bank.mapping, 0xa5, 64); C.memset(bank.mapping + bank.page - 32, 0xa5, 32)
		pointer := match destination { 0 { voidptr(bank.mapping + 8) } 1 { voidptr(bank.mapping + 9) } 2 { voidptr(nil) } 3 { voidptr(1) } 4 { voidptr(u64(0xffff000000000001)) } 5 { voidptr(bank.mapping + bank.page) } 6 { voidptr(bank.mapping + bank.page * 2) } else { voidptr(bank.mapping + bank.page - 4) } }
		slot := C.__errno_location(); *slot = 0; result := C.syscall(C.SYS_pipe2, pointer, flags); code := *slot
		if result == 0 {
			if destination !in [0, 1] { return false }
			ends := &i32(C.alloca(usize(2 * sizeof(i32)))); C.memcpy(ends, pointer, usize(2 * sizeof(i32)))
			mut good := expected == 0 && code == 0 && destination in [0, 1]
			if good { good = pair_good(ends, u32(flags), ordinary) } else { C.close(ends[0]); C.close(ends[1]) }
			if destination in [0, 1] { offset := if destination == 0 { 8 } else { 9 }; for index in 0 .. 64 { if (index < offset || index >= offset + 8) && bank.mapping[index] != 0xa5 { good = false } } }; return good
		}
		mut good := result == -1 && code == expected
		if expected != C.EFAULT { for index in 0 .. 64 { if bank.mapping[index] != 0xa5 { good = false } }; for index in 0 .. 32 { if bank.mapping[bank.page - 32 + u64(index)] != 0xa5 { good = false } } }
		return good
	}
}
fn state(counts &Counts, bank &Bank, ordinary bool) {
	unsafe { data := &C.stat(C.alloca(usize(sizeof(C.stat)))); for index in 0 .. 9 { record(counts, 3, C.fstat(bank.fds[index], data) == 0 && same(data, &bank.meta[index / 3]) && C.fcntl(bank.fds[index], C.F_GETFL) == bank.status[index / 3] && C.fcntl(bank.fds[index], C.F_GETFD) == if index % 3 == 1 { i32(0) } else { i32(C.FD_CLOEXEC) }, ordinary) }
		mut bytes := [4]char{}; record(counts, 3, C.lseek(bank.fds[0], 0, C.SEEK_CUR) == 1 && C.pread(bank.fds[0], &bytes[0], 3, 0) == 3 && bytes[0] == char(`X`) && bytes[1] == char(`Y`) && bytes[2] == char(`Z`), ordinary)
		mut available := i32(-1); record(counts, 3, C.ioctl(bank.fds[3], C.FIONREAD, &available) == 0 && available == 2, ordinary)
		mut unchanged := true; for fd in 0 .. 64 { if C.fcntl(i32(fd), C.F_GETFD) != bank.slots[fd] { unchanged = false } }; record(counts, 3, unchanged, ordinary)
		record(counts, 3, C.read(bank.fds[3], &bytes[0], 2) == 2 && bytes[0] == char(`A`) && bytes[1] == char(`B`), ordinary)
	}
}
fn qualify(counts &Counts, ordinary bool, reference_run bool) bool {
	unsafe { C.alarm(240); bank := &Bank(C.alloca(usize(sizeof(Bank)))); prepare(bank, ordinary)
		for base in [u32(0), C.O_NONBLOCK, C.O_CLOEXEC, C.O_NONBLOCK | C.O_CLOEXEC]! { for upper in [u64(0), 0x100000000, 0x8000000000000000, 0xffffffff00000000, 0x1234567800000000]! {
			for destination in 0 .. 8 { record(counts, 0, query(bank, u64(base) | upper, i32(destination), if destination < 2 { 0 } else { C.EFAULT }, ordinary), ordinary) }
			for invalid in [u32(C.O_WRONLY), C.O_RDWR, C.O_APPEND, C.O_CREAT, C.O_TRUNC, C.O_PATH, C.O_ASYNC, C.O_DIRECTORY, 0x80000000, 0xffffffff]! { for destination in 0 .. 8 { record(counts, 1, query(bank, u64(base | invalid) | upper, i32(destination), C.EINVAL, ordinary), ordinary) } }
			if !reference_run { for kind in 0 .. 2 { extra := if kind == 0 { u32(C.O_DIRECT) } else { u32(C.O_EXCL) }; code := if kind == 0 { i32(C.EOPNOTSUPP) } else { i32(C.ENOPKG) }; for destination in 0 .. 8 { record(counts, 2, query(bank, u64(base | extra) | upper, i32(destination), code, ordinary), ordinary) } } }
		} }
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0
		if good && !reference_run && !storage(bank, ordinary) { good = false }; state(counts, bank, ordinary)
		for kind in 0 .. 4 { C.printf(c'LINUX PIPEABI CASES: ordinary=%d namespace=0 kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }
		for index in 0 .. 9 { if C.close(bank.fds[index]) != 0 { good = false } }; if C.munmap(bank.mapping, usize(bank.page * 3)) != 0 { good = false }; C.alarm(0); C.fflush(nil); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe { reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0; mut good := true
		for ordinary in [true, false]! { pipe := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(pipe, C.O_CLOEXEC) != 0 { return 1 }; child := C.fork(); if child < 0 { return 1 }
			if child == 0 { C.close(pipe[0]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; passed := qualify(counts, ordinary, reference_run); sent := C.write(pipe[1], counts, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(pipe[1]); C._exit(if passed && sent { 0 } else { 1 }) }
			C.close(pipe[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); received := C.read(pipe[0], counts, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(pipe[0]); mut status := i32(-1); completed := C.waitpid(child, &status, 0) == child && status == 0
			if !received || !completed { good = false }; if received { for kind in 0 .. 4 { C.printf(c'LINUX PIPEABI FINAL: ordinary=%d namespace=0 kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } } }; C.fflush(nil)
		}
		if !good { C.puts(c'LINUX PIPEABI FAIL: native flags, refusal or retained state'); C.fflush(nil); return 1 }; C.puts(if reference_run { c'LINUX PIPEABI REFERENCE: PASS' } else { c'LINUX PIPEABI: PASS' }); C.fflush(nil); for { C.pause() }
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
		if !query(bank, u64(C.O_NONBLOCK | C.O_CLOEXEC) | upper, 1, 0, ordinary) || !query(bank, u64(C.O_APPEND) | upper, 0, C.EINVAL, ordinary) || !query(bank, u64(C.O_CREAT) | upper, 7, C.EINVAL, ordinary) || !query(bank, u64(C.O_DIRECT) | upper, 0, C.EOPNOTSUPP, ordinary) || !query(bank, u64(C.O_EXCL) | upper, 2, C.ENOPKG, ordinary) { return false }
	}; return true }
}
fn storage(bank &Bank, ordinary bool) bool {
	unsafe { observer := C.open(c'/proc/slabinfo', C.O_RDONLY | C.O_CLOEXEC); if observer < 0 { return false }
		for _ in 0 .. 32 { if !cycle(bank, ordinary) { C.close(observer); return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { C.close(observer); return false }
		for _ in 0 .. 200 { if !cycle(bank, ordinary) { C.close(observer); return false } }; C.usleep(13000000); if !snapshot(observer, after) { C.close(observer); return false }; mut good := before.rows == after.rows && before.large == after.large
		for index in 0 .. int(before.rows) { if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }; C.printf(c'LINUX PIPEABI SLAB: ordinary=%d namespace=0 size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index]) }
		C.printf(c'LINUX PIPEABI STORAGE: ordinary=%d namespace=0 cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); C.close(observer); return good
	}
}
