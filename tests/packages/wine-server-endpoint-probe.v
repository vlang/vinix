// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import tools.packages.wineadapter

#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <sys/syscall.h>
#include <grp.h>
#include <sys/stat.h>
#define identity_fixture_link link
#define identity_fixture_mkfifo mkfifo
fn C.identity_fixture_link(&char, &char) i32
fn C.identity_fixture_mkfifo(&char, u32) i32
#define identity_fixture_open open
#define identity_fixture_close close
#define identity_fixture_fcntl fcntl
#define identity_fixture_pipe pipe2
#define identity_fixture_fork fork
#define identity_fixture_waitpid waitpid
#define identity_fixture_waitid waitid
#define identity_fixture_read read
#define identity_fixture_write write
#define identity_fixture_socket socket
#define identity_fixture_socketpair socketpair
#define identity_fixture_bind(fd, address, length) bind((fd), (const struct sockaddr *)(address), (length))
#define identity_fixture_connect(fd, address, length) connect((fd), (const struct sockaddr *)(address), (length))
#define identity_fixture_listen listen
#define identity_fixture_accept accept4
#define identity_fixture_recv recv
#define identity_fixture_lock flock
#define identity_fixture_address sockaddr_un
#define identity_fixture_info siginfo_t
#define identity_fixture_sysconf sysconf
#define identity_fixture_syscall syscall
fn C.identity_fixture_open(&char, i32, ...i32) i32
fn C.identity_fixture_close(i32) i32
fn C.identity_fixture_fcntl(i32, i32, ...voidptr) i32
fn C.identity_fixture_pipe(&i32, i32) i32
fn C.identity_fixture_fork() i32
fn C.identity_fixture_waitpid(i32, &i32, i32) i32
fn C.identity_fixture_waitid(i32, u32, voidptr, i32) i32
fn C.identity_fixture_read(i32, voidptr, u64) i64
fn C.identity_fixture_write(i32, voidptr, u64) i64
fn C.identity_fixture_socket(i32, i32, i32) i32
fn C.identity_fixture_socketpair(i32, i32, i32, &i32) i32
fn C.identity_fixture_bind(i32, voidptr, u32) i32
fn C.identity_fixture_connect(i32, voidptr, u32) i32
fn C.identity_fixture_listen(i32, i32) i32
fn C.identity_fixture_accept(i32, voidptr, voidptr, i32) i32
fn C.identity_fixture_recv(i32, voidptr, u64, i32) i64
fn C.identity_fixture_sysconf(i32) i64
fn C.identity_fixture_syscall(i64, ...) i64
fn C.getpid() i32
fn C.getppid() i32
fn C.dup2(i32, i32) i32
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.alarm(u32) u32
fn C._exit(i32)
fn C.signal(i32, voidptr) voidptr
struct C.identity_fixture_lock { mut: l_type i16 l_whence i16 l_start i64 l_len i64 l_pid i32 }
struct C.identity_fixture_address { mut: sun_family u16 sun_path [108]char }
@[typedef]
struct C.identity_fixture_info { mut: si_pid i32 }

$if track_heap ? {
	#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn descriptor_count() !int {
	limit := C.identity_fixture_sysconf(C._SC_OPEN_MAX)
	need(limit >= 3 && limit <= 1048576, 'fixture needs a bounded descriptor limit')!
	mut count := 0
	for fd in 3 .. int(limit) {
		if C.identity_fixture_fcntl(i32(fd), C.F_GETFD) >= 0 { count++ }
		else if C.errno != C.EBADF { return error('fixture cannot inspect descriptors') }
	}
	return count
}

