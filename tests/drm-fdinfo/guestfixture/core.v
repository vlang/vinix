// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/fsuid.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/reboot.h>
#include <sys/resource.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, u64) i64
fn C.readlinkat(i32, &char, voidptr, u64) i64
fn C.syscall(isize, ...) isize
fn C.lseek(i32, i64, i32) i64
fn C.write(i32, voidptr, u64) i64
fn C.ioctl(i32, i32, ...) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.mprotect(voidptr, usize, i32) i32
fn C.mremap(voidptr, usize, usize, i32, ...) voidptr
fn C.getpagesize() i32
fn C.setfsuid(u32) i32
fn C.setfsgid(u32) i32
fn C.clock_gettime(i32, &C.timespec) i32
fn C.fstat(i32, &C.stat) i32
fn C.fstatfs(i32, &C.statfs) i32
fn C.fcntl(i32, i32, ...) i32
fn C.ftruncate(i32, i64) i32
fn C.poll(&C.pollfd, u64, i32) i32
fn C.__errno_location() &i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.fork() i32
fn C.signal(i32, voidptr) voidptr
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.alarm(u32) u32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFSIGNALED(i32) i32
fn C.WTERMSIG(i32) i32
fn C.snprintf(voidptr, u64, &char, ...) i32
fn C.strstr(voidptr, &char) &char
fn C.strlen(&char) u64
fn C.strcmp(&char, &char) i32
fn C.strncmp(&char, &char, u64) i32
fn C.strtoull(&char, &&char, i32) u64
fn C.sscanf(&char, &char, ...) i32
fn C.fopen(&char, &char) voidptr
fn C.fgets(&char, i32, voidptr) &char
fn C.fclose(voidptr) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.reboot(i32) i32
fn C.pause() i32
fn C.pipe(&i32) i32
fn C.getpid() i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.prctl(i32, ...) i32
fn C.unshare(i32) i32
fn C.setrlimit(i32, &C.rlimit) i32
fn C.setresuid(u32, u32, u32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.sendmsg(i32, &C.msghdr, i32) i64
fn C.recvmsg(i32, &C.msghdr, i32) i64

struct C.sigaction {
	sa_handler fn (i32)
	sa_flags i32
}

struct C.rlimit {
	rlim_cur u64
	rlim_max u64
}

struct C.timespec {
	tv_sec i64
	tv_nsec i64
}

struct C.signalfd_siginfo {
	ssi_signo u32
	ssi_errno i32
	ssi_code i32
	ssi_pid u32
	ssi_uid u32
}

struct C.stat {
	st_dev u64
	st_ino u64
	st_mode u32
	st_nlink u64
	st_uid u32
	st_gid u32
	st_size i64
	st_blksize i64
	st_blocks i64
	st_atim C.timespec
	st_mtim C.timespec
	st_ctim C.timespec
}

@[typedef]
struct C.fsid_t {}

struct C.statfs {
	f_type u64
	f_bsize u64
	f_frsize u64
	f_namelen u64
	f_blocks u64
	f_files u64
	f_fsid C.fsid_t
}

struct C.pollfd {
mut:
	fd i32
	events i16
	revents i16
}

struct C.iovec {
	iov_base voidptr
	iov_len usize
}

struct C.cmsghdr {
	cmsg_len usize
	cmsg_level i32
	cmsg_type i32
}

struct C.msghdr {
	msg_iov &C.iovec
	msg_iovlen usize
	msg_control voidptr
	msg_controllen usize
}

fn read_fdinfo(fd i32, buffer voidptr, capacity u64) bool {
	if fd < 0 { return false }
	mut path := [64]u8{}
	C.snprintf(&path[0], sizeof(path), c'/proc/self/fdinfo/%d', fd)
	info := C.open(unsafe { &char(&path[0]) }, C.O_RDONLY)
	if info < 0 { return false }
	count := C.read(info, buffer, capacity - 1)
	C.close(info)
	return count > 0
}

// Zero means fdinfo has no DRM client line. A negative result is a read or
// format error.
fn client_id(fd i32) i64 {
	mut buffer := [512]u8{}
	if !read_fdinfo(fd, &buffer[0], sizeof(buffer)) { return -1 }
	key := c'\ndrm-client-id:\t'
	line := C.strstr(&buffer[0], key)
	if line == unsafe { nil } { return 0 }
	value := unsafe { line + C.strlen(key) }
	mut end := &char(unsafe { nil })
	id := C.strtoull(value, &end, 10)
	if end == value || unsafe { *end } != char(10) { return -1 }
	return i64(id)
}

fn test_open_order() bool {
	card := c'/dev/dri/card0'
	first := C.open(card, C.O_RDWR)
	path := C.open(card, C.O_PATH)
	ordinary := C.open(c'/dev/null', C.O_RDONLY)
	second := C.open(card, C.O_RDWR)
	if first < 0 || second < 0 || path < 0 || ordinary < 0 { return false }

	newer := client_id(second)
	older := client_id(first)
	C.printf(c'DRM client IDs in open order: %ld %ld\n', older, newer)
	if older <= 0 || newer != older + 1 { return false }
	if client_id(path) != 0 || client_id(ordinary) != 0 { return false }
	dup := C.dup(first)
	if dup < 0 { return false }
	C.close(first)
	if client_id(dup) != older { return false }

	child := C.fork()
	if child == 0 { C._exit(if client_id(dup) == older { 0 } else { 1 }) }
	mut status := i32(0)
	if child < 0 || C.waitpid(child, &status, 0) != child || status != 0 { return false }

	reopened := C.open(card, C.O_RDWR)
	passed := reopened == first && client_id(reopened) == newer + 1 && client_id(second) == newer
	C.close(reopened)
	C.close(dup)
	C.close(second)
	C.close(ordinary)
	C.close(path)
	return passed
}

struct ClientNameRequest {
	length u64
	address u64
}

fn set_name(fd i32, address u64, length u64) i32 {
	request := ClientNameRequest{length: length, address: address}
	result := C.ioctl(fd, i32(u32(0xc01064d1)), &request)
	return if result == -1 { unsafe { *C.__errno_location() } } else { result }
}

fn has_name(fd i32, name &char) bool {
	mut buffer := [512]u8{}
	if !read_fdinfo(fd, &buffer[0], sizeof(buffer)) { return false }
	if name == unsafe { nil } {
		return C.strstr(&buffer[0], c'\ndrm-client-name:\t') == unsafe { nil }
	}
	mut expected := [96]u8{}
	C.snprintf(&expected[0], sizeof(expected), c'\ndrm-client-name:\t%s\n', name)
	return C.strstr(&buffer[0], unsafe { &char(&expected[0]) }) != unsafe { nil }
}

fn test_client_names() bool {
	card := c'/dev/dri/card0'
	fd := C.open(card, C.O_RDWR)
	other := C.open(card, C.O_RDWR)
	path := C.open(card, C.O_PATH)
	alias := C.dup(fd)
	if fd < 0 || other < 0 || path < 0 || alias < 0 { return false }
	defer {
		C.close(alias)
		C.close(path)
		C.close(other)
		C.close(fd)
	}
	if !has_name(fd, unsafe { nil }) { return false }
	name := c'Mesa-worker_0'
	if set_name(alias, u64(name), C.strlen(name)) != 0
		|| !has_name(fd, name) || !has_name(other, unsafe { nil }) { return false }
	if set_name(path, u64(name), C.strlen(name)) != C.EBADF { return false }

	long_name := c'0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-~'
	if C.strlen(long_name) != 64 || set_name(fd, u64(long_name), 64) != 0
		|| !has_name(alias, long_name) { return false }
	invalid := [u8(0), 0x09, 0x20, 0x7f, 0x80]!
	for i in 0 .. invalid.len {
		if set_name(fd, u64(unsafe { &invalid[i] }), 1) != C.EINVAL { return false }
	}
	if set_name(fd, 0, 65) != C.EINVAL || set_name(fd, 0, 1) != C.EFAULT
		|| set_name(fd, ~u64(0), 2) != C.EFAULT || !has_name(alias, long_name) { return false }

	if set_name(alias, ~u64(0), 0) != 0 || !has_name(fd, unsafe { nil }) { return false }
	if set_name(fd, u64(name), C.strlen(name)) != 0 { return false }
	// A short read/write request supplies only the zero length.
	mut zero_length := u64(0)
	if C.ioctl(fd, i32(u32(0xc00864d1)), &zero_length) != 0
		|| !has_name(alias, unsafe { nil }) { return false }
	return true
}

const clients_path = c'/sys/kernel/debug/dri/0/clients'

fn same_client_rows(expected &char) bool {
	info := C.open(clients_path, C.O_RDONLY)
	if info < 0 { return false }
	defer { C.close(info) }
	return match_client_rows(info, expected)
}

fn match_client_rows(info i32, expected &char) bool {
	mut actual := [512]u8{}
	count := C.read(info, &actual[0], sizeof(actual) - 1)
	return count >= 0 && C.strcmp(expected, unsafe { &char(&actual[0]) }) == 0
}

fn format_client_header(buffer voidptr, capacity u64) i32 {
	return C.snprintf(buffer, capacity,
		c'%20s %5s %3s master a %5s %10s %64s %20s\n',
		c'command', c'tgid', c'dev', c'uid', c'magic', c'name', c'id')
}

fn format_client_row(buffer voidptr, capacity u64, command &char, pid i32, uid u32, name &char, id u64) i32 {
	return C.snprintf(buffer, capacity, c'%20s %5d %3d   n    y %5d %10u %64s %20lu\n',
		command, pid, i32(0), i32(uid), u32(0), name, id)
}

fn test_debugfs_clients() bool {
	mut expected := [512]u8{}
	header_len := format_client_header(&expected[0], sizeof(expected))
	if !same_client_rows(unsafe { &char(&expected[0]) }) { return false }
	if C.prctl(C.PR_SET_NAME, c'vinix-clients', u64(0), u64(0), u64(0)) != 0 { return false }
	card := c'/dev/dri/card0'
	first := C.open(card, C.O_RDWR)
	path := C.open(card, C.O_PATH)
	second := C.open(card, C.O_RDWR)
	alias := C.dup(first)
	if first < 0 || path < 0 || second < 0 || alias < 0 { return false }
	C.close(first)
	name := c'0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-~'
	if set_name(second, u64(name), 64) != 0 { return false }
	first_len := format_client_row(unsafe { &expected[header_len] }, sizeof(expected) - u64(header_len),
		c'vinix-clients', C.getpid(), C.geteuid(), c'<unset>', u64(client_id(alias)))
	second_at := header_len + first_len
	format_client_row(unsafe { &expected[second_at] }, sizeof(expected) - u64(second_at),
		c'vinix-clients', C.getpid(), C.geteuid(), name, u64(client_id(second)))
	if !same_client_rows(unsafe { &char(&expected[0]) }) { return false }
	C.close(second)
	unsafe { expected[second_at] = 0 }

	// The child must retain the description, including after it tries an
	// open that fails at fd publication. Wait for that attempt before reading.
	mut ready := [2]i32{}
	mut release := [2]i32{}
	if C.pipe(&ready[0]) != 0 || C.pipe(&release[0]) != 0 { return false }
	child := C.fork()
	mut byte := u8(0)
	if child == 0 {
		C.close(ready[0])
		C.close(release[1])
		limit := C.rlimit{}
		if C.setrlimit(C.RLIMIT_NOFILE, &limit) != 0 { C._exit(2) }
		if C.open(card, C.O_RDWR) != -1 || unsafe { *C.__errno_location() } != C.EMFILE { C._exit(3) }
		if C.write(ready[1], &byte, 1) != 1 || C.read(release[0], &byte, 1) != 0 { C._exit(4) }
		C._exit(0)
	}
	C.close(ready[1])
	C.close(release[0])
	C.close(alias)
	child_ready := child > 0 && C.read(ready[0], &byte, 1) == 1
	row_retained := child_ready && same_client_rows(unsafe { &char(&expected[0]) })
	C.close(ready[0])
	C.close(release[1])
	mut status := i32(0)
	exited := child > 0 && C.waitpid(child, &status, 0) == child && status == 0
	unsafe { expected[header_len] = 0 }
	empty := same_client_rows(unsafe { &char(&expected[0]) })
	C.close(path)
	return row_retained && exited && empty
}

fn pass_fd(socket i32, outgoing i32) i32 {
	unsafe {
		mut byte := u8(0)
		mut control := [3]u64{}
		header := &C.cmsghdr(&control[0])
		fd := &i32(&control[2])
		mut vector := C.iovec{iov_base: &byte, iov_len: 1}
		mut message := C.msghdr{msg_iov: &vector, msg_iovlen: 1, msg_control: &control[0], msg_controllen: 24}
		if outgoing >= 0 {
			*header = C.cmsghdr{cmsg_len: 20, cmsg_level: C.SOL_SOCKET, cmsg_type: C.SCM_RIGHTS}
			*fd = outgoing
			return if C.sendmsg(socket, &message, C.MSG_NOSIGNAL) == 1 { outgoing } else { -1 }
		}
		if C.recvmsg(socket, &message, 0) != 1 || message.msg_controllen < 20
			|| header.cmsg_len != 20 || header.cmsg_level != C.SOL_SOCKET || header.cmsg_type != C.SCM_RIGHTS {
			return -1
		}
		return *fd
	}
}

fn test_client_ioctl_handoff(fd i32, previous &char, id u64) bool {
	// Admission failures leave the previous process associated with the file.
	if C.ioctl(fd, i32(0x78ff), u64(0)) != -1 || unsafe { *C.__errno_location() } != C.ENOTTY
		|| !same_client_rows(previous) {
		return false
	}
	if C.ioctl(fd, i32(0x64ff), u64(0)) != -1 || unsafe { *C.__errno_location() } != C.EINVAL
		|| !same_client_rows(previous) {
		return false
	}
	// The simple DRM driver has no private 0x41 handler.
	mut private_data := [16]u8{}
	private_request := i32(u32(0xc0106441))
	if C.ioctl(fd, private_request, u64(1)) != -1 || unsafe { *C.__errno_location() } != C.EINVAL
		|| C.ioctl(fd, private_request, &private_data[0]) != -1 || unsafe { *C.__errno_location() } != C.EINVAL
		|| !same_client_rows(previous) {
		return false
	}
	if C.ioctl(fd, i32(u32(0xc01064d1)), u64(1)) != -1 || unsafe { *C.__errno_location() } != C.EFAULT
		|| !same_client_rows(previous) {
		return false
	}

	// A request that reaches the handler changes attribution even if the
	// driver rejects its contents. The open description keeps its client ID.
	if set_name(fd, 0, 65) != C.EINVAL { return false }
	mut expected := [512]u8{}
	header_len := format_client_header(&expected[0], sizeof(expected))
	format_client_row(unsafe { &expected[header_len] }, sizeof(expected) - u64(header_len),
		c'vinix-clients', C.getpid(), C.geteuid(), c'<unset>', id)
	if !same_client_rows(unsafe { &char(&expected[0]) }) { return false }

	name := c'received-client'
	if set_name(fd, u64(name), C.strlen(name)) != 0 || client_id(fd) != i64(id) { return false }
	format_client_row(unsafe { &expected[header_len] }, sizeof(expected) - u64(header_len),
		c'vinix-clients', C.getpid(), C.geteuid(), name, id)
	return same_client_rows(unsafe { &char(&expected[0]) })
}

fn test_live_client_identity() bool {
	mut sockets := [2]i32{}
	if C.socketpair(C.AF_UNIX, C.SOCK_SEQPACKET, 0, &sockets[0]) != 0 { return false }
	child := C.fork()
	if child == 0 {
		C.close(sockets[0])
		client := C.open(c'/dev/dri/card0', C.O_RDWR)
		if client < 0 || C.prctl(C.PR_SET_NAME, c'live-drm-opener', u64(0), u64(0), u64(0)) != 0
			|| C.setresuid(0, 1234, 0) != 0 || C.geteuid() != 1234 || pass_fd(sockets[1], client) < 0 {
			C._exit(2)
		}
		mut byte := u8(0)
		C._exit(if C.read(sockets[1], &byte, 1) == 0 { 0 } else { 3 })
	}
	C.close(sockets[1])
	passed := if child > 0 { pass_fd(sockets[0], -1) } else { -1 }
	mut expected := [512]u8{}
	header_len := format_client_header(&expected[0], sizeof(expected))
	id := client_id(passed)
	format_client_row(unsafe { &expected[header_len] }, sizeof(expected) - u64(header_len),
		c'live-drm-opener', child, 1234, c'<unset>', u64(id))
	live := id > 0 && same_client_rows(unsafe { &char(&expected[0]) })
	C.close(sockets[0])
	mut status := i32(0)
	reaped := child > 0 && C.waitpid(child, &status, 0) == child && status == 0
	format_client_row(unsafe { &expected[header_len] }, sizeof(expected) - u64(header_len),
		c'<unknown>', child, 0, c'<unset>', u64(id))
	gone := reaped && same_client_rows(unsafe { &char(&expected[0]) })
	if gone && test_client_ioctl_handoff(passed, unsafe { &char(&expected[0]) }, u64(id)) {
		C.puts(c'VINIX DRM CLIENT IOCTL HANDOFF: PASS')
	} else {
		C.puts(c'DRM CLIENT IOCTL HANDOFF FAIL: incorrect ioctl attribution')
	}
	if passed >= 0 { C.close(passed) }
	unsafe { expected[header_len] = 0 }
	return live && gone && same_client_rows(unsafe { &char(&expected[0]) })
}

fn test_client_user_namespace(mapping &char, uid u32) bool {
	client := C.open(c'/dev/dri/card0', C.O_RDWR)
	if client < 0 { return false }
	defer { C.close(client) }
	view := C.open(clients_path, C.O_RDONLY)
	if view < 0 { return false }
	defer { C.close(view) }
	id := client_id(client)
	if id <= 0 { return false }
	pid := C.getpid()
	mut expected := [512]u8{}
	header_len := format_client_header(&expected[0], sizeof(expected))
	row := unsafe { &expected[header_len] }
	capacity := sizeof(expected) - u64(header_len)
	command := c'vinix-clients'
	format_client_row(row, capacity, command, pid, 0, c'<unset>', u64(id))

	mut sockets := [2]i32{}
	if C.socketpair(C.AF_UNIX, C.SOCK_SEQPACKET, 0, &sockets[0]) != 0 { return false }
	child := C.fork()
	if child == 0 {
		C.close(sockets[0])
		if C.unshare(C.CLONE_NEWUSER) != 0 { C._exit(2) }
		// This inherited description was opened in the initial user namespace.
		if !match_client_rows(view, unsafe { &char(&expected[0]) }) { C._exit(3) }
		own := C.open(clients_path, C.O_RDONLY)
		if own < 0 { C._exit(4) }
		format_client_row(row, capacity, command, pid, 65534, c'<unset>', u64(id))
		if !match_client_rows(own, unsafe { &char(&expected[0]) }) { C._exit(5) }

		// The open description retains the namespace and observes its new map.
		map_fd := C.open(c'/proc/self/uid_map', C.O_WRONLY)
		if map_fd < 0 || C.write(map_fd, mapping, C.strlen(mapping)) != i64(C.strlen(mapping)) { C._exit(6) }
		C.close(map_fd)
		format_client_row(row, capacity, command, pid, uid, c'<unset>', u64(id))
		if C.lseek(own, 0, C.SEEK_SET) != 0 || !match_client_rows(own, unsafe { &char(&expected[0]) }) {
			C._exit(7)
		}
		alias := C.dup(own)
		C.close(own)
		if alias < 0 || C.lseek(alias, 0, C.SEEK_SET) != 0 || pass_fd(sockets[1], alias) < 0 { C._exit(8) }
		C._exit(0)
	}
	C.close(sockets[1])
	received := if child > 0 { pass_fd(sockets[0], -1) } else { -1 }
	C.close(sockets[0])
	mut status := i32(0)
	reaped := child > 0 && C.waitpid(child, &status, 0) == child && status == 0
	if received < 0 || !reaped {
		if received >= 0 { C.close(received) }
		C.printf(c'DRM user namespace child status: %d\n', status)
		return false
	}
	// Read in the initial user namespace after the mapped namespace's task exited.
	format_client_row(row, capacity, command, pid, uid, c'<unset>', u64(id))
	mapped := match_client_rows(received, unsafe { &char(&expected[0]) })
	C.close(received)
	return mapped
}

fn client_read_heap(objects &i64, capacity int) int {
	info := C.fopen(c'/proc/slabinfo', c'r')
	if info == unsafe { nil } { return 0 }
	defer { C.fclose(info) }
	mut line := [256]char{}
	mut count := 0
	for count < capacity && C.fgets(&line[0], line.len, info) != unsafe { nil } {
		if C.sscanf(&line[0], c'size-%*d %*d %ld', unsafe { objects + count }) == 1 {
			count++
		}
	}
	return count
}

fn test_client_read_allocations() bool {
	fd := C.open(c'/dev/dri/card0', C.O_RDWR)
	if fd < 0 { return false }
	defer { C.close(fd) }
	id := client_id(fd)
	if id <= 0 { return false }
	mut expected := [512]u8{}
	header_len := format_client_header(&expected[0], sizeof(expected))
	format_client_row(unsafe { &expected[header_len] }, sizeof(expected) - u64(header_len),
		c'vinix-clients', C.getpid(), C.geteuid(), c'<unset>', u64(id))
	for _ in 0 .. 20 {
		if !same_client_rows(unsafe { &char(&expected[0]) }) { return false }
	}
	mut before := [64]i64{}
	mut after := [64]i64{}
	count := client_read_heap(&before[0], before.len)
	for _ in 0 .. 200 {
		if !same_client_rows(unsafe { &char(&expected[0]) }) { return false }
	}
	if count <= 0 || client_read_heap(&after[0], after.len) != count { return false }
	mut largest := i64(0)
	for i in 0 .. count {
		growth := unsafe { after[i] - before[i] }
		if growth > largest { largest = growth }
	}
	C.printf(c'DRM client table: peak slab-class growth %ld over 200 reads\n', largest)
	return largest <= 8
}

fn test_core_query_transport() bool {
	fd := C.open(c'/dev/dri/card0', C.O_RDWR)
	if fd < 0 { return false }
	defer { C.close(fd) }
	mut version := [4]i32{init: -1}
	if C.ioctl(fd, i32(u32(0x800c6400)), &version[0]) != 0
		|| version[0] != 1 || version[1] != 0 || version[2] != 0 || version[3] != -1 {
		return false
	}
	mut cap := [u64(1), 99, 0x1234, 0x5678]!
	if C.ioctl(fd, i32(u32(0xc008640c)), &cap[0]) != 0 || cap[1] != 99
		|| C.ioctl(fd, i32(u32(0xc018640c)), &cap[0]) != 0 || cap[1] != 1
		|| cap[2] != 0x1234 || cap[3] != 0x5678 {
		return false
	}
	cap[0] = 0x6 // DRM_CAP_TIMESTAMP_MONOTONIC
	cap[1] = ~u64(0)
	if C.ioctl(fd, i32(u32(0xc010640c)), &cap[0]) != 0 || cap[0] != 0x6 || cap[1] != 1 {
		return false
	}
	cap[0] = 0x3 // DRM_CAP_DUMB_PREFERRED_DEPTH
	if C.ioctl(fd, i32(u32(0xc010640c)), &cap[0]) != 0 || cap[1] != 32 {
		return false
	}
	cap[0] = 0x4 // DRM_CAP_DUMB_PREFER_SHADOW
	cap[1] = ~u64(0)
	if C.ioctl(fd, i32(u32(0xc010640c)), &cap[0]) != 0 || cap[1] != 0 {
		return false
	}
	cap[0] = ~u64(0)
	return C.ioctl(fd, i32(u32(0xc018640c)), &cap[0]) == -1
		&& unsafe { *C.__errno_location() } == C.EINVAL
		&& cap[1] == 0 && cap[2] == 0x1234 && cap[3] == 0x5678
}

fn test_render_capabilities(fd i32) bool {
	mut cap := [u64(0x5), ~u64(0), 0x1234]!
	if C.ioctl(fd, i32(u32(0xc018640c)), &cap[0]) != 0 || cap[1] != 3 || cap[2] != 0x1234 {
		return false
	}
	cap[0] = 0x13 // DRM_CAP_SYNCOBJ
	if C.ioctl(fd, i32(u32(0xc010640c)), &cap[0]) != 0 || cap[1] != 1 {
		return false
	}
	capabilities := [u64(0x1), 0x3, 0x4, ~u64(0)]!
	for i in 0 .. capabilities.len {
		capability := unsafe { capabilities[i] }
		cap[0] = capability
		cap[1] = ~u64(0)
		if C.ioctl(fd, i32(u32(0xc018640c)), &cap[0]) != -1
			|| unsafe { *C.__errno_location() } != C.EOPNOTSUPP
			|| cap[0] != capability || cap[1] != 0 || cap[2] != 0x1234 {
			return false
		}
	}
	return true
}

struct DumbCreateRequest {
mut:
	height u32
	width u32
	bpp u32
	flags u32
	handle u32
	pitch u32
	size u64
}

struct ExtendedDumbMapRequest {
mut:
	handle u32
	pad u32
	offset u64
	tail u64
}

fn test_render_dumb_permissions(fd i32) bool {
	commands := [u32(0xc02064b2), 0xc01064b3, 0xc00464b4]!
	mut data := [4]u64{init: ~u64(0)}
	for i in 0 .. commands.len {
		command := i32(unsafe { commands[i] })
		if C.ioctl(fd, command, &data[0]) != -1 || unsafe { *C.__errno_location() } != C.EACCES
			|| C.ioctl(fd, command, u64(1)) != -1 || unsafe { *C.__errno_location() } != C.EFAULT {
			return false
		}
	}
	// The denied read-only map still copies the zeroed reply back.
	return C.ioctl(fd, i32(u32(0x801864b3)), &data[0]) == -1
		&& unsafe { *C.__errno_location() } == C.EACCES
		&& data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == ~u64(0)
}

fn test_dumb_buffer_error_replies(fd i32, create_errno i32, map_errno i32) bool {
	mut create := DumbCreateRequest{height: 1, bpp: 32, handle: 77, pitch: 77, size: 77}
	if C.ioctl(fd, i32(u32(0xc02064b2)), &create) != -1
		|| unsafe { *C.__errno_location() } != create_errno
		|| create.height != 1 || create.width != 0 || create.bpp != 32
		|| create.handle != 0 || create.pitch != 0 || create.size != 0 {
		return false
	}
	mut mapping := ExtendedDumbMapRequest{pad: 99, offset: 77, tail: 0x12345678}
	return C.ioctl(fd, i32(u32(0xc01864b3)), &mapping) == -1
		&& unsafe { *C.__errno_location() } == map_errno
		&& mapping.handle == 0 && mapping.pad == 99 && mapping.offset == 0 && mapping.tail == 0x12345678
}

fn test_unsupported_dumb_buffers(card &char) bool {
	fd := C.open(card, C.O_RDWR)
	if fd < 0 { return false }
	defer { C.close(fd) }
	mut handle := u32(0)
	return test_dumb_buffer_error_replies(fd, C.ENOSYS, C.ENOSYS)
		&& C.ioctl(fd, i32(u32(0xc00464b4)), unsafe { &handle }) == -1
		&& unsafe { *C.__errno_location() } == C.ENOSYS
}

fn test_dumb_buffer_geometry(fd i32) bool {
	requests := [DumbCreateRequest{width: 1 << 30, height: 1, bpp: 32},
		DumbCreateRequest{width: 1 << 20, height: 1 << 10, bpp: 32},
		DumbCreateRequest{width: ~u32(0), height: 1, bpp: 8},
		DumbCreateRequest{width: 1, height: 1 << 26, bpp: 8}]!
	for i in 0 .. requests.len {
		mut request := unsafe { requests[i] }
		request.handle = 77
		request.pitch = 77
		request.size = 77
		if C.ioctl(fd, i32(u32(0xc02064b2)), &request) != -1
			|| unsafe { *C.__errno_location() } != C.EINVAL
			|| request.handle != 0 || request.pitch != 0 || request.size != 0 {
			return false
		}
	}
	return true
}

fn test_dumb_buffer_transport() bool {
	fd := C.open(c'/dev/dri/card0', C.O_RDWR)
	if fd < 0 { return false }
	defer { C.close(fd) }
	if !test_dumb_buffer_error_replies(fd, C.EINVAL, C.ENOENT) { return false }
	if !test_dumb_buffer_geometry(fd) { return false }
	// The short CREATE reply ends after pitch and leaves the caller's size alone.
	mut create := DumbCreateRequest{height: 1, width: 1, bpp: 32, size: 123}
	if C.ioctl(fd, i32(u32(0xc01864b2)), &create) != 0 || create.handle == 0
		|| create.pitch < 4 || create.size != 123 {
		return false
	}
	mut mapping := ExtendedDumbMapRequest{handle: create.handle, pad: 99, tail: 0x12345678}
	if C.ioctl(fd, i32(u32(0xc01864b3)), &mapping) != 0 || mapping.offset == 0
		|| mapping.handle != create.handle || mapping.pad != 99 || mapping.tail != 0x12345678 {
		return false
	}
	// Read-only DESTROY supplies a zero handle and copies back the error reply.
	mut read_only := create.handle
	if C.ioctl(fd, i32(u32(0x800464b4)), unsafe { &read_only }) != -1
		|| unsafe { *C.__errno_location() } != C.EINVAL || read_only != 0 {
		return false
	}
	mut destroy := [create.handle, u32(0x87654321)]!
	if C.ioctl(fd, i32(u32(0xc00864b4)), &destroy[0]) != 0 || destroy[0] != create.handle
		|| destroy[1] != 0x87654321 {
		return false
	}
	if C.ioctl(fd, i32(u32(0xc00464b4)), &destroy[0]) != -1
		|| unsafe { *C.__errno_location() } != C.EINVAL {
		return false
	}
	if C.ioctl(fd, i32(u32(0xc02064b2)), &create) != 0 || create.handle == 0 {
		return false
	}
	return C.ioctl(fd, i32(0x400464b4), unsafe { &create.handle }) == 0
}

fn test_gem_close_transport() bool {
	fd := C.open(c'/dev/dri/card0', C.O_RDWR)
	if fd < 0 { return false }
	defer { C.close(fd) }
	other := C.open(c'/dev/dri/card0', C.O_RDWR)
	if other < 0 { return false }
	defer { C.close(other) }
	commands := [u32(0x40046409), u32(0xc0106409)]!
	for i in 0 .. commands.len {
		command := unsafe { commands[i] }
		mut create := DumbCreateRequest{height: 1, width: 1, bpp: 32}
		if C.ioctl(fd, i32(u32(0xc02064b2)), &create) != 0 || create.handle == 0 {
			return false
		}
		mut close_data := [create.handle, u32(0xffffffff), 0x1234, 0x5678]!
		if C.ioctl(other, i32(0x40086409), &close_data[0]) != -1
			|| unsafe { *C.__errno_location() } != C.EINVAL {
			return false
		}
		// A read-only request supplies a zero handle. The original buffer
		// should survive it and close on the following write request.
		if command == u32(0xc0106409) {
			if C.ioctl(fd, i32(u32(0x80086409)), &close_data[0]) != -1
				|| unsafe { *C.__errno_location() } != C.EINVAL || close_data[0] != create.handle {
				return false
			}
		}
		if C.ioctl(fd, i32(command), &close_data[0]) != 0 || close_data[0] != create.handle
			|| close_data[1] != 0xffffffff || close_data[2] != 0x1234 || close_data[3] != 0x5678 {
			return false
		}
		if C.ioctl(fd, i32(0x40086409), &close_data[0]) != -1 || unsafe { *C.__errno_location() } != C.EINVAL {
			return false
		}
	}
	return true
}

fn test_render_gem_close(fd i32) bool {
	mut missing := [u32(1), 0]!
	return C.ioctl(fd, i32(0x40086409), &missing[0]) == -1
		&& unsafe { *C.__errno_location() } == C.EINVAL
}

struct ExtendedPrimeRequest {
mut:
	handle u32
	flags u32
	fd i32
	tail u32
}

fn gem_close_cycle(fd i32, prime bool) bool {
	mut create := DumbCreateRequest{height: 1, width: 1, bpp: 32}
	if C.ioctl(fd, i32(u32(0xc02064b2)), &create) != 0 || create.handle == 0 {
		return false
	}
	mut export := ExtendedPrimeRequest{handle: create.handle, fd: -1}
	if prime && (C.ioctl(fd, i32(u32(0xc00c642d)), &export) != 0 || export.fd < 0) {
		return false
	}
	defer { if export.fd >= 0 { C.close(export.fd) } }
	return C.ioctl(fd, i32(u32(0xc00464b4)), unsafe { &create.handle }) == 0
}

fn measure_gem_close_cycles(fd i32, prime bool) bool {
	for _ in 0 .. 20 {
		if !gem_close_cycle(fd, prime) { return false }
	}
	mut before := [64]i64{}
	mut after := [64]i64{}
	count := client_read_heap(&before[0], before.len)
	for _ in 0 .. 200 {
		if !gem_close_cycle(fd, prime) { return false }
	}
	if count <= 0 || client_read_heap(&after[0], after.len) != count { return false }
	mut largest := i64(0)
	for i in 0 .. count {
		growth := unsafe { after[i] - before[i] }
		if growth > largest { largest = growth }
	}
	C.printf(c'DRM GEM metadata: peak live slab growth %ld over 200 closes (PRIME %d)\n',
		largest, i32(prime))
	return largest <= 8
}

fn test_gem_metadata_reclamation() bool {
	fd := C.open(c'/dev/dri/card0', C.O_RDWR)
	if fd < 0 { return false }
	defer { C.close(fd) }
	direct := measure_gem_close_cycles(fd, false)
	prime := measure_gem_close_cycles(fd, true)
	return direct && prime
}

fn test_prime_inode_metadata(fd i32, size u64) bool {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 { return false }
	truncate_refused := C.ftruncate(fd, 0) == -1 && unsafe { *C.__errno_location() } == C.EINVAL
	C.printf(c'DRM PRIME fstat: mode %#o links %u block size %ld truncate refused %d\n',
		info.st_mode, u32(info.st_nlink), i64(info.st_blksize), i32(truncate_refused))
	return info.st_mode == 0o600 && info.st_nlink == 1 && i64(info.st_blksize) == i64(C.getpagesize())
		&& info.st_size == i64(size) && info.st_blocks == i64(size / 512) && truncate_refused
}

const prime_fixture_uid = u32(1234)
const prime_fixture_gid = u32(2345)

fn export_with_filesystem_ids(card i32, mut request ExtendedPrimeRequest) bool {
	old_gid := C.setfsgid(prime_fixture_gid)
	old_uid := C.setfsuid(prime_fixture_uid)
	defer {
		C.setfsuid(u32(old_uid))
		C.setfsgid(u32(old_gid))
	}
	return u32(C.setfsuid(~u32(0))) == prime_fixture_uid
		&& u32(C.setfsgid(~u32(0))) == prime_fixture_gid
		&& C.ioctl(card, i32(u32(0xc00c642d)), unsafe { &request }) == 0 && request.fd >= 0
}

fn time_at_most(left C.timespec, right C.timespec) bool {
	return left.tv_sec < right.tv_sec || (left.tv_sec == right.tv_sec && left.tv_nsec <= right.tv_nsec)
}

fn test_prime_inode_owner_times(fd i32, before C.timespec, after C.timespec) bool {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 { return false }
	timestamp := info.st_ctim
	C.printf(c'DRM PRIME inode: uid %u gid %u ctime %ld.%09ld\n',
		info.st_uid, info.st_gid, timestamp.tv_sec, timestamp.tv_nsec)
	return info.st_uid == prime_fixture_uid && info.st_gid == prime_fixture_gid
		&& time_at_most(before, timestamp) && time_at_most(timestamp, after)
		&& info.st_atim.tv_sec == timestamp.tv_sec && info.st_atim.tv_nsec == timestamp.tv_nsec
		&& info.st_mtim.tv_sec == timestamp.tv_sec && info.st_mtim.tv_nsec == timestamp.tv_nsec
}

fn test_prime_fdinfo(fd i32, size u64, refs i32) bool {
	mut info := [512]u8{}
	if !read_fdinfo(fd, &info[0], sizeof(info)) { return false }
	mut expected := [80]char{}
	C.snprintf(&expected[0], sizeof(expected), c'\nsize:\t%lu\ncount:\t%d\nexp_name:\tdrm\n', size, refs)
	suffix := C.strstr(&info[0], c'\nsize:\t')
	return suffix != unsafe { nil } && C.strcmp(suffix, &expected[0]) == 0
}

fn prime_fdinfo_has_flags(fd i32, expected i32) bool {
	mut info := [512]u8{}
	if !read_fdinfo(fd, &info[0], sizeof(info)) { return false }
	line := C.strstr(&info[0], c'\nflags:\t')
	if line == unsafe { nil } { return false }
	value := unsafe { line + C.strlen(c'\nflags:\t') }
	mut end := &char(unsafe { nil })
	flags := C.strtoull(value, &end, 8)
	return end != value && unsafe { *end } == char(10) && flags == u64(expected)
}

fn fdinfo_mount_id(fd i32) i32 {
	mut info := [512]u8{}
	if !read_fdinfo(fd, &info[0], sizeof(info)) { return 0 }
	line := C.strstr(&info[0], c'\nmnt_id:\t')
	if line == unsafe { nil } { return 0 }
	mut id := i32(0)
	if C.sscanf(line, c' mnt_id: %d', &id) != 1 { return 0 }
	return id
}

struct C.statx {
	stx_mask u32
	stx_mode u16
	stx_ino u64
}

fn statx_mount_id(result &C.statx) u64 {
	// Older musl headers leave this Linux ABI field in the reserved area.
	return unsafe { *(&u64(u64(result) + 0x90)) }
}

const statx_mount_id_mask = u32(0x1000)
const statx_unique_mount_id_mask = u32(0x4000)
const statx_mount_id_masks = statx_mount_id_mask | statx_unique_mount_id_mask

fn prime_statx_mount_matches(fd i32, path &char, flags i32, mask u32, id u64, ino u64) bool {
	mut result := C.statx{}
	return C.syscall(C.SYS_statx, fd, path, flags, mask, &result) == 0
		&& result.stx_mask & statx_mount_id_masks == statx_mount_id_mask
		&& statx_mount_id(&result) == id && result.stx_ino == ino
}

fn test_prime_statx_mount_id(fd i32, ino u64) bool {
	id := fdinfo_mount_id(fd)
	if id <= 0 { return false }
	mut path := [64]char{}
	C.snprintf(&path[0], sizeof(path), c'/proc/self/fd/%d', fd)
	if !prime_statx_mount_matches(fd, c'', C.AT_EMPTY_PATH, statx_mount_id_mask, u64(id), ino)
		|| !prime_statx_mount_matches(fd, unsafe { nil }, C.AT_EMPTY_PATH, 0x7ff, u64(id), ino)
		|| !prime_statx_mount_matches(C.AT_FDCWD, &path[0], 0, statx_mount_id_mask, u64(id), ino) {
		return false
	}
	mut link := C.statx{}
	return C.syscall(C.SYS_statx, C.AT_FDCWD, &path[0], C.AT_SYMLINK_NOFOLLOW, statx_mount_id_mask, &link) == 0
		&& link.stx_mode & u16(C.S_IFMT) == u16(C.S_IFLNK)
		&& (link.stx_mask & statx_mount_id_mask == 0 || statx_mount_id(&link) != u64(id))
}

fn prime_statx_unique_mount_id(fd i32, path &char, flags i32, mask u32) u64 {
	mut result := C.statx{}
	if C.syscall(C.SYS_statx, fd, path, flags, mask, &result) != 0
		|| result.stx_mask & statx_mount_id_masks != statx_unique_mount_id_mask { return 0 }
	return statx_mount_id(&result)
}

fn test_prime_statx_unique_mount_id(first i32, duplicate i32, second i32) bool {
	id := prime_statx_unique_mount_id(first, c'', C.AT_EMPTY_PATH, statx_unique_mount_id_mask)
	if id <= (u64(1) << 31) { return false }
	mut path := [64]char{}
	C.snprintf(&path[0], sizeof(path), c'/proc/self/fd/%d', second)
	return prime_statx_unique_mount_id(duplicate, unsafe { nil }, C.AT_EMPTY_PATH, statx_mount_id_masks) == id
		&& prime_statx_unique_mount_id(second, c'', C.AT_EMPTY_PATH, statx_unique_mount_id_mask) == id
		&& prime_statx_unique_mount_id(C.AT_FDCWD, &path[0], 0, statx_mount_id_masks) == id
}

fn sync_file_range_replies(fd u64, offset i64, length i64, flags u64, code i32) bool {
	result := C.syscall(C.SYS_sync_file_range, fd, offset, length, flags)
	if code == 0 { return result == 0 }
	return result == -1 && unsafe { *C.__errno_location() } == code
}

fn prime_sync_file_range_rejects(fd u64) bool {
	for flags in 0 .. 8 {
		if !sync_file_range_replies(fd, 0, 128, u64(flags), C.ESPIPE) { return false }
	}
	return sync_file_range_replies(fd, -1, 0, 2, C.EINVAL)
		&& sync_file_range_replies(fd, 0, -1, 2, C.EINVAL)
		&& sync_file_range_replies(fd, 0x7fffffffffffffff, 1, 2, C.EINVAL)
		&& sync_file_range_replies(fd, 0, 0, 8, C.EINVAL)
}

fn test_prime_sync_file_range(writable i32, read_only i32) bool {
	if !prime_sync_file_range_rejects(u64(writable))
		|| !prime_sync_file_range_rejects(u64(read_only)) { return false }
	file := C.open(c'/proc/self/mountinfo', C.O_RDONLY)
	if file < 0 { return false }
	defer { C.close(file) }
	dir := C.open(c'/dev', C.O_RDONLY | C.O_DIRECTORY)
	if dir < 0 { return false }
	defer { C.close(dir) }
	path := C.open(c'/dev', C.O_PATH)
	if path < 0 { return false }
	defer { C.close(path) }
	upper := u64(0xa5a5a5a500000000)
	return sync_file_range_replies(upper | u64(file), 0, 0, upper | 2, 0)
		&& sync_file_range_replies(u64(dir), 0, 0, 7, 0)
		&& sync_file_range_replies(u64(path), -1, -1, 8, C.EBADF)
		&& sync_file_range_replies(u64(u32(-1)), -1, -1, 8, C.EBADF)
}

fn prime_io_replies(call isize, fd i32, buffer voidptr, count u64, offset i64, code i32) bool {
	return C.syscall(call, fd, buffer, count, offset, u64(0), u64(0)) == -1
		&& unsafe { *C.__errno_location() } == code
}

fn test_prime_byte_io(fd i32, writable bool) bool {
	mut byte := u8(0x5a)
	mut vector := C.iovec{iov_base: unsafe { &byte }, iov_len: 1}
	for operation in 0 .. 10 {
		call := isize(match operation {
			0 { C.SYS_read }
			1 { C.SYS_write }
			2 { C.SYS_pread64 }
			3 { C.SYS_pwrite64 }
			4 { C.SYS_readv }
			5 { C.SYS_writev }
			6 { C.SYS_preadv }
			7 { C.SYS_pwritev }
			8 { C.SYS_preadv2 }
			else { C.SYS_pwritev2 }
		})
		missing_access := operation % 2 != 0 && !writable
		ordinary_code := if missing_access { C.EBADF } else { C.EINVAL }
		positioned := operation == 2 || operation == 3 || operation >= 6
		code := if positioned { C.ESPIPE } else { ordinary_code }
		buffer := if operation >= 4 { voidptr(&vector) } else { voidptr(&byte) }
		if !prime_io_replies(call, fd, buffer, 1, 0, code)
			|| !prime_io_replies(call, fd, unsafe { nil }, 0, 0, code)
			|| !prime_io_replies(call, fd, voidptr(~u64(0)), 1, 0, code) {
			return false
		}
		if positioned && !prime_io_replies(call, fd, buffer, 1, -2, C.EINVAL) {
			return false
		}
		if operation >= 8 && !prime_io_replies(call, fd, buffer, 1, -1, ordinary_code) {
			return false
		}
	}
	return byte == 0x5a
}

fn splice_replies(input i32, input_offset voidptr, output i32, output_offset voidptr, code i32) bool {
	return C.syscall(C.SYS_splice, input, input_offset, output, output_offset, u64(4), u32(0)) == -1
		&& unsafe { *C.__errno_location() } == code
}

fn test_prime_splice(read_write i32, read_only i32) bool {
	mut fds := [2]i32{}
	if C.pipe(&fds[0]) != 0 { return false }
	defer {
		C.close(fds[0])
		C.close(fds[1])
	}
	if C.fcntl(fds[0], C.F_SETFL, C.O_NONBLOCK) != 0
		|| C.write(fds[1], c'keep', 4) != 4 { return false }
	mut result := [5]char{}
	if !splice_replies(fds[0], unsafe { nil }, read_write, unsafe { nil }, C.EINVAL)
		|| C.read(fds[0], &result[0], 4) != 4 || C.strcmp(&result[0], c'keep') != 0
		|| C.write(fds[1], c'keep', 4) != 4 { return false }
	mut offset := i64(1)
	bad_pointer := voidptr(~u64(0))
	if !splice_replies(read_only, unsafe { nil }, fds[1], unsafe { nil }, C.EINVAL)
		|| !splice_replies(read_only, &offset, fds[1], unsafe { nil }, C.EINVAL)
		|| !splice_replies(read_only, bad_pointer, fds[1], unsafe { nil }, C.EFAULT)
		|| !splice_replies(fds[0], unsafe { nil }, read_write, &offset, C.EINVAL)
		|| !splice_replies(fds[0], unsafe { nil }, read_only, unsafe { nil }, C.EBADF)
		|| !splice_replies(fds[0], unsafe { nil }, read_only, bad_pointer, C.EFAULT)
		|| !splice_replies(fds[0], &offset, read_only, unsafe { nil }, C.ESPIPE) {
		return false
	}
	if offset != 1 || C.syscall(C.SYS_splice, i32(-1), bad_pointer, i32(-1), bad_pointer, u64(0), u32(16)) != 0 {
		return false
	}
	if C.read(fds[0], &result[0], 4) != 4 || C.strcmp(&result[0], c'keep') != 0 { return false }

	ordinary := i32(C.syscall(C.SYS_memfd_create, c'prime-splice-control', u32(0)))
	if ordinary < 0 { return false }
	defer { C.close(ordinary) }
	if C.write(ordinary, c'abcd', 4) != 4 { return false }
	if C.syscall(C.SYS_splice, ordinary, &offset, fds[1], unsafe { nil }, u64(2), u32(0)) != 2
		|| offset != 3 || C.lseek(ordinary, 0, C.SEEK_CUR) != 4
		|| C.read(fds[0], &result[0], 2) != 2 || C.strncmp(&result[0], c'bc', 2) != 0 { return false }

	copy := i32(C.syscall(C.SYS_memfd_create, c'prime-copy-control', u32(0)))
	if copy < 0 { return false }
	defer { C.close(copy) }
	mut output_offset := i64(0)
	offset = 1
	return C.syscall(C.SYS_copy_file_range, ordinary, &offset, copy, &output_offset, u64(2), u32(0)) == 2
		&& offset == 3 && output_offset == 2 && C.lseek(ordinary, 0, C.SEEK_CUR) == 4
		&& C.read(copy, &result[0], 2) == 2 && C.strncmp(&result[0], c'bc', 2) == 0
}

fn sendfile_replies(output i32, input i32, offset voidptr, count u64, code i32) bool {
	return C.syscall(C.SYS_sendfile, output, input, offset, count) == -1
		&& unsafe { *C.__errno_location() } == code
}

fn test_prime_sendfile(read_write i32, read_only i32) bool {
	mut fds := [2]i32{}
	if C.pipe(&fds[0]) != 0 { return false }
	defer {
		C.close(fds[0])
		C.close(fds[1])
	}
	if C.fcntl(fds[0], C.F_SETFL, C.O_NONBLOCK) != 0
		|| C.write(fds[1], c'keep', 4) != 4 { return false }
	mut result := [5]char{}
	if !sendfile_replies(read_write, fds[0], unsafe { nil }, 4, C.EINVAL)
		|| C.read(fds[0], &result[0], 4) != 4 || C.strcmp(&result[0], c'keep') != 0 { return false }

	mut offset := i64(-1)
	if !sendfile_replies(fds[1], read_only, &offset, 0, C.ESPIPE) || offset != -1
		|| !sendfile_replies(fds[1], read_only, unsafe { nil }, 4, C.EINVAL)
		|| !sendfile_replies(read_only, fds[0], unsafe { nil }, 0, C.EBADF)
		|| C.syscall(C.SYS_sendfile, fds[1], read_only, unsafe { nil }, u64(0)) != 0 {
		return false
	}

	ordinary := i32(C.syscall(C.SYS_memfd_create, c'prime-sendfile-control', u32(0)))
	if ordinary < 0 { return false }
	defer { C.close(ordinary) }
	if C.write(ordinary, c'abcd', 4) != 4 || C.lseek(ordinary, 0, C.SEEK_SET) != 0 { return false }
	if !sendfile_replies(read_write, ordinary, unsafe { nil }, 2, C.EINVAL)
		|| C.lseek(ordinary, 0, C.SEEK_CUR) != 0 { return false }
	offset = 1
	upper := u64(0xfedcfedc00000000)
	if C.syscall(C.SYS_sendfile, upper | u64(fds[1]), upper | u64(ordinary), &offset, u64(2)) != 2
		|| offset != 3 || C.lseek(ordinary, 0, C.SEEK_CUR) != 0
		|| C.read(fds[0], &result[0], 2) != 2 || C.strncmp(&result[0], c'bc', 2) != 0 { return false }
	return C.syscall(C.SYS_sendfile, fds[1], ordinary, unsafe { nil }, u64(2)) == 2
		&& C.lseek(ordinary, 0, C.SEEK_CUR) == 2 && C.read(fds[0], &result[0], 2) == 2
		&& C.strncmp(&result[0], c'ab', 2) == 0
}

fn test_prime_sendfile_eof(read_write i32, read_only i32) bool {
	input := i32(C.syscall(C.SYS_memfd_create, c'prime-sendfile-eof', u32(0)))
	if input < 0 { return false }
	defer { C.close(input) }
	if C.syscall(C.SYS_sendfile, read_write, input, unsafe { nil }, u64(1)) != 0
		|| C.lseek(input, 0, C.SEEK_CUR) != 0 || C.write(input, c'abcd', 4) != 4 {
		return false
	}
	mut offset := i64(3)
	if !sendfile_replies(read_write, input, &offset, 2, C.EINVAL) || offset != 3
		|| C.syscall(C.SYS_sendfile, read_write, input, unsafe { nil }, u64(2)) != 0
		|| C.lseek(input, 0, C.SEEK_CUR) != 4 {
		return false
	}
	for position in 4 .. 6 {
		offset = i64(position)
		if C.syscall(C.SYS_sendfile, read_write, input, &offset, u64(2)) != 0
			|| offset != position || C.lseek(input, 0, C.SEEK_CUR) != 4 {
			return false
		}
	}
	return sendfile_replies(read_only, input, &offset, 2, C.EBADF) && offset == 5
}

fn test_sendfile_append(prime i32) bool {
	input := i32(C.syscall(C.SYS_memfd_create, c'sendfile-append-source', u32(0)))
	if input < 0 { return false }
	defer { C.close(input) }
	output := i32(C.syscall(C.SYS_memfd_create, c'sendfile-append-destination', u32(0)))
	if output < 0 { return false }
	defer { C.close(output) }
	if C.write(input, c'abcd', 4) != 4 || C.lseek(input, 0, C.SEEK_SET) != 0
		|| C.write(output, c'keep', 4) != 4 || C.lseek(output, 1, C.SEEK_SET) != 1 {
		return false
	}
	flags := C.fcntl(prime, C.F_GETFL)
	if flags < 0 || C.fcntl(prime, C.F_SETFL, flags | C.O_APPEND) != 0 { return false }
	defer { C.fcntl(prime, C.F_SETFL, flags) }
	if C.fcntl(output, C.F_SETFL, C.O_APPEND) != 0 { return false }
	mut eof := i64(4)
	if !sendfile_replies(prime, input, &eof, 0, C.EINVAL)
		|| !sendfile_replies(prime, input, &eof, 2, C.EINVAL) || eof != 4
		|| !sendfile_replies(output, input, unsafe { nil }, 0, C.EINVAL)
		|| !sendfile_replies(output, input, unsafe { nil }, 2, C.EINVAL)
		|| C.lseek(input, 0, C.SEEK_CUR) != 0 || C.lseek(output, 0, C.SEEK_CUR) != 1
		|| C.lseek(output, 0, C.SEEK_END) != 4 {
		return false
	}
	mut fds := [2]i32{}
	if C.pipe(&fds[0]) != 0 { return false }
	defer {
		C.close(fds[0])
		C.close(fds[1])
	}
	mut data := [3]char{}
	return C.fcntl(fds[1], C.F_SETFL, C.O_APPEND) == 0
		&& C.syscall(C.SYS_sendfile, fds[1], input, unsafe { nil }, u64(0)) == 0
		&& C.syscall(C.SYS_sendfile, fds[1], input, unsafe { nil }, u64(2)) == 2
		&& C.read(fds[0], &data[0], 2) == 2 && C.strncmp(&data[0], c'ab', 2) == 0
}

fn test_sendfile_stream_source(input i32, writer i32, output i32) bool {
	if C.fcntl(input, C.F_SETFL, C.O_NONBLOCK) != 0 || C.write(writer, c'keep', 4) != 4 {
		return false
	}
	mut offset := i64(0)
	if !sendfile_replies(output, input, &offset, 0, C.ESPIPE) || offset != 0
		|| !sendfile_replies(-1, input, &offset, 4, C.ESPIPE) || offset != 0 {
		return false
	}
	offset = -1
	if !sendfile_replies(output, input, &offset, 4, C.ESPIPE) || offset != -1 {
		return false
	}
	if !sendfile_replies(output, input, unsafe { nil }, 0, C.EINVAL)
		|| !sendfile_replies(output, input, unsafe { nil }, 4, C.EINVAL)
		|| !sendfile_replies(-1, input, unsafe { nil }, 0, C.EBADF) {
		return false
	}
	mut data := [5]char{}
	return C.read(input, &data[0], 4) == 4 && C.strcmp(&data[0], c'keep') == 0
}

fn test_sendfile_stream_offsets(prime i32) bool {
	ordinary := i32(C.syscall(C.SYS_memfd_create, c'sendfile-stream-destination', u32(0)))
	if ordinary < 0 { return false }
	defer { C.close(ordinary) }
	mut pipe := [2]i32{}
	if C.pipe(&pipe[0]) != 0 { return false }
	defer {
		C.close(pipe[0])
		C.close(pipe[1])
	}
	mut offset := i64(-1)
	if !sendfile_replies(prime, pipe[1], &offset, 0, C.EBADF) || offset != -1
		|| !test_sendfile_stream_source(pipe[0], pipe[1], prime)
		|| !test_sendfile_stream_source(pipe[0], pipe[1], ordinary) {
		return false
	}
	mut sockets := [2]i32{}
	if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) != 0 { return false }
	defer {
		C.close(sockets[0])
		C.close(sockets[1])
	}
	if !test_sendfile_stream_source(sockets[0], sockets[1], prime)
		|| !test_sendfile_stream_source(sockets[0], sockets[1], ordinary)
		|| C.lseek(ordinary, 0, C.SEEK_CUR) != 0 || C.lseek(ordinary, 0, C.SEEK_END) != 0 {
		return false
	}
	mut destination := [2]i32{}
	if C.pipe(&destination[0]) != 0 { return false }
	defer {
		C.close(destination[0])
		C.close(destination[1])
	}
	mut data := [5]char{}
	if C.fcntl(destination[0], C.F_SETFL, C.O_NONBLOCK) != 0
		|| C.write(pipe[1], c'keep', 4) != 4
		|| C.syscall(C.SYS_sendfile, destination[1], pipe[0], unsafe { nil }, u64(0)) != 0
		|| !sendfile_replies(destination[1], pipe[0], unsafe { nil }, 4, C.EINVAL)
		|| C.read(pipe[0], &data[0], 4) != 4 || C.strcmp(&data[0], c'keep') != 0 {
		return false
	}
	return C.write(sockets[1], c'pass', 4) == 4
		&& C.syscall(C.SYS_sendfile, destination[1], sockets[0], unsafe { nil }, u64(4)) == 4
		&& C.read(destination[0], &data[0], 4) == 4 && C.strcmp(&data[0], c'pass') == 0
}

