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
	need(cwd == '/tmp/wine-server-child/data/wine', 'child did not start in captured prefix')!
	unsafe { cwd.free() }
	if os.args[4] == 'quick' { return 37 }
	if os.args[4] == 'hold' { for { time.sleep(time.second) } }
	need(os.args.len == 6 && os.args[4] == 'server', 'unknown child mode')!
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
	client := C.accept4(socket_fd, unsafe { nil }, unsafe { nil }, C.SOCK_CLOEXEC)
	need(client >= 3, 'child cannot accept')!
	defer { C.close(client) }
	mut byte := u8(`Q`)
	need(C.send(client, unsafe { &byte }, 1, C.MSG_NOSIGNAL) == 1, 'child greeting failed')!
	need(C.recv(client, unsafe { &byte }, 1, 0) == 0, 'connector wrote protocol bytes or retained socket')!
	os.rm('socket')!
	return 37
}

fn suite() ! {
	C.alarm(60)
	root := '/tmp/wine-server-child'
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
	mut action := FixtureAction{handler: 1}
	need(signal_action(C.SIGUSR1, unsafe { &action }, unsafe { nil }) == 0, 'cannot ignore signal')!
	action = FixtureAction{handler: u64(voidptr(caught))}
	need(signal_action(C.SIGTERM, unsafe { &action }, unsafe { nil }) == 0, 'cannot catch signal')!
	blocked := u64(1) << (C.SIGUSR2 - 1)
	need(C.child_fixture_syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, unsafe { &blocked }, voidptr(0), u64(8)) == 0, 'cannot set caller mask')!
	need(C.pthread_atfork(voidptr(forbidden_callback), voidptr(forbidden_callback), voidptr(forbidden_callback)) == 0, 'cannot install atfork controls')!
	leak := C.child_fixture_open(c'/dev/null', C.O_RDONLY) // Deliberately no CLOEXEC.
	need(leak >= 3, 'cannot create inherited descriptor control')!
	baseline := descriptors()!
	command := wineadapter.ServerCommand{program: '/sbin/init', arguments: ['fixture-child', 'literal $; argument', '', 'quick']}
	defer { unsafe { command.arguments.free() } }
	start_refused(&directory, &guard, data, wineadapter.ServerCommand{program: 'relative'}, 'absolute executable')!
	start_refused(&directory, &guard, data, wineadapter.ServerCommand{program: '/bad\x00program'}, 'absolute executable')!
	start_refused(&directory, &guard, data, wineadapter.ServerCommand{program: '/sbin/init', arguments: ['bad\x00argument']}, 'argument contains NUL')!
	action = FixtureAction{handler: 1}
	need(signal_action(C.SIGCHLD, unsafe { &action }, unsafe { nil }) == 0, 'cannot set ignored SIGCHLD')!
	start_refused(&directory, &guard, data, command, 'default waitable SIGCHLD')!
	action = FixtureAction{flags: u64(C.SA_NOCLDWAIT)}
	need(signal_action(C.SIGCHLD, unsafe { &action }, unsafe { nil }) == 0, 'cannot set NOCLDWAIT')!
	start_refused(&directory, &guard, data, command, 'default waitable SIGCHLD')!
	action = FixtureAction{}
	need(signal_action(C.SIGCHLD, unsafe { &action }, unsafe { nil }) == 0, 'cannot restore SIGCHLD')!
	mut child := directory.start_child(&guard, data, command)!
	defer { cleanup(mut child) }
	$if wine_child_signal_window ? {
		// Pending caught SIGTERM must take its default action when unmasked,
		// before exec. EOF is intentionally insufficient to claim readiness.
		ready(mut child)!; collect(mut child, 143)!
		need(mask()! == blocked && descriptors()! == baseline, 'signal control changed parent resources')!
		println('WINE SERVER CHILD CONTROL PASS signal')
		return
	}
	$if wine_child_close_failure ? {
		mut failed := false
		ready(mut child) or { failed = err.msg().contains('setup stage 2'); unsafe { err.free() } }
		need(failed && child.process_id() > 0, 'descriptor isolation failure lost child')!
		collect(mut child, 126)!
		need(mask()! == blocked && descriptors()! == baseline, 'close control changed parent resources')!
		println('WINE SERVER CHILD CONTROL PASS close')
		return
	}
	ready(mut child)!
	need(mask()! == blocked, 'fork changed caller mask')!
	collect(mut child, 37)!
	// Repeated observations cannot reap or accidentally target another process.
	mut refused := false
	child.terminate() or { refused = err.msg().contains('already collected'); unsafe { err.free() } }
	need(refused, 'collected child termination accepted')!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 100 {
		child = directory.start_child(&guard, data, command)!
		ready(mut child)!; collect(mut child, 37)!
	}
	$if track_heap ? { need(C.vinix_heap_end() == 0, 'child lifecycle retained V allocations')! }
	need(descriptors()! == baseline && mask()! == blocked, 'child lifecycle retained descriptors or changed mask')!
	// Exec failure stays owned; repeated report reads preserve its exact status.
	child = directory.start_child(&guard, data, wineadapter.ServerCommand{program: '/missing-wine-server'})!
	for _ in 0 .. 2 {
		mut failed := false
		ready(mut child) or { failed = err.msg().contains('setup stage 4'); unsafe { err.free() } }
		need(failed && child.process_id() > 0, 'exec failure lost ownership/report')!
	}
	collect(mut child, 126)!
	// Terminate only the held child, with an unrelated waitable child still live.
	child = directory.start_child(&guard, data, wineadapter.ServerCommand{program: '/sbin/init', arguments: ['fixture-child', 'literal $; argument', '', 'hold']})!
	ready(mut child)!
	mut unrelated := directory.start_child(&guard, data, wineadapter.ServerCommand{program: '/sbin/init', arguments: ['fixture-child', 'literal $; argument', '', 'hold']})!
	defer { cleanup(mut unrelated) }
	ready(mut unrelated)!
	need(!child.collect()!.collected, 'live server was collected')!
	need(child.terminate()! == 137, 'owned child termination status differs')!
	need(!unrelated.collect()!.collected, 'termination affected unrelated child')!
	need(unrelated.terminate()! == 137, 'unrelated child status differs')!
	// End-to-end use of owned PID with the retained, authenticated connector.
	child = directory.start_child(&guard, data, wineadapter.ServerCommand{program: '/sbin/init', arguments: ['fixture-child', 'literal $; argument', '', 'server', directory.path]})!
	ready(mut child)!
	deadline := time.sys_mono_now() + 5 * time.second
	socket_path := directory.path + '/socket'
	for !os.exists(socket_path) { need(time.sys_mono_now() < deadline, 'owned listener did not appear')!; time.sleep(time.millisecond) }
	start_refused(&directory, &guard, data, command, 'lock already has an owner')!
	mut endpoint := directory.capture_endpoint(&guard, data)!
	defer { endpoint.close() }
	mut connection := endpoint.connect(&directory, &guard, data, child.process_id(), 1000)!
	defer { connection.close() }
	mut byte := u8(0)
	need(C.recv(connection.descriptor(), unsafe { &byte }, 1, 0) == 1 && byte == `Q`, 'authenticated owned greeting differs')!
	connection.close(); endpoint.close(); collect(mut child, 37)!
	// Existing entries are refused before fork, without removing them.
	os.write_file(socket_path, 'foreign entry')!
	mut existing := false
	mut unexpected := directory.start_child(&guard, data, command) or {
		existing = err.msg().contains('socket entry already exists'); unsafe { err.free() }
		wineadapter.ServerChild{}
	}
	cleanup(mut unexpected)
	need(existing && os.read_file(socket_path)! == 'foreign entry', 'startup modified/accepted foreign entry')!
	os.rm(socket_path)!
	C.close(leak)
	directory.close(); guard.close(); prefix.close()
	need(descriptors()! == initial && mask()! == blocked, 'closed fixture retained descriptors/mutated mask')!
	println('WINE SERVER CHILD PASS direct ownership; exec report; isolated descriptors; signal policy; authenticated connection; 100 cycles')
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
		suite() or { eprintln('HWTEST FAIL wine-server-child: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	mut status := i32(0)
	if pid <= 0 || C.child_fixture_waitpid(pid, &status, 0) != pid || status != 0 {
		eprintln('HWTEST FAIL wine-server-child: suite status'); for { time.sleep(time.second) }
	}
	println('HWTEST PASS wine-server-child fixture')
	for { time.sleep(time.second) }
}
