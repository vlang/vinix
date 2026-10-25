// SPDX-License-Identifier: GPL-2.0-or-later
// Compile the actual native queue with a controlled clock and real host pipes.
module main

import crypto.sha256
import json2
import os

const harness = r'
module main

#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <stdlib.h>

fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.poll(voidptr, usize, i32) i32
fn C.calloc(usize, usize) voidptr
fn C.free(voidptr)
fn C.pthread_create(voidptr, voidptr, fn (voidptr) voidptr, voidptr) i32
$if macos {
	fn C.pthread_join(voidptr, voidptr) i32
} $else {
	fn C.pthread_join(usize, voidptr) i32
}

struct WsState {
mut:
	main_thread usize
	queue_pump_active bool
	queue_pump_polls i32
	queue_pump_deadline i64
}

__global ws &WsState
__global fake_millis i64
__global clock_reads i32

fn ws_millis() i64 {
	clock_reads++
	return fake_millis
}

fn host_queue() i64 {
	pointer := ws_queue_new()
	assert pointer != 0, "queue allocation"
	unsafe {
		q := &WsQueue(pointer)
		assert q.read_fd >= 0 && q.write_fd >= 0
		// The production runtime targets Linux. Its numeric O_NONBLOCK is
		// different on Darwin; preserve the exact queue source and normalize
		// both real descriptors before exercising wake or drain on the host.
		for fd in [q.read_fd, q.write_fd] {
			flags := C.fcntl(fd, C.F_GETFL)
			assert flags >= 0
			assert C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) == 0
			assert C.fcntl(fd, C.F_GETFL) & C.O_NONBLOCK != 0
			assert C.fcntl(fd, C.F_GETFD) & C.FD_CLOEXEC != 0
		}
	}
	return pointer
}

fn readable(pointer i64) bool {
	unsafe {
		mut descriptor := WsPoll{fd: (&WsQueue(pointer)).read_fd, events: 1}
		result := C.poll(voidptr(&descriptor), 1, 0)
		assert result >= 0
		return result == 1 && descriptor.returned & 1 != 0
	}
}

fn destroyed(pointer i64) {
	unsafe {
		read_fd := (&WsQueue(pointer)).read_fd
		write_fd := (&WsQueue(pointer)).write_fd
		ws_queue_destroy(pointer)
		assert C.fcntl(read_fd, C.F_GETFD) == -1, "read descriptor closed"
		assert C.fcntl(write_fd, C.F_GETFD) == -1, "write descriptor closed"
	}
}

fn limits(pointer i64) {
	fake_millis = 100
	ws_queue_begin_pump()
	assert ws.queue_pump_active && ws.queue_pump_polls == 0
	assert ws.queue_pump_deadline == 116
	for count in 0 .. 64 {
		assert ws_queue_poll(pointer, 0) == 0, "poll within count limit"
		assert ws.queue_pump_polls == count + 1
	}
	for _ in 0 .. 3 {
		assert ws_queue_poll(pointer, 0) == 1, "poll count budget exhausted"
		assert ws.queue_pump_polls == 64, "denied poll preserves count"
	}
	// Every native pass gets its own allowance and deadline.
	fake_millis = 500
	ws_queue_begin_pump()
	assert ws.queue_pump_polls == 0 && ws.queue_pump_deadline == 516
	assert ws_queue_poll(pointer, 0) == 0 && ws.queue_pump_polls == 1
	ws_queue_end_pump()
	assert !ws.queue_pump_active
	fake_millis = 10000
	for _ in 0 .. 100 {
		assert ws_queue_poll(pointer, 0) == 0, "no budget outside native pump"
	}
	assert ws.queue_pump_polls == 1
	println("QUEUE-PUMP-COUNT-RESET-PASS")
}

