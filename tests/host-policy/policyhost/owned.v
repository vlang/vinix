// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module policyhost

import fixturehost
import hosttest

#include <signal.h>
#include <unistd.h>
fn C.signal(i32, voidptr) voidptr
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32

__global (
	owned_command_signal i32
	owned_command_depth int
)

fn owned_interrupt(_signal i32) {
	unsafe { C.__atomic_store_n(&owned_command_signal, i32(1), C.__ATOMIC_RELAXED) }
}

pub struct CommandGuard {
	previous voidptr
	previous_pipe voidptr
	installed bool
}

// A CLI owns one signal scope; nested compiler commands share its pending
// interrupt and cannot clear a signal delivered between two build steps.
pub fn own_commands() CommandGuard {
	owned_command_depth++
	if owned_command_depth > 1 { return CommandGuard{} }
	unsafe { C.__atomic_store_n(&owned_command_signal, i32(0), C.__ATOMIC_RELAXED) }
	return CommandGuard{unsafe { C.signal(C.SIGINT, voidptr(owned_interrupt)) },
		unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }, true}
}

pub fn (guard CommandGuard) close() {
	owned_command_depth--
	if guard.installed {
		unsafe { C.signal(C.SIGINT, guard.previous); C.signal(C.SIGPIPE, guard.previous_pipe) }
	}
}

pub fn commands_owned() bool { return owned_command_depth > 0 }
pub fn command_interrupted() bool {
	return unsafe { C.__atomic_load_n(&owned_command_signal, C.__ATOMIC_RELAXED) } != 0
}
pub fn command_checkpoint() ! {
	if command_interrupted() { return error_with_code('Host test interrupted', 130) }
}

fn owned_stream(fd i32, text string) ! {
	mut offset := 0
	for offset < text.len {
		count := unsafe { C.write(fd, text.str + offset, uint(text.len - offset)) }
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return error('Cannot write compiler diagnostics') }
		offset += int(count)
	}
}

pub fn owned_inherited_environment(argv []string, env map[string]string, host_arch string, directory string) ! {
	guard := own_commands()
	defer { guard.close() }
	command_checkpoint()!
	result := fixturehost.capture_owned_bounded(argv, env, host_arch, directory, -1,
		command_interrupted, false)!
	owned_stream(1, result.stdout)!
	owned_stream(2, result.stderr)!
	if result.status != 0 {
		return fixturehost.CommandError{argv: argv.clone(), status: result.status, inherited: true}
	}
	command_checkpoint()!
}

fn owned_capture(argv []string) !string {
	guard := own_commands()
	defer { guard.close() }
	command_checkpoint()!
	result := fixturehost.capture_owned_bounded(argv, environment(), caller_arch(), '', -1,
		command_interrupted, false)!
	owned_stream(2, result.stderr)!
	hosttest.module_decode_utf8(result.stdout)!
	text := result.stdout.replace('\r\n', '\n').replace('\r', '\n')
	if result.status != 0 { return fixturehost.CommandError{argv: argv.clone(), status: result.status, output: text} }
	command_checkpoint()!
	return text
}