fn test_sendfile_source_range(prime i32) bool {
	input := i32(C.syscall(C.SYS_memfd_create, c'sendfile-range-source', u32(0)))
	if input < 0 { return false }
	defer { C.close(input) }
	output := i32(C.syscall(C.SYS_memfd_create, c'sendfile-range-destination', u32(0)))
	if output < 0 { return false }
	defer { C.close(output) }
	if C.write(input, c'abcd', 4) != 4 || C.lseek(input, 0, C.SEEK_SET) != 0 {
		return false
	}
	max_signed := u64(0x7fffffffffffffff)
	bad_count := max_signed + 1
	if !sendfile_replies(output, input, unsafe { nil }, bad_count, C.EINVAL)
		|| !sendfile_replies(-1, input, unsafe { nil }, bad_count, C.EINVAL)
		|| !sendfile_replies(-1, prime, unsafe { nil }, bad_count, C.EINVAL)
		|| !sendfile_replies(output, -1, unsafe { nil }, bad_count, C.EBADF)
		|| C.lseek(input, 0, C.SEEK_CUR) != 0 || C.lseek(output, 0, C.SEEK_END) != 0 {
		return false
	}
	near_limit := i64(max_signed - 1)
	mut offset := near_limit
	if C.lseek(input, near_limit, C.SEEK_SET) != near_limit
		|| !sendfile_replies(prime, input, unsafe { nil }, 2, C.EINVAL)
		|| !sendfile_replies(-1, input, unsafe { nil }, 2, C.EINVAL)
		|| !sendfile_replies(-1, input, &offset, 2, C.EINVAL)
		|| !sendfile_replies(-1, prime, &offset, bad_count, C.ESPIPE)
		|| offset != near_limit || C.lseek(input, 0, C.SEEK_CUR) != near_limit {
		return false
	}
	mut data := [5]char{}
	return C.lseek(input, 0, C.SEEK_SET) == 0
		&& C.syscall(C.SYS_sendfile, output, input, unsafe { nil }, max_signed) == 4
		&& C.lseek(input, 0, C.SEEK_CUR) == 4 && C.lseek(output, 0, C.SEEK_SET) == 0
		&& C.read(output, &data[0], 4) == 4 && C.strcmp(&data[0], c'abcd') == 0
}

