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
		server_child(path, lock_path, command[0], ready[1]) or { eprintln('HWTEST FAIL wine-server-identity child: ' + err.msg()); C._exit(94) }
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

fn suite() ! {
	C.alarm(60)
	root := '/tmp/wine-server-identity'
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	first_lock := root + '/first-lock'; second_lock := root + '/second-lock'
	for path in [first_lock, second_lock]! { os.write_file(path, '')!; os.chmod(path, 0o600)! }
	mut first := start(root + '/first-socket', first_lock)!
	defer { first.close() }
	mut second := start(root + '/second-socket', second_lock)!
	defer { second.close() }
	baseline := descriptor_count()!
	wineadapter.verify_server_identity(first.socket_fd, first.lock_fd, first.pid)!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 { wineadapter.verify_server_identity(first.socket_fd, first.lock_fd, first.pid)! }
	$if track_heap ? { need(C.vinix_heap_end() == 0, 'server verification retained V allocations')! }
	need(descriptor_count()! == baseline, 'server verification leaked descriptors')!
	mut payload := u8(0)
	need(C.identity_fixture_recv(first.socket_fd, &payload, 1, C.MSG_DONTWAIT) == 1 && payload == `Q`, 'verification consumed protocol bytes')!
	refused(second.socket_fd, first.lock_fd, first.pid, 'socket peer does not identify')!
	refused(first.socket_fd, second.lock_fd, first.pid, 'lock does not identify')!
	for child in [i32(0), -1, C.getpid()]! { refused(first.socket_fd, first.lock_fd, child, 'ordinary-account child')! }
	refused(first.socket_fd, first.lock_fd, C.getppid(), 'owned waitable child')!
	refused(-1, first.lock_fd, first.pid, 'private descriptors')!
	refused(first.socket_fd, -1, first.pid, 'private descriptors')!
	refused(first.lock_fd, first.lock_fd, first.pid, 'private descriptors')!
	refused(first.lock_fd, second.lock_fd, second.pid, 'connected Unix stream')!
	mut datagrams := [i32(-1), -1]!
	need(C.identity_fixture_socketpair(C.AF_UNIX, C.SOCK_DGRAM | C.SOCK_CLOEXEC, 0, &datagrams[0]) == 0, 'datagram fixture failed')!
	refused(datagrams[0], first.lock_fd, first.pid, 'connected Unix stream')!
	for value in datagrams { C.identity_fixture_close(value) }
	unconnected := C.identity_fixture_socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC, 0)
	need(unconnected >= 3, 'unconnected fixture failed')!
	refused(unconnected, first.lock_fd, first.pid, 'connected Unix stream')!
	C.identity_fixture_close(unconnected)
	for fd in [first.socket_fd, first.lock_fd]! {
		need(C.identity_fixture_fcntl(fd, C.F_SETFD, voidptr(0)) == 0, 'cannot clear CLOEXEC')!
		refused(first.socket_fd, first.lock_fd, first.pid, 'close-on-exec')!
		need(C.identity_fixture_fcntl(fd, C.F_SETFD, voidptr(C.FD_CLOEXEC)) == 0, 'cannot restore CLOEXEC')!
	}
	os.chmod(first_lock, 0o644)!
	refused(first.socket_fd, first.lock_fd, first.pid, 'ordinary file')!
	os.chmod(first_lock, 0o600)!
	C.signal(C.SIGCHLD, C.SIG_IGN)
	refused(first.socket_fd, first.lock_fd, first.pid, 'default waitable SIGCHLD')!
	C.signal(C.SIGCHLD, C.SIG_DFL)
	no_wait := [u64(0), u64(C.SA_NOCLDWAIT), 0, 0]!
	mut previous := [4]u64{}
	need(C.identity_fixture_syscall(C.SYS_rt_sigaction, C.SIGCHLD, &no_wait[0], &previous[0], u64(8)) == 0, 'cannot set no-child-wait fixture policy')!
	mut policy_refused := false
	wineadapter.verify_server_identity(first.socket_fd, first.lock_fd, first.pid) or { policy_refused = err.msg().contains('default waitable SIGCHLD'); unsafe { err.free() } }
	need(C.identity_fixture_syscall(C.SYS_rt_sigaction, C.SIGCHLD, &previous[0], voidptr(0), u64(8)) == 0, 'cannot restore fixture child policy')!
	need(policy_refused, 'no-child-wait policy accepted')!
	dead := C.identity_fixture_fork()
	if dead == 0 { C._exit(23) }
	need(dead > 0, 'dead child fork failed')!
	zombie(dead)!
	refused(first.socket_fd, first.lock_fd, dead, 'child has already exited')!
	wait_exit(dead, 23 << 8)!
	refused(first.socket_fd, first.lock_fd, dead, 'owned waitable child')!
	first.tell(`U`)!
	refused(first.socket_fd, first.lock_fd, first.pid, 'lock does not identify')!
	first.tell(`L`)!
	wineadapter.verify_server_identity(first.socket_fd, first.lock_fd, first.pid)!
	first.tell(`R`)!
	refused(first.socket_fd, first.lock_fd, first.pid, 'lock does not identify')!
	first.tell(`L`)!
	wineadapter.verify_server_identity(first.socket_fd, first.lock_fd, first.pid)!
	first.tell(`C`)!
	refused(first.socket_fd, first.lock_fd, first.pid, 'peer has disconnected')!
	need(descriptor_count()! == baseline, 'server verification refusals leaked descriptors')!
	byte_write(first.command, `X`)!
	zombie(first.pid)!
	refused(first.socket_fd, first.lock_fd, first.pid, 'child has already exited')!
	wait_exit(first.pid, 0)!
	byte_write(second.command, `X`)!
	wait_exit(second.pid, 0)!
	println('WINE SERVER IDENTITY PASS owned child; record lock; Unix peer; protocol preserved; 1000 checks; refusal gates; status preserved')
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
		suite() or { eprintln('HWTEST FAIL wine-server-identity: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	if pid > 0 { wait_exit(pid, 0) or { eprintln('HWTEST FAIL wine-server-identity: ' + err.msg()); for { time.sleep(time.second) } } }
	else { eprintln('HWTEST FAIL wine-server-identity: fork'); for { time.sleep(time.second) } }
	println('HWTEST PASS wine-server-identity fixture')
	for { time.sleep(time.second) }
}
