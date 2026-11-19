// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Starting an allowed action. The program gets nothing of the caller's:
// not its environment, its descriptors, its directory or its terminal. It
// gets a fixed environment, the checked arguments, the input on standard
// input, and a pipe for what it prints, of which the caller is sent the
// first part.
module authcore

import os

#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include <sys/wait.h>
#include <fcntl.h>

fn C.fork() int
fn C.pipe(fds &i32) int
fn C.dup2(old int, new int) int
fn C.setsid() int
fn C.execve(path &char, argv &&char, envp &&char) int
fn C._exit(status int)
fn C.waitpid(pid int, status &i32, options int) int
fn C.kill(pid int, signal int) int
fn C.poll(fds voidptr, count u64, timeout int) int
fn C.chdir(path &char) int
fn C.umask(mask u32) u32

struct PollFd {
mut:
	fd      i32
	events  i16
	revents i16
}

pub const max_output = 32 * 1024
const run_timeout_ms = 120_000

// The program an action names must itself be root's alone: a file anyone
// else can write is not an action, it is a way in.
fn trusted_program(path string, owned bool) bool {
	info := os.lstat(path) or { return false }
	if info.get_filetype() != .regular || info.mode & 0o022 != 0 || info.mode & 0o100 == 0 {
		return false
	}
	return !owned || info.uid == 0
}

pub fn run_action(action Action, argv []string, input []u8, peer Peer, user string) RunResult {
	if !trusted_program(action.exec, true) {
		return RunResult{}
	}
	mut to_child := [2]i32{}
	mut from_child := [2]i32{}
	if C.pipe(&to_child[0]) != 0 {
		return RunResult{}
	}
	if C.pipe(&from_child[0]) != 0 {
		C.close(to_child[0])
		C.close(to_child[1])
		return RunResult{}
	}
	mut c_argv := []&char{cap: argv.len + 1}
	for argument in argv {
		c_argv << &char(argument.str)
	}
	c_argv << &char(unsafe { nil })
	environment := ['PATH=/usr/sbin:/usr/bin:/sbin:/bin', 'HOME=/root', 'USER=root', 'LOGNAME=root',
		'LANG=C', 'VINIX_AUTH_UID=${peer.uid}', 'VINIX_AUTH_USER=${user}']
	mut c_env := []&char{cap: environment.len + 1}
	for variable in environment {
		c_env << &char(variable.str)
	}
	c_env << &char(unsafe { nil })

	child := C.fork()
	if child < 0 {
		C.close(to_child[0])
		C.close(to_child[1])
		C.close(from_child[0])
		C.close(from_child[1])
		return RunResult{}
	}
	if child == 0 {
		C.setsid()
		C.dup2(to_child[0], 0)
		C.dup2(from_child[1], 1)
		C.dup2(from_child[1], 2)
		for fd in 3 .. 1024 {
			C.close(fd)
		}
		C.chdir(c'/')
		C.umask(0o022)
		C.execve(c_argv[0], &c_argv[0], &c_env[0])
		C._exit(127)
	}
	C.close(to_child[0])
	C.close(from_child[1])
	// The input is at most one field, which fits a pipe: this cannot block
	// on a program that does not read it.
	if input.len > 0 {
		C.write(to_child[1], input.data, uint(input.len))
	}
	C.close(to_child[1])

	mut output := []u8{cap: 1024}
	mut buffer := []u8{len: 4096}
	mut waited := 0
	mut timed_out := false
	for {
		mut poll_fd := PollFd{
			fd:     from_child[0]
			events: 1
		}
		ready := C.poll(voidptr(&poll_fd), 1, 1000)
		if ready == 0 {
			waited += 1000
			if waited >= run_timeout_ms {
				timed_out = true
				break
			}
			continue
		}
		if ready < 0 {
			continue
		}
		got := C.read(from_child[0], buffer.data, uint(buffer.len))
		if got <= 0 {
			break
		}
		room := max_output - output.len
		if room > 0 {
			output << buffer[..if int(got) < room { int(got) } else { room }]
		}
	}
	C.close(from_child[0])
	if timed_out {
		// The action made itself a session leader: this reaches what it
		// started as well.
		C.kill(-child, C.SIGKILL)
		C.kill(child, C.SIGKILL)
	}
	mut status := i32(0)
	for C.waitpid(child, &status, 0) < 0 {
		if C.errno != C.EINTR {
			return RunResult{}
		}
	}
	if timed_out {
		return RunResult{
			started: true
			status:  124
			output:  output
		}
	}
	code := if status & 0x7f == 0 { (status >> 8) & 0xff } else { 128 + (status & 0x7f) }
	return RunResult{
		started: true
		status:  code
		output:  output
	}
}
