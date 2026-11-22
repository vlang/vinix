// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/reboot.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, u64) i64
fn C.lseek(i32, i64, i32) i64
fn C.write(i32, voidptr, u64) i64
fn C.ioctl(i32, i32, ...) i32
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
	cap[0] = ~u64(0)
	return C.ioctl(fd, i32(u32(0xc018640c)), &cap[0]) == -1
		&& unsafe { *C.__errno_location() } == C.EINVAL
		&& cap[1] == 0 && cap[2] == 0x1234 && cap[3] == 0x5678
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

fn test_gem_close_transport() bool {
	fd := C.open(c'/dev/dri/card0', C.O_RDWR)
	if fd < 0 { return false }
	defer { C.close(fd) }
	commands := [u32(0x40046409), u32(0xc0106409)]!
	for i in 0 .. commands.len {
		command := unsafe { commands[i] }
		mut create := DumbCreateRequest{height: 1, width: 1, bpp: 32}
		if C.ioctl(fd, i32(u32(0xc02064b2)), &create) != 0 || create.handle == 0 {
			return false
		}
		mut close_data := [create.handle, u32(0), 0x1234, 0x5678]!
		// A read-only request supplies a zero handle. The original buffer
		// should survive it and close on the following write request.
		if command == u32(0xc0106409) {
			if C.ioctl(fd, i32(u32(0x80086409)), &close_data[0]) != -1
				|| unsafe { *C.__errno_location() } != C.ENOENT || close_data[0] != create.handle {
				return false
			}
		}
		if C.ioctl(fd, i32(command), &close_data[0]) != 0 || close_data[0] != create.handle
			|| close_data[1] != 0 || close_data[2] != 0x1234 || close_data[3] != 0x5678 {
			return false
		}
		if C.ioctl(fd, i32(0x40086409), &close_data[0]) != -1 || unsafe { *C.__errno_location() } != C.ENOENT {
			return false
		}
	}
	return true
}

struct ExtendedPrimeRequest {
mut:
	handle u32
	flags u32
	fd i32
	tail u32
}

fn test_prime_transport() bool {
	card := c'/dev/dri/card0'
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
	if export.handle != create.handle || export.flags != u32(C.O_CLOEXEC)
		|| export.tail != 0x12345678 || export.fd > 0x00ffffff {
		return false
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
		if test_gem_close_transport() {
			C.puts(c'VINIX DRM GEM CLOSE TRANSPORT: PASS')
		} else {
			C.puts(c'DRM GEM CLOSE TRANSPORT FAIL: unexpected framed close or handle state')
		}
		if test_prime_transport() {
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
	}
	C.fflush(unsafe { nil })
	C.reboot(C.RB_POWER_OFF)
	for { C.pause() }
	return 1
}
