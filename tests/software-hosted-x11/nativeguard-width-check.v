// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit checks survive -prod; every waiting child has an alarm backstop.
module main

import json2
import nativeguard
import os
import recoveryguard
import time

#include <errno.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.waitpid(pid i32, status &i32, options i32) i32
fn C.alarm(seconds u32) u32
fn C.pause() i32
fn C.pipe(fds &i32) i32
fn C.getpgid(pid i32) i32

struct WaitSlot {
mut:
	before [8]u8
	status i32
	after [8]u8
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn slot() WaitSlot {
	return WaitSlot{before: [u8(0xa7), 0x32, 0x90, 0x15, 0x4c, 0xe2, 0x61, 0x8b]!,
		status: i32(-991), after: [u8(0xd8), 0x43, 0x16, 0xa9, 0x70, 0x2f, 0xbc, 0x05]!}
}

fn guards(value &WaitSlot) ! {
	expected := slot()
	require(sizeof(i32) == 4 && usize(unsafe { &value.after[0] }) - usize(unsafe { &value.status }) == 4,
		'wait status has no adjacent four-byte boundary')!
	require(value.before == expected.before && value.after == expected.after,
		'waitpid changed bytes adjacent to its status slot')!
}

fn waited(pid int, mut value WaitSlot, options i32) i32 {
	for {
		C.errno = 0
		got := C.waitpid(i32(pid), &value.status, options)
		if got >= 0 || C.errno != C.EINTR { return got }
	}
	return -1
}

fn reap_on_error(pid int) {
	mut value := slot()
	if waited(pid, mut value, C.WNOHANG) != 0 { return }
	C.kill(pid, C.SIGKILL)
	waited(pid, mut value, 0)
}

fn echild(pid int, mut value WaitSlot) ! {
	previous := value.status
	require(waited(pid, mut value, C.WNOHANG) == -1 && C.errno == C.ECHILD,
		'reaped child did not report ECHILD')!
	require(value.status == previous, 'ECHILD changed the status slot')!
	guards(&value)!
}

fn raw_width() ! {
	mut value := slot()
	pid := C.fork()
	require(pid >= 0, 'normal fork failed')!
	if pid == 0 { C._exit(37) }
	mut collected := false
	defer { if !collected { reap_on_error(pid) } }
	collected = waited(pid, mut value, 0) == pid
	require(collected && value.status == i32(37 << 8), 'normal exit status differs')!
	guards(&value)!
	echild(pid, mut value)!

	signaled := C.fork()
	require(signaled >= 0, 'signal fork failed')!
	if signaled == 0 { C.alarm(10); for { C.pause() } }
	mut signal_collected := false
	defer { if !signal_collected { reap_on_error(signaled) } }
	require(C.kill(signaled, C.SIGKILL) == 0, 'signal failed')!
	value = slot()
	signal_collected = waited(signaled, mut value, 0) == signaled
	require(signal_collected && value.status & 0x7f == C.SIGKILL, 'signal status differs')!
	guards(&value)!
	echild(signaled, mut value)!

	mut pipe := [i32(-1), i32(-1)]!
	require(C.pipe(&pipe[0]) == 0, 'running-child pipe failed')!
	defer { for fd in pipe { if fd >= 0 { C.close(fd) } } }
	running := C.fork()
	require(running >= 0, 'running fork failed')!
	if running == 0 {
		C.alarm(10)
		C.close(pipe[1])
		mut byte := u8(0)
		got := C.read(pipe[0], &byte, 1)
		C._exit(if got == 1 && byte == 0x67 { 23 } else { 99 })
	}
	mut running_collected := false
	defer { if !running_collected { reap_on_error(running) } }
	C.close(pipe[0]); pipe[0] = -1
	value = slot()
	require(waited(running, mut value, C.WNOHANG) == 0 && value.status == -991,
		'WNOHANG did not preserve a running child status slot')!
	guards(&value)!
	byte := u8(0x67)
	require(C.write(pipe[1], &byte, 1) == 1, 'running-child release failed')!
	running_collected = waited(running, mut value, 0) == running
	require(running_collected && value.status == i32(23 << 8), 'released exit status differs')!
	guards(&value)!
	echild(running, mut value)!
}

fn native_case(state string, blocking bool) ! {
	label := if blocking { 'native-signal' } else { 'native-exit' }
	mode := if blocking { '--child-block' } else { '--child-exit' }
	mut child := nativeguard.launch([os.executable(), mode], state, state + '/' + label)!
	defer { nativeguard.close_output(mut child) }
	mut cleaned := false
	defer {
		if !cleaned {
			final := nativeguard.cleanup(mut child, 5000) or { eprintln(err); nativeguard.Cleanup{} }
			os.write_file(state + '/' + label + '-error-cleanup.json', json2.encode(final)) or { eprintln(err) }
		}
	}
	if blocking {
		require(nativeguard.poll(mut child)! && !child.reaped && child.exit_code == -1,
			'native WNOHANG running observation differs')!
	} else {
		start := time.sys_mono_now()
		for nativeguard.poll(mut child)! {
			require(!recoveryguard.deadline_expired(start, 5000), 'native exit polling deadline')!
			time.sleep(time.millisecond)
		}
		require(child.reaped && child.exit_code == 37, 'native exit decoding differs')!
	}
	final := nativeguard.cleanup(mut child, 5000)!
	cleaned = true
	expected := if blocking { 128 + int(C.SIGKILL) } else { 37 }
	require(child.reaped && !nativeguard.poll(mut child)! && final.reaped && final.group_empty
		&& final.final_wait == -1 && final.final_errno == C.ECHILD && final.exit_code == expected,
		'native cleanup receipt differs')!
	repeated := nativeguard.cleanup(mut child, 5000)!
	require(repeated.exit_code == expected && repeated.final_wait == -1 && repeated.final_errno == C.ECHILD
		&& repeated.kill_attempts == 0, 'native repeated cleanup changed its public receipt')!
	os.write_file(state + '/' + label + '.json', json2.encode(final))!
	mut value := slot()
	echild(child.pid, mut value)!
}

fn recovery_case(state string, blocking bool) ! {
	label := if blocking { 'recovery-signal' } else { 'recovery-exit' }
	mode := if blocking { '--child-block' } else { '--child-exit' }
	mut child := os.new_process(os.executable())
	defer { child.close() }
	child.use_pgroup = true
	child.set_args([mode]); child.run()
	require(child.pid > 1, 'recovery Process did not start')!
	mut cleaned := false
	defer {
		if !cleaned {
			recoveryguard.terminate_group(mut child, 5000) or { eprintln(err); reap_on_error(child.pid) }
		}
	}
	start := time.sys_mono_now()
	if blocking {
		for C.getpgid(i32(child.pid)) != child.pid {
			require(child.is_alive() && !recoveryguard.deadline_expired(start, 5000), 'recovery group creation deadline')!
			time.sleep(time.millisecond)
		}
		require(child.is_alive(), 'recovery Process did not observe WNOHANG running')!
	} else {
		for child.is_alive() {
			require(!recoveryguard.deadline_expired(start, 5000), 'recovery exit polling deadline')!
			time.sleep(time.millisecond)
		}
		require(child.code == 37, 'recovery Process exit decoding differs')!
	}
	recoveryguard.terminate_group(mut child, 5000)!
	cleaned = true
	expected := if blocking { 128 + int(C.SIGKILL) } else { 37 }
	require(child.status in [.exited, .aborted] && child.code == expected
		&& !recoveryguard.group_present(child.pid)!, 'recovery cleanup result differs')!
	previous := child.status
	child.wait(); child.wait()
	recoveryguard.terminate_group(mut child, 5000)!
	require(child.status == previous && child.code == expected, 'recovery repeated wait changed its public result')!
	mut value := slot()
	echild(child.pid, mut value)!
	os.write_file(state + '/' + label + '.json', json2.encode({'pid': child.pid,
		'exit_code': child.code, 'final_wait': -1, 'final_errno': int(C.ECHILD)}))!
}

fn check(state string) ! {
	require(os.is_dir(state) && os.ls(state)!.len == 0, 'fixture needs a fresh existing state directory')!
	nativeguard.watch_interrupts()!
	raw_width()!
	native_case(state, false)!
	native_case(state, true)!
	recovery_case(state, false)!
	recovery_case(state, true)!
	println('NATIVEGUARD WIDTH i32 canaries, WNOHANG/exit/signal/ECHILD, poll/cleanup and Process wait/repeat PASS')
}

fn main() {
	if os.args.len == 2 && os.args[1].starts_with('--child-') {
		C.alarm(10)
		match os.args[1] {
			'--child-exit' { C._exit(37) }
			'--child-block' { for { C.pause() } }
			else { C._exit(98) }
		}
	}
	if os.args.len != 2 { eprintln('expected fresh fixture state'); exit(2) }
	check(os.args[1]) or { eprintln(err); exit(1) }
}
