// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

#include <signal.h>
#include <sys/wait.h>

fn C.pipe(&i32) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, uint) int
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32

__global test_calls int

fn backend() {
	unsafe {
		assert C.errno == 71
		test_calls++
		C.errno = 72
	}
}

fn reset() { unsafe { ap_reported = 0; ap_active = 0; test_calls = 0 } }

fn capture(callback fn ()) string {
	mut pipes := [2]i32{}
	assert C.pipe(&pipes[0]) == 0
	saved := C.dup(2)
	assert saved >= 0 && C.dup2(pipes[1], 2) == 2
	callback()
	assert C.dup2(saved, 2) == 2
	C.close(saved); C.close(pipes[1])
	mut bytes := [4096]u8{}
	n := C.read(pipes[0], &bytes[0], sizeof(bytes))
	C.close(pipes[0])
	assert n >= 0
	return bytes[..int(n)].bytestr()
}

fn forwarding() {
	reset()
	unsafe {
		for _ in 0 .. 64 {
			C.errno = 71
			forward(1, uint(backend), C.errno)
			assert C.errno == 72
		}
		assert test_calls == 64
	}
}

fn test_single_report_and_one_native_forward_per_call_with_errno() {
	assert capture(forwarding) == 'BROWSER-ABORT caller=1 module-base=0 offset=0 resolved=0 native=1\n'
}

fn broken_stderr() {
	reset()
	unsafe {
		assert C.close(2) == 0
		C.errno = 71
		forward(1, uint(backend), C.errno)
		assert C.errno == 72 && test_calls == 1
	}
}

fn test_failed_diagnostic_write_does_not_change_errno_or_skip_forwarding() {
	assert capture(broken_stderr) == ''
}

fn module_address() {
	reset()
	unsafe {
		C.errno = 71
		forward(uint(backend), uint(backend), C.errno)
		assert C.errno == 72 && test_calls == 1
	}
}

fn test_module_resolution_only_emits_numeric_fields() {
	line := capture(module_address).trim_space()
	fields := line.split(' ')
	assert fields.len == 6 && fields[0] == 'BROWSER-ABORT'
	for index, name in ['caller', 'module-base', 'offset', 'resolved', 'native'] {
		field := fields[index + 1]
		assert field.starts_with(name + '=')
		assert field.all_after('=').len > 0 && field.all_after('=').bytes().all(it >= `0` && it <= `9`)
	}
	assert fields[4] == 'resolved=1' && fields[5] == 'native=1'
}

fn wait_child(pid i32) i32 {
	mut status := i32(0)
	mut reaped := C.waitpid(pid, &status, 0)
	for reaped < 0 && unsafe { C.errno == C.EINTR } { reaped = C.waitpid(pid, &status, 0) }
	assert reaped == pid
	return status
}

fn unresolved_child() {
	reset()
	pid := C.fork()
	assert pid >= 0
	if pid == 0 { forward(1, 0, 71); C._exit(99) }
	assert wait_child(pid) == 127 << 8
}

fn test_unresolved_native_symbol_is_bounded_fatal_without_recursion() {
	assert capture(unresolved_child) == 'BROWSER-ABORT caller=1 module-base=0 offset=0 resolved=0 native=0\n'
}

fn native_child() {
	reset()
	pid := C.fork()
	assert pid >= 0
	if pid == 0 { interposed(1); C._exit(99) }
	// Only the child calls native abort. No signal disposition is replaced.
	assert wait_child(pid) & 127 == C.SIGABRT
}

fn test_native_symbol_resolution_reaches_libc_sigabrt_in_child_only() {
	assert capture(native_child) == 'BROWSER-ABORT caller=1 module-base=0 offset=0 resolved=0 native=1\n'
}

fn reentered_child() {
	reset()
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		unsafe { ap_active = 1 }
		interposed(1)
		C._exit(99)
	}
	assert wait_child(pid) == 127 << 8
}

fn test_reentry_is_fatal_without_repeating_loader_calls_or_reporting() {
	assert capture(reentered_child) == ''
}

fn returned_backend_child() {
	reset()
	pid := C.fork()
	assert pid >= 0
	if pid == 0 { dispatch(1, uint(backend), 71) }
	assert wait_child(pid) == 127 << 8
}

fn test_unexpected_backend_return_stays_fatal() {
	assert capture(returned_backend_child) == 'BROWSER-ABORT caller=1 module-base=0 offset=0 resolved=0 native=1\n'
}
