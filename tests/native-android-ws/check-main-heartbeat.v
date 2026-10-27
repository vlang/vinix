// SPDX-License-Identifier: GPL-2.0-or-later
// Execute production native heartbeat helpers against a real pipe, without ART.
module main

import os

fn position(source string, marker string) int {
	return source.index(marker) or { panic('missing ' + marker) }
}

fn block(source string, marker string) !string {
	assert source.count(marker) == 1, marker
	start := position(source, marker)
	end := position(source[start..], '\n}')
	return source[start..start + end + 2]
}

fn main() {
	assert os.args.len == 2, 'usage: check-main-heartbeat FRESH_OUTPUT_DIR'
	repo := os.real_path(os.dir(@FILE) + '/../..')
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out), 'fresh output required'
	assert !out.starts_with(repo + '/'), 'use an external evidence directory'
	os.mkdir_all(out)!
	diagnostics := os.read_file(repo + '/build-support/android/nativews/diagnostics.v')!
	runtime := os.read_file(repo + '/build-support/android/nativews/runtime.v')!
	views := os.read_file(repo + '/build-support/android/nativews/ws_views.v')!
	for name in ['diagnostics.v', 'runtime.v', 'ws_views.v'] {
		os.cp(repo + '/build-support/android/nativews/' + name, out + '/' + name)!
	}
	os.cp(@FILE, out + '/checker.v')!
	worker := block(diagnostics, 'fn ws_trace_threads(')!
	assert worker.count('for _ in 0 .. 10 {') == 1
	assert worker.count('C.usleep(30000000)') == 1
	assert position(worker, 'ws_trace_main_sample()') < position(worker, 'ws_dump_threads(e)')
	assert worker.contains("if C.getenv(c'VINIX_ANDROID_TRACE_THREADS') != nil {")
	starter := block(diagnostics, 'fn ws_start_diagnostics(')!
	assert starter.contains("C.getenv(c'VINIX_ANDROID_TRACE_THREADS') == nil && C.getenv(c'VINIX_ANDROID_TRACE_TREE') == nil")
	assert starter.contains('if !ws.service {')
	for pair in [
		['ws_trace_main(.looper)', "static_void(e, c'android/os/Looper'"],
		['ws_trace_main(.web)', 'ws_web_pump(e)'],
		['ws_trace_main(.account)', 'ws_account_client_pump(e)'],
		['ws_trace_main(.input_ready)', 'input_dispatched := ws_input_before_render(e)'],
		['ws_trace_main(.frames)', 'ws_frames_dispatch()'],
		['ws_trace_main(.render)', 'ws_render(e)'],
	] {
		assert runtime.count(pair[0]) == 1 && position(runtime, pair[0]) < position(runtime, pair[1]), pair[0]
	}
	assert runtime.count('ws_trace_main(.input_before)\n\t\t\t\tws_input(e)') == 1
	assert runtime.count('ws_trace_main(.input_after)\n\t\t\t\tws_input(e)') == 1
	for pair in [
		['ws_trace_main(.input_poll)', 'if C.poll(voidptr(&descriptor), 1, 0) <= 0'],
		['ws_trace_main(.input_header)', 'count := C.read(ws.input, &event, sizeof(WsEvent))'],
		['ws_trace_main(.input_text)', 'n := C.read(ws.input, &bytes[read], usize(event.length) - read)'],
	] {
		assert views.count(pair[0]) == 1 && position(views, pair[0]) < position(views, pair[1]), pair[0]
	}
	start := position(diagnostics, '// Only the native main thread writes these fields.')
	helpers := diagnostics[start..].replace('C.write(', 'probe_write(').replace('C.poll(', 'probe_poll(')
	probe := model + '\n' + block(runtime, 'struct WsPoll {')! + '\n' + helpers + cases
	os.write_file(out + '/main.v', probe)!
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { @VEXE })
	argv := [compiler, '-nocache', '-w', '-gc', 'none', '-enable-globals', '-cc', 'cc',
		'-cflags', '-Wformat=2 -Werror=format -Werror=pointer-sign', '-o', out + '/probe', out + '/main.v']
	built := os.exec(argv)
	os.write_file(out + '/build.log', built.output)!
	assert built.exit_code == 0, built.output
	ran := os.exec([out + '/probe'])
	os.write_file(out + '/run.log', ran.output)!
	assert ran.exit_code == 0, ran.output
	assert ran.output.trim_space() == 'MAIN-HEARTBEAT-PASS opt-in atomic-progress age-wrap bounded-snapshot poll-readable poll-hup poll-invalid bytes-preserved snapshot-before-poll'
	for name, source in {'diagnostics.v': diagnostics, 'runtime.v': runtime, 'ws_views.v': views} {
		assert os.read_file(repo + '/build-support/android/nativews/' + name)! == source, 'source changed: ' + name
	}
	println(ran.output.trim_space() + ' finite-sampler stage-checkpoints')
}