fn test_sendfile_destination_range() bool {
	input := i32(C.syscall(C.SYS_memfd_create, c'sendfile-output-range-source', u32(0)))
	if input < 0 { return false }
	defer { C.close(input) }
	output := i32(C.syscall(C.SYS_memfd_create, c'sendfile-output-range-destination', u32(C.MFD_ALLOW_SEALING)))
	if output < 0 { return false }
	defer { C.close(output) }
	max_position := i64(0x7fffffffffffffff)
	near_limit := max_position - 1
	if C.fcntl(output, C.F_ADD_SEALS, C.F_SEAL_GROW) != 0
		|| C.lseek(output, near_limit, C.SEEK_SET) != near_limit
		|| !sendfile_replies(output, input, unsafe { nil }, 2, C.EINVAL)
		|| C.syscall(C.SYS_sendfile, output, input, unsafe { nil }, u64(1)) != 0 {
		return false
	}
	mut offset := i64(1)
	if C.write(input, c'abcd', 4) != 4 || C.lseek(input, 0, C.SEEK_SET) != 0
		|| !sendfile_replies(output, input, unsafe { nil }, 2, C.EINVAL)
		|| !sendfile_replies(output, input, &offset, 2, C.EINVAL) || offset != 1
		|| C.lseek(input, 0, C.SEEK_CUR) != 0 || C.lseek(output, 0, C.SEEK_CUR) != near_limit
		|| C.lseek(output, 0, C.SEEK_END) != 0 {
		return false
	}
	offset = 4
	capped_position := max_position - i64(0x7fffffff)
	return C.lseek(output, capped_position, C.SEEK_SET) == capped_position
		&& C.syscall(C.SYS_sendfile, output, input, &offset, u64(1) << 32) == 0
		&& offset == 4 && C.lseek(input, 0, C.SEEK_CUR) == 0
		&& C.lseek(output, 0, C.SEEK_CUR) == capped_position
}