fn need(value bool, message string) ! { if !value { return error(message) } }
fn byte_write(fd i32, byte u8) ! {
	mut value := byte
	for {
		n := C.identity_fixture_write(fd, &value, 1)
		if n < 0 && C.errno == C.EINTR { continue }
		need(n == 1, 'fixture write failed')!; return
	}
}
fn byte_read(fd i32) !u8 {
	mut value := u8(0)
	for {
		n := C.identity_fixture_read(fd, &value, 1)
		if n < 0 && C.errno == C.EINTR { continue }
		need(n == 1, 'fixture read failed')!; return value
	}
}
fn wait_exit(pid i32, expected i32) ! {
	mut status := i32(0)
	for {
		result := C.identity_fixture_waitpid(pid, &status, 0)
		if result < 0 && C.errno == C.EINTR { continue }
		need(result == pid && status == expected, 'fixture child status differs')!; return
	}
}
fn zombie(pid i32) ! {
	deadline := time.sys_mono_now() + 5 * time.second
	for {
		mut info := C.identity_fixture_info{}
		need(C.identity_fixture_waitid(C.P_PID, u32(pid), &info, C.WEXITED | C.WNOHANG | C.WNOWAIT) == 0, 'fixture cannot observe child exit')!
		if info.si_pid == pid { return }
		need(time.sys_mono_now() < deadline, 'fixture child did not exit')!
		time.sleep(time.millisecond)
	}
}
fn address(path string) !C.identity_fixture_address {
	need(path.len > 0 && path.len < 108 && !path.contains('\x00'), 'fixture address invalid')!
	mut value := C.identity_fixture_address{sun_family: u16(C.AF_UNIX)}
	unsafe { vmemcpy(&value.sun_path[0], path.str, path.len) }
	return value
}
fn set_lock(fd i32, kind i16) ! {
	mut value := C.identity_fixture_lock{l_type: kind, l_whence: i16(C.SEEK_SET), l_len: 1}
	need(C.identity_fixture_fcntl(fd, C.F_SETLK, &value) == 0, 'fixture record lock failed')!
}
fn refused(socket_fd i32, lock_fd i32, child i32, gate string) ! {
	mut rejected := false
	wineadapter.verify_server_identity(socket_fd, lock_fd, child) or {
		rejected = err.msg().contains(gate)
		unsafe { err.free() }
	}
	need(rejected, 'identity refusal did not reach gate: ' + gate)!
}

