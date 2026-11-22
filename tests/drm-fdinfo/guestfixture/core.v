// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/fsuid.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/reboot.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, u64) i64
fn C.lseek(i32, i64, i32) i64
fn C.write(i32, voidptr, u64) i64
fn C.ioctl(i32, i32, ...) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.mremap(voidptr, usize, usize, i32, ...) voidptr
fn C.getpagesize() i32
fn C.setfsuid(u32) i32
fn C.setfsgid(u32) i32
fn C.clock_gettime(i32, &C.timespec) i32
fn C.fstat(i32, &C.stat) i32
fn C.fstatfs(i32, &C.statfs) i32
fn C.ftruncate(i32, i64) i32
fn C.poll(&C.pollfd, u64, i32) i32
fn C.__errno_location() &i32
fn C.dup(i32) i32
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.snprintf(voidptr, u64, &char, ...) i32
fn C.strstr(voidptr, &char) &char
fn C.strlen(&char) u64
fn C.strcmp(&char, &char) i32
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
fn C.geteuid() u32
fn C.prctl(i32, ...) i32
fn C.unshare(i32) i32
fn C.setrlimit(i32, &C.rlimit) i32
fn C.setresuid(u32, u32, u32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.sendmsg(i32, &C.msghdr, i32) i64
fn C.recvmsg(i32, &C.msghdr, i32) i64

struct C.rlimit {
	rlim_cur u64
	rlim_max u64
}

struct C.timespec {
	tv_sec i64
	tv_nsec i64
}

struct C.stat {
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

struct C.statfs {
	f_type u64
	f_bsize u64
	f_frsize u64
	f_namelen u64
	f_blocks u64
	f_files u64
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

fn test_prime_filesystem_type() bool {
	mut info := C.statfs{}
	card := C.open(c'/dev/dri/card0', C.O_RDWR)
	if card < 0 { return false }
	defer { C.close(card) }
	if C.fstatfs(card, &info) != 0 || info.f_type == 0x444d4142 { return false }
	mut create := DumbCreateRequest{width: 1, height: 1, bpp: 32}
	if C.ioctl(card, i32(u32(0xc02064b2)), &create) != 0 { return false }
	mut before := C.timespec{}
	mut after := C.timespec{}
	if C.clock_gettime(C.CLOCK_REALTIME, &before) != 0 { return false }
	mut export := ExtendedPrimeRequest{handle: create.handle, flags: u32(C.O_RDWR), fd: -1}
	if !export_with_filesystem_ids(card, mut export) { return false }
	clock_ok := C.clock_gettime(C.CLOCK_REALTIME, &after) == 0
	duplicate := C.dup(export.fd)
	C.close(export.fd)
	if duplicate < 0 { return false }
	defer { C.close(duplicate) }
	if C.ioctl(card, i32(u32(0xc00464b4)), unsafe { &create.handle }) != 0 { return false }
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
