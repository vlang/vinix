// SPDX-License-Identifier: GPL-2.0-or-later
module pipesizefixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#define __EXPORTED_HEADERS__
#include <linux/capability.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_dev u64 st_ino u64 st_mode u32 st_uid u32 st_gid u32 st_nlink u64 st_size i64 }
struct C.rlimit { mut: rlim_cur u64 rlim_max u64 }
struct Counts { mut: calls [5]u64 failures [5]u64 capability bool }
struct C.__user_cap_header_struct { mut: version u32 pid i32 }
struct C.__user_cap_data_struct { mut: effective u32 permitted u32 inheritable u32 }
struct Bank { mut: fds [29]i32 meta [29]C.stat flags [29]i32 status [29]i32 cursor [29]i64 capacity [29]i64 slots [80]i32 peer i32 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Query { ret isize code i32 }
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.sysconf(i32) i64
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.dup3(i32, i32, i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fstat(i32, &C.stat) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.ioctl(i32, u64, ...) i32
fn C.pipe2(&i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.mkdir(&char, u32) i32
fn C.mkfifo(&char, u32) i32
fn C.unlink(&char) i32
fn C.getrlimit(i32, &C.rlimit) i32
fn C.setrlimit(i32, &C.rlimit) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C._exit(i32)

fn fatal() { C.puts(c'LINUX PIPESIZE FAIL: setup or child protocol'); C.fflush(unsafe { nil }); C._exit(1) }
fn query(fd u64, cmd u64, arg u64) Query {
	unsafe { slot := C.__errno_location(); *slot = 0; ret := C.syscall(C.SYS_fcntl, fd, cmd, arg); return Query{ret, *slot} }
}
fn words(source u32, cmd u32, arg u64, prefix i32) Query {
	fd := u64(source) | if prefix == 1 || prefix == 4 { u64(0xffffffff00000000) } else { 0 }
	command := u64(cmd) | if prefix == 2 || prefix == 4 { u64(0x8000000000000000) } else { 0 }
	value := arg | if prefix == 3 { u64(0xabcdef0100000000) } else if prefix == 4 { u64(0xffffffff00000000) } else { 0 }
	return query(fd, command, value)
}
fn record(counts &Counts, kind i32, good bool, ordinary bool, result Query) {
	unsafe { mut value := &Counts(counts); value.calls[kind]++; if !good { value.failures[kind]++; if value.failures[kind] <= 3 { C.printf(c'LINUX PIPESIZE DETAIL: ordinary=%d capability=%d kind=%d call=%lu ret=%ld errno=%d\n', i32(ordinary), i32(value.capability), kind, value.calls[kind], result.ret, result.code); C.fflush(nil) } } }
}
fn pipe_index(index i32) bool { return (index >= 18 && index <= 26) || index == 28 }
fn equal(left &C.stat, right &C.stat) bool {
	return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode && left.st_uid == right.st_uid && left.st_gid == right.st_gid && left.st_nlink == right.st_nlink && left.st_size == right.st_size
}
fn stable(bank &Bank, index i32) bool {
	unsafe { data := &C.stat(C.alloca(usize(sizeof(C.stat)))); fd := bank.fds[index]; return C.fstat(fd, data) == 0 && equal(data, &bank.meta[index]) && C.fcntl(fd, C.F_GETFD) == bank.flags[index] && C.fcntl(fd, C.F_GETFL) == bank.status[index] && C.lseek(fd, 0, C.SEEK_CUR) == bank.cursor[index] }
}
fn available(fd i32, amount i32) bool {
	unsafe { count := &i32(C.alloca(usize(sizeof(i32)))); *count = -1; return C.ioctl(fd, u64(C.FIONREAD), count) == 0 && *count == amount }
}
fn prepare(bank &Bank) {
	unsafe { mut value := &Bank(bank); for index in 0 .. 29 { value.fds[index] = -1 }
		value.fds[0] = C.open(c'/tmp/pipesize-file', C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, 0o600)
		value.fds[3] = C.open(c'/tmp/pipesize-gone', C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, 0o600)
		if value.fds[0] < 0 || value.fds[3] < 0 || C.unlink(c'/tmp/pipesize-gone') != 0 || C.mkdir(c'/tmp/pipesize-dir', 0o700) != 0 || C.mkfifo(c'/tmp/pipesize-fifo', 0o600) != 0 { fatal() }
		for index in [i32(0), 3]! { if C.write(value.fds[index], c'XYZ', 3) != 3 || C.lseek(value.fds[index], 1, C.SEEK_SET) != 1 { fatal() } }
		value.fds[6] = C.open(c'/tmp/pipesize-dir', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		value.fds[9] = C.open(c'/dev/null', C.O_RDWR | C.O_CLOEXEC)
		pair := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.socketpair(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_NONBLOCK | C.SOCK_CLOEXEC, 0, pair) != 0 { fatal() }; value.fds[12] = pair[0]; value.peer = pair[1]
		value.fds[15] = C.open(c'/tmp/pipesize-file', C.O_PATH | C.O_CLOEXEC)
		if C.pipe2(pair, C.O_NONBLOCK | C.O_CLOEXEC) != 0 { fatal() }; value.fds[18] = pair[0]; value.fds[21] = pair[1]
		value.fds[24] = C.open(c'/tmp/pipesize-fifo', C.O_RDWR | C.O_NONBLOCK | C.O_CLOEXEC)
		for class in 0 .. 9 { index := class * 3; if value.fds[index] < 0 { fatal() }; value.fds[index + 1] = C.dup(value.fds[index]); value.fds[index + 2] = C.fcntl(value.fds[index], C.F_DUPFD_CLOEXEC, 40); if value.fds[index + 1] < 0 || value.fds[index + 2] < 0 { fatal() } }
		if C.dup3(value.fds[0], 64, C.O_CLOEXEC) != 64 || C.dup3(value.fds[21], 65, 0) != 65 { fatal() }; value.fds[27] = 64; value.fds[28] = 65
	}
}
fn capture(bank &Bank) {
	unsafe { mut value := &Bank(bank); for index in 0 .. 29 {
		fd := value.fds[index]; if C.fstat(fd, &value.meta[index]) != 0 { fatal() }; value.flags[index] = C.fcntl(fd, C.F_GETFD); value.status[index] = C.fcntl(fd, C.F_GETFL); value.cursor[index] = C.lseek(fd, 0, C.SEEK_CUR)
		if value.flags[index] < 0 || value.status[index] < 0 { fatal() }; if pipe_index(i32(index)) { value.capacity[index] = C.fcntl(fd, C.F_GETPIPE_SZ); if value.capacity[index] < 4096 { fatal() } }
	}; for fd in 0 .. 80 { value.slots[fd] = C.fcntl(i32(fd), C.F_GETFD) } }
}
fn caps(data &C.__user_cap_data_struct, update bool) bool {
	unsafe { header := &C.__user_cap_header_struct(C.alloca(usize(sizeof(C.__user_cap_header_struct)))); *header = C.__user_cap_header_struct{version: u32(C._LINUX_CAPABILITY_VERSION_3)}; return C.syscall(if update { isize(C.SYS_capset) } else { isize(C.SYS_capget) }, header, data) == 0 }
}
fn effective(enabled bool) {
	unsafe { data := &C.__user_cap_data_struct(C.alloca(usize(2 * sizeof(C.__user_cap_data_struct)))); if !caps(data, false) { fatal() }; if enabled { data[0].effective |= u32(1) << 24 } else { data[0].effective &= ~(u32(1) << 24) }; if !caps(data, true) { fatal() } }
}
fn credentials(ordinary bool, capability bool) {
	unsafe {
		if ordinary {
			if capability && C.syscall(C.SYS_prctl, u64(C.PR_SET_KEEPCAPS), u64(1), u64(0), u64(0), u64(0)) != 0 { fatal() }
			if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { fatal() }
		}
		effective(capability)
		data := &C.__user_cap_data_struct(C.alloca(usize(2 * sizeof(C.__user_cap_data_struct)))); if !caps(data, false) || (data[0].effective & (u32(1) << 24) != 0) != capability { fatal() }
	}
}
fn rounded(request u64, page u64) u64 { mut result := page; for result < request { result *= 2 }; return result }
fn state(bank &Bank, index i32, expected i64) bool {
	unsafe {
	if !stable(bank, index) { return false }
	if !pipe_index(index) { return true }
	for other in 0 .. 29 { if pipe_index(i32(other)) && bank.meta[other].st_ino == bank.meta[index].st_ino && C.fcntl(bank.fds[other], C.F_GETPIPE_SZ) != expected { return false } }
	return available(bank.fds[18], 2) && available(bank.fds[12], 2) && available(bank.fds[24], 2)
	}
}
// Each request begins with the captured capacity. Refusals must preserve it,
// and successes must be visible through every alias without consuming data.
fn checked(counts &Counts, bank &Bank, index i32, arg u64, prefix i32, kind i32, ordinary bool, libc bool, wanted i64, code i32) {
	unsafe {
		if pipe_index(index) && C.fcntl(bank.fds[index], C.F_SETPIPE_SZ, bank.capacity[index]) != bank.capacity[index] { fatal() }
		mut result := Query{}; if libc { slot := C.__errno_location(); *slot = 0; result = Query{isize(C.fcntl(bank.fds[index], C.F_SETPIPE_SZ, arg)), *slot} } else { result = words(u32(bank.fds[index]), u32(C.F_SETPIPE_SZ), arg, prefix) }
		expected := if wanted < 0 { bank.capacity[index] } else { wanted }
		record(counts, kind, result.ret == wanted && result.code == code && state(bank, index, expected), ordinary, result)
		if pipe_index(index) && C.fcntl(bank.fds[index], C.F_SETPIPE_SZ, bank.capacity[index]) != bank.capacity[index] { fatal() }
	}
}
fn matrix(counts &Counts, bank &Bank, ordinary bool, page u64) {
	unsafe {
		for index in 0 .. 29 {
			if pipe_index(i32(index)) {
				for arg in [u64(0), 1, 4095, 4096, 4097, 8191, 8192, 8193, 16383, 16384, 16385, 32768, 65535, 65536, 65537, 1048576]! { for prefix in 0 .. 6 { checked(counts, bank, i32(index), arg, i32(prefix % 5), 0, ordinary, prefix == 5, i64(rounded(arg, page)), 0) } }
				for arg in [u64(0x80000001), 0x90000000, 0xfffffffe, 0xffffffff]! { for prefix in 0 .. 6 { checked(counts, bank, i32(index), arg, i32(prefix % 5), 1, ordinary, prefix == 5, -1, C.EINVAL) } }
				for arg in [u64(1048577), 1572864, 2097152]! { for prefix in 0 .. 6 { checked(counts, bank, i32(index), arg, i32(prefix % 5), 2, ordinary, prefix == 5, if counts.capability { i64(2097152) } else { -1 }, if counts.capability { i32(0) } else { i32(C.EPERM) }) } }
				if !counts.capability { for prefix in 0 .. 6 { checked(counts, bank, i32(index), 0x80000000, i32(prefix % 5), 2, ordinary, prefix == 5, -1, C.EPERM) } }
			} else { for arg in [u64(0x80000001), 0x90000000, 0xfffffffe, 0xffffffff]! { for prefix in 0 .. 5 { checked(counts, bank, i32(index), arg, i32(prefix), 1, ordinary, false, -1, C.EBADF) } } }
		}
		for source in [u32(127), 0x80000000, 0xffffffff]! { for arg in [u64(0x80000001), 0x90000000, 0xfffffffe, 0xffffffff]! { for prefix in 0 .. 5 { result := words(source, u32(C.F_SETPIPE_SZ), arg, i32(prefix)); record(counts, 1, result.ret == -1 && result.code == C.EBADF, ordinary, result) } } }
		limits := &C.rlimit(C.alloca(usize(sizeof(C.rlimit)))); if C.getrlimit(C.RLIMIT_NOFILE, limits) != 0 { fatal() }; saved := limits.rlim_cur
		for limit in [u64(8), 0]! {
			limits.rlim_cur = limit; if C.setrlimit(C.RLIMIT_NOFILE, limits) != 0 { fatal() }
			for index in [i32(27), 28]! { for prefix in 0 .. 5 {
				checked(counts, bank, index, 0, i32(prefix), 0, ordinary, false, if pipe_index(index) { i64(page) } else { -1 }, if pipe_index(index) { i32(0) } else { i32(C.EBADF) })
				checked(counts, bank, index, 0xffffffff, i32(prefix), 1, ordinary, false, -1, if pipe_index(index) { i32(C.EINVAL) } else { i32(C.EBADF) })
			} }
		}; limits.rlim_cur = saved; if C.setrlimit(C.RLIMIT_NOFILE, limits) != 0 { fatal() }
		// Reuse the same numeric descriptor for closed, pipe and regular states.
		for step in 0 .. 4 {
			if step == 1 && C.dup3(bank.fds[21], 66, 0) != 66 { fatal() }
			if step == 2 && C.dup3(bank.fds[0], 66, C.O_CLOEXEC) != 66 { fatal() }
			if step == 3 && C.close(66) != 0 { fatal() }
			for prefix in 0 .. 5 { for arg in [u64(0), 0xffffffff]! {
				result := words(66, u32(C.F_SETPIPE_SZ), arg, i32(prefix)); wanted := if step == 1 && arg == 0 { isize(page) } else { -1 }; code := if step == 1 { if arg == 0 { i32(0) } else { i32(C.EINVAL) } } else { i32(C.EBADF) }
				record(counts, if arg == 0 { 0 } else { 1 }, result.ret == wanted && result.code == code && state(bank, 21, if step == 1 && arg == 0 { i64(page) } else { bank.capacity[21] }), ordinary, result)
				if C.fcntl(bank.fds[21], C.F_SETPIPE_SZ, bank.capacity[21]) != bank.capacity[21] { fatal() }
			} }
		}
		if counts.capability { for index in [i32(21), 24]! {
			result := words(u32(bank.fds[index]), u32(C.F_SETPIPE_SZ), 2097152, 0); record(counts, 2, result.ret == 2097152 && result.code == 0 && state(bank, index, 2097152), ordinary, result)
			effective(false)
			for arg in [u64(1048577), 1572864, 2097152]! { value := words(u32(bank.fds[index]), u32(C.F_SETPIPE_SZ), arg, 0); record(counts, 2, value.ret == 2097152 && value.code == 0 && state(bank, index, 2097152), ordinary, value) }
			before := C.fcntl(bank.fds[index], C.F_GETPIPE_SZ); denied := words(u32(bank.fds[index]), u32(C.F_SETPIPE_SZ), 2097153, 0); record(counts, 2, denied.ret == -1 && denied.code == C.EPERM && state(bank, index, before), ordinary, denied)
			shrunk := words(u32(bank.fds[index]), u32(C.F_SETPIPE_SZ), 1048576, 0); record(counts, 2, shrunk.ret == 1048576 && shrunk.code == 0 && state(bank, index, 1048576), ordinary, shrunk)
			refused := words(u32(bank.fds[index]), u32(C.F_SETPIPE_SZ), 1048577, 0); record(counts, 2, refused.ret == -1 && refused.code == C.EPERM && state(bank, index, 1048576), ordinary, refused)
			if C.fcntl(bank.fds[index], C.F_SETPIPE_SZ, bank.capacity[index]) != bank.capacity[index] { fatal() }; effective(true)
		} }
	}
}
fn final_state(counts &Counts, bank &Bank, ordinary bool) {
	unsafe {
		for index in 0 .. 29 { record(counts, 4, stable(bank, i32(index)), ordinary, Query{}); if pipe_index(i32(index)) { record(counts, 4, C.fcntl(bank.fds[index], C.F_GETPIPE_SZ) == bank.capacity[index], ordinary, Query{}) } }
		data := C.alloca(usize(8)); for index in [i32(0), 3]! { record(counts, 4, C.pread(bank.fds[index], data, 3, 0) == 3 && C.memcmp(data, c'XYZ', 3) == 0 && C.lseek(bank.fds[index], 0, C.SEEK_CUR) == 1, ordinary, Query{}) }
		for index in [i32(18), 12, 24]! { record(counts, 4, available(bank.fds[index], 2), ordinary, Query{}) }
		mut slots := true; for fd in 0 .. 80 { if C.fcntl(i32(fd), C.F_GETFD) != bank.slots[fd] { slots = false } }; record(counts, 4, slots, ordinary, Query{})
		for index, source in [i32(18), 12, 24]! { target := if index == 0 { &char(c'AB') } else if index == 1 { &char(c'CD') } else { &char(c'GH') }; record(counts, 4, C.read(bank.fds[source], data, 2) == 2 && C.memcmp(data, target, 2) == 0, ordinary, Query{}) }
	}
}
fn filled(data voidptr, length u64, expected u8) bool { unsafe { bytes := &u8(data); for index in 0 .. int(length) { if bytes[index] != expected { return false } }; return true } }
fn positive(counts &Counts, bank &Bank, ordinary bool, page u64) {
	unsafe {
		data := C.mmap(nil, usize(8 * page), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0); if data == voidptr(-1) { fatal() }
		ends := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(ends, C.O_NONBLOCK | C.O_CLOEXEC) != 0 { fatal() }
		alias := C.dup(ends[0]); if alias < 0 { fatal() }
		for resource in 0 .. 2 {
			reader := if resource == 0 { ends[0] } else { bank.fds[24] }; writer := if resource == 0 { ends[1] } else { bank.fds[24] }; observer := if resource == 0 { alias } else { bank.fds[26] }
			original := C.fcntl(reader, C.F_GETPIPE_SZ); initial := words(u32(writer), u32(C.F_SETPIPE_SZ), 2 * page, 0); record(counts, 3, initial.ret == isize(2 * page) && initial.code == 0, ordinary, initial)
			C.memset(data, `Q`, usize(8 * page)); record(counts, 3, C.write(writer, data, usize(2 * page - 1)) == isize(2 * page - 1), ordinary, Query{})
			record(counts, 3, C.read(reader, data, usize(2 * page - 2)) == isize(2 * page - 2) && filled(data, 2 * page - 2, `Q`), ordinary, Query{})
			record(counts, 3, C.write(writer, c'RST', 3) == 3, ordinary, Query{})
			grown := words(u32(writer), u32(C.F_SETPIPE_SZ), 4 * page, 0); record(counts, 3, grown.ret == isize(4 * page) && grown.code == 0, ordinary, grown)
			record(counts, 3, C.fcntl(observer, C.F_GETPIPE_SZ) == i32(4 * page) && available(reader, 4), ordinary, Query{})
			record(counts, 3, C.read(reader, data, 4) == 4 && C.memcmp(data, c'QRST', 4) == 0, ordinary, Query{})
			reset := words(u32(writer), u32(C.F_SETPIPE_SZ), 2 * page, 0); record(counts, 3, reset.ret == isize(2 * page) && reset.code == 0, ordinary, reset)
			C.memset(data, `Q`, usize(8 * page)); record(counts, 3, C.write(writer, data, usize(2 * page)) == isize(2 * page) && available(reader, i32(2 * page)), ordinary, Query{})
			overflow := words(u32(writer), u32(C.F_SETPIPE_SZ), 0xffffffff, 0); record(counts, 1, overflow.ret == -1 && overflow.code == C.EINVAL && C.fcntl(observer, C.F_GETPIPE_SZ) == i32(2 * page) && available(reader, i32(2 * page)), ordinary, overflow)
			busy := words(u32(writer), u32(C.F_SETPIPE_SZ), page, 0); record(counts, 3, busy.ret == -1 && busy.code == C.EBUSY && C.fcntl(observer, C.F_GETPIPE_SZ) == i32(2 * page) && available(reader, i32(2 * page)), ordinary, busy)
			record(counts, 3, C.read(reader, data, usize(2 * page - 1)) == isize(2 * page - 1) && filled(data, 2 * page - 1, `Q`), ordinary, Query{})
			shrunk := words(u32(writer), u32(C.F_SETPIPE_SZ), page, 0); record(counts, 3, shrunk.ret == isize(page) && shrunk.code == 0 && C.fcntl(observer, C.F_GETPIPE_SZ) == i32(page) && available(reader, 1), ordinary, shrunk)
			record(counts, 3, C.read(reader, data, 1) == 1 && filled(data, 1, `Q`), ordinary, Query{})
			restored := words(u32(writer), u32(C.F_SETPIPE_SZ), u64(original), 0); record(counts, 3, restored.ret == original && restored.code == 0 && C.fcntl(observer, C.F_GETPIPE_SZ) == original && available(reader, 0), ordinary, restored)
		}
		if C.close(alias) != 0 || C.close(ends[0]) != 0 || C.close(ends[1]) != 0 || C.munmap(data, usize(8 * page)) != 0 { fatal() }
	}
}
fn cycle(bank &Bank, capability bool, page u64) bool {
	unsafe {
		for index in [i32(0), 12, 15, 18, 24]! {
			alias := C.dup(bank.fds[index]); if alias < 0 { return false }; mut good := true
			if pipe_index(index) {
				for amount in [page, 2 * page, u64(65536)]! { value := words(u32(alias), u32(C.F_SETPIPE_SZ), amount, 4); if value.ret != isize(amount) || value.code != 0 || !state(bank, index, i64(amount)) { good = false } }
				if capability { value := words(u32(alias), u32(C.F_SETPIPE_SZ), 2097152, 4); if value.ret != 2097152 || value.code != 0 || !state(bank, index, 2097152) { good = false }; if C.fcntl(alias, C.F_SETPIPE_SZ, bank.capacity[index]) != bank.capacity[index] { good = false } }
			} else { value := words(u32(alias), u32(C.F_SETPIPE_SZ), 0xffffffff, 4); if value.ret != -1 || value.code != C.EBADF { good = false } }
			if C.close(alias) != 0 || !stable(bank, index) { good = false }; if !good { return false }
		}
		return available(bank.fds[18], 2) && available(bank.fds[12], 2) && available(bank.fds[24], 2)
	}
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
fn storage(bank &Bank, ordinary bool, capability bool, page u64) bool {
	unsafe { observer := C.open(c'/proc/slabinfo', C.O_RDONLY | C.O_CLOEXEC); if observer < 0 { return false }
		for _ in 0 .. 32 { if !cycle(bank, capability, page) { C.close(observer); return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { C.close(observer); return false }
		for _ in 0 .. 200 { if !cycle(bank, capability, page) { C.close(observer); return false } }; C.usleep(13000000); if !snapshot(observer, after) { C.close(observer); return false }; mut good := before.rows == after.rows && before.large == after.large
		for index in 0 .. int(before.rows) { if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }; C.printf(c'LINUX PIPESIZE SLAB: ordinary=%d capability=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), i32(capability), before.sizes[index], before.live[index], after.live[index]) }
		C.printf(c'LINUX PIPESIZE STORAGE: ordinary=%d capability=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), i32(capability), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); if C.close(observer) != 0 { good = false }; return good
	}
}
fn qualify(bank &Bank, counts &Counts, ordinary bool, reference bool) bool {
	unsafe { C.alarm(600); credentials(ordinary, counts.capability)
		page := u64(C.sysconf(C._SC_PAGESIZE)); if page < 4096 || page > 16384 || page & (page - 1) != 0 { fatal() }
		C.printf(c'LINUX PIPESIZE PAGE: ordinary=%d capability=%d bytes=%lu reference=%d\n', i32(ordinary), i32(counts.capability), page, i32(reference)); C.fflush(nil)
		limits := &C.rlimit(C.alloca(usize(sizeof(C.rlimit)))); if C.getrlimit(C.RLIMIT_NOFILE, limits) != 0 { fatal() }; limits.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, limits) != 0 { fatal() }
		capture(bank); matrix(counts, bank, ordinary, page); mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0
		if good && !reference && !storage(bank, ordinary, counts.capability, page) { good = false }; final_state(counts, bank, ordinary); positive(counts, bank, ordinary, page)
		for kind in 0 .. 5 { C.printf(c'LINUX PIPESIZE CASES: ordinary=%d capability=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), i32(counts.capability), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.alarm(0); C.fflush(nil); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe { reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0; bank := &Bank(C.alloca(usize(sizeof(Bank)))); *bank = Bank{}; prepare(bank); mut good := true
		for group in 0 .. 4 {
			ordinary := group >= 2; capability := group % 2 == 0
			ends := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(ends, C.O_CLOEXEC) != 0 || C.write(bank.fds[21], c'AB', 2) != 2 || C.write(bank.peer, c'CD', 2) != 2 || C.write(bank.fds[24], c'GH', 2) != 2 { fatal() }
			child := C.fork(); if child < 0 { fatal() }; if child == 0 { C.close(ends[0]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{capability: capability}; passed := qualify(bank, counts, ordinary, reference); sent := C.write(ends[1], counts, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[1]); C._exit(if passed && sent { 0 } else { 1 }) }
			C.close(ends[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); received := C.read(ends[0], counts, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[0]); mut status := i32(-1); completed := C.waitpid(child, &status, 0) == child && status == 0
			if !received || !completed { good = false }; if received { for kind in 0 .. 5 { C.printf(c'LINUX PIPESIZE FINAL: ordinary=%d capability=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), i32(capability), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } } }; C.fflush(nil)
		}
		for index in 0 .. 29 { if C.close(bank.fds[index]) != 0 { good = false } }; if C.close(bank.peer) != 0 { good = false }
		if !good { C.puts(c'LINUX PIPESIZE FAIL: resizing or retained state'); C.fflush(nil); return 1 }; C.puts(if reference { c'LINUX PIPESIZE REFERENCE: PASS' } else { c'LINUX PIPESIZE: PASS' }); C.fflush(nil); for { C.pause() }
	}; return 0
}