struct Server {
mut:
	pid i32
	command i32 = -1
	ready i32 = -1
	socket_fd i32 = -1
	lock_fd i32 = -1
}
fn server_child(path string, lock_path string, command i32, ready i32) ! {
	fd := C.identity_fixture_open(lock_path.str, C.O_RDWR | C.O_CLOEXEC)
	need(fd >= 3, 'child lock open failed')!
	defer { C.identity_fixture_close(fd) }
	set_lock(fd, i16(C.F_WRLCK))!
	listener := C.identity_fixture_socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC, 0)
	need(listener >= 3, 'child socket failed')!
	defer { C.identity_fixture_close(listener) }
	endpoint := address(path)!
	need(C.identity_fixture_bind(listener, unsafe { &endpoint }, u32(2 + path.len + 1)) == 0, 'child bind failed')!
	os.chmod(path, 0o600)!
	need(C.identity_fixture_listen(listener, 5) == 0, 'child listen failed')!
	byte_write(ready, `R`)!
	mut connection := C.identity_fixture_accept(listener, unsafe { nil }, unsafe { nil }, C.SOCK_CLOEXEC)
	need(connection >= 3, 'child accept failed')!
	defer { if connection >= 0 { C.identity_fixture_close(connection) } }
	byte_write(connection, `Q`)!
	byte_write(ready, `A`)!
	for {
		command_byte := byte_read(command)!
		match command_byte {
			`U` { set_lock(fd, i16(C.F_UNLCK))! }
			`L` { set_lock(fd, i16(C.F_WRLCK))! }
			`R` { set_lock(fd, i16(C.F_RDLCK))! }
			`C` { C.identity_fixture_close(connection); connection = -1 }
			`X` { return }
			else { return error('unknown fixture command') }
		}
		byte_write(ready, command_byte)!
	}
}
fn start(path string, lock_path string) !Server {
	mut command := [i32(-1), -1]!
	mut ready := [i32(-1), -1]!
	need(C.identity_fixture_pipe(&command[0], C.O_CLOEXEC) == 0, 'command pipe failed')!
	defer { C.identity_fixture_close(command[0]) }
	need(C.identity_fixture_pipe(&ready[0], C.O_CLOEXEC) == 0, 'ready pipe failed')!
	defer { C.identity_fixture_close(ready[1]) }
	pid := C.identity_fixture_fork()
	if pid == 0 {
		C.identity_fixture_close(command[1]); C.identity_fixture_close(ready[0])
		server_child(path, lock_path, command[0], ready[1]) or { eprintln('HWTEST FAIL wine-server-endpoint child: ' + err.msg()); C._exit(94) }
		C._exit(0)
	}
	need(pid > 0, 'server fork failed')!
	need(byte_read(ready[0])! == `R`, 'child ready marker differs')!
	fd := C.identity_fixture_socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC | C.SOCK_NONBLOCK, 0)
	need(fd >= 3, 'client socket failed')!
	endpoint := address(path)!
	need(C.identity_fixture_connect(fd, unsafe { &endpoint }, u32(2 + path.len + 1)) == 0, 'client connect failed')!
	need(byte_read(ready[0])! == `A`, 'child accept marker differs')!
	lock_fd := C.identity_fixture_open(lock_path.str, C.O_RDONLY | C.O_CLOEXEC)
	need(lock_fd >= 3, 'parent lock open failed')!
	return Server{pid: pid, command: command[1], ready: ready[0], socket_fd: fd, lock_fd: lock_fd}
}
fn (server &Server) tell(value u8) ! {
	byte_write(server.command, value)!
	need(byte_read(server.ready)! == value, 'child command acknowledgement differs')!
}
fn (mut server Server) close() {
	for fd in [server.command, server.ready, server.socket_fd, server.lock_fd]! { if fd >= 0 { C.identity_fixture_close(fd) } }
	server = Server{}
}

