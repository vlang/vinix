// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module waitshim

fn C.pipe(&i32) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, uint) int
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32

__global (
	test_calls int
	test_errno i32
	test_result i32
	test_pid i32
	test_kind i32
	test_id u32
	test_options i32
	test_pointer uint
	test_set_errno bool
)

fn backend(kind C.vinix_wait_idtype, id u32, info &C.siginfo_t, options i32) i32 {
	unsafe {
		test_calls++
		C.memcpy(&test_kind, &kind, sizeof(i32))
		test_id = id; test_options = options; test_pointer = uint(info)
		assert C.errno == 71
		if test_result == 0 && info != nil {
			mut out := info
			out.si_pid = test_pid; out.si_code = 3; out.si_status = 11
		}
		if test_set_errno { C.errno = test_errno }
		return test_result
	}
}

fn reset() {
	unsafe {
		wp_native_wait = uint(backend); wp_reports = 0; wp_resolve_lock = 0
		test_calls = 0; test_result = 0; test_errno = 72; test_pid = 456; test_set_errno = true
	}
}

fn capture(callback fn ()) string {
	mut pipes := [2]i32{}
	assert C.pipe(&pipes[0]) == 0
	saved := C.dup(2)
	assert saved >= 0 && C.dup2(pipes[1], 2) == 2
	callback()
	assert C.dup2(saved, 2) == 2
	C.close(saved); C.close(pipes[1])
	mut bytes := [16384]u8{}
	n := C.read(pipes[0], &bytes[0], sizeof(bytes))
	C.close(pipes[0])
	assert n >= 0
	return bytes[..int(n)].bytestr()
}

fn forwarding() {
	reset()
	unsafe {
		mut info := C.siginfo_t{}
		C.errno = 71
		assert interposed(3, 4294967295, &info, 16777221) == 0
		assert C.errno == 72 && test_calls == 1
		assert test_kind == 3 && test_id == 4294967295 && test_options == 16777221
		assert test_pointer == uint(&info)
		assert info.si_pid == 456 && info.si_code == 3 && info.si_status == 11
		test_result = -1; test_errno = C.ECHILD
		C.errno = 71
		assert interposed(3, 9, &info, 5) == -1
		assert C.errno == C.ECHILD && test_calls == 2 && wp_reports == 1
		// An error need not leave any readable siginfo at all.
		test_errno = C.EFAULT; C.errno = 71
		assert interposed(3, 9, &C.siginfo_t(voidptr(1)), 5) == -1
		assert C.errno == C.EFAULT && test_calls == 3 && wp_reports == 1
		test_result = 0; test_set_errno = false; test_pid = 0; C.errno = 71
		assert interposed(3, 9, &info, 5) == 0
		assert C.errno == 71 && test_calls == 4 && wp_reports == 1
	}
}

fn test_one_native_wait_and_result_errno_argument_forwarding() {
	assert capture(forwarding) == 'BROWSER-WAITID idtype=3 id=4294967295 options=16777221 pid=456 code=3 status=11\n'
}

fn empty_status() {
	reset()
	unsafe {
		mut info := C.siginfo_t{}
		test_pid = 0
		C.errno = 71
		assert interposed(3, 9, &info, 5) == 0
		assert C.errno == 72 && test_calls == 1 && wp_reports == 0
		C.errno = 71
		assert interposed(0, 0, nil, 5) == 0
		assert C.errno == 72 && test_calls == 2 && test_pointer == 0
	}
}

fn test_empty_poll_and_null_pointer_do_not_report() { assert capture(empty_status) == '' }

fn bounded() {
	reset()
	unsafe {
		mut info := C.siginfo_t{}
		for _ in 0 .. 64 {
			C.errno = 71
			assert interposed(3, 9, &info, 5) == 0
			assert C.errno == 72
		}
		assert test_calls == 64 && wp_reports == 32
	}
}

fn test_at_most_32_reports_without_skipping_native_waits() {
	text := capture(bounded)
	assert text.count('BROWSER-WAITID ') == 32
	assert text.count('\n') == 32
}

fn broken_stderr() {
	reset()
	unsafe {
		mut info := C.siginfo_t{}
		assert C.close(2) == 0
		C.errno = 71
		assert interposed(3, 9, &info, 5) == 0
		assert C.errno == 72 && test_calls == 1
	}
}

fn test_failed_diagnostic_write_preserves_wait_errno() { assert capture(broken_stderr) == '' }

fn test_first_symbol_resolution_preserves_errno_on_real_empty_poll() {
	// A pipe keeps the child alive until after the real libc WNOHANG poll.
	// Only the final waitpid reaps it; the observed poll consumes no status.
	mut pipes := [2]i32{}
	assert C.pipe(&pipes[0]) == 0
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		C.close(pipes[1])
		mut byte := u8(0)
		C.read(pipes[0], &byte, 1)
		C._exit(0)
	}
	C.close(pipes[0])
	unsafe {
		wp_native_wait = 0; wp_reports = 0; wp_resolve_lock = 0
		mut info := C.siginfo_t{}
		C.errno = 71
		result := interposed(C.P_PID, u32(pid), &info, C.WEXITED | C.WNOHANG)
		saved_errno := C.errno
		C.close(pipes[1])
		mut status := i32(0)
		mut reaped := C.waitpid(pid, &status, 0)
		for reaped < 0 && C.errno == C.EINTR { reaped = C.waitpid(pid, &status, 0) }
		assert reaped == pid && status == 0
		assert result == 0 && saved_errno == 71 && info.si_pid == 0 && wp_reports == 0
	}
}
