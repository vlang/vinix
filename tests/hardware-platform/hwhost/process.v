// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Child processes: QEMU, and the tools that build what it boots.
//
// The one rule is that no child outlives the controller's interest in it. A
// QEMU left running holds a gigabyte and a disk image on a machine other
// people share, and nothing else will ever stop it: a guest that is waiting
// for a power button waits for good. So a child is started in one place,
// stopped in one place, and every wait in the controller is a poll that also
// looks at whether the user asked for the run to end.
//
// A child's output goes to a file. QEMU and the image tools say little, but a
// pipe nobody reads blocks its writer once it is full, and what they do say
// is wanted afterwards, when something failed.
@[has_globals]
module hwhost

import os
import time

#include <signal.h>
#include <sys/wait.h>

// Set from the signal handler and only ever read elsewhere.
__global hw_interrupted = i32(0)

fn note_interrupt(_ os.Signal) {
	hw_interrupted = 1
}

// From here on Ctrl-C, a hang-up and a polite kill end the run through the
// same path as a failure does, so the machine is stopped and the images are
// removed before the controller exits.
pub fn watch_interrupts() {
	for signal in [os.Signal.int, .term, .hup] {
		os.signal_opt(signal, note_interrupt) or {}
	}
}

pub fn interrupted() bool {
	return hw_interrupted != 0
}

// The error every wait returns once the user has asked for the run to end.
pub struct Interrupted {
	Error
}

pub fn (e Interrupted) msg() string {
	return 'interrupted'
}

pub fn now_ms() i64 {
	return i64(time.sys_mono_now() / 1_000_000)
}

pub struct Child {
pub:
	pid  int
	name string
mut:
	ended  bool
	status int // as waitpid() reported it
}

fn resolve_program(name string) !string {
	if name.contains('/') {
		if !os.is_executable(name) {
			return error('not an executable: ${name}')
		}
		return name
	}
	return os.find_abs_path_of_executable(name) or { error('${name} is not on PATH') }
}

// Starts `argv` with its output appended to `log_path` and no input.
//
// Everything the child needs is made before the fork. The V runtime may have
// other threads, and after a fork the child has only this one: a lock one of
// the others held, the allocator's for instance, is never released there. So
// between fork and exec the child makes system calls and nothing else.
pub fn start_child(argv []string, extra_environment map[string]string, log_path string) !Child {
	if argv.len == 0 {
		return error('nothing to run')
	}
	program := resolve_program(argv[0])!
	mut c_argv := []&char{cap: argv.len + 1}
	for argument in argv {
		c_argv << &char(argument.str)
	}
	c_argv << &char(unsafe { nil })
	mut environment := os.environ()
	for name, value in extra_environment {
		environment[name] = value
	}
	mut pairs := []string{cap: environment.len}
	for name, value in environment {
		pairs << '${name}=${value}'
	}
	mut c_environment := []&char{cap: pairs.len + 1}
	for pair in pairs {
		c_environment << &char(pair.str)
	}
	c_environment << &char(unsafe { nil })
	log_fd := C.open(&char(log_path.str), C.O_WRONLY | C.O_CREAT | C.O_APPEND, 0o644)
	if log_fd < 0 {
		return error('cannot write ${log_path}: ${os.posix_get_error_msg(C.errno)}')
	}
	null_fd := C.open(c'/dev/null', C.O_RDONLY)
	if null_fd < 0 {
		C.close(log_fd)
		return error('cannot open /dev/null: ${os.posix_get_error_msg(C.errno)}')
	}
	pid := C.fork()
	if pid < 0 {
		C.close(log_fd)
		C.close(null_fd)
		return error('cannot fork for ${program}: ${os.posix_get_error_msg(C.errno)}')
	}
	if pid == 0 {
		C.dup2(null_fd, 0)
		C.dup2(log_fd, 1)
		C.dup2(log_fd, 2)
		if null_fd > 2 {
			C.close(null_fd)
		}
		if log_fd > 2 {
			C.close(log_fd)
		}
		C.execve(&char(program.str), c_argv.data, c_environment.data)
		C._exit(127)
	}
	C.close(log_fd)
	C.close(null_fd)
	return Child{
		pid:  pid
		name: os.file_name(program)
	}
}