fn capture_refused(directory &wineadapter.ServerDirectory, guard &wineadapter.LaunchGuard, data string) bool {
	mut value := directory.capture_endpoint(guard, data) or { unsafe { err.free() }; return true }
	value.close(); return false
}
fn changed(endpoint &wineadapter.ServerEndpoint, directory &wineadapter.ServerDirectory, guard &wineadapter.LaunchGuard, data string) bool {
	endpoint.recheck(directory, guard, data) or { unsafe { err.free() }; return true }
	return false
}
fn fresh_connection(path string, lock_fd i32, pid i32) ! {
	fd := C.identity_fixture_socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC | C.SOCK_NONBLOCK, 0)
	need(fd >= 3, 'fresh client socket failed')!
	defer { C.identity_fixture_close(fd) }
	endpoint := address(path)!
	need(C.identity_fixture_connect(fd, unsafe { &endpoint }, u32(2 + path.len + 1)) == 0, 'metadata close destroyed listener')!
	wineadapter.verify_server_identity(fd, lock_fd, pid)!
}
fn suite() ! {
	C.alarm(60)
	root := '/tmp/wine-server-endpoint'
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	data := root + '/data'; builtins := root + '/builtins'
	os.mkdir(data)!; os.chmod(data, 0o700)!
	os.mkdir(builtins)!; os.write_file(builtins + '/kernel32.dll', 'fixture builtin')!
	initial := descriptor_count()!
	mut prefix := wineadapter.prepare_prefix(data, builtins)!
	defer { prefix.close() }
	mut guard := prefix.acquire_launch(data)!
	defer { guard.close() }
	prefix.close()
	mut directory := guard.prepare_server_directory(data)!
	defer { directory.close() }
	socket_path := directory.path + '/socket'; lock_path := directory.path + '/lock'
	old_socket := directory.path + '/saved-socket'
	old_directory := directory.path + '-saved'
	need(capture_refused(&directory, &guard, data), 'missing endpoint accepted')!
	mut server := start(socket_path, lock_path)!
	defer { server.close() }
	mut endpoint := directory.capture_endpoint(&guard, data)!
	defer { endpoint.close() }
	baseline := descriptor_count()!
	endpoint.recheck(&directory, &guard, data)!
	wineadapter.verify_server_identity(server.socket_fd, server.lock_fd, server.pid)!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		mut value := directory.capture_endpoint(&guard, data)!
		value.recheck(&directory, &guard, data)!
		value.close(); value.close()
	}
	$if track_heap ? { need(C.vinix_heap_end() == 0, 'endpoint capture retained V allocations')! }
	need(descriptor_count()! == baseline, 'endpoint capture leaked descriptors')!
	mut payload := u8(0)
	need(C.identity_fixture_recv(server.socket_fd, &payload, 1, C.MSG_DONTWAIT) == 1 && payload == `Q`, 'metadata capture consumed protocol bytes')!
	// A queued old greeting alone cannot prove the listener survived O_PATH
	// close. Establish another connection, without asking the server to exit.
	fresh_connection(socket_path, server.lock_fd, server.pid)!
	os.chmod(socket_path, 0o644)!
	need(changed(&endpoint, &directory, &guard, data), 'changed socket mode accepted')!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 { need(capture_refused(&directory, &guard, data), 'unsafe endpoint capture accepted')! }
	$if track_heap ? { need(C.vinix_heap_end() == 0, 'failed endpoint capture retained V allocations')! }
	os.chmod(socket_path, 0o600)!
	endpoint.recheck(&directory, &guard, data)!
	need(C.identity_fixture_link(socket_path.str, old_socket.str) == 0, 'socket hardlink fixture failed')!
	need(changed(&endpoint, &directory, &guard, data) && capture_refused(&directory, &guard, data), 'multiply linked socket accepted')!
	os.rm(old_socket)!
	os.mv(socket_path, old_socket)!
	os.symlink(old_socket, socket_path)!
	need(changed(&endpoint, &directory, &guard, data) && capture_refused(&directory, &guard, data), 'linked endpoint accepted')!
	os.rm(socket_path)!
	os.symlink('/missing-endpoint-fixture', socket_path)!
	need(capture_refused(&directory, &guard, data) && os.is_link(socket_path), 'dangling endpoint accepted or removed')!
	os.rm(socket_path)!
	os.write_file(socket_path, '')!; os.chmod(socket_path, 0o600)!
	need(capture_refused(&directory, &guard, data), 'ordinary endpoint file accepted')!
	os.rm(socket_path)!
	need(C.identity_fixture_mkfifo(socket_path.str, 0o600) == 0, 'endpoint FIFO fixture failed')!
	need(capture_refused(&directory, &guard, data), 'FIFO endpoint accepted')!
	os.rm(socket_path)!; os.mkdir(socket_path)!; os.chmod(socket_path, 0o700)!
	need(capture_refused(&directory, &guard, data), 'directory endpoint accepted')!
	os.rmdir(socket_path)!
	// A same-account replacement socket is well-formed but has a different
	// inode. The retained O_PATH reference keeps the original inode alive.
	replacement := C.identity_fixture_socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC, 0)
	need(replacement >= 3, 'replacement socket failed')!
	endpoint_address := address(socket_path)!
	need(C.identity_fixture_bind(replacement, unsafe { &endpoint_address }, u32(2 + socket_path.len + 1)) == 0, 'replacement bind failed')!
	os.chmod(socket_path, 0o600)!
	need(changed(&endpoint, &directory, &guard, data), 'replacement socket identity accepted')!
	mut replacement_capture := directory.capture_endpoint(&guard, data)!
	replacement_capture.close()
	os.rm(socket_path)!; C.identity_fixture_close(replacement)
	os.mv(old_socket, socket_path)!
	endpoint.recheck(&directory, &guard, data)!
	// The same inode moved into a different captured server directory must
	// not be admitted as if it belonged to that other prefix.
	other_data := root + '/other-data'
	os.mkdir(other_data)!; os.chmod(other_data, 0o700)!
	mut other_prefix := wineadapter.prepare_prefix(other_data, builtins)!
	defer { other_prefix.close() }
	mut other_guard := other_prefix.acquire_launch(other_data)!
	defer { other_guard.close() }
	other_prefix.close()
	mut other_directory := other_guard.prepare_server_directory(other_data)!
	defer { other_directory.close() }
	other_socket := other_directory.path + '/socket'
	os.mv(socket_path, other_socket)!
	need(changed(&endpoint, &directory, &guard, data), 'removed endpoint accepted')!
	mut wrong_parent := false
	endpoint.recheck(&other_directory, &other_guard, other_data) or { wrong_parent = err.msg().contains('different server directory'); unsafe { err.free() } }
	need(wrong_parent, 'endpoint admitted in a different parent directory')!
	os.mv(other_socket, socket_path)!
	other_directory.close(); other_guard.close()
	os.mv(directory.path, old_directory)!
	os.mkdir(directory.path)!; os.chmod(directory.path, 0o700)!
	need(changed(&endpoint, &directory, &guard, data), 'replaced endpoint directory accepted')!
	os.rmdir(directory.path)!; os.mv(old_directory, directory.path)!
	endpoint.recheck(&directory, &guard, data)!
	need(descriptor_count()! == baseline, 'endpoint refusal paths leaked descriptors')!
	endpoint.close(); endpoint.close()
	need(changed(&endpoint, &directory, &guard, data), 'closed endpoint accepted')!
	endpoint = directory.capture_endpoint(&guard, data)!
	mut survivor := directory.capture_endpoint(&guard, data)!
	defer { survivor.close() }
	directory.close()
	need(changed(&endpoint, &directory, &guard, data), 'closed server directory accepted')!
	endpoint.close()
	// Closing the independently retained metadata after its parent object
	// must leave both the listener and connected client's identity intact.
	fresh_connection(socket_path, server.lock_fd, server.pid)!
	wineadapter.verify_server_identity(server.socket_fd, server.lock_fd, server.pid)!
	guard.close()
	byte_write(server.command, `X`)!
	wait_exit(server.pid, 0)!
	// Keep the O_PATH capture alive while the real listener's final owner
	// retires. Metadata references must not keep its transport accepting.
	retired := C.identity_fixture_socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC | C.SOCK_NONBLOCK, 0)
	need(retired >= 3, 'retired listener probe socket failed')!
	retired_address := address(socket_path)!
	need(C.identity_fixture_connect(retired, unsafe { &retired_address }, u32(2 + socket_path.len + 1)) == -1
		&& C.errno == C.ECONNREFUSED, 'metadata kept retired listener accepting')!
	C.identity_fixture_close(retired)
	survivor.close(); survivor.close()
	server.close()
	need(descriptor_count()! == initial, 'closed endpoint fixture retained descriptors')!
	println('WINE SERVER ENDPOINT PASS pinned socket; parent binding; replacement refusal; live transport; retired listener; 1000 cycles')
}
fn main() {
	if C.getpid() != 1 { eprintln('requires fixture PID 1'); exit(2) }
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.identity_fixture_open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.identity_fixture_close(fd) } }
	os.mkdir_all('/tmp') or { panic(err) }; os.chmod('/tmp', 0o1777) or { panic(err) }
	pid := C.identity_fixture_fork()
	if pid == 0 {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		suite() or { eprintln('HWTEST FAIL wine-server-endpoint: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	if pid > 0 { wait_exit(pid, 0) or { eprintln('HWTEST FAIL wine-server-endpoint: ' + err.msg()); for { time.sleep(time.second) } } }
	else { eprintln('HWTEST FAIL wine-server-endpoint: fork'); for { time.sleep(time.second) } }
	println('HWTEST PASS wine-server-endpoint fixture')
	for { time.sleep(time.second) }
}
