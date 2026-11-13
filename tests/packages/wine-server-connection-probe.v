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
		n := C.identity_fixture_write(fd, unsafe { &value }, 1)
		if n < 0 && C.errno == C.EINTR { continue }
		need(n == 1, 'fixture write failed')!; return
	}
}
fn byte_read(fd i32) !u8 {
	mut value := u8(0)
	for {
		n := C.identity_fixture_read(fd, unsafe { &value }, 1)
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
	need(C.identity_fixture_fcntl(fd, C.F_SETLK, unsafe { &value }) == 0, 'fixture record lock failed')!
}
fn refused(socket_fd i32, lock_fd i32, child i32, gate string) ! {
	mut rejected := false
	wineadapter.verify_server_identity(socket_fd, lock_fd, child) or {
		rejected = err.msg().contains(gate)
		unsafe { err.free() }
	}
	need(rejected, 'identity refusal did not reach gate: ' + gate)!
}

#define connection_fixture_fchdir fchdir
#define connection_fixture_send send
fn C.connection_fixture_fchdir(i32) i32
fn C.connection_fixture_send(i32, voidptr, u64, i32) i64

struct Server { mut: pid i32 command i32 = -1 ready i32 = -1 }
fn serve(path string, lock_path string, command i32, ready i32) ! {
	fd := C.identity_fixture_open(lock_path.str, C.O_RDWR | C.O_CLOEXEC)
	need(fd >= 3, 'server lock open failed')!
	defer { C.identity_fixture_close(fd) }
	set_lock(fd, i16(C.F_WRLCK))!
	dir := C.identity_fixture_open(path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	need(dir >= 3 && C.connection_fixture_fchdir(dir) == 0, 'server directory capture failed')!
	C.identity_fixture_close(dir)
	listener := C.identity_fixture_socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC, 0)
	need(listener >= 3, 'listener failed')!
	defer { C.identity_fixture_close(listener) }
	endpoint := address('socket')!
	need(C.identity_fixture_bind(listener, unsafe { &endpoint }, 9) == 0, 'server bind failed')!
	os.chmod('socket', 0o600)!
	need(C.identity_fixture_listen(listener, 5) == 0, 'server listen failed')!
	byte_write(ready, `R`)!
	for {
		value := byte_read(command)!
		match value {
			`X` { return }
			`U` { set_lock(fd, i16(C.F_UNLCK))!; byte_write(ready, value)! }
			`L` { set_lock(fd, i16(C.F_WRLCK))!; byte_write(ready, value)! }
			`A`, `E` {
				client := C.identity_fixture_accept(listener, unsafe { nil }, unsafe { nil }, C.SOCK_CLOEXEC)
				need(client >= 3, 'server accept failed')!
				mut byte := u8(`Q`)
				n := C.connection_fixture_send(client, unsafe { &byte }, 1, C.MSG_NOSIGNAL)
				need(n == 1 || (n == -1 && C.errno == C.EPIPE), 'server greeting failed')!
				byte_write(ready, value)!
				if value == `E` { C._exit(37) }
				need(C.identity_fixture_read(client, unsafe { &byte }, 1) == 0, 'connector wrote unexpected protocol bytes')!
				C.identity_fixture_close(client)
				byte_write(ready, `D`)!
			}
			else { return error('bad server command') }
		}
	}
}
fn start(path string) !Server {
	mut command := [i32(-1), -1]!
	mut ready := [i32(-1), -1]!
	need(C.identity_fixture_pipe(&command[0], C.O_CLOEXEC) == 0, 'command pipe failed')!
	defer { C.identity_fixture_close(command[0]) }
	need(C.identity_fixture_pipe(&ready[0], C.O_CLOEXEC) == 0, 'ready pipe failed')!
	defer { C.identity_fixture_close(ready[1]) }
	pid := C.identity_fixture_fork()
	if pid == 0 {
		C.identity_fixture_close(command[1]); C.identity_fixture_close(ready[0])
		serve(path, path + '/lock', command[0], ready[1]) or { eprintln('HWTEST FAIL wine-server-connection child: ' + err.msg()); C._exit(94) }
		C._exit(0)
	}
	need(pid > 0 && byte_read(ready[0])! == `R`, 'server ready failed')!
	return Server{pid: pid, command: command[1], ready: ready[0]}
}
fn (server &Server) tell(value u8) ! {
	byte_write(server.command, value)!
	need(byte_read(server.ready)! == value, 'server acknowledgement differs')!
}
fn (server &Server) drained() ! { need(byte_read(server.ready)! == `D`, 'client did not drain')! }
fn (mut server Server) close() {
	if server.command >= 0 { C.identity_fixture_close(server.command) }
	if server.ready >= 0 { C.identity_fixture_close(server.ready) }
	server = Server{}
}
fn greeting(connection &wineadapter.ServerConnection) ! {
	mut byte := u8(0)
	need(C.identity_fixture_recv(connection.descriptor(), unsafe { &byte }, 1, C.MSG_DONTWAIT) == 1 && byte == `Q`, 'connection consumed greeting')!
	need(C.identity_fixture_fcntl(connection.descriptor(), C.F_GETFD) & C.FD_CLOEXEC != 0, 'connection lost CLOEXEC')!
	need(C.identity_fixture_fcntl(connection.descriptor(), C.F_GETFL) & C.O_NONBLOCK == 0, 'retained protocol socket is nonblocking')!
}
fn rejected(endpoint &wineadapter.ServerEndpoint, directory &wineadapter.ServerDirectory, guard &wineadapter.LaunchGuard, data string, pid i32, timeout_ms int, gate string) ! {
	mut value := endpoint.connect(directory, guard, data, pid, timeout_ms) or {
		matched := err.msg().contains(gate)
		unsafe { err.free() }
		need(matched, 'connection refused at wrong gate')!; return
	}
	value.close(); return error('connection unexpectedly accepted')
}
fn suite() ! {
	C.alarm(60)
	root := '/tmp/wine-server-connection'
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	// A legitimate Wine-style relative bind beneath a path longer than the
	// Unix address limit. The launcher must never chdir to connect to it.
	data := root + '/a-long-private-application-data-directory-for-the-connection-fixture-01234567890123456789'
	builtins := root + '/builtins'
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
	need(directory.path.len + 7 >= 108, 'fixture path is not long enough')!
	mut server := start(directory.path)!
	defer { server.close() }
	mut endpoint := directory.capture_endpoint(&guard, data)!
	defer { endpoint.close() }
	baseline := descriptor_count()!
	cwd := os.getwd()
	defer { unsafe { cwd.free() } }
	mut connection := endpoint.connect(&directory, &guard, data, server.pid, 1000)!
	server.tell(`A`)!
	connection.recheck(&directory, &guard, data)!
	greeting(&connection)!
	endpoint.close()
	connection.recheck(&directory, &guard, data)!
	connection.close(); connection.close()
	server.drained()!
	need(connection.descriptor() == -1, 'closed connection descriptor retained')!
	mut closed := false
	connection.recheck(&directory, &guard, data) or { closed = true; unsafe { err.free() } }
	need(closed, 'closed connection recheck accepted')!
	endpoint = directory.capture_endpoint(&guard, data)!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		mut value := endpoint.connect(&directory, &guard, data, server.pid, 1000)!
		server.tell(`A`)!
		value.recheck(&directory, &guard, data)!
		greeting(&value)!
		value.close(); value.close()
		server.drained()!
	}
	$if track_heap ? { need(C.vinix_heap_end() == 0, 'connection retained V allocations')! }
	need(descriptor_count()! == baseline, 'connection leaked descriptors')!
	for timeout_ms in [0, 5001]! { rejected(&endpoint, &directory, &guard, data, server.pid, timeout_ms, 'between 1 and 5000')! }
	server.tell(`U`)!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 { rejected(&endpoint, &directory, &guard, data, server.pid, 1000, 'lock does not identify')! }
	$if track_heap ? { need(C.vinix_heap_end() == 0, 'refused connection retained V allocations')! }
	server.tell(`L`)!
	// Place another live child's socket beneath this prefix while the
	// expected child still owns this prefix's lock. Metadata alone admits
	// the socket; the connected kernel peer must reject it independently.
	foreign_data := root + '/foreign-data'
	os.mkdir(foreign_data)!; os.chmod(foreign_data, 0o700)!
	mut foreign_prefix := wineadapter.prepare_prefix(foreign_data, builtins)!
	defer { foreign_prefix.close() }
	mut foreign_guard := foreign_prefix.acquire_launch(foreign_data)!
	defer { foreign_guard.close() }
	foreign_prefix.close()
	mut foreign_directory := foreign_guard.prepare_server_directory(foreign_data)!
	defer { foreign_directory.close() }
	mut foreign_server := start(foreign_directory.path)!
	defer { foreign_server.close() }
	socket_path := directory.path + '/socket'
	foreign_socket := foreign_directory.path + '/socket'
	saved_socket := directory.path + '/saved-socket'
	pinned_node := C.identity_fixture_open(socket_path.str, C.O_PATH | C.O_NOFOLLOW | C.O_CLOEXEC)
	need(pinned_node >= 3, 'pinned-route control open failed')!
	os.mv(socket_path, saved_socket)!
	os.mv(foreign_socket, socket_path)!
	// Independently qualify descriptor-link routing while the old pathname
	// actually names a foreign listener. The route must still reach the held
	// inode, not follow its old pathname into the replacement.
	pinned_text := pinned_node.str()
	pinned_route := '/proc/self/fd/' + pinned_text
	pinned_address := address(pinned_route)!
	pinned_client := C.identity_fixture_socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC | C.SOCK_NONBLOCK, 0)
	need(pinned_client >= 3 && C.identity_fixture_connect(pinned_client, unsafe { &pinned_address }, u32(2 + pinned_route.len + 1)) == 0, 'pinned-route control connect failed')!
	pinned_lock := C.identity_fixture_open((directory.path + '/lock').str, C.O_RDONLY | C.O_CLOEXEC)
	need(pinned_lock >= 3, 'pinned-route control lock failed')!
	wineadapter.verify_server_identity(pinned_client, pinned_lock, server.pid)!
	server.tell(`A`)!
	mut pinned_byte := u8(0)
	need(C.identity_fixture_recv(pinned_client, unsafe { &pinned_byte }, 1, C.MSG_DONTWAIT) == 1 && pinned_byte == `Q`, 'pinned-route control reached wrong transport')!
	C.identity_fixture_close(pinned_client); server.drained()!
	C.identity_fixture_close(pinned_lock); C.identity_fixture_close(pinned_node)
	unsafe { pinned_text.free(); pinned_route.free() }
	rejected(&endpoint, &directory, &guard, data, server.pid, 1000, 'endpoint identity changed')!
	mut foreign_endpoint := directory.capture_endpoint(&guard, data)!
	rejected(&foreign_endpoint, &directory, &guard, data, server.pid, 1000, 'socket peer does not identify')!
	foreign_endpoint.close()
	foreign_server.tell(`A`)!; foreign_server.drained()!
	foreign_server.tell(`L`)!
	os.mv(socket_path, foreign_socket)!; os.mv(saved_socket, socket_path)!
	byte_write(foreign_server.command, `X`)!; wait_exit(foreign_server.pid, 0)!
	foreign_server.close(); foreign_directory.close(); foreign_guard.close()
	endpoint.recheck(&directory, &guard, data)!
	need(descriptor_count()! == baseline, 'foreign peer refusal leaked descriptors')!
	// Hold five unaccepted connections, then require bounded EAGAIN handling.
	mut pending := [wineadapter.ServerConnection{}, wineadapter.ServerConnection{}, wineadapter.ServerConnection{}, wineadapter.ServerConnection{}, wineadapter.ServerConnection{}]!
	for index in 0 .. 5 { pending[index] = endpoint.connect(&directory, &guard, data, server.pid, 1000)! }
	started := time.sys_mono_now()
	rejected(&endpoint, &directory, &guard, data, server.pid, 50, 'connect timed out')!
	elapsed := time.sys_mono_now() - started
	need(elapsed >= 50 * time.millisecond && elapsed < 5 * time.second, 'backlog wait was not bounded')!
	for index in 0 .. 5 {
		server.tell(`A`)!
		greeting(&pending[index])!
		pending[index].close(); server.drained()!
	}
	need(descriptor_count()! == baseline, 'backlog refusal leaked descriptors')!
	// A retained connection must detect child retirement without collecting it.
	connection = endpoint.connect(&directory, &guard, data, server.pid, 1000)!
	server.tell(`E`)!
	zombie(server.pid)!
	mut exited := false
	connection.recheck(&directory, &guard, data) or { exited = err.msg().contains('child has already exited'); unsafe { err.free() } }
	need(exited, 'retired server connection accepted')!
	rejected(&endpoint, &directory, &guard, data, server.pid, 1000, 'child has already exited')!
	wait_exit(server.pid, 37 << 8)!
	connection.close(); server.close()
	endpoint.close(); directory.close(); guard.close()
	need(descriptor_count()! == initial, 'closed connection fixture retained descriptors')!
	current_cwd := os.getwd()
	need(current_cwd == cwd, 'connector changed launcher cwd')!
	unsafe { current_cwd.free() }
	println('WINE SERVER CONNECTION PASS retained inode; authenticated peer; long path; bounded backlog; protocol preserved; 1000 cycles')
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
		suite() or { eprintln('HWTEST FAIL wine-server-connection: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	if pid > 0 { wait_exit(pid, 0) or { eprintln('HWTEST FAIL wine-server-connection: ' + err.msg()); for { time.sleep(time.second) } } }
	else { eprintln('HWTEST FAIL wine-server-connection: fork'); for { time.sleep(time.second) } }
	println('HWTEST PASS wine-server-connection fixture')
	for { time.sleep(time.second) }
}