fn deadlines(pointer i64) {
	fake_millis = 1000
	ws_queue_begin_pump()
	assert ws_queue_poll(pointer, 0) == 0
	fake_millis = 1015
	assert ws_queue_poll(pointer, 0) == 0, "before deadline"
	fake_millis = 1016
	assert ws_queue_poll(pointer, 0) == 1, "deadline is inclusive"
	assert ws.queue_pump_polls == 2
	// A slow transition into Java must still let its first queued task run.
	fake_millis = 2000
	ws_queue_begin_pump()
	fake_millis = 2100
	assert ws_queue_poll(pointer, 0) == 0, "first poll guarantees progress"
	assert ws.queue_pump_polls == 1
	assert ws_queue_poll(pointer, 0) == 1, "second expired poll yields"
	assert ws.queue_pump_polls == 1
	ws_queue_end_pump()
	println("QUEUE-PUMP-DEADLINE-PROGRESS-PASS")
}

fn timeouts(pointer i64) {
	fake_millis = 3000
	ws_queue_begin_pump()
	reads := clock_reads
	for timeout in [i32(-1), 1, 1000] {
		assert ws_queue_poll(pointer, timeout) == 1, "main never blocks"
	}
	assert clock_reads == reads && ws.queue_pump_polls == 0
	assert ws_queue_poll(0, 0) == 1
	assert ws_queue_poll(0, -1) == 1
	assert ws.queue_pump_polls == 0
	assert ws_queue_poll(pointer, 0) == 0
	ws_queue_end_pump()
	assert ws_queue_poll(pointer, -1) == 1
	assert ws_queue_poll(pointer, 10) == 1
	assert ws_queue_poll(pointer, 0) == 0
	println("QUEUE-PUMP-TIMEOUT-NULL-PASS")
}

struct HostWorker {
	queue i64
	done_fd i32
mut:
	result u8
}

fn blocking_worker(argument voidptr) voidptr {
	unsafe {
		mut worker := &HostWorker(argument)
		(&WsQueue(worker.queue)).thread = usize(C.pthread_self())
		worker.result = ws_queue_poll(worker.queue, -1)
		byte := u8(1)
		assert C.write(worker.done_fd, &byte, 1) == 1
		return nil
	}
}

fn workers() {
	// Exhaust the main allowance. Worker polling must still use its pipe.
	fake_millis = 4000
	ws_queue_begin_pump()
	ws.queue_pump_polls = 64
	fake_millis = 5000
	reads := clock_reads
	pointer := host_queue()
	unsafe { (&WsQueue(pointer)).thread = ws.main_thread + 1 }
	assert !readable(pointer)
	assert ws_queue_poll(pointer, 0) == 0
	assert ws_queue_poll(pointer, 1) == 0, "worker finite timeout does not yield"
	for _ in 0 .. 300 { ws_queue_wake(pointer) }
	assert readable(pointer), "wake writes to pipe"
	assert ws_queue_poll(pointer, 0) == 0
	assert !readable(pointer), "drains multiple 128-byte reads"
	assert ws_queue_poll(pointer, 0) == 0
	unsafe { assert !(&WsQueue(pointer)).idling }
	assert clock_reads == reads && ws.queue_pump_polls == 64
	destroyed(pointer)
	// Also exercise an actual worker thread with an indefinite pipe poll.
	worker := host_queue()
	mut completion := [2]i32{}
	unsafe {
		assert C.pipe(&completion[0]) == 0
		mut context := HostWorker{queue: worker, done_fd: completion[1]}
		mut worker_thread := usize(0)
		assert C.pthread_create(voidptr(&worker_thread), nil, blocking_worker, voidptr(&context)) == 0
		ws_queue_wake(worker)
		mut descriptor := WsPoll{fd: completion[0], events: 1}
		assert C.poll(voidptr(&descriptor), 1, 2000) == 1, "worker wake timed out"
		$if macos {
			assert C.pthread_join(voidptr(worker_thread), nil) == 0
		} $else {
			assert C.pthread_join(worker_thread, nil) == 0
		}
		assert context.result == 0, "worker wakes without main yield"
		assert (&WsQueue(worker)).thread != ws.main_thread
		assert C.close(completion[0]) == 0
		assert C.close(completion[1]) == 0
	}
	unsafe { assert !(&WsQueue(worker)).idling }
	assert !readable(worker)
	assert clock_reads == reads && ws.queue_pump_polls == 64
	destroyed(worker)
	ws_queue_end_pump()
	ws_queue_wake(0)
	ws_queue_destroy(0)
	println("QUEUE-PUMP-WORKER-PIPES-DESTROY-PASS")
}

