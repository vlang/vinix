// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit checks survive -prod. The same source is also compiled for ARM.
module main

import os
import time

#include <errno.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.pause() i32
fn C.usleep(u32) i32

struct WaitSlot {
mut:
	before [8]u8
	status i32
	after [8]u8
}

fn width_require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn width_slot() WaitSlot {
	return WaitSlot{before: [u8(0xa7), 0x32, 0x90, 0x15, 0x4c, 0xe2, 0x61, 0x8b]!,
		status: i32(-991), after: [u8(0xd8), 0x43, 0x16, 0xa9, 0x70, 0x2f, 0xbc, 0x05]!}
}

fn width_guards(slot &WaitSlot) ! {
	expected := width_slot()
	width_require(sizeof(i32) == 4 && usize(unsafe { &slot.after[0] }) - usize(unsafe { &slot.status }) == 4,
		'wait status does not have an adjacent four-byte boundary')!
	width_require(slot.before == expected.before && slot.after == expected.after,
		'waitpid changed bytes adjacent to the status slot')!
}

fn width_wait(pid i32, mut slot WaitSlot, options i32) i32 {
	for {
		C.errno = 0
		got := C.waitpid(pid, &slot.status, options)
		if got >= 0 || C.errno != C.EINTR { return got }
	}
	return -1
}

fn width_reap(pid i32) {
	mut slot := width_slot()
	if width_wait(pid, mut slot, C.WNOHANG) != 0 { return }
	C.kill(pid, C.SIGKILL)
	width_wait(pid, mut slot, 0)
}

fn width_double_reap(pid i32, mut slot WaitSlot) ! {
	previous := slot.status
	width_require(width_wait(pid, mut slot, C.WNOHANG) == -1 && C.errno == C.ECHILD,
		'a reaped child did not report ECHILD')!
	width_require(slot.status == previous, 'ECHILD changed the status slot')!
	width_guards(&slot)!
}

fn width_raw() ! {
	mut slot := width_slot()
	pid := C.fork()
	width_require(pid >= 0, 'exit fork failed')!
	if pid == 0 { C._exit(37) }
	mut collected := false
	defer { if !collected { width_reap(pid) } }
	got := width_wait(pid, mut slot, 0)
	collected = got == pid
	width_require(collected && slot.status == i32(37 << 8),
		'normal waitpid exit status differs')!
	width_guards(&slot)!
	width_double_reap(pid, mut slot)!

	signaled := C.fork()
	width_require(signaled >= 0, 'signal fork failed')!
	if signaled == 0 { for { C.pause() } }
	mut signal_collected := false
	defer { if !signal_collected { width_reap(signaled) } }
	width_require(C.kill(signaled, C.SIGKILL) == 0, 'raw signal failed')!
	slot = width_slot()
	signal_collected = width_wait(signaled, mut slot, 0) == signaled
	width_require(signal_collected && slot.status & 0x7f == C.SIGKILL,
		'signal waitpid status differs')!
	width_guards(&slot)!
	width_double_reap(signaled, mut slot)!

	mut pipe := [2]i32{}
	width_require(C.pipe(&pipe[0]) == 0, 'running-child pipe failed')!
	defer { C.close(pipe[0]); C.close(pipe[1]) }
	running := C.fork()
	width_require(running >= 0, 'running fork failed')!
	if running == 0 {
		C.close(pipe[1])
		mut byte := u8(0)
		child_read := C.read(pipe[0], &byte, 1)
		C._exit(if child_read == 1 && byte == 0x67 { 23 } else { 99 })
	}
	mut running_collected := false
	defer { if !running_collected { width_reap(running) } }
	C.close(pipe[0]); pipe[0] = -1
	slot = width_slot()
	width_require(width_wait(running, mut slot, C.WNOHANG) == 0 && slot.status == -991,
		'WNOHANG did not preserve a running child status slot')!
	width_guards(&slot)!
	byte := u8(0x67)
	width_require(C.write(pipe[1], &byte, 1) == 1, 'running-child release failed')!
	running_collected = width_wait(running, mut slot, 0) == running
	width_require(running_collected && slot.status == i32(23 << 8),
		'released child status differs')!
	width_guards(&slot)!
	width_double_reap(running, mut slot)!
}

fn width_process(argument string, signal bool, poll bool) ! {
	mut child := os.new_process(os.executable())
	defer { child.close() }
	child.set_args([argument]); child.set_redirect_stdio(); child.run()
	width_require(child.pid > 0, 'Process did not start')!
	defer {
		if child.status in [.running, .stopped, .aborted] { width_reap(i32(child.pid)) }
	}
	mut expected := 29
	if signal {
		width_require(child.is_alive(), 'Process did not observe a running signal child')!
		child.signal_kill()
		expected = 128 + int(C.SIGKILL)
	} else if poll {
		width_require(child.is_alive(), 'Process did not observe a running pipe child')!
		byte := u8(0x67)
		width_require(C.write(child.stdio_fd[0], &byte, 1) == 1, 'Process pipe release failed')!
		expected = 23
		started := time.sys_mono_now()
		for child.is_alive() {
			width_require(time.sys_mono_now() - started < 5 * time.second, 'Process polling deadline exceeded')!
			C.usleep(1000)
		}
	}
	child.wait()
	width_require(child.status in [.exited, .aborted] && child.code == expected, 'Process wait decoded the wrong status')!
	status := child.status
	child.wait(); child.wait()
	width_require(child.code == expected && child.status == status,
		'repeated Process wait changed the result')!
	mut slot := width_slot()
	width_double_reap(i32(child.pid), mut slot)!
}

fn width_check() ! {
	width_raw()!
	width_process('--child-exit', false, false)!
	width_process('--child-block', true, false)!
	width_process('--child-pipe', false, true)!
	result := os.exec(['/bin/sh', '-c', 'exit 31'])
	width_require(result.exit_code == 31 && result.output == '', 'os.exec decoded the wrong status')!
	println('WAITPID WIDTH 4-byte status, adjacent guards, exit/signal/WNOHANG/ECHILD, Process wait/poll/repeat and execute PASS')
}

fn main() {
	if os.args.len == 2 {
		match os.args[1] {
			'--child-exit' { C._exit(29) }
			'--child-block' { for { C.pause() } }
			'--child-pipe' {
				mut byte := u8(0)
				got := C.read(0, &byte, 1)
				C._exit(if got == 1 && byte == 0x67 { 23 } else { 99 })
			}
			else { eprintln('unexpected child mode'); exit(2) }
		}
	}
	if os.args.len != 1 { eprintln('unexpected arguments'); exit(2) }
	width_check() or { eprintln(err); exit(1) }
}