fn test_sendfile_pipe_write_errors() bool {
	input := i32(C.syscall(C.SYS_memfd_create, c'sendfile-pipe-write-source', u32(0)))
	if input < 0 { return false }
	defer { C.close(input) }
	mut fds := [2]i32{}
	if C.pipe(&fds[0]) != 0 { return false }
	mut reader := fds[0]
	defer {
		if reader >= 0 { C.close(reader) }
		C.close(fds[1])
	}
	mut chunk := [4096]char{}
	capacity := C.fcntl(fds[1], C.F_SETPIPE_SZ, i32(chunk.len))
	if capacity <= 0 || capacity % chunk.len != 0
		|| C.fcntl(fds[1], C.F_SETFL, C.O_NONBLOCK) != 0 {
		return false
	}
	for _ in 0 .. capacity / chunk.len {
		if C.write(input, &chunk[0], u64(chunk.len)) != chunk.len { return false }
	}
	if C.write(input, c'keep', 4) != 4 || C.lseek(input, 0, C.SEEK_SET) != 0
		|| C.syscall(C.SYS_sendfile, fds[1], input, unsafe { nil }, u64(capacity) + 4) != capacity
		|| C.lseek(input, 0, C.SEEK_CUR) != capacity
		|| !sendfile_replies(fds[1], input, unsafe { nil }, 4, C.EAGAIN)
		|| C.lseek(input, 0, C.SEEK_CUR) != capacity {
		return false
	}
	mut offset := i64(1)
	if !sendfile_replies(fds[1], input, &offset, 4, C.EAGAIN) || offset != 1 { return false }
	for _ in 0 .. capacity / chunk.len {
		if C.read(reader, &chunk[0], u64(chunk.len)) != chunk.len { return false }
	}
	if C.syscall(C.SYS_sendfile, fds[1], input, unsafe { nil }, u64(4)) != 4
		|| C.read(reader, &chunk[0], 4) != 4 || C.strncmp(&chunk[0], c'keep', 4) != 0
		|| C.lseek(input, 0, C.SEEK_CUR) != i64(capacity) + 4
		|| C.lseek(input, i64(capacity), C.SEEK_SET) != capacity || C.close(reader) != 0 {
		return false
	}
	reader = -1
	previous := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	defer { C.signal(C.SIGPIPE, previous) }
	return sendfile_replies(fds[1], input, unsafe { nil }, 4, C.EPIPE)
		&& C.lseek(input, 0, C.SEEK_CUR) == capacity
}

