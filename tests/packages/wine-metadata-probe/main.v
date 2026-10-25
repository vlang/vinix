// SPDX-License-Identifier: GPL-2.0-or-later
// Native ownership control for the Windows-only fattr launch promise.
module main

import os
import time

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/xattr.h>

fn C.dup2(i32, i32) i32
fn C.fchmod(i32, u32) i32
fn C.futimens(i32, &C.timespec) i32
fn C.fsetxattr(i32, &char, voidptr, usize, i32) i32
fn C.socket(i32, i32, i32) i32
fn C.bind(i32, voidptr, u32) i32

struct C.sockaddr_un {
mut:
	sun_family u16
	sun_path [108]u8
}

const root_dir = '/tmp/wine-fattr-root'
const private_dir = '/tmp/wine-fattr-private'
const payload = root_dir + '/payload'
const socket_path = private_dir + '/socket'

fn child() ! {
	if os.getuid() != 1000 || os.geteuid() != 1000 || os.getgid() != 1000 || os.getegid() != 1000 {
		return error('metadata child identity differs')
	}
	fd := C.open(payload.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return error('cannot open root-owned payload read-only') }
	defer { C.close(fd) }
	mut before := C.stat{}
	if C.fstat(fd, &before) != 0 || before.st_uid != 0 || before.st_mode & 0o7777 != 0o644 {
		return error('root payload owner/mode differs')
	}
	if C.fchmod(fd, 0o666) != -1 || C.errno != C.EPERM {
		return error('root payload descriptor chmod was not refused by ownership')
	}
	mut times := [2]C.timespec{init: C.timespec{tv_sec: 123, tv_nsec: 456}}
	if C.futimens(fd, &times[0]) != -1 || C.errno != C.EPERM {
		return error('root payload explicit descriptor timestamp was not refused by ownership')
	}
	mut acl := [28]u8{}
	acl[0] = 2
	for i, tag in [u8(1), 4, 32]! {
		offset := 4 + i * 8
		acl[offset] = tag
		acl[offset + 2] = 6
		for byte in 0 .. 4 { acl[offset + 4 + byte] = 255 }
	}
	if C.fsetxattr(fd, c'system.posix_acl_access', &acl[0], 28, 0) != -1 || C.errno != C.EPERM {
		return error('root payload descriptor ACL was not refused by ownership')
	}
	mut after := C.stat{}
	if C.fstat(fd, &after) != 0 || before.st_mode != after.st_mode || before.st_uid != after.st_uid
		|| before.st_gid != after.st_gid || before.st_size != after.st_size || before.st_mtime != after.st_mtime
		|| before.st_ctime != after.st_ctime {
		return error('root payload metadata changed after refused operations')
	}
	file := private_dir + '/file'
	defer { unsafe { file.free() } }
	private_fd := C.open(file.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o644)
	if private_fd < 0 { return error('cannot create own private file') }
	defer { C.close(private_fd) }
	if C.fchmod(private_fd, 0o600) != 0 { return error('own private descriptor chmod failed') }
	mut own := C.stat{}
	if C.fstat(private_fd, &own) != 0 || own.st_uid != 1000 || own.st_mode & 0o7777 != 0o600 {
		return error('own private file metadata differs')
	}
	socket_fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if socket_fd < 0 { return error('cannot create private Unix socket') }
	defer { C.close(socket_fd) }
	mut address := C.sockaddr_un{sun_family: u16(C.AF_UNIX)}
	for i, byte in socket_path { address.sun_path[i] = byte }
	if C.bind(socket_fd, unsafe { &address }, u32(sizeof(C.sockaddr_un))) != 0 || C.chmod(socket_path.str, 0o600) != 0 {
		return error('own private socket bind/chmod failed')
	}
	mut socket_info := C.stat{}
	if C.lstat(socket_path.str, &socket_info) != 0 || socket_info.st_uid != 1000
		|| socket_info.st_mode & 0o170000 != 0o140000 || socket_info.st_mode & 0o7777 != 0o600 {
		return error('own private socket metadata differs')
	}
	println('WINE FATTR root-owned FD chmod/timestamp/ACL refused; own private file/socket chmod PASS')
}

fn run() ! {
	os.mkdir_all(root_dir)!
	os.mkdir_all(private_dir)!
	os.chmod(root_dir, 0o755)!
	os.chmod(private_dir, 0o700)!
	os.chown(private_dir, 1000, 1000)!
	os.write_file(payload, 'root-owned signed-payload ownership analogue\n')!
	os.chmod(payload, 0o644)!
	before := os.read_file(payload)!
	defer { unsafe { before.free() } }
	mut process := os.new_process('/usr/bin/vinix-sandbox')
	defer {
		if process.is_alive() { process.signal_kill(); process.wait() }
		unsafe { process.free(); free(process) }
	}
	process.set_environment(map[string]string{})
	process.set_args(['--uid', '1000', '--gid', '1000', '--promises', 'stdio rpath wpath cpath fattr unix',
		'--unveil', root_dir, 'rx', '--unveil', private_dir, 'rwc', '--', '/sbin/init', '--metadata-child'])
	process.set_redirect_stdio_merged()
	process.run()
	if process.pid <= 0 { return error('metadata sandbox did not start') }
	C.close(process.stdio_fd[0]); process.stdio_fd[0] = -1
	deadline := time.sys_mono_now() + 15 * time.second
	for process.is_alive() && time.sys_mono_now() < deadline { time.sleep(10 * time.millisecond) }
	if process.is_alive() { return error('metadata sandbox timed out') }
	output := process.stdout_slurp()
	defer { unsafe { output.free() } }
	process.wait()
	print(output)
	if process.code != 0 || !output.contains('own private file/socket chmod PASS\n') {
		return error('native metadata boundary control failed')
	}
	after := os.read_file(payload)!
	defer { unsafe { after.free() } }
	if before != after { return error('root payload bytes changed') }
	println('HWTEST PASS Wine-metadata-ownership')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--metadata-child' {
		child() or { eprintln('WINE FATTR FAIL ' + err.msg()); exit(1) }
		return
	}
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	run() or { eprintln('HWTEST FAIL Wine-metadata-ownership: ' + err.msg()) }
	for { time.sleep(time.second) }
}