fn main() {
	ws = &WsState{main_thread: usize(C.pthread_self())}
	pointer := host_queue()
	limits(pointer)
	deadlines(pointer)
	timeouts(pointer)
	destroyed(pointer)
	workers()
	println("QUEUE-PUMP-HOST-PASS")
}
'

fn source_struct(body string, name string) string {
	marker := 'struct ' + name + ' {'
	assert body.count(marker) == 1, name
	return marker + body.all_after(marker).all_before('\n}') + '\n}\n'
}

struct Receipt {
	queue_sha256   string
	runtime_sha256 string
	runner_sha256  string
	build_argv     []string
	build_exit     int
	run_exit       int
}

fn main() {
	repo := os.real_path(os.dir(@FILE) + '/../..')
	mut source := repo + '/build-support/android/nativews/queue.v'
	mut runtime_path := repo + '/build-support/android/nativews/runtime.v'
	mut out := repo + '/tests/native-android-ws/results/queue-pump-check'
	for arg in os.args[1..] {
		if arg.starts_with('source=') {
			source = os.abs_path(arg.all_after('source='))
		} else if arg.starts_with('runtime=') {
			runtime_path = os.abs_path(arg.all_after('runtime='))
		} else if arg.starts_with('out=') {
			out = os.abs_path(arg.all_after('out='))
		} else {
			panic('usage: queue-pump-check [source=QUEUE_V] [runtime=RUNTIME_V] [out=OUTPUT_DIR]')
		}
	}
	queue := os.read_file(source)!
	runtime := os.read_file(runtime_path)!
	assert queue.count('module atlframework') == 1
	// This is the actual runtime call scope, including the exception path.
	loop := runtime.all_after('for ws.running {')
	begin := loop.index('ws_queue_begin_pump()') or { panic('missing pump begin') }
	call := loop.index("static_void(e, c'android/os/Looper', c'loop', c'()V', nil)") or {
		panic('missing main Looper call')
	}
	end := loop.index('ws_queue_end_pump()') or { panic('missing pump end') }
	failure := loop.index("if ws_failure(e, c'ANDROID-WS-FAIL main looper')") or {
		panic('missing exception check')
	}
	assert begin < call && call < end && end < failure, 'pump ends before exception handling'
	os.mkdir_all(out + '/src')!
	os.write_file(out + '/src/actual_queue.v', queue.replace('module atlframework', 'module main'))!
	os.write_file(out + '/src/actual_protocol.v', 'module main\n' + source_struct(runtime, 'WsPoll'))!
	os.write_file(out + '/src/main.v', harness)!
	os.write_file(out + '/queue.v.txt', queue)!
	os.write_file(out + '/runtime.v.txt', runtime)!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { @VEXE }
	argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-enable-globals', '-gc', 'none',
		'-o', out + '/host', out + '/src']
	build := os.exec(argv)
	os.write_file(out + '/build.log', build.output)!
	print(build.output)
	mut run_exit := -1
	if build.exit_code == 0 {
		result := os.exec([out + '/host'])
		os.write_file(out + '/run.log', result.output)!
		print(result.output)
		run_exit = result.exit_code
	}
	receipt := Receipt{
		queue_sha256:   sha256.sum(queue.bytes()).hex()
		runtime_sha256: sha256.sum(runtime.bytes()).hex()
		runner_sha256:  sha256.sum(os.read_bytes(@FILE)!).hex()
		build_argv:     argv
		build_exit:     build.exit_code
		run_exit:       run_exit
	}
	os.write_file(out + '/receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	if build.exit_code != 0 { exit(build.exit_code) }
	exit(run_exit)
}
