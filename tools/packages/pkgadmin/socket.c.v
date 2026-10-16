// SPDX-License-Identifier: GPL-2.0-or-later
module pkgadmin

import os
import time

#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include <unistd.h>
#include <fcntl.h>
// Bind this symbol independently of desktop/account poll declarations; their
// V pointer spellings differ while the C ABI is the same poll(2) interface.
#define vinix_package_admin_poll poll
#define vinix_package_admin_address sockaddr_un

fn C.socket(int, int, int) int
fn C.bind(int, voidptr, u32) int
fn C.connect(int, voidptr, u32) int
fn C.listen(int, int) int
fn C.accept(int, voidptr, voidptr) int
fn C.unlink(&char) int
fn C.getsockopt(int, int, int, voidptr, &u32) int
fn C.vinix_package_admin_poll(voidptr, u64, int) int
$if !linux { fn C.getpeereid(int, &u32, &u32) int }

struct C.vinix_package_admin_address {
mut:
	sun_family u16
	sun_path [108]char
}
struct Credentials { mut: pid i32 uid u32 gid u32 }
struct Poll { mut: fd i32 events i16 revents i16 }

pub struct Listener {
pub mut:
	fd int = -1
	path string
}

fn peer(fd int) !u32 {
	$if linux {
		mut credentials := Credentials{}
		mut length := u32(sizeof(Credentials))
		if C.getsockopt(fd, 1, 17, &credentials, &length) != 0 || length != sizeof(Credentials) { return error('package administrator peer identity is unavailable') }
		return credentials.uid
	} $else {
		mut uid := u32(0)
		mut gid := u32(0)
		if C.getpeereid(fd, &uid, &gid) != 0 { return error('package administrator peer identity is unavailable') }
		return uid
	}
}

fn private_directory(directory string, uid u32) ! {
	info := os.lstat(directory)!
	if info.get_filetype() != .directory || info.uid != uid || info.mode & 0o777 != 0o700 {
		return error('package administration requires the caller\'s private runtime directory')
	}
}

pub fn runtime_directory(uid u32) !string {
	for parent in ['/run', '/run/user']! {
		info := os.lstat(parent)!
		if info.get_filetype() != .directory || info.uid != 0 || info.mode & 0o022 != 0 { return error('unsafe package runtime parent') }
	}
	value := uid.str()
	defer { unsafe { value.free() } }
	directory := '/run/user/' + value
	private_directory(directory, uid) or { unsafe { directory.free() }; return err }
	return directory
}

fn address(path string) !C.vinix_package_admin_address {
	if !path.starts_with('/') || path.len >= 100 || path.contains('\x00') { return error('package administrator socket path is invalid') }
	mut result := C.vinix_package_admin_address{ sun_family: u16(C.AF_UNIX) }
	unsafe { vmemcpy(&result.sun_path[0], path.str, path.len) }
	return result
}

pub fn listen_private(directory string, uid u32, nonce string) !Listener {
	private_directory(directory, uid)!
	if !hex(nonce, 32) { return error('invalid package administrator nonce') }
	path := directory + '/pkg-' + nonce + '.sock'
	mut accepted := false
	defer { if !accepted { unsafe { path.free() } } }
	location := address(path)!
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create package administrator socket') }
	defer { if !accepted { C.close(fd) } }
	if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 { return error('cannot protect package administrator socket') }
	// Never unlink a caller-supplied existing name or follow a planted link.
	if C.bind(fd, voidptr(&location), u32(sizeof(C.vinix_package_admin_address))) != 0 { return error('cannot bind package administrator socket') }
	os.chmod(path, 0o600) or { C.unlink(path.str); return err }
	if C.listen(fd, 8) != 0 { C.unlink(path.str); return error('cannot listen for package administrator worker') }
	accepted = true
	return Listener{ fd: fd, path: path }
}

pub fn connect_private(directory string, uid u32, nonce string) !int {
	private_directory(directory, uid)!
	if !hex(nonce, 32) { return error('invalid package administrator nonce') }
	path := directory + '/pkg-' + nonce + '.sock'
	defer { unsafe { path.free() } }
	location := address(path)!
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create package administrator connection') }
	mut accepted := false
	defer { if !accepted { C.close(fd) } }
	if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 { return error('cannot protect package administrator connection') }
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) != 0 { return error('cannot bound package administrator connection time') }
	if C.connect(fd, voidptr(&location), u32(sizeof(C.vinix_package_admin_address))) != 0 {
		if C.errno !in [C.EINPROGRESS, C.EAGAIN] { return error('the requesting package client is unavailable') }
		mut readiness := Poll{ fd: i32(fd), events: 4 }
		mut failure := i32(0)
		mut length := u32(sizeof(i32))
		if C.vinix_package_admin_poll(voidptr(&readiness), 1, 5000) <= 0
			|| C.getsockopt(fd, C.SOL_SOCKET, C.SO_ERROR, &failure, &length) != 0 || failure != 0 { return error('the requesting package client is unavailable') }
	}
	if peer(fd)! != uid { return error('package administrator destination belongs to another account') }
	if C.fcntl(fd, C.F_SETFL, flags) != 0 { return error('cannot configure package administrator output') }
	accepted = true
	return fd
}

pub fn (listener &Listener) accept_root() !int {
	deadline := time.sys_mono_now() + 10_000_000_000
	for _ in 0 .. 8 {
		now := time.sys_mono_now()
		if now >= deadline { break }
		remaining := deadline - now
		mut readiness := Poll{ fd: i32(listener.fd), events: 1 }
		if C.vinix_package_admin_poll(voidptr(&readiness), 1, int(remaining / 1_000_000)) <= 0 { break }
		fd := C.accept(listener.fd, unsafe { nil }, unsafe { nil })
		if fd < 0 { return error('cannot accept package administrator worker') }
		identity := peer(fd) or { C.close(fd); return err }
		if identity == 0 { return fd }
		C.close(fd)
	}
	return error('administrator approval succeeded but its worker connection is unavailable; check package state before retrying')
}

pub fn (mut listener Listener) close() {
	if listener.fd >= 0 {
		C.close(listener.fd)
		C.unlink(listener.path.str)
	}
	unsafe { listener.path.free() }
	listener = Listener{}
}
