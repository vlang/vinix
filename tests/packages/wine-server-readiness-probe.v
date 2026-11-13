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
	need(cwd == '/tmp/wine-server-readiness/data/wine', 'child did not start in captured prefix')!
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
	need(C.recv(client, unsafe { &byte }, 1, 0) == 0, 'connector wrote protocol bytes or retained socket')!
	os.rm('socket')!
	return 37
}

#define readiness_fixture_info siginfo_t
#define readiness_fixture_waitid waitid
@[typedef]
struct C.readiness_fixture_info { mut: si_pid i32 }
fn C.readiness_fixture_waitid(i32, u32, voidptr, i32) i32

fn retired(pid i32) ! {
 deadline := time.sys_mono_now() + 5 * time.second
 for {
  mut info := C.readiness_fixture_info{}
  need(C.readiness_fixture_waitid(C.P_PID, u32(pid), unsafe { &info }, C.WEXITED | C.WNOHANG | C.WNOWAIT) == 0, 'cannot observe child retirement')!
  if info.si_pid == pid { return }
  need(time.sys_mono_now() < deadline, 'child retirement timed out')!
  time.sleep(time.millisecond)
 }
}
fn refused(mut child wineadapter.ServerChild, server &wineadapter.ServerDirectory, guard &wineadapter.LaunchGuard, data string, budget int, gate string) ! {
 mut connection := child.await_connection(server, guard, data, budget) or {
  matched := err.msg().contains(gate)
  unsafe { err.free() }
  need(matched, 'readiness refused at wrong gate')!
  return
 }
 connection.close()
 return error('readiness unexpectedly accepted')
}
fn marker(path string) ! {
 deadline := time.sys_mono_now() + 5 * time.second
 for !os.exists(path) { need(time.sys_mono_now() < deadline, 'fixture barrier timed out')!; time.sleep(time.millisecond) }
}
fn greeting(mut connection wineadapter.ServerConnection) ! {
 mut byte := u8(0)
 need(C.recv(connection.descriptor(), unsafe { &byte }, 1, 0) == 1 && byte == `Q`, 'readiness consumed protocol greeting')!
 need(C.child_fixture_fcntl(connection.descriptor(), C.F_GETFD) & C.FD_CLOEXEC != 0, 'connection lost CLOEXEC')!
 need(C.child_fixture_fcntl(connection.descriptor(), C.F_GETFL) & C.O_NONBLOCK == 0, 'connection is nonblocking')!
 connection.close()
}
fn suite() ! {
 C.alarm(60)
 root := '/tmp/wine-server-readiness'
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
 mut server := guard.prepare_server_directory(data)!
 defer { server.close() }
 action := FixtureAction{handler: 1}
 need(signal_action(C.SIGUSR1, unsafe { &action }, unsafe { nil }) == 0, 'cannot ignore signal')!
 blocked := u64(1) << (C.SIGUSR2 - 1)
 need(C.child_fixture_syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, unsafe { &blocked }, voidptr(0), u64(8)) == 0, 'cannot set mask')!
 baseline := descriptors()!
 cwd := os.getwd()
 defer { unsafe { cwd.free() } }
 start_path := data + '/wine/start-server'
 socket_path := server.path + '/socket'
 listening := server.path + '/listening'
 command := wineadapter.ServerCommand{program: '/sbin/init', arguments: ['fixture-child', 'literal $; argument', '', 'server', server.path]}
 hold := wineadapter.ServerCommand{program: '/sbin/init', arguments: ['fixture-child', 'literal $; argument', '', 'hold']}
 defer { unsafe { (&array(&command.arguments)).free(); (&array(&hold.arguments)).free(); start_path.free(); socket_path.free(); listening.free() } }
 mut child := server.start_child(&guard, data, command)!
 defer { cleanup(mut child) }
 ready(mut child)!
 pid := child.process_id()
 started := time.sys_mono_now()
 refused(mut child, &server, &guard, data, 20, 'readiness timed out')!
 elapsed := time.sys_mono_now() - started
 need(elapsed >= 20 * time.millisecond && elapsed < 5 * time.second, 'readiness timeout was not bounded')!
 need(child.process_id() == pid && !child.collect()!.collected, 'timeout consumed/stopped child')!
 refused(mut child, &server, &guard, data, 0, 'between 1 and 5000')!
 refused(mut child, &server, &guard, data, 5001, 'between 1 and 5000')!
 os.write_file(socket_path, 'foreign entry')!
 refused(mut child, &server, &guard, data, 1000, 'lock does not identify')!
 need(os.read_file(socket_path)! == 'foreign entry' && !child.collect()!.collected, 'foreign entry refusal changed child/entry')!
 os.rm(socket_path)!
 os.write_file(start_path, 'go')!
 marker(listening)!
 os.chmod(socket_path, 0o644)!
 refused(mut child, &server, &guard, data, 1000, 'mode 0600')!
 need(!child.collect()!.collected, 'metadata refusal stopped child')!
 os.chmod(socket_path, 0o600)!
 mut connection := child.await_connection(&server, &guard, data, 1000)!
 greeting(mut connection)!
 collect(mut child, 37)!
 need(descriptors()! == baseline, 'readiness success/refusal retained descriptors')!
 // Exercise readiness over the actual exec/lock/bind scheduling interleaving.
 $if track_heap ? { C.vinix_heap_begin() }
 for _ in 0 .. 100 {
  child = server.start_child(&guard, data, command)!
  connection = child.await_connection(&server, &guard, data, 1000)!
  greeting(mut connection)!; collect(mut child, 37)!
 }
 $if track_heap ? { need(C.vinix_heap_end() == 0, 'readiness lifecycle retained V bytes')! }
 need(descriptors()! == baseline, 'readiness lifecycle retained descriptors')!
 os.rm(start_path)!
 child = server.start_child(&guard, data, hold)!
 ready(mut child)!
 $if track_heap ? { C.vinix_heap_begin() }
 for _ in 0 .. 100 { refused(mut child, &server, &guard, data, 1, 'readiness timed out')! }
 $if track_heap ? { need(C.vinix_heap_end() == 0, 'readiness timeouts retained V bytes')! }
 need(!child.collect()!.collected && descriptors()! == baseline, 'timeouts changed child/resources')!
 // A second child is the foreign lock owner. Do not contact or kill it.
 os.rm(listening)!
 mut foreign := server.start_child(&guard, data, command)!
 defer { cleanup(mut foreign) }
 ready(mut foreign)!
 os.write_file(start_path, 'go')!; marker(listening)!
 refused(mut child, &server, &guard, data, 1000, 'lock does not identify')!
 need(!foreign.collect()!.collected && !child.collect()!.collected, 'foreign lock refusal stopped a child')!
 need(foreign.terminate()! == 137, 'foreign fixture status differs')!
 os.rm(socket_path)!; os.rm(start_path)!
 // Continuity checks still run during the wait, before any socket contact.
 old_prefix := data + '/wine-held'
 os.mv(data + '/wine', old_prefix)!; os.mkdir(data + '/wine')!; os.chmod(data + '/wine', 0o700)!
 refused(mut child, &server, &guard, data, 1000, 'prefix identity changed')!
 os.rmdir(data + '/wine')!; os.mv(old_prefix, data + '/wine')!
 unsafe { old_prefix.free() }
 need(child.terminate()! == 137, 'pending owned fixture status differs')!
 // Early exit and exec failure must refuse without consuming exact status.
 quick := wineadapter.ServerCommand{program: '/sbin/init', arguments: ['fixture-child', 'literal $; argument', '', 'quick']}
 defer { unsafe { (&array(&quick.arguments)).free() } }
 child = server.start_child(&guard, data, quick)!
 ready(mut child)!
 // Wait without reaping, so readiness sees an unequivocally retired child.
 retired(child.process_id())!
 refused(mut child, &server, &guard, data, 1000, 'child has already exited')!
 collect(mut child, 37)!
 child = server.start_child(&guard, data, wineadapter.ServerCommand{program: '/missing-wine-server'})!
 mut failed := false
 ready(mut child) or { failed = err.msg().contains('setup stage 4'); unsafe { err.free() } }
 need(failed, 'exec failure did not report')!
 refused(mut child, &server, &guard, data, 1000, 'setup stage 4')!
 collect(mut child, 126)!
 server.close(); guard.close(); prefix.close()
 need(descriptors()! == initial && mask()! == blocked, 'readiness fixture changed descriptors/mask')!
 current := os.getwd()
 need(current == cwd, 'readiness changed launcher cwd')!
 unsafe { current.free() }
 println('WINE SERVER READINESS PASS bounded wait; owned child; foreign refusal; authenticated connection; 100 cycles')
}

fn main() {
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
		suite() or { eprintln('HWTEST FAIL wine-server-readiness: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	mut status := i32(0)
	if pid <= 0 || C.child_fixture_waitpid(pid, &status, 0) != pid || status != 0 {
		eprintln('HWTEST FAIL wine-server-readiness: suite status ' + status.str()); for { time.sleep(time.second) }
	}
	println('HWTEST PASS wine-server-readiness fixture')
	for { time.sleep(time.second) }
}