fn test_sendfile_pipe_admission() bool {
	mut sockets := [2]i32{}
	if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) != 0 { return false }
	defer {
		C.close(sockets[0])
		C.close(sockets[1])
	}
	mut fds := [2]i32{}
	if C.pipe(&fds[0]) != 0 { return false }
	mut reader := fds[0]
	defer {
		if reader >= 0 { C.close(reader) }
		C.close(fds[1])
	}
	mut chunk := [4096]char{}
	capacity := C.fcntl(fds[1], C.F_SETPIPE_SZ, i32(chunk.len))
	if capacity <= 0 || capacity % chunk.len != 0
		|| C.fcntl(fds[1], C.F_SETFL, C.O_NONBLOCK) != 0
		|| C.fcntl(sockets[0], C.F_SETFL, C.O_NONBLOCK) != 0 {
		return false
	}
	for _ in 0 .. capacity / chunk.len {
		if C.write(fds[1], &chunk[0], u64(chunk.len)) != chunk.len { return false }
	}
	if C.write(sockets[1], c'keep', 4) != 4
		|| !sendfile_replies(fds[1], sockets[0], unsafe { nil }, 4, C.EAGAIN)
		|| !sendfile_replies(fds[1], sockets[0], unsafe { nil }, 0, C.EAGAIN)
		|| C.read(sockets[0], &chunk[0], 4) != 4 || C.strncmp(&chunk[0], c'keep', 4) != 0
		|| C.close(reader) != 0 {
		return false
	}
	reader = -1
	previous := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	defer { C.signal(C.SIGPIPE, previous) }
	return C.write(sockets[1], c'keep', 4) == 4
		&& sendfile_replies(fds[1], sockets[0], unsafe { nil }, 4, C.EPIPE)
		&& sendfile_replies(fds[1], sockets[0], unsafe { nil }, 0, C.EPIPE)
		&& C.read(sockets[0], &chunk[0], 4) == 4 && C.strncmp(&chunk[0], c'keep', 4) == 0
}

fn read_pending_sigpipe(signal_fd i32) bool {
	mut info := C.signalfd_siginfo{}
	got := C.read(signal_fd, &info, sizeof(info))
	if got != sizeof(info)
		|| info.ssi_signo != u32(C.SIGPIPE) || info.ssi_errno != 0 || info.ssi_code != C.SI_USER
		|| info.ssi_pid != u32(C.getpid()) || info.ssi_uid != C.getuid() {
		C.printf(c'DRM pipe signal read %d errno %d number %u code %d pid %u uid %u\n',
			i32(got), unsafe { *C.__errno_location() }, info.ssi_signo, info.ssi_code,
			info.ssi_pid, info.ssi_uid)
		return false
	}
	return true
}

fn check_pending_sendfile_sigpipe(output i32, input i32, mask u64) bool {
	signal_fd := i32(C.syscall(C.SYS_signalfd4, i64(-1), &mask, u64(sizeof(u64)), C.SFD_NONBLOCK))
	if signal_fd < 0 {
		C.printf(c'DRM sendfile signal fd errno %d\n', unsafe { *C.__errno_location() })
		return false
	}
	defer { C.close(signal_fd) }
	mut info := C.signalfd_siginfo{}
	for attempt in 0 .. 2 {
		if !sendfile_replies(output, input, unsafe { nil }, u64(attempt * 4), C.EPIPE)
			|| !read_pending_sigpipe(signal_fd) {
			return false
		}
	}
	return C.read(signal_fd, &info, sizeof(info)) == -1
		&& unsafe { *C.__errno_location() } == C.EAGAIN && C.lseek(input, 0, C.SEEK_CUR) == 0
}

fn test_sendfile_pipe_signal() bool {
	input := i32(C.syscall(C.SYS_memfd_create, c'sendfile-pipe-signal-source', u32(0)))
	if input < 0 { return false }
	defer { C.close(input) }
	mut fds := [2]i32{}
	if C.pipe(&fds[0]) != 0 { return false }
	defer { C.close(fds[1]) }
	if C.close(fds[0]) != 0 || C.write(input, c'keep', 4) != 4
		|| C.lseek(input, 0, C.SEEK_SET) != 0 {
		return false
	}
	mask := u64(1) << (C.SIGPIPE - 1)
	mut previous := u64(0)
	if C.syscall(C.SYS_rt_sigprocmask, C.SIG_BLOCK, &mask, &previous, u64(sizeof(u64))) != 0 {
		return false
	}
	defer {
		C.syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, &previous, unsafe { nil }, u64(sizeof(u64)))
	}
	if !check_pending_sendfile_sigpipe(fds[1], input, mask) { return false }
	child := C.fork()
	if child < 0 { return false }
	if child == 0 {
		if C.unshare(C.CLONE_NEWUSER) != 0 || C.getuid() != 65534
			|| !check_pending_sendfile_sigpipe(fds[1], input, mask) {
			C._exit(2)
		}
		unsafe { C.signal(C.SIGPIPE, C.SIG_DFL) }
		if C.syscall(C.SYS_rt_sigprocmask, C.SIG_UNBLOCK, &mask, unsafe { nil }, u64(sizeof(u64))) != 0 {
			C._exit(1)
		}
		C.syscall(C.SYS_sendfile, fds[1], input, unsafe { nil }, u64(4))
		C._exit(1)
	}
	mut status := i32(0)
	return C.waitpid(child, &status, 0) == child && C.WIFSIGNALED(status) != 0
		&& C.WTERMSIG(status) == C.SIGPIPE
}

fn test_partial_pipe_write_signal(signal_fd i32) bool {
	mut fds := [2]i32{}
	if C.pipe(&fds[0]) != 0 { return false }
	capacity := C.fcntl(fds[1], C.F_SETPIPE_SZ, i32(4096))
	if capacity <= 0 {
		C.close(fds[0])
		C.close(fds[1])
		return false
	}
	length := u64(capacity) * 2
	data := C.mmap(unsafe { nil }, usize(length), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if data == voidptr(C.MAP_FAILED) {
		C.close(fds[0])
		C.close(fds[1])
		return false
	}
	defer { C.munmap(data, usize(length)) }
	child := C.fork()
	if child == 0 {
		C.close(fds[0])
		ok := C.write(fds[1], data, length) == capacity && read_pending_sigpipe(signal_fd)
		C._exit(if ok { 0 } else { 1 })
	}
	C.close(fds[1])
	mut ready := C.pollfd{fd: fds[0], events: i16(C.POLLIN)}
	started := child > 0 && C.poll(&ready, 1, 5000) == 1 && ready.revents & C.POLLIN != 0
	C.close(fds[0])
	mut status := i32(0)
	reaped := child > 0 && C.waitpid(child, &status, 0) == child
	return started && reaped && status == 0
}

fn test_pipe_write_signal() bool {
	mask := u64(1) << (C.SIGPIPE - 1)
	mut previous := u64(0)
	if C.syscall(C.SYS_rt_sigprocmask, C.SIG_BLOCK, &mask, &previous, u64(sizeof(u64))) != 0 {
		return false
	}
	defer {
		C.syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, &previous, unsafe { nil }, u64(sizeof(u64)))
	}
	signal_fd := i32(C.syscall(C.SYS_signalfd4, i64(-1), &mask, u64(sizeof(u64)), C.SFD_NONBLOCK))
	if signal_fd < 0 { return false }
	defer { C.close(signal_fd) }
	mut fds := [2]i32{}
	if C.pipe(&fds[0]) != 0 { return false }
	defer { C.close(fds[1]) }
	if C.close(fds[0]) != 0 { return false }
	byte := u8(1)
	empty := C.iovec{}
	vector := C.iovec{iov_base: unsafe { &byte }, iov_len: 1}
	mut info := C.signalfd_siginfo{}
	if C.write(fds[1], &byte, 0) != 0 || C.syscall(C.SYS_writev, fds[1], &empty, i64(1)) != 0
		|| C.read(signal_fd, &info, sizeof(info)) != -1 || unsafe { *C.__errno_location() } != C.EAGAIN {
		return false
	}
	return C.write(fds[1], &byte, 1) == -1 && unsafe { *C.__errno_location() } == C.EPIPE
		&& read_pending_sigpipe(signal_fd)
		&& C.syscall(C.SYS_writev, fds[1], &vector, i64(1)) == -1
		&& unsafe { *C.__errno_location() } == C.EPIPE && read_pending_sigpipe(signal_fd)
		&& test_partial_pipe_write_signal(signal_fd)
}

fn tee_replies(input i32, output i32, code i32) bool {
	return C.syscall(C.SYS_tee, input, output, u64(4), u32(0)) == -1
		&& unsafe { *C.__errno_location() } == code
}

