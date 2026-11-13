// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import tools.packages.wineadapter

#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <pthread.h>
#include <grp.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/syscall.h>
#define child_fixture_open open
#define child_fixture_fcntl fcntl
#define child_fixture_syscall syscall
#define child_fixture_waitpid waitpid
#define child_fixture_lock flock
#define child_fixture_address sockaddr_un
#define child_fixture_bind(fd,a,n) bind((fd),(const struct sockaddr *)(a),(n))
fn C.child_fixture_open(&char, i32, ...i32) i32
fn C.child_fixture_fcntl(i32, i32, ...voidptr) i32
fn C.child_fixture_syscall(i64, ...) i64
fn C.child_fixture_waitpid(i32, &i32, i32) i32
fn C.child_fixture_bind(i32, voidptr, u32) i32
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.fork() i32
fn C.getpid() i32
fn C.getppid() i32
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.alarm(u32) u32
fn C._exit(i32)
fn C.socket(i32, i32, i32) i32
fn C.listen(i32, i32) i32
fn C.accept4(i32, voidptr, voidptr, i32) i32
fn C.send(i32, voidptr, u64, i32) i64
fn C.recv(i32, voidptr, u64, i32) i64
fn C.pthread_atfork(voidptr, voidptr, voidptr) i32
struct C.child_fixture_lock { mut: l_type i16 l_whence i16 l_start i64 l_len i64 l_pid i32 }
struct C.child_fixture_address { mut: sun_family u16 sun_path [108]char }
struct FixtureAction { handler u64 flags u64 restorer u64 mask u64 }
$if track_heap ? {
	#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn need(ok bool, message string) ! { if !ok { return error(message) } }
fn forbidden_callback() { C._exit(88) }
fn caught(signal i32) { C._exit(89) }
fn signal_action(signal i32, next &FixtureAction, previous &FixtureAction) i64 {
	return C.child_fixture_syscall(C.SYS_rt_sigaction, signal, next, previous, u64(8))
}
fn mask() !u64 {
	mut value := u64(0)
	need(C.child_fixture_syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, voidptr(0), unsafe { &value }, u64(8)) == 0, 'cannot read signal mask')!
	return value
}
fn descriptors() !int {
	mut count := 0
	// Fixture descriptors are deliberately below 1024 (including an explicitly
	// non-CLOEXEC descriptor); raw fcntl avoids allocating /proc directory lists.
	for fd in 3 .. 1024 {
		if C.child_fixture_fcntl(i32(fd), C.F_GETFD) >= 0 { count++ }
		else { need(C.errno == C.EBADF, 'descriptor query failed')! }
	}
	return count
}
fn ready(mut child wineadapter.ServerChild) ! {
	deadline := time.sys_mono_now() + 5 * time.second
	for {
		if child.exec_ready()! { return }
		need(time.sys_mono_now() < deadline, 'exec acknowledgement timed out')!
		time.sleep(time.millisecond)
	}
}
fn collect(mut child wineadapter.ServerChild, expected int) ! {
	deadline := time.sys_mono_now() + 5 * time.second
	for {
		result := child.collect()!
		if result.collected { need(result.code == expected && child.process_id() == 0, 'exit status/ownership differs')!; return }
		need(time.sys_mono_now() < deadline, 'collection timed out')!
		time.sleep(time.millisecond)
	}
}
fn cleanup(mut child wineadapter.ServerChild) {
	if child.process_id() > 0 { child.terminate() or { eprintln('HWTEST FAIL child cleanup: ' + err.msg()) } }
}
fn start_refused(directory &wineadapter.ServerDirectory, guard &wineadapter.LaunchGuard, data string, command wineadapter.ServerCommand, gate string) ! {
	mut owned := directory.start_child(guard, data, command) or {
		matched := err.msg().contains(gate)
		unsafe { err.free() }
		need(matched, 'startup refused at wrong gate')!
		return
	}
	cleanup(mut owned)
	return error('startup unexpectedly accepted')
}
fn fixture_child() !int {
	need(os.args.len >= 5, 'child arguments missing')!
	need(os.args[2] == 'literal $; argument' && os.args[3] == '', 'exec changed argument boundaries')!
	need(descriptors()! == 0, 'exec inherited private descriptors')!
	need(os.getuid() == 1000 && os.getgid() == 1000, 'exec changed account')!
	need(C.getppid() > 1, 'server was daemonized')!
	need(mask()! == u64(1) << (C.SIGUSR2 - 1), 'child did not inherit original signal mask')!
	mut disposition := FixtureAction{}
	need(signal_action(C.SIGUSR1, unsafe { nil }, unsafe { &disposition }) == 0 && disposition.handler == 1, 'ignored disposition changed')!
	need(signal_action(C.SIGTERM, unsafe { nil }, unsafe { &disposition }) == 0 && disposition.handler == 0, 'caught disposition survived exec')!
	cwd := os.getwd()
	need(cwd == '/tmp/wine-client-handoff/data/wine', 'child did not start in captured prefix')!
	unsafe { cwd.free() }
	if os.args[4] == 'quick' { return 37 }
	if os.args[4] == 'hold' { for { time.sleep(time.second) } }
	need(os.args.len == 6 && os.args[4] == 'server', 'unknown child mode')!
	for !os.exists('start-server') { time.sleep(time.millisecond) }
	lock_path := os.args[5] + '/lock'
	lock_fd := C.child_fixture_open(lock_path.str, C.O_WRONLY | C.O_CLOEXEC)
	unsafe { lock_path.free() }
	need(lock_fd >= 3, 'child cannot open server lock')!
	defer { C.close(lock_fd) }
	mut record := C.child_fixture_lock{l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_SET), l_len: 1}
	need(C.child_fixture_fcntl(lock_fd, C.F_SETLK, unsafe { &record }) == 0, 'child cannot own server lock')!
	os.chdir(os.args[5])!
	socket_fd := C.socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC, 0)
	need(socket_fd >= 3, 'child cannot create server socket')!
	defer { C.close(socket_fd) }
	mut address := C.child_fixture_address{sun_family: u16(C.AF_UNIX)}
	unsafe { vmemcpy(&address.sun_path[0], c'socket', 7) }
	need(C.child_fixture_bind(socket_fd, unsafe { &address }, 9) == 0, 'child cannot bind server socket')!
	os.chmod('socket', 0o600)!
	need(C.listen(socket_fd, 5) == 0, 'child cannot listen')!
	os.write_file('listening', 'ready')!
	client := C.accept4(socket_fd, unsafe { nil }, unsafe { nil }, C.SOCK_CLOEXEC)
	need(client >= 3, 'child cannot accept')!
	defer { C.close(client) }
	mut byte := u8(`Q`)
	need(C.send(client, unsafe { &byte }, 1, C.MSG_NOSIGNAL) == 1, 'child greeting failed')!
	os.write_file('greeted', 'ready')!
	n := C.recv(client, unsafe { &byte }, 1, 0)
	need(n == 0 || (n < 0 && C.errno == C.ECONNRESET), 'client wrote unexpected protocol bytes')!
	os.rm('greeted')!
	os.rm('socket')!
	return 37
}

