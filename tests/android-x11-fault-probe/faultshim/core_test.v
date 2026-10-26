// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module faultshim

fn C.pipe(&i32) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32

__global (
	test_action C.sigaction
	test_result i32
	test_calls int
	test_one_calls int
	test_info_calls int
)

fn backend(_number i32, input voidptr, output voidptr) i32 {
	unsafe {
		test_calls++
		if test_result != 0 { return test_result }
		if output != nil { C.memcpy(output, &test_action, sizeof(C.sigaction)) }
		if input != nil { C.memcpy(&test_action, input, sizeof(C.sigaction)) }
		return 0
	}
}

fn one(_number i32) { unsafe { test_one_calls++ } }
fn three(_number i32, _info voidptr, _context voidptr) { unsafe { test_info_calls++ } }

fn reset() {
	unsafe {
		xfp_native_action = backend
		xfp_active = [65]usize{}
		xfp_next_record = 0
		test_calls = 0
		test_result = 0
		test_one_calls = 0
		test_info_calls = 0
		test_action = C.sigaction{}
	}
}

fn test_query_replace_restore_and_failure() {
	reset()
	unsafe {
		mut requested := C.sigaction{sa_handler: one, sa_flags: C.SA_RESTART}
		assert interposed(11, &requested, nil) == 0
		assert usize(test_action.sa_sigaction) == usize(caught)
		mut queried := C.sigaction{}
		assert interposed(11, nil, &queried) == 0
		assert usize(queried.sa_handler) == usize(one)
		assert queried.sa_flags == requested.sa_flags
		mut replacement := C.sigaction{sa_sigaction: three, sa_flags: C.SA_SIGINFO}
		mut old := C.sigaction{}
		assert interposed(11, &replacement, &old) == 0
		assert usize(old.sa_handler) == usize(one)
		test_result = -1
		assert interposed(11, &requested, nil) == -1
		test_result = 0
		assert interposed(11, nil, &queried) == 0
		assert usize(queried.sa_sigaction) == usize(three)
		assert interposed(11, &old, nil) == 0
		assert interposed(11, nil, &queried) == 0
		assert usize(queried.sa_handler) == usize(one)
		// Default and ignore dispositions must never be wrapped.
		mut ignored := C.sigaction{sa_handler: Handler(voidptr(1))}
		assert interposed(11, &ignored, nil) == 0
		assert usize(test_action.sa_handler) == 1
		mut defaulted := C.sigaction{}
		assert interposed(11, &defaulted, nil) == 0
		assert usize(test_action.sa_handler) == 0
		assert xfp_active[11] == 0
	}
}

fn capture(callback fn ()) string {
	mut pipes := [2]i32{}
	assert C.pipe(&pipes[0]) == 0
	saved := C.dup(2)
	assert saved >= 0
	assert C.dup2(pipes[1], 2) == 2
	callback()
	assert C.dup2(saved, 2) == 2
	C.close(saved); C.close(pipes[1])
	mut bytes := [4096]u8{}
	n := C.read(pipes[0], &bytes[0], sizeof(bytes))
	C.close(pipes[0])
	assert n > 0
	return bytes[..int(n)].bytestr()
}

fn sample() {
	unsafe {
		mut info := [16]u64{}
		mut context := [64]u64{}
		info[0] = 11; info[1] = 2; info[2] = 0x8
		context[54] = 0xfeed0000; context[55] = 0x123456780000; context[56] = 0x60000000
		for i in 0 .. 31 { context[23 + i] = 0x1000 + u64(i) }
		report(&info[0], &context[0])
	}
}

fn test_aarch64_signal_context_report() {
	text := capture(sample)
	assert text.contains('signal=0x000000000000000b code=0x0000000000000002 address=0x0000000000000008')
	assert text.contains('pc=0x0000123456780000 sp=0x00000000feed0000 pstate=0x0000000060000000')
	assert text.contains('x00=0x0000000000001000')
	assert text.contains('x30=0x000000000000101e')
	assert text.count(' x') == 31
	assert text.ends_with('\n')
}

fn chained() {
	reset()
	unsafe {
		mut requested := C.sigaction{sa_handler: one}
		assert interposed(11, &requested, nil) == 0
		test_action.sa_sigaction(11, nil, nil)
		assert test_one_calls == 1
		requested = C.sigaction{sa_sigaction: three, sa_flags: C.SA_SIGINFO | C.SA_RESETHAND}
		assert interposed(11, &requested, nil) == 0
		test_action.sa_sigaction(11, nil, nil)
		assert test_info_calls == 1
		assert xfp_active[11] == 0
	}
}

fn test_one_and_three_argument_handler_chaining() {
	assert capture(chained).count('X11-FAULT\n') == 2
}

fn test_unwatched_and_record_exhaustion_pass_through() {
	reset()
	unsafe {
		mut requested := C.sigaction{sa_handler: one}
		assert interposed(10, &requested, nil) == 0
		assert usize(test_action.sa_handler) == usize(one)
		xfp_next_record = xfp_records.len
		assert interposed(11, &requested, nil) == 0
		assert usize(test_action.sa_handler) == usize(one)
		assert xfp_active[11] == 0
	}
}