const model = '
module main
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <poll.h>
#include <alloca.h>
type C.intmax_t = i64
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)
fn C.alloca(usize) voidptr
fn C.snprintf(&char, usize, &char, ...) i32
fn C.poll(voidptr, usize, i32) i32
fn C.pipe(&i32) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
__global now_ms i64
__global output []string
__global last_revents i32
fn ws_millis() i64 { return now_ms }
fn probe_write(fd i32, buffer voidptr, count usize) isize {
 assert fd == 2 && count > 0 && count < 256
 text := unsafe { cstring_to_vstring(&char(buffer)) }
 assert text.len == int(count) && text.ends_with("\n")
 output << text.clone()
 return isize(count)
}
fn probe_poll(fds voidptr, count usize, timeout i32) i32 {
 assert count == 1 && timeout == 0
 assert output.len % 2 == 1 && output.last().starts_with("ANDROID-WS-MAIN "), "snapshot must precede poll"
 status := C.poll(fds, count, timeout)
 last_revents = unsafe { i32((&WsPoll(fds)).returned) }
 return status
}
'

const cases = '
fn main() {
 now_ms = 1000
 ws_trace_main(.render)
 ws_trace_main_sample()
 assert output.len == 0 && ws_main_trace_sequence == 0
 mut fds := [2]i32{}
 assert C.pipe(&fds[0]) == 0
 C.__atomic_store_n(&ws_main_trace_input, u32(fds[0] + 1), 5)
 C.__atomic_store_n(&ws_main_trace_enabled, 1, 5)
 ws_trace_main(.looper)
 now_ms += 17
 ws_trace_main_sample()
 assert output.len == 2
 assert output[0].contains("stage=looper progress=1 age_ms=17 stable=1")
 assert output.last().contains("poll=0 revents=0")
 byte := u8(42)
 assert C.write(fds[1], &byte, 1) == 1
 ws_trace_main(.input_header)
 now_ms += 30000
 ws_trace_main_sample()
 assert output[2].contains("stage=input-header-read progress=2 age_ms=30000 stable=1")
 assert output.last().contains("poll=1 revents=1")
 mut received := u8(0)
 assert C.read(fds[0], &received, 1) == 1 && received == byte
 assert C.close(fds[1]) == 0
 ws_trace_main_sample()
 assert output.last().contains("poll=1 revents=") && last_revents & C.POLLHUP != 0
 assert C.close(fds[0]) == 0
 ws_trace_main_sample()
 assert output.last().contains("poll=1 revents=") && last_revents & C.POLLNVAL != 0
 C.__atomic_store_n(&ws_main_trace_input, 0, 5)
 now_ms = 4294967290
 ws_trace_main(.render)
 now_ms += 15
 ws_trace_main_sample()
 assert output[8].contains("stage=render progress=3 age_ms=15 stable=1 input_fd=-1")
 assert output.last().contains("poll=0 revents=0")
 // A writer interrupted between publication stores cannot spin the reader.
 C.__atomic_store_n(&ws_main_trace_sequence, 7, 5)
 ws_trace_main_sample()
 assert output[10].contains("stable=0")
 C.__atomic_store_n(&ws_main_trace_sequence, 0xfffffffe, 5)
 ws_trace_main(.sleep)
 ws_trace_main_sample()
 assert output[12].contains("stage=sleep progress=0 age_ms=0 stable=1")
 count := output.len
 C.__atomic_store_n(&ws_main_trace_enabled, 0, 5)
 ws_trace_main(.account)
 ws_trace_main_sample()
 assert output.len == count && ws_main_trace_sequence == 0
 println("MAIN-HEARTBEAT-PASS opt-in atomic-progress age-wrap bounded-snapshot poll-readable poll-hup poll-invalid bytes-preserved snapshot-before-poll")
}
'