#define handoff_fixture_fcntl fcntl
fn C.handoff_fixture_fcntl(i32, i32, ...i32) i32

fn client_ready(mut client wineadapter.ClientChild) ! {
 deadline := time.sys_mono_now() + 5 * time.second
 for {
  if client.exec_ready()! { return }
  need(time.sys_mono_now() < deadline, 'client exec acknowledgement timed out')!
  time.sleep(time.millisecond)
 }
}
fn client_collect(mut client wineadapter.ClientChild, expected int) ! {
 deadline := time.sys_mono_now() + 5 * time.second
 for {
  result := client.collect()!
  if result.collected { need(result.code == expected && client.process_id() == 0, 'client status/ownership differs')!; return }
  need(time.sys_mono_now() < deadline, 'client collection timed out')!
  time.sleep(time.millisecond)
 }
}
fn client_cleanup(mut client wineadapter.ClientChild) {
 if client.process_id() > 0 { client.terminate() or { eprintln('HWTEST FAIL client cleanup: ' + err.msg()) } }
}
fn client_fixture() !int {
 need(os.args.len == 4 && os.args[2] == 'literal $; argument' && os.args[3] == '', 'client argument boundaries differ')!
 value := os.getenv('WINESERVERSOCKET')
 defer { unsafe { value.free() } }
 need(value.len > 0 && value.len < 10, 'client handoff is not a descriptor')!
 for byte in value { need(byte >= `0` && byte <= `9`, 'client handoff is not canonical numeric')! }
 fd := i32(value.int())
 need(fd >= 3 && descriptors()! == 1, 'client inherited wrong descriptors')!
 need(C.handoff_fixture_fcntl(fd, C.F_GETFD) == 0, 'client socket did not survive exec')!
 need(C.handoff_fixture_fcntl(fd, C.F_GETFL) & C.O_NONBLOCK == 0, 'client socket is nonblocking')!
 literal := os.getenv('LITERAL')
 need(literal == 'space $; literal\nnext', 'client environment changed literal value')!
 unsafe { literal.free() }
 if unexpected := os.getenv_opt('VINIX_CLIENT_PARENT_ONLY') {
  unsafe { unexpected.free() }; return error('client inherited parent environment')
 }
 cwd := os.getwd()
 need(cwd == '/tmp/wine-client-handoff/data/wine', 'client cwd differs')!
 unsafe { cwd.free() }
 need(mask()! == u64(1) << (C.SIGUSR2 - 1), 'client signal mask differs')!
 mut action := FixtureAction{}
 need(signal_action(C.SIGUSR1, unsafe { nil }, unsafe { &action }) == 0 && action.handler == 1, 'ignored client signal changed')!
 need(signal_action(C.SIGTERM, unsafe { nil }, unsafe { &action }) == 0 && action.handler == 0, 'caught client signal survived exec')!
 // Match Wine's initial consumption: protect the inherited protocol FD again.
 need(C.handoff_fixture_fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) == 0, 'client cannot protect consumed socket')!
 mut byte := u8(0)
 need(C.recv(fd, unsafe { &byte }, 1, 0) == 1 && byte == `Q`, 'handoff consumed/replaced greeting')!
 need(C.close(fd) == 0, 'client cannot close socket')!
 return 42
}
fn greeted(path string) ! {
 deadline := time.sys_mono_now() + 5 * time.second
 for !os.exists(path) { need(time.sys_mono_now() < deadline, 'server greeting barrier timed out')!; time.sleep(time.millisecond) }
}
fn rejected(mut connection wineadapter.ServerConnection, directory &wineadapter.ServerDirectory, guard &wineadapter.LaunchGuard, data string, command wineadapter.ServerCommand, environment []string, gate string) ! {
 original := connection.descriptor()
 mut client := connection.start_client(directory, guard, data, command, environment) or {
  matched := err.msg().contains(gate)
  unsafe { err.free() }
  need(matched && connection.descriptor() == original && C.handoff_fixture_fcntl(original, C.F_GETFD) & C.FD_CLOEXEC != 0, 'pre-fork refusal consumed/changed connection')!
  return
 }
 client_cleanup(mut client)
 return error('client handoff unexpectedly accepted')
}
fn suite() ! {
 C.alarm(60)
 root := '/tmp/wine-client-handoff'
 os.mkdir(root)!
 defer { os.rmdir_all(root) or {} }
 data := root + '/data'; builtins := root + '/builtins'
 os.mkdir(data)!; os.chmod(data, 0o700)!; os.mkdir(builtins)!
 os.write_file(builtins + '/kernel32.dll', 'fixture builtin')!
 initial := descriptors()!
 mut prefix := wineadapter.prepare_prefix(data, builtins)!
 defer { prefix.close() }
 mut guard := prefix.acquire_launch(data)!
 defer { guard.close() }
 mut directory := guard.prepare_server_directory(data)!
 defer { directory.close() }
 action := FixtureAction{handler: 1}
 need(signal_action(C.SIGUSR1, unsafe { &action }, unsafe { nil }) == 0, 'cannot ignore signal')!
 caught_action := FixtureAction{handler: u64(voidptr(caught))}
 need(signal_action(C.SIGTERM, unsafe { &caught_action }, unsafe { nil }) == 0, 'cannot catch signal')!
 blocked := u64(1) << (C.SIGUSR2 - 1)
 need(C.child_fixture_syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, unsafe { &blocked }, voidptr(0), u64(8)) == 0, 'cannot set caller mask')!
 need(C.pthread_atfork(voidptr(forbidden_callback), voidptr(forbidden_callback), voidptr(forbidden_callback)) == 0, 'cannot register fork controls')!
 need(os.setenv('WINESERVERSOCKET', 'parent-sentinel', true) == 0 && os.setenv('VINIX_CLIENT_PARENT_ONLY', 'not-inherited', true) == 0, 'cannot set parent environment')!
 leak := C.child_fixture_open(c'/dev/null', C.O_RDONLY)
 need(leak >= 3, 'cannot create unrelated descriptor')!
 defer { C.close(leak) }
 baseline := descriptors()!
 marker := directory.path + '/greeted'
 start := data + '/wine/start-server'
 os.write_file(start, 'go')!
 defer { unsafe { marker.free(); start.free() } }
 server_command := wineadapter.ServerCommand{program: '/sbin/init', arguments: ['fixture-child', 'literal $; argument', '', 'server', directory.path]}
 client_command := wineadapter.ServerCommand{program: '/sbin/init', arguments: ['fixture-client', 'literal $; argument', '']}
 environment := ['WINESERVERSOCKET=0', 'LITERAL=space $; literal\nnext', 'WINESERVERSOCKET=999999999']
 defer { unsafe { (&array(&server_command.arguments)).free(); (&array(&client_command.arguments)).free(); environment.free() } }
 mut server := directory.start_child(&guard, data, server_command)!
 defer { cleanup(mut server) }
 mut connection := server.await_connection(&directory, &guard, data, 1000)!
 defer { connection.close() }
 greeted(marker)!
 rejected(mut connection, &directory, &guard, data, wineadapter.ServerCommand{program: 'relative'}, environment, 'absolute executable')!
 rejected(mut connection, &directory, &guard, data, wineadapter.ServerCommand{program: '/sbin/init', arguments: ['bad\x00argument']}, environment, 'argument contains NUL')!
 for bad in ['NO_EQUALS', '=empty-name', 'NAME=value\x00bad']! {
  bad_environment := [bad]
  rejected(mut connection, &directory, &guard, data, client_command, bad_environment, 'NAME=VALUE')!
  unsafe { (&array(&bad_environment)).free() }
 }
 flags := C.handoff_fixture_fcntl(connection.descriptor(), C.F_GETFL)
 need(C.handoff_fixture_fcntl(connection.descriptor(), C.F_SETFL, flags | C.O_NONBLOCK) == 0, 'cannot set nonblocking refusal control')!
 rejected(mut connection, &directory, &guard, data, client_command, environment, 'blocking socket')!
 need(C.handoff_fixture_fcntl(connection.descriptor(), C.F_SETFL, flags) == 0, 'cannot restore blocking socket')!
 old_fd := connection.descriptor()
 mut client := connection.start_client(&directory, &guard, data, client_command, environment)!
 defer { client_cleanup(mut client) }
 need(connection.descriptor() == -1 && C.handoff_fixture_fcntl(old_fd, C.F_GETFD) == -1 && C.errno == C.EBADF, 'parent kept handoff socket')!
 connection.close(); connection.close()
 client_ready(mut client)!
 $if wine_client_signal_window ? {
  client_collect(mut client, 143)!; collect(mut server, 37)!
  need(mask()! == blocked && descriptors()! == baseline, 'signal refusal changed parent resources')!
  println('WINE CLIENT HANDOFF SIGNAL PASS')
  return
 }
 client_collect(mut client, 42)!; collect(mut server, 37)!
 need(descriptors()! == baseline, 'handoff retained parent descriptors')!
 $if track_heap ? { C.vinix_heap_begin() }
 for _ in 0 .. 100 {
  server = directory.start_child(&guard, data, server_command)!
  connection = server.await_connection(&directory, &guard, data, 1000)!
  greeted(marker)!
  client = connection.start_client(&directory, &guard, data, client_command, environment)!
  client_ready(mut client)!; client_collect(mut client, 42)!; collect(mut server, 37)!
 }
 $if track_heap ? { need(C.vinix_heap_end() == 0, 'client handoff retained V bytes')! }
 need(descriptors()! == baseline && mask()! == blocked, 'client handoff changed descriptors/mask')!
 // Exec failure still consumes the connection and returns exact owned status.
 server = directory.start_child(&guard, data, server_command)!
 connection = server.await_connection(&directory, &guard, data, 1000)!
 greeted(marker)!
 client = connection.start_client(&directory, &guard, data, wineadapter.ServerCommand{program: '/missing-client'}, environment)!
 need(connection.descriptor() == -1, 'exec failure did not transfer connection')!
 mut failed := false
 client_ready(mut client) or { failed = err.msg().contains('setup stage 4'); unsafe { err.free() } }
 need(failed, 'client exec failure was not reported')!
 client_collect(mut client, 126)!; collect(mut server, 37)!
 need(descriptors()! == baseline, 'exec failure retained descriptors')!
 parent_value := os.getenv('WINESERVERSOCKET')
 need(parent_value == 'parent-sentinel', 'handoff changed parent environment')!
 unsafe { parent_value.free() }
 need(C.handoff_fixture_fcntl(leak, C.F_GETFD) >= 0, 'handoff closed unrelated parent descriptor')!
 directory.close(); guard.close(); prefix.close()
 need(descriptors()! == initial + 1, 'closed handoff fixture retained descriptors')!
 println('WINE CLIENT HANDOFF PASS consumed socket; explicit environment; protocol preserved; exec failure; 100 cycles')
}

fn main() {
	if os.args.len > 1 && os.args[1] == 'fixture-client' {
		code := client_fixture() or { eprintln('HWTEST FAIL exec client: ' + err.msg()); C._exit(93); return }
		C._exit(i32(code)); return
	}

	if os.args.len > 1 && os.args[1] == 'fixture-child' {
		code := fixture_child() or { eprintln('HWTEST FAIL exec child: ' + err.msg()); C._exit(92); return }
		C._exit(i32(code)); return
	}
	if C.getpid() != 1 { eprintln('requires fixture PID 1'); exit(2) }
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.child_fixture_open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	os.mkdir_all('/tmp') or { panic(err) }; os.chmod('/tmp', 0o1777) or { panic(err) }
	pid := C.fork()
	if pid == 0 {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		suite() or { eprintln('HWTEST FAIL wine-client-handoff: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	mut status := i32(0)
	if pid <= 0 || C.child_fixture_waitpid(pid, &status, 0) != pid || status != 0 {
		eprintln('HWTEST FAIL wine-client-handoff: suite status ' + status.str()); for { time.sleep(time.second) }
	}
	println('HWTEST PASS wine-client-handoff fixture')
	for { time.sleep(time.second) }
}