fn test_pipe_transfer_admission(prime i32) bool {
	mask := u64(1) << (C.SIGPIPE - 1)
	mut previous := u64(0)
	if C.syscall(C.SYS_rt_sigprocmask, C.SIG_BLOCK, &mask, &previous, u64(sizeof(u64))) != 0 {
		return false
	}
	defer {
		C.syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, &previous, unsafe { nil }, u64(sizeof(u64)))
	}
	signal_fd := i32(C.syscall(C.SYS_signalfd4, i64(-1), &mask, u64(sizeof(u64)), C.SFD_NONBLOCK))
	if signal_fd < 0 { return false }
	defer { C.close(signal_fd) }
	mut source := [2]i32{}
	if C.pipe(&source[0]) != 0 { return false }
	defer {
		C.close(source[0])
		if source[1] >= 0 { C.close(source[1]) }
	}
	mut sink := [2]i32{}
	if C.pipe(&sink[0]) != 0 { return false }
	defer {
		if sink[0] >= 0 { C.close(sink[0]) }
		C.close(sink[1])
	}
	mut data := [4096]char{}
	capacity := C.fcntl(sink[1], C.F_SETPIPE_SZ, i32(data.len))
	if capacity <= 0 || capacity % data.len != 0
		|| C.fcntl(source[0], C.F_SETFL, C.O_NONBLOCK) != 0
		|| C.fcntl(sink[1], C.F_SETFL, C.O_NONBLOCK) != 0 {
		return false
	}
	for _ in 0 .. capacity / data.len {
		if C.write(sink[1], &data[0], u64(data.len)) != data.len { return false }
	}
	if C.write(source[1], c'keep', 4) != 4
		|| !splice_replies(source[0], unsafe { nil }, sink[1], unsafe { nil }, C.EAGAIN)
		|| !tee_replies(source[0], sink[1], C.EAGAIN)
		|| !splice_replies(source[0], unsafe { nil }, source[1], unsafe { nil }, C.EINVAL)
		|| C.close(sink[0]) != 0 {
		return false
	}
	sink[0] = -1
	if !splice_replies(source[0], unsafe { nil }, sink[1], unsafe { nil }, C.EPIPE)
		|| !read_pending_sigpipe(signal_fd) || !tee_replies(source[0], sink[1], C.EPIPE)
		|| !read_pending_sigpipe(signal_fd)
		|| C.read(source[0], &data[0], 4) != 4 || C.strncmp(&data[0], c'keep', 4) != 0
		|| !splice_replies(source[0], unsafe { nil }, sink[1], unsafe { nil }, C.EAGAIN)
		|| !tee_replies(source[0], sink[1], C.EAGAIN) || C.close(source[1]) != 0 {
		return false
	}
	source[1] = -1
	return splice_replies(source[0], unsafe { nil }, sink[1], unsafe { nil }, C.EPIPE)
		&& read_pending_sigpipe(signal_fd) && tee_replies(source[0], sink[1], C.EPIPE)
		&& read_pending_sigpipe(signal_fd)
		&& splice_replies(prime, unsafe { nil }, sink[1], unsafe { nil }, C.EPIPE)
		&& read_pending_sigpipe(signal_fd)
}

fn splice_wait_deadline(_ i32) {}

fn test_splice_pipe_input() bool {
	sink := i32(C.syscall(C.SYS_memfd_create, c'splice-pipe-input', u32(0)))
	if sink < 0 { return false }
	defer { C.close(sink) }
	mut source := [2]i32{}
	if C.pipe(&source[0]) != 0 { return false }
	defer {
		C.close(source[0])
		if source[1] >= 0 { C.close(source[1]) }
	}
	alias := C.dup(source[0])
	if alias < 0 { return false }
	defer { C.close(alias) }

	action := C.sigaction{sa_handler: splice_wait_deadline}
	mut previous := C.sigaction{}
	if C.sigaction(C.SIGALRM, &action, &previous) != 0 { return false }
	defer { C.sigaction(C.SIGALRM, &previous, unsafe { nil }) }

	mut offset := i64(3)
	C.alarm(2)
	empty := C.syscall(C.SYS_splice, source[0], unsafe { nil }, sink, &offset, u64(8),
		u32(C.SPLICE_F_NONBLOCK))
	empty_error := unsafe { *C.__errno_location() }
	empty_before_deadline := C.alarm(0) != 0
	if C.write(source[1], c'data', 4) != 4 { return false }
	C.alarm(2)
	moved := C.syscall(C.SYS_splice, source[0], unsafe { nil }, sink, unsafe { nil }, u64(8), u32(0))
	short_before_deadline := C.alarm(0) != 0

	if empty != -1 || empty_error != C.EAGAIN || !empty_before_deadline || offset != 3
		|| moved != 4 || !short_before_deadline || C.fcntl(alias, C.F_GETFL) != C.O_RDONLY
		|| C.lseek(sink, 0, C.SEEK_CUR) != 4 || C.lseek(sink, 0, C.SEEK_SET) != 0 {
		C.printf(c'DRM SPLICE PIPE INPUT DETAIL: empty=%ld errno=%d early=%d offset=%ld moved=%ld early=%d\n',
			empty, empty_error, int(empty_before_deadline), offset, moved, int(short_before_deadline))
		return false
	}
	mut data := [5]char{}
	if C.read(sink, &data[0], u64(data.len)) != 4 || C.strncmp(&data[0], c'data', 4) != 0
		|| C.close(source[1]) != 0 {
		return false
	}
	source[1] = -1
	return C.syscall(C.SYS_splice, source[0], unsafe { nil }, sink, &offset, u64(8),
		u32(C.SPLICE_F_NONBLOCK)) == 0 && offset == 3
}

fn copy_range_replies(input i32, input_offset voidptr, output i32, output_offset voidptr, length u64, flags u32, code i32) bool {
	return C.syscall(C.SYS_copy_file_range, input, input_offset, output, output_offset, length, flags) == -1
		&& unsafe { *C.__errno_location() } == code
}

fn test_prime_copy_range(read_write i32, read_only i32) bool {
	input := i32(C.syscall(C.SYS_memfd_create, c'prime-copy-range-input', u32(0)))
	if input < 0 { return false }
	defer { C.close(input) }
	output := i32(C.syscall(C.SYS_memfd_create, c'prime-copy-range-output', u32(0)))
	if output < 0 { return false }
	defer { C.close(output) }
	path := C.open(c'/', C.O_PATH)
	if path < 0 { return false }
	defer { C.close(path) }
	directory := C.open(c'/', C.O_DIRECTORY | C.O_RDONLY)
	if directory < 0 { return false }
	defer { C.close(directory) }
	if C.write(input, c'abcd', 4) != 4 || C.lseek(input, 0, C.SEEK_SET) != 0 { return false }
	mut input_offset := i64(1)
	mut output_offset := i64(2)
	bad := voidptr(~u64(0))
	for index in 0 .. 2 {
		count := u64(index * 2)
		if !copy_range_replies(read_only, &input_offset, output, &output_offset, count, 0, C.EINVAL)
			|| !copy_range_replies(input, &input_offset, read_write, &output_offset, count, 0, C.EINVAL)
			|| !copy_range_replies(input, &input_offset, read_only, &output_offset, count, 0, C.EINVAL)
			|| !copy_range_replies(read_only, &input_offset, directory, &output_offset, count, 0, C.EISDIR)
			|| !copy_range_replies(read_only, bad, output, &output_offset, count, 1, C.EFAULT)
			|| !copy_range_replies(input, &input_offset, read_write, bad, count, 1, C.EFAULT)
			|| !copy_range_replies(input, bad, path, bad, count, 1, C.EBADF)
			|| !copy_range_replies(-1, bad, read_write, bad, count, 1, C.EBADF) {
			return false
		}
	}
	upper := u64(0xfedcfedc00000000)
	return C.syscall(C.SYS_copy_file_range, upper | u64(input), &input_offset,
		upper | u64(output), &output_offset, u64(0), u32(0)) == 0
		&& input_offset == 1 && output_offset == 2
		&& C.lseek(input, 0, C.SEEK_CUR) == 0 && C.lseek(output, 0, C.SEEK_END) == 0
}

fn check_mountinfo_ids(internal_id i32, visible_id i32) bool {
	stream := C.fopen(c'/proc/self/mountinfo', c'r')
	if stream == unsafe { nil } { return false }
	defer { C.fclose(stream) }
	mut line := [1024]char{}
	mut found_visible := false
	for C.fgets(&line[0], line.len, stream) != unsafe { nil } {
		mut id := i32(0)
		if C.sscanf(&line[0], c'%d', &id) != 1 { continue }
		if id == internal_id { return false }
		if id == visible_id { found_visible = true }
	}
	return found_visible
}

fn check_prime_export_pair(card i32, first i32, duplicate i32) bool {
	internal_id := fdinfo_mount_id(first)
	visible_id := fdinfo_mount_id(card)
	if internal_id <= 0 || visible_id <= 0 || internal_id == visible_id
		|| fdinfo_mount_id(duplicate) != internal_id { return false }
	mut create := DumbCreateRequest{width: 1, height: 1, bpp: 32}
	if C.ioctl(card, i32(u32(0xc02064b2)), &create) != 0 { return false }
	defer { C.ioctl(card, i32(u32(0xc00464b4)), unsafe { &create.handle }) }
	mut export := ExtendedPrimeRequest{handle: create.handle, fd: -1}
	if C.ioctl(card, i32(u32(0xc00c642d)), &export) != 0 || export.fd < 0 { return false }
	defer { C.close(export.fd) }
	if test_prime_statx_unique_mount_id(first, duplicate, export.fd) {
		C.puts(c'VINIX DRM PRIME STATX UNIQUE MOUNT ID: PASS')
	} else {
		C.puts(c'DRM PRIME STATX UNIQUE MOUNT ID FAIL: incorrect unique mount ID or result mask')
	}
	if test_prime_sync_file_range(first, export.fd) {
		C.puts(c'VINIX DRM PRIME SYNC FILE RANGE: PASS')
	} else {
		C.puts(c'DRM PRIME SYNC FILE RANGE FAIL: incorrect descriptor or range admission')
	}
	if test_prime_byte_io(first, true) && test_prime_byte_io(export.fd, false) {
		C.puts(c'VINIX DRM PRIME BYTE IO: PASS')
	} else {
		C.puts(c'DRM PRIME BYTE IO FAIL: incorrect scalar or vectored I/O error')
	}
	if test_prime_splice(first, export.fd) {
		C.puts(c'VINIX DRM PRIME SPLICE: PASS')
	} else {
		C.puts(c'DRM PRIME SPLICE FAIL: incorrect error, queued data or cursor')
	}
	if test_prime_sendfile(first, export.fd) {
		C.puts(c'VINIX DRM PRIME SENDFILE: PASS')
	} else {
		C.puts(c'DRM PRIME SENDFILE FAIL: incorrect error, input data or cursor')
	}
	if test_prime_sendfile_eof(first, export.fd) {
		C.puts(c'VINIX DRM PRIME SENDFILE EOF: PASS')
	} else {
		C.puts(c'DRM PRIME SENDFILE EOF FAIL: incorrect result, offset or cursor')
	}
	if test_sendfile_append(first) {
		C.puts(c'VINIX DRM PRIME SENDFILE APPEND: PASS')
	} else {
		C.puts(c'DRM PRIME SENDFILE APPEND FAIL: incorrect result, offset, cursor or pipe data')
	}
	if test_sendfile_stream_offsets(first) {
		C.puts(c'VINIX DRM PRIME SENDFILE STREAM OFFSET: PASS')
	} else {
		C.puts(c'DRM PRIME SENDFILE STREAM OFFSET FAIL: incorrect error, offset or queued bytes')
	}
	if test_sendfile_source_range(first) {
		C.puts(c'VINIX DRM PRIME SENDFILE RANGE: PASS')
	} else {
		C.puts(c'DRM PRIME SENDFILE RANGE FAIL: incorrect error, offset or transferred bytes')
	}
	if test_sendfile_destination_range() {
		C.puts(c'VINIX DRM SENDFILE DESTINATION RANGE: PASS')
	} else {
		C.puts(c'DRM SENDFILE DESTINATION RANGE FAIL: incorrect error, offset or position')
	}
	if test_sendfile_pipe_write_errors() {
		C.puts(c'VINIX DRM SENDFILE PIPE WRITE: PASS')
	} else {
		C.puts(c'DRM SENDFILE PIPE WRITE FAIL: incorrect error, bytes or source position')
	}
	if test_sendfile_pipe_admission() {
		C.puts(c'VINIX DRM SENDFILE PIPE ADMISSION: PASS')
	} else {
		C.puts(c'DRM SENDFILE PIPE ADMISSION FAIL: incorrect error or socket data was consumed')
	}
	if test_sendfile_pipe_signal() {
		C.puts(c'VINIX DRM SENDFILE SIGPIPE: PASS')
	} else {
		C.puts(c'DRM SENDFILE SIGPIPE FAIL: incorrect signal, sender, error or position')
	}
	if test_pipe_write_signal() {
		C.puts(c'VINIX DRM PIPE WRITE SIGPIPE: PASS')
	} else {
		C.puts(c'DRM PIPE WRITE SIGPIPE FAIL: incorrect signal, write result or partial count')
	}
	if test_pipe_transfer_admission(export.fd) {
		C.puts(c'VINIX DRM PIPE TRANSFER ADMISSION: PASS')
	} else {
		C.puts(c'DRM PIPE TRANSFER ADMISSION FAIL: incorrect error, signal or source data')
	}
	if test_splice_pipe_input() {
		C.puts(c'VINIX DRM SPLICE PIPE INPUT: PASS')
	} else {
		C.puts(c'DRM SPLICE PIPE INPUT FAIL: incorrect wait, transfer or offset')
	}
	if test_prime_copy_range(first, export.fd) {
		C.puts(c'VINIX DRM PRIME COPY FILE RANGE: PASS')
	} else {
		C.puts(c'DRM PRIME COPY FILE RANGE FAIL: incorrect error, offset or cursor')
	}
	return fdinfo_mount_id(export.fd) == internal_id
		&& check_mountinfo_ids(internal_id, visible_id)
}