// True once the child has ended. Collects it, so it is never left a zombie.
pub fn (mut c Child) poll() bool {
	if c.ended {
		return true
	}
	mut status := i32(0)
	for {
		waited := C.waitpid(c.pid, &status, C.WNOHANG)
		if waited == c.pid {
			c.ended = true
			c.status = int(status)
			return true
		}
		if waited < 0 && C.errno == C.EINTR {
			continue
		}
		if waited < 0 {
			// Not ours to wait for any more; there is nothing left to stop.
			c.ended = true
			c.status = -1
			return true
		}
		return false
	}
	return false
}

fn (mut c Child) wait_ended(milliseconds int) bool {
	deadline := now_ms() + milliseconds
	for {
		if c.poll() {
			return true
		}
		if now_ms() >= deadline {
			return false
		}
		time.sleep(10 * time.millisecond)
	}
	return false
}

// Ends the child: asked first, so QEMU flushes its disk images and removes
// its socket, then killed. Returns only when it is gone and collected. This
// does not look at interrupted(): it is what an interrupt leads to.
pub fn (mut c Child) stop() {
	if c.poll() {
		return
	}
	C.kill(c.pid, C.SIGTERM)
	if c.wait_ended(5000) {
		return
	}
	C.kill(c.pid, C.SIGKILL)
	for !c.poll() {
		time.sleep(10 * time.millisecond)
	}
}

// A crash fixture deliberately skips orderly QEMU shutdown and cache flushing.
pub fn (mut c Child) cut_power() ! {
	if c.poll() { return error('machine ended before the requested power cut') }
	if C.kill(c.pid, C.SIGKILL) != 0 { return error('cannot cut power to the test machine') }
	if !c.wait_ended(5000) { return error('test machine did not end after SIGKILL') }
	if c.outcome() != 'killed by signal 9' {
		return error('unexpected power-cut outcome: ${c.outcome()}')
	}
}

// The exit status, or -1 when a signal ended the child.
pub fn (c &Child) exit_code() int {
	status := c.status
	if c.ended && status >= 0 && C.WIFEXITED(status) {
		return C.WEXITSTATUS(status)
	}
	return -1
}

// How the child ended, in words.
pub fn (c &Child) outcome() string {
	if !c.ended {
		return 'still running'
	}
	status := c.status
	if status < 0 {
		return 'lost'
	}
	if C.WIFEXITED(status) {
		return 'exit status ${C.WEXITSTATUS(status)}'
	}
	if C.WIFSIGNALED(status) {
		return 'killed by signal ${C.WTERMSIG(status)}'
	}
	return 'wait status ${status}'
}

// The last lines of a log, for an error message.
pub fn log_tail(path string, count int) string {
	text := os.read_file(path) or { return '' }
	lines := text.split_into_lines()
	start := if lines.len > count { lines.len - count } else { 0 }
	return lines[start..].join('\n')
}

// Runs a build tool to its end. Its output is kept in `log_path` and quoted
// when the tool fails.
pub fn run_tool(argv []string, extra_environment map[string]string, log_path string, timeout_seconds int) ! {
	mut child := start_child(argv, extra_environment, log_path)!
	deadline := now_ms() + i64(timeout_seconds) * 1000
	for !child.poll() {
		if interrupted() {
			child.stop()
			return Interrupted{}
		}
		if now_ms() >= deadline {
			child.stop()
			return error('${child.name} did not finish in ${timeout_seconds} s\n${log_tail(log_path, 20)}')
		}
		time.sleep(10 * time.millisecond)
	}
	if child.exit_code() != 0 {
		return error('${argv.join(' ')}\n${child.name}: ${child.outcome()}\n${log_tail(log_path, 20)}')
	}
}