fn test_prime_fdinfo_flags(card i32, flags i32) bool {
	mut create := DumbCreateRequest{width: 1, height: 1, bpp: 32}
	if C.ioctl(card, i32(u32(0xc02064b2)), &create) != 0 { return false }
	defer { C.ioctl(card, i32(u32(0xc00464b4)), unsafe { &create.handle }) }
	mut export := ExtendedPrimeRequest{handle: create.handle, flags: u32(flags | C.O_CLOEXEC), fd: -1}
	if C.ioctl(card, i32(u32(0xc00c642d)), &export) != 0 || export.fd < 0 { return false }
	defer { C.close(export.fd) }
	duplicate := C.dup(export.fd)
	if duplicate < 0 { return false }
	defer { C.close(duplicate) }
	if C.fcntl(export.fd, C.F_GETFL) != flags || C.fcntl(export.fd, C.F_GETFD) != C.FD_CLOEXEC
		|| !prime_fdinfo_has_flags(export.fd, flags | C.O_CLOEXEC)
		|| !prime_fdinfo_has_flags(duplicate, flags) {
		return false
	}
	if C.fcntl(duplicate, C.F_SETFL, C.O_NONBLOCK) != 0
		|| C.fcntl(export.fd, C.F_SETFD, 0) != 0 { return false }
	status := flags | C.O_NONBLOCK
	return C.fcntl(export.fd, C.F_GETFL) == status
		&& prime_fdinfo_has_flags(export.fd, status)
		&& prime_fdinfo_has_flags(duplicate, status)
}

fn prime_fdinfo_has_name(fd i32, expected &char) bool {
	mut info := [512]u8{}
	if !read_fdinfo(fd, &info[0], sizeof(info)) { return false }
	line := C.strstr(&info[0], c'\nname:\t')
	if expected == unsafe { nil } { return line == unsafe { nil } }
	mut name := [48]char{}
	C.snprintf(&name[0], sizeof(name), c'\nname:\t%s\n', expected)
	return line != unsafe { nil } && C.strcmp(line, &name[0]) == 0
}

fn test_prime_name_page_end(writer i32, reader i32, command i32) bool {
	page := u64(C.getpagesize())
	mapping := C.mmap(unsafe { nil }, 2 * page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if mapping == voidptr(C.MAP_FAILED) { return false }
	defer { C.munmap(mapping, 2 * page) }
	if C.mprotect(unsafe { &u8(mapping) + page }, page, C.PROT_NONE) != 0 { return false }
	name := unsafe { &u8(mapping) + page - 2 }
	unsafe { name[0] = `p` }
	if C.ioctl(writer, command, name) != 0 || !prime_fdinfo_has_name(reader, c'p') { return false }
	unsafe { name[1] = `x` }
	return C.ioctl(writer, command, name) == -1 && unsafe { *C.__errno_location() } == C.EFAULT
		&& prime_fdinfo_has_name(reader, c'p')
}

fn test_prime_names() bool {
	card := C.open(c'/dev/dri/card0', C.O_RDWR)
	if card < 0 { return false }
	defer { C.close(card) }
	mut create := DumbCreateRequest{width: 1, height: 1, bpp: 32}
	if C.ioctl(card, i32(u32(0xc02064b2)), &create) != 0 { return false }
	mut original := ExtendedPrimeRequest{handle: create.handle, fd: -1}
	mut other := original
	if C.ioctl(card, i32(u32(0xc00c642d)), &original) != 0 || original.fd < 0 { return false }
	defer { C.close(original.fd) }
	if C.ioctl(card, i32(u32(0xc00c642d)), &other) != 0 || other.fd < 0 { return false }
	defer { C.close(other.fd) }
	duplicate := C.dup(original.fd)
	if duplicate < 0 { return false }
	defer { C.close(duplicate) }
	first := i32(0x40046201)
	second := i32(0x40086201)
	longest := c'0123456789012345678901234567890'
	if !prime_fdinfo_has_name(other.fd, unsafe { nil }) { return false }
	if C.ioctl(original.fd, first, c'render target') != 0
		|| !prime_fdinfo_has_name(other.fd, c'render target') { return false }
	if C.ioctl(other.fd, second, longest) != 0 || !prime_fdinfo_has_name(duplicate, longest) { return false }
	if C.ioctl(other.fd, second, c'01234567890123456789012345678901') != -1
		|| unsafe { *C.__errno_location() } != C.EINVAL { return false }
	if C.ioctl(other.fd, first, voidptr(0)) != -1
		|| unsafe { *C.__errno_location() } != C.EFAULT { return false }
	if !prime_fdinfo_has_name(duplicate, longest) || !test_prime_name_page_end(other.fd, duplicate, second) {
		return false
	}
	if C.ioctl(card, i32(u32(0xc00464b4)), unsafe { &create.handle }) != 0 { return false }
	return C.ioctl(duplicate, first, c'') == 0 && prime_fdinfo_has_name(other.fd, c'')
}

fn expect_prime_link(dirfd i32, path &char, expected &char, capacity u64) bool {
	mut result := [64]char{}
	length := C.strlen(expected)
	if length >= u64(result.len) { return false }
	unsafe { result[length] = char(`!`) }
	return C.readlinkat(dirfd, path, &result[0], capacity) == i64(length)
		&& C.strncmp(&result[0], expected, length) == 0 && unsafe { result[length] } == char(`!`)
}

fn test_prime_link_reused_slot(prime i32) bool {
	mut fds := [2]i32{}
	if C.pipe(&fds[0]) != 0 { return false }
	defer {
		C.close(fds[0])
		C.close(fds[1])
	}
	mut path := [64]char{}
	C.snprintf(&path[0], sizeof(path), c'/proc/self/fd/%d', fds[0])
	linkfd := C.open(&path[0], C.O_PATH | C.O_NOFOLLOW)
	if linkfd < 0 { return false }
	defer { C.close(linkfd) }
	return C.dup2(prime, fds[0]) == fds[0]
		&& expect_prime_link(linkfd, c'', c'/dmabuf:frame buffer', 64)
}

fn test_prime_descriptor_links() bool {
	card := C.open(c'/dev/dri/card0', C.O_RDWR)
	if card < 0 { return false }
	defer { C.close(card) }
	mut create := DumbCreateRequest{width: 1, height: 1, bpp: 32}
	if C.ioctl(card, i32(u32(0xc02064b2)), &create) != 0 { return false }
	mut export := ExtendedPrimeRequest{handle: create.handle, fd: -1}
	if C.ioctl(card, i32(u32(0xc00c642d)), &export) != 0 || export.fd < 0 { return false }
	defer { if export.fd >= 0 { C.close(export.fd) } }
	mut path := [64]char{}
	C.snprintf(&path[0], sizeof(path), c'/proc/self/fd/%d', export.fd)
	if !expect_prime_link(C.AT_FDCWD, &path[0], c'/dmabuf:', 64) { return false }
	linkfd := C.open(&path[0], C.O_PATH | C.O_NOFOLLOW)
	if linkfd < 0 { return false }
	defer { C.close(linkfd) }
	if C.ioctl(export.fd, i32(0x40086201), c'frame buffer') != 0
		|| !expect_prime_link(linkfd, c'', c'/dmabuf:frame buffer', 64) { return false }
	if !expect_prime_link(C.AT_FDCWD, &path[0], c'/dmabuf:frame buffer', 64)
		|| !expect_prime_link(linkfd, c'', c'/dma', 4)
		|| !test_prime_link_reused_slot(export.fd) { return false }
	if C.ioctl(card, i32(u32(0xc00464b4)), unsafe { &create.handle }) != 0 { return false }
	if C.ioctl(export.fd, i32(0x40046201), c'') != 0
		|| !expect_prime_link(linkfd, c'', c'/dmabuf:', 64) { return false }
	if C.close(export.fd) != 0 { return false }
	export.fd = -1
	mut result := [64]char{}
	return C.readlinkat(linkfd, c'', &result[0], sizeof(result)) == -1
		&& unsafe { *C.__errno_location() } == C.ENOENT
}

fn test_prime_filesystem_type() bool {
	mut info := C.statfs{}
	card := C.open(c'/dev/dri/card0', C.O_RDWR)
	if card < 0 { return false }
	defer { C.close(card) }
	if C.fstatfs(card, &info) != 0 || info.f_type == 0x444d4142 { return false }
	if test_prime_fdinfo_flags(card, C.O_RDONLY) && test_prime_fdinfo_flags(card, C.O_RDWR) {
		C.puts(c'VINIX DRM PRIME FDINFO FLAGS: PASS')
	} else {
		C.puts(c'DRM PRIME FDINFO FLAGS FAIL: incorrect descriptor or status flags')
	}
	mut create := DumbCreateRequest{width: 1, height: 1, bpp: 32}
	if C.ioctl(card, i32(u32(0xc02064b2)), &create) != 0 { return false }
	mut before := C.timespec{}
	mut after := C.timespec{}
	if C.clock_gettime(C.CLOCK_REALTIME, &before) != 0 { return false }
	mut export := ExtendedPrimeRequest{handle: create.handle, flags: u32(C.O_RDWR), fd: -1}
	if !export_with_filesystem_ids(card, mut export) { return false }
	clock_ok := C.clock_gettime(C.CLOCK_REALTIME, &after) == 0
	duplicate := C.dup(export.fd)
	two_refs := duplicate >= 0 && test_prime_fdinfo(duplicate, create.size, 2)
	mount_id_ok := duplicate >= 0 && check_prime_export_pair(card, export.fd, duplicate)
	C.close(export.fd)
	if duplicate < 0 { return false }
	defer { C.close(duplicate) }
	if C.ioctl(card, i32(u32(0xc00464b4)), unsafe { &create.handle }) != 0 { return false }
	if two_refs && test_prime_fdinfo(duplicate, create.size, 1) {
		C.puts(c'VINIX DRM PRIME FDINFO: PASS')
	} else {
		C.puts(c'DRM PRIME FDINFO FAIL: incorrect size, count or exporter')
	}
	if mount_id_ok {
		C.puts(c'VINIX DRM PRIME FDINFO MOUNT ID: PASS')
	} else {
		C.puts(c'DRM PRIME FDINFO MOUNT ID FAIL: DMA-BUF did not share a private mount ID')
	}
	if test_prime_inode_metadata(duplicate, create.size) {
		C.puts(c'VINIX DRM PRIME INODE METADATA: PASS')
	} else {
		C.puts(c'DRM PRIME INODE METADATA FAIL: incorrect anonymous inode reply')
	}
	if clock_ok && test_prime_inode_owner_times(duplicate, before, after) {
		C.puts(c'VINIX DRM PRIME INODE OWNER AND TIMES: PASS')
	} else {
		C.puts(c'DRM PRIME INODE OWNER AND TIMES FAIL: incorrect creation metadata')
	}
	if C.fstatfs(duplicate, &info) != 0 { return false }
	mut inode := C.stat{}
	if C.fstat(duplicate, &inode) != 0 { return false }
	if test_prime_statx_mount_id(duplicate, inode.st_ino) {
		C.puts(c'VINIX DRM PRIME STATX MOUNT ID: PASS')
	} else {
		C.puts(c'DRM PRIME STATX MOUNT ID FAIL: statx mount ID did not match fdinfo')
	}
	words := unsafe { &u32(&info.f_fsid) }
	bits := unsafe { u64(words[0]) | (u64(words[1]) << 32) }
	if bits != 0 && bits == inode.st_dev {
		C.puts(c'VINIX DRM PRIME FILESYSTEM ID: PASS')
	} else {
		C.printf(c'DRM PRIME FILESYSTEM ID FAIL: filesystem id %#lx device %#lx\n',
			bits, inode.st_dev)
	}
	C.printf(c'DRM PRIME fstatfs: type %#lx block %lu fragment %lu name limit %lu\n',
		info.f_type, info.f_bsize, info.f_frsize, info.f_namelen)
	page := u64(C.getpagesize())
	return info.f_type == 0x444d4142 && info.f_bsize == page && info.f_frsize == page
		&& info.f_namelen == 255 && info.f_blocks == 0 && info.f_files == 0
}

fn prime_mmap_rejected(fd i32, length usize, offset i64) bool {
	result := C.mmap(unsafe { nil }, length, C.PROT_READ, C.MAP_SHARED, fd, offset)
	if result == voidptr(C.MAP_FAILED) { return unsafe { *C.__errno_location() } == C.EINVAL }
	C.munmap(result, length)
	return false
}

fn test_prime_mmap_bounds() bool {
	fd := C.open(c'/dev/dri/card0', C.O_RDWR)
	if fd < 0 { return false }
	defer { C.close(fd) }
	page := usize(C.getpagesize())
	mut create := DumbCreateRequest{width: 1, height: u32(page / 2), bpp: 32}
	if C.ioctl(fd, i32(u32(0xc02064b2)), &create) != 0 || create.size < 2 * page {
		return false
	}
	mut export := ExtendedPrimeRequest{handle: create.handle, flags: u32(C.O_RDWR), fd: -1}
	if C.ioctl(fd, i32(u32(0xc00c642d)), &export) != 0 || export.fd < 0 { return false }
	defer { C.close(export.fd) }
	size := usize(create.size)
	too_long := prime_mmap_rejected(export.fd, size + 1, 0)
	at_end := prime_mmap_rejected(export.fd, page, i64(size))
	crosses_end := prime_mmap_rejected(export.fd, page + 1, i64(size - page))
	prot := C.PROT_READ | C.PROT_WRITE
	full := C.mmap(unsafe { nil }, size, prot, C.MAP_SHARED, export.fd, 0)
	if full == voidptr(C.MAP_FAILED) { return false }
	defer { C.munmap(full, size) }
	tail := C.mmap(unsafe { nil }, page, prot, C.MAP_SHARED, export.fd, i64(size - page))
	if tail == voidptr(C.MAP_FAILED) { return false }
	// Confirm that a valid final page aliases the original buffer.
	unsafe { *(&u8(tail)) = 0x5a }
	alias_ok := unsafe { *(&u8(full) + size - page) == 0x5a }
	grown := C.mremap(tail, page, 2 * page, C.MREMAP_MAYMOVE)
	fixed_size := grown == voidptr(C.MAP_FAILED) && unsafe { *C.__errno_location() } == C.EFAULT
	if grown == voidptr(C.MAP_FAILED) { C.munmap(tail, page) }
	else { C.munmap(grown, 2 * page) }
	C.printf(c'DRM PRIME mmap: length %d end %d subrange %d alias %d no growth %d\n',
		i32(too_long), i32(at_end), i32(crosses_end), i32(alias_ok), i32(fixed_size))
	return too_long && at_end && crosses_end && alias_ok && fixed_size
}

fn test_prime_cpu_access(fd i32) bool {
	command := i32(0x40086200)
	mut flags := u64(1) // START | READ
	if C.ioctl(fd, command, unsafe { &flags }) != 0 { return false }
	flags = 7 // END | READ | WRITE
	if C.ioctl(fd, command, unsafe { &flags }) != 0 { return false }
	flags = 4 // END requires an access direction.
	return C.ioctl(fd, command, unsafe { &flags }) == -1
		&& unsafe { *C.__errno_location() } == C.EINVAL
		&& C.ioctl(fd, command, u64(1)) == -1
		&& unsafe { *C.__errno_location() } == C.EFAULT
}

fn test_prime_sync_file(fd i32) bool {
	ready := i16(C.POLLIN | C.POLLOUT)
	mut buffer_poll := C.pollfd{fd: fd, events: ready}
	if C.poll(&buffer_poll, 1, 0) != 1 || buffer_poll.revents != ready {
		return false
	}
	mut request := [i32(1), -1]! // Export a READ snapshot of the empty reservation.
	if C.ioctl(fd, i32(u32(0xc0086202)), &request[0]) != 0 || request[0] != 1 || request[1] < 0 {
		return false
	}
	fence := request[1]
	defer { C.close(fence) }
	mut fence_poll := C.pollfd{fd: fence, events: i16(C.POLLIN)}
	if C.poll(&fence_poll, 1, 0) != 1 || fence_poll.revents != i16(C.POLLIN) {
		return false
	}
	request[0] = 2 // Import the completed fence as a writer.
	return C.ioctl(fd, i32(0x40086203), &request[0]) == 0
		&& C.poll(&buffer_poll, 1, 0) == 1 && buffer_poll.revents == ready
}

fn test_prime_transport(card &char, foreign i32) bool {
	exporter := C.open(card, C.O_RDWR)
	if exporter < 0 { return false }
	defer { C.close(exporter) }
	importer := C.open(card, C.O_RDWR)
	if importer < 0 { return false }
	defer { C.close(importer) }
	mut create := DumbCreateRequest{height: 1, width: 1, bpp: 32}
	if C.ioctl(exporter, i32(u32(0xc02064b2)), &create) != 0 || create.handle == 0 {
		return false
	}
	mut missing := u32(0)
	if C.ioctl(exporter, i32(u32(0xc004642d)), unsafe { &missing }) != -1
		|| unsafe { *C.__errno_location() } != C.ENOENT {
		return false
	}
	mut export := ExtendedPrimeRequest{handle: create.handle, flags: u32(C.O_CLOEXEC),
		fd: -1, tail: 0x12345678}
	if C.ioctl(exporter, i32(u32(0xc010642d)), unsafe { &export }) != 0 || export.fd < 0 {
		return false
	}
	defer { C.close(export.fd) }
	if !test_prime_cpu_access(export.fd) || !test_prime_sync_file(export.fd) { return false }
	if export.handle != create.handle || export.flags != u32(C.O_CLOEXEC)
		|| export.tail != 0x12345678 || export.fd > 0x00ffffff {
		return false
	}
	if foreign >= 0 {
		mut request := ExtendedPrimeRequest{handle: 99, fd: export.fd, tail: 0x87654321}
		if C.ioctl(foreign, i32(u32(0xc010642e)), &request) != -1
			|| unsafe { *C.__errno_location() } != C.EINVAL || request.handle != 99
			|| request.fd != export.fd || request.tail != 0x87654321 {
			return false
		}
	}
	// The eleven-byte little-endian request omits the top byte of the fd.
	// Kernel storage must zero-extend it and leave that user byte alone.
	short_fd := i32(u32(export.fd) | 0xff000000)
	mut imported := ExtendedPrimeRequest{fd: short_fd, tail: 0x87654321}
	if C.ioctl(importer, i32(u32(0xc00b642e)), unsafe { &imported }) != 0 || imported.handle == 0
		|| imported.fd != short_fd || imported.tail != 0x87654321 {
		return false
	}
	handle := imported.handle
	imported.handle = 0
	imported.fd = export.fd
	return C.ioctl(importer, i32(u32(0xc010642e)), unsafe { &imported }) == 0
		&& imported.handle == handle && imported.fd == export.fd && imported.tail == 0x87654321
}

fn test_syncobj_handle_transport() bool {
	fd := C.open(c'/dev/dri/card0', C.O_RDWR)
	if fd < 0 { return false }
	defer { C.close(fd) }
	// The four-byte requests omit the flags and padding words, which are
	// deliberately nonzero in userspace. Only the handle is copied back.
	mut short := [u32(0), 0xffffffff]!
	if C.ioctl(fd, i32(u32(0xc00464bf)), &short[0]) != 0 || short[0] == 0
		|| short[1] != 0xffffffff {
		return false
	}
	handle := short[0]
	if C.ioctl(fd, i32(u32(0xc00464c0)), &short[0]) != 0 || short[0] != handle
		|| short[1] != 0xffffffff {
		return false
	}
	mut extended := [u32(0), 0, 0x1234, 0x5678]!
	if C.ioctl(fd, i32(u32(0xc01064bf)), &extended[0]) != 0 || extended[0] == 0
		|| extended[1] != 0 || extended[2] != 0x1234 || extended[3] != 0x5678 {
		return false
	}
	// A read-only destroy supplies a zero handle. Its error reply must
	// still be copied out, and the live handle can then be destroyed.
	mut read_only := extended[0]
	if C.ioctl(fd, i32(u32(0x800464c0)), unsafe { &read_only }) != -1
		|| unsafe { *C.__errno_location() } != C.EINVAL || read_only != 0 {
		return false
	}
	extended_handle := extended[0]
	if C.ioctl(fd, i32(u32(0xc01064c0)), &extended[0]) != 0 || extended[0] != extended_handle
		|| extended[1] != 0 || extended[2] != 0x1234 || extended[3] != 0x5678 {
		return false
	}
	return C.ioctl(fd, i32(u32(0xc00864c0)), &extended[0]) == -1
		&& unsafe { *C.__errno_location() } == C.EINVAL
}

struct SyncobjArrayRequest {
	handles u64
	count u32
	pad u32
}

struct SyncobjTransferRequest {
	source u32
	destination u32
	source_point u64
	destination_point u64
	flags u32
	pad u32
}

struct ExtendedSyncobjTimelineRequest {
	handles u64
	points u64
	count u32
	flags u32
	tail u64
}

fn test_syncobj_update_transport() bool {
	fd := C.open(c'/dev/dri/card0', C.O_RDWR)
	if fd < 0 { return false }
	defer { C.close(fd) }
	mut source := [u32(0), 0]!
	mut destination := [u32(0), 0]!
	if C.ioctl(fd, i32(u32(0xc00864bf)), &source[0]) != 0
		|| C.ioctl(fd, i32(u32(0xc00864bf)), &destination[0]) != 0 {
		return false
	}
	source_address := u64(unsafe { &source[0] })
	destination_address := u64(unsafe { &destination[0] })
	// Short SIGNAL and TRANSFER omit padding and flags. The transfer uses
	// the signal on the source and publishes it at point 7 on the destination.
	signal := SyncobjArrayRequest{handles: source_address, count: 1, pad: 99}
	transfer := SyncobjTransferRequest{source: source[0], destination: destination[0],
		destination_point: 7, flags: 99, pad: 99}
	if C.ioctl(fd, i32(u32(0xc00c64c5)), unsafe { &signal }) != 0
		|| C.ioctl(fd, i32(u32(0xc01864cc)), unsafe { &transfer }) != 0 {
		return false
	}
	mut point := u64(99)
	mut timeline := ExtendedSyncobjTimelineRequest{handles: destination_address,
		points: u64(unsafe { &point }), count: 1, tail: 0x12345678}
	if C.ioctl(fd, i32(u32(0xc01464cb)), unsafe { &timeline }) != 0 || point != 7 {
		return false
	}
	point = 11
	if C.ioctl(fd, i32(u32(0xc02064cd)), unsafe { &timeline }) != 0 || timeline.tail != 0x12345678
		|| C.ioctl(fd, i32(u32(0xc01464cb)), unsafe { &timeline }) != 0 || point != 11 {
		return false
	}
	reset := SyncobjArrayRequest{handles: destination_address, count: 1, pad: 99}
	return C.ioctl(fd, i32(u32(0xc00c64c4)), unsafe { &reset }) == 0
		&& C.ioctl(fd, i32(u32(0xc02064cb)), unsafe { &timeline }) == 0
		&& point == 0 && timeline.tail == 0x12345678
}

@[export: 'main']
pub fn run() i32 {
	if test_open_order() {
		C.puts(c'VINIX DRM CLIENT IDS: PASS')
	} else {
		C.puts(c'DRM CLIENT IDS FAIL: expected open-order IDs and shared duplicates')
	}
	if test_client_names() {
		C.puts(c'VINIX DRM CLIENT NAMES: PASS')
	} else {
		C.puts(c'DRM CLIENT NAMES FAIL: expected validated names shared by duplicate descriptors')
	}
	clients := C.open(clients_path, C.O_RDONLY)
	if clients >= 0 {
		C.close(clients)
		if test_core_query_transport() {
			C.puts(c'VINIX DRM CORE QUERY TRANSPORT: PASS')
		} else {
			C.puts(c'DRM CORE QUERY TRANSPORT FAIL: unexpected request or reply shape')
		}
		if test_dumb_buffer_transport() {
			C.puts(c'VINIX DRM DUMB BUFFER TRANSPORT: PASS')
		} else {
			C.puts(c'DRM DUMB BUFFER TRANSPORT FAIL: unexpected request, reply or handle state')
		}
		if test_gem_close_transport() {
			C.puts(c'VINIX DRM GEM CLOSE TRANSPORT: PASS')
		} else {
			C.puts(c'DRM GEM CLOSE TRANSPORT FAIL: unexpected framed close or handle state')
		}
		if test_prime_transport(c'/dev/dri/card0', -1) {
			C.puts(c'VINIX DRM PRIME TRANSPORT: PASS')
		} else {
			C.puts(c'DRM PRIME TRANSPORT FAIL: unexpected request, reply or imported handle')
		}
		if test_syncobj_handle_transport() {
			C.puts(c'VINIX DRM SYNCOBJ HANDLE TRANSPORT: PASS')
		} else {
			C.puts(c'DRM SYNCOBJ HANDLE TRANSPORT FAIL: unexpected request, reply or handle state')
		}
		if test_syncobj_update_transport() {
			C.puts(c'VINIX DRM SYNCOBJ UPDATE TRANSPORT: PASS')
		} else {
			C.puts(c'DRM SYNCOBJ UPDATE TRANSPORT FAIL: unexpected request, reply or timeline point')
		}
		if test_debugfs_clients() {
			C.puts(c'VINIX DRM DEBUGFS CLIENTS: PASS')
		} else {
			C.puts(c'DRM DEBUGFS CLIENTS FAIL: unexpected rows or lifecycle')
		}
		if test_live_client_identity() {
			C.puts(c'VINIX DRM LIVE CLIENT IDENTITY: PASS')
		} else {
			C.puts(c'DRM LIVE CLIENT IDENTITY FAIL: incorrect live or reaped opener')
		}
		if test_client_user_namespace(c'1234 0 1\n', 1234) {
			C.puts(c'VINIX DRM CLIENT USER NAMESPACE: PASS')
		} else {
			C.puts(c'DRM CLIENT USER NAMESPACE FAIL: incorrect UID mapping')
		}
		min_uid := test_client_user_namespace(c'2147483648 0 1\n', u32(0x80000000))
		short_uid := test_client_user_namespace(c'4294967294 0 1\n', u32(0xfffffffe))
		if min_uid && short_uid {
			C.puts(c'VINIX DRM CLIENT SIGNED UID: PASS')
		} else {
			C.puts(c'DRM CLIENT SIGNED UID FAIL: wrong sign or padding')
		}
		if test_client_read_allocations() {
			C.puts(c'VINIX DRM CLIENT READ ALLOCATIONS: PASS')
		} else {
			C.puts(c'DRM CLIENT READ ALLOCATIONS FAIL: table or slab usage changed')
		}
		if test_gem_metadata_reclamation() {
			C.puts(c'VINIX DRM GEM METADATA RECLAMATION: PASS')
		} else {
			C.puts(c'DRM GEM METADATA RECLAMATION FAIL: objects retained after final close')
		}
		if test_prime_filesystem_type() {
			C.puts(c'VINIX DRM PRIME FILESYSTEM TYPE: PASS')
		} else {
			C.puts(c'DRM PRIME FILESYSTEM TYPE FAIL: incorrect DMA-BUF filesystem reply')
		}
		if test_prime_names() {
			C.puts(c'VINIX DRM PRIME DMA-BUF NAMES: PASS')
		} else {
			C.puts(c'DRM PRIME DMA-BUF NAMES FAIL: incorrect name or ioctl result')
		}
		if test_prime_descriptor_links() {
			C.puts(c'VINIX DRM PRIME FD LINKS: PASS')
		} else {
			C.puts(c'DRM PRIME FD LINKS FAIL: incorrect descriptor link text')
		}
		if test_prime_mmap_bounds() {
			C.puts(c'VINIX DRM PRIME MMAP BOUNDS: PASS')
		} else {
			C.puts(c'DRM PRIME MMAP BOUNDS FAIL: incorrect extent or alias')
		}
	}
	mut render := C.open(c'/dev/dri/renderD129', C.O_RDWR)
	mut render_primary := c'/dev/dri/card1'
	mut framebuffer := c'/dev/dri/card0'
	if render < 0 {
		render = C.open(c'/dev/dri/renderD128', C.O_RDWR)
		render_primary = c'/dev/dri/card0'
		framebuffer = c'/dev/dri/card1'
	}
	if render >= 0 {
		if test_render_capabilities(render) {
			C.puts(c'VINIX DRM RENDER CAPABILITIES: PASS')
		} else {
			C.puts(c'DRM RENDER CAPABILITIES FAIL: wrong capability reply or error')
		}
		if test_render_dumb_permissions(render) {
			C.puts(c'VINIX DRM RENDER DUMB PERMISSIONS: PASS')
		} else {
			C.puts(c'DRM RENDER DUMB PERMISSIONS FAIL: wrong permission or copy result')
		}
		if test_render_gem_close(render) {
			C.puts(c'VINIX DRM RENDER GEM CLOSE: PASS')
		} else {
			C.puts(c'DRM RENDER GEM CLOSE FAIL: wrong missing handle reply')
		}
		if test_unsupported_dumb_buffers(render_primary) {
			C.puts(c'VINIX DRM UNSUPPORTED DUMB BUFFERS: PASS')
		} else {
			C.puts(c'DRM UNSUPPORTED DUMB BUFFERS FAIL: wrong primary-node error reply')
		}
		if test_prime_transport(framebuffer, render) {
			C.puts(c'VINIX DRM FOREIGN PRIME IMPORT: PASS')
		} else {
			C.puts(c'DRM FOREIGN PRIME IMPORT FAIL: wrong rejection or same-device import')
		}
		C.close(render)
	}
	C.fflush(unsafe { nil })
	C.reboot(C.RB_POWER_OFF)
	for { C.pause() }
	return 1
}
