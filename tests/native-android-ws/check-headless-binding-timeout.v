// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production timeout diagnostic and binding loop with deterministic
// time/control/JNI state. No ART, guest, account data or long-running process.
module main

import os

fn binding_block(source string, name string) !string {
	start := source.index('fn ' + name + '(') or { return error('missing ' + name) }
	end := source[start..].index('\n}') or { return error('unclosed ' + name) }
	return source[start..start + end + 2]
}

fn binding_format_abis(compiler string, work string) ! {
	generated := os.exec([compiler, '-w', '-n', '-gc', 'none', '-enable-globals', '-o', work + '/probe.c', work + '/main.v'])
	assert generated.exit_code == 0, generated.output
	code := os.read_file(work + '/probe.c')!
	lines := code.split_into_lines().filter(it.contains('ANDROID-SERVICE-BINDING-WAIT') && it.contains('snprintf('))
	assert lines.len == 1, 'missing generated diagnostic call'
	call := lines[0].replace('main__ws_millis()', '((i64)123)')
		.replace('ws_millis()', '((i64)123)')
	// int64_t is long on AArch64 Linux, long long on macOS. Check the actual
	// generated call under both typedefs so a native macOS pass cannot hide the
	// target mismatch. Standard intmax_t casts must preserve every 64-bit value.
	cc := os.find_abs_path_of_executable('cc')!
	for i, spelling in ['long', 'long long'] {
		path := work + '/format-' + i.str() + '.c'
		os.write_file(path, '#include <stdio.h>\n#include <stdint.h>\n#include <stdbool.h>\ntypedef ${spelling} i64;\ntypedef unsigned ${spelling} u64;\ntypedef int32_t i32;\nvoid check(char *buffer, i64 started_ms, u64 pumps, i32 active, bool record, i32 reason, i32 control) {\n${call}\n}\n')!
		checked := os.exec([cc, '-std=gnu11', '-fsyntax-only', '-Wformat=2', '-Werror=format', path])
		assert checked.exit_code == 0, '${spelling}: ${checked.output}'
	}
}

fn main() {
	assert os.args.len in [1, 2], 'usage: check-headless-binding-timeout [REPO]'
	repo := if os.args.len == 2 { os.real_path(os.args[1]) } else { os.getwd() }
	source := os.read_file(repo + '/build-support/android/nativews/headless.v')!
	diagnostic := binding_block(source, 'ws_service_binding_timeout')!
		.replace('C.getenv(', 'probe_getenv(').replace('C.write(', 'probe_write(')
	run := binding_block(source, 'ws_service_run')!
		.replace('C.puts(', 'probe_puts(').replace('C.printf(', 'probe_printf(')
		.replace('C.fflush(', 'probe_fflush(')
	work := os.join_path(os.temp_dir(), 'vinix-binding-timeout-' + os.getpid().str())
	assert !os.exists(work)
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/main.v', binding_probe + diagnostic + '\n' + run + binding_cases)!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	built := os.exec([compiler, '-w', '-n', '-gc', 'none', '-enable-globals', '-cc', 'cc', '-cflags', '-Wformat=2 -Werror=format', '-o', work + '/probe', work + '/main.v'])
	if built.exit_code != 0 { panic(built.output) }
	result := os.exec([work + '/probe'])
	if result.exit_code != 0 { panic(result.output) }
	assert result.output.trim_space() == 'HEADLESS-BINDING-TIMEOUT-PASS cases=20'
	binding_format_abis(compiler, work)!
	println(result.output.trim_space() + ' format-abis=2')
}

const binding_probe = '
module main
#include <stdio.h>
#include <stdint.h>
#include <alloca.h>
type C.intmax_t = i64
type C.uintmax_t = u64
fn C.alloca(usize) voidptr
fn C.snprintf(&char, usize, &char, ...) i32
type WsBoolField = fn (voidptr, voidptr, voidptr) u8
type WsApplicationClear = fn (voidptr)
struct Probe {
mut:
 env &char = unsafe { nil }
 now i64
 tick i64
 ticks []i64
 controls []i32
 polls []i32
 control_index int
 pumps int
 bind_after int = 100
 active u8 = 1
 field_calls int
 read_calls int
 clears int
 frame_depth int
 exception bool
 field_throws bool
 read_throws bool
 missing_field bool
 output string
 writes int
 failed int
 ready int
}
__global p = Probe{}
fn probe_getenv(name &char) &char {
 assert unsafe { cstring_to_vstring(name) } == "VINIX_ANDROID_TRACE_SERVICE_BINDING"
 return p.env
}
fn probe_write(fd i32, buffer voidptr, count usize) isize {
 assert fd == 2 && count > 0 && count < 256
 text := unsafe { cstring_to_vstring(&char(buffer)) }
 assert text.len == int(count) && text.ends_with("\n")
 p.output += text
 p.writes++
 return isize(count)
}
fn ws_millis() i64 { return p.now }
fn pending(e voidptr) bool { assert e == voidptr(1); return p.exception }
fn field(e voidptr, class &char, name &char, descriptor &char) voidptr {
 assert !pending(e) && p.frame_depth == 0
 assert unsafe { cstring_to_vstring(class) } == "android/atl/VinixServiceBinding"
 assert unsafe { cstring_to_vstring(name) } == "active"
 assert unsafe { cstring_to_vstring(descriptor) } == "Z"
 p.field_calls++
 if p.field_throws { p.exception = true }
 return if p.missing_field { unsafe { nil } } else { voidptr(3) }
}
fn probe_active(e voidptr, object voidptr, member voidptr) u8 {
 assert !pending(e) && object == voidptr(2) && member == voidptr(3)
 p.read_calls++
 if p.read_throws { p.exception = true }
 return p.active
}
fn probe_clear(e voidptr) { assert pending(e); p.exception = false; p.clears++ }
fn slot(e voidptr, index i32) voidptr {
 assert e == voidptr(1)
 return if index == 96 { voidptr(probe_active) } else { assert index == 17; voidptr(probe_clear) }
}
fn ws_service_control(fd i32, timeout i32) i32 {
 assert fd == 7 && timeout in [0, 16] && p.control_index < p.controls.len
 p.polls << timeout
 result := p.controls[p.control_index]
 p.control_index++
 return result
}
fn push_frame(e voidptr) { assert !pending(e) && p.frame_depth == 0; p.frame_depth++ }
fn pop_frame(e voidptr) { assert !pending(e) && p.frame_depth == 1; p.frame_depth-- }
fn ws_service_pump(e voidptr) bool {
 assert !pending(e)
 p.now += if p.pumps < p.ticks.len { p.ticks[p.pumps] } else { p.tick }
 p.pumps++
 return true
}
fn ws_failure(e voidptr, message &char) bool { assert !pending(e); return false }
// The terminal observer has its own executable ordering/quietness check.
fn ws_service_terminal_fail(phase i32, reason i32) i32 { return 1 }
fn ws_service_failure(e voidptr, stage &char, phase i32, reason i32) bool { return ws_failure(e, stage) }
fn get_object(e voidptr, object voidptr, class &char, name &char, descriptor &char) voidptr {
 assert !pending(e) && p.frame_depth == 1
 return if p.pumps >= p.bind_after { voidptr(4) } else { unsafe { nil } }
}
fn ws_account_service_pump(e voidptr, binder voidptr) bool { return true }
fn ws_service_ui_pump(e voidptr) bool { return true }
fn probe_puts(message &char) i32 {
 assert unsafe { cstring_to_vstring(message) } == "ANDROID-SERVICE-FAIL service binding incomplete"
 p.failed++
 return 1
}
fn probe_printf(format &char, package_name &char, service &char) i32 { p.ready++; return 1 }
fn probe_fflush(stream voidptr) i32 { return 0 }
fn run_case(setup Probe) {
 p = setup
 assert ws_service_run(voidptr(1), voidptr(2), 7, c"private-package", c"private-service") == 1
 assert p.frame_depth == 0 && !p.exception && p.ready == 0 && p.failed == 1
 assert p.control_index == p.controls.len
}
fn run_ready_case(setup Probe) {
 p = setup
 assert ws_service_run(voidptr(1), voidptr(2), 7, c"private-package", c"private-service") == 0
 assert p.frame_depth == 0 && !p.exception && p.ready == 1 && p.failed == 0
 assert p.control_index == p.controls.len && p.writes == 0
}
fn trace(record bool, reason i32, control i32) {
 ws_service_binding_timeout(voidptr(1), voidptr(2), 10, 7, record, reason, control)
}
'

const binding_cases = '
fn main() {
 // The startup budget is inclusive, and expiry skips the blocking poll.
 run_case(Probe{env:c"1",now:100,tick:45000,controls:[i32(1),1]})
 assert p.output == "ANDROID-SERVICE-BINDING-WAIT elapsed_ms=45000 pumps=1 active=1 record=0 reason=1 control=1\n"
 assert p.polls == [i32(0),0] && p.pumps == 1 && p.writes == 1
 run_case(Probe{env:c"1",now:100,tick:44999,controls:[i32(1),1,1,1,1]})
 assert p.output == "ANDROID-SERVICE-BINDING-WAIT elapsed_ms=89998 pumps=2 active=1 record=0 reason=1 control=1\n"
 assert p.polls == [i32(0),0,16,0,0] && p.pumps == 2
 // Missing binding is observed after an unpreemptible callback returns.
 run_case(Probe{env:c"1",tick:45001,controls:[i32(1),1]})
 assert p.output.contains("elapsed_ms=45001 pumps=1") && p.polls == [i32(0),0]
 // Pumping earlier work never resets the finite startup deadline.
 run_case(Probe{env:c"1",tick:15000,controls:[i32(1),1,1,1,1,1,1,1]})
 assert p.output.contains("elapsed_ms=45000 pumps=3")
 assert p.polls == [i32(0),0,16,0,0,16,0,0]
 // A 12-second unrelated callback may precede the queued service callback.
 run_ready_case(Probe{env:c"1",ticks:[i64(12011),0],bind_after:2,controls:[i32(1),1,1,1,1,1,0]})
 assert p.pumps == 2 && p.now == 12011
 // Preserve acceptance of a valid Binder produced by a slow callback.
 run_ready_case(Probe{env:c"1",tick:45001,bind_after:1,controls:[i32(1),1,1,0]})
 assert p.pumps == 1 && p.now == 45001
 for state in [i32(0), -1] {
  p = Probe{env:c"1",tick:12011,bind_after:2,controls:[i32(1),state]}
  assert ws_service_run(voidptr(1),voidptr(2),7,c"private-package",c"private-service") == 1
  assert p.pumps == 1 && p.control_index == 2 && p.ready == 0 && p.failed == 0
  assert p.frame_depth == 0 && !p.exception && p.writes == 0
 }
 for state in [i32(0), -1] {
  run_case(Probe{env:c"1",tick:12011,controls:[i32(1),1,state]})
  assert p.output == "ANDROID-SERVICE-BINDING-WAIT elapsed_ms=12011 pumps=1 active=1 record=0 reason=2 control=" + state.str() + "\n"
  assert p.polls == [i32(0),0,16]
 }
 // Opt-in is exact and disabled diagnostics perform no Java field lookup.
 for env in [unsafe { &char(nil) }, c"", c"0", c"1extra"] {
  run_case(Probe{env:env,tick:45000,controls:[i32(1),1]})
  assert p.field_calls == 0 && p.read_calls == 0 && p.writes == 0 && p.output == ""
 }
 p = Probe{env:c"1",now:123,active:0}
 trace(true,2,0)
 assert p.output == "ANDROID-SERVICE-BINDING-WAIT elapsed_ms=113 pumps=7 active=0 record=1 reason=2 control=0\n"
 assert p.field_calls == 1 && p.read_calls == 1 && p.clears == 0
 p = Probe{env:c"1",now:123,exception:true}
 trace(false,1,1)
 assert p.output.contains("active=-1") && p.exception && p.field_calls == 0 && p.clears == 0
 p = Probe{env:c"1",field_throws:true}
 trace(false,1,1)
 assert p.output.contains("active=-1") && !p.exception && p.read_calls == 0 && p.clears == 1
 p = Probe{env:c"1",read_throws:true}
 trace(false,1,1)
 assert p.output.contains("active=-1") && !p.exception && p.read_calls == 1 && p.clears == 1
 p = Probe{env:c"1",missing_field:true}
 trace(false,1,1)
 assert p.output.contains("active=-1") && !p.exception && p.read_calls == 0 && p.clears == 0
 // Maximum integer widths still fit one bounded record; no input strings appear.
 p = Probe{env:c"1",now:9223372036854775807}
 ws_service_binding_timeout(voidptr(1), unsafe { nil }, 0, u64(18446744073709551615), false, 1, -1)
 assert p.output == "ANDROID-SERVICE-BINDING-WAIT elapsed_ms=9223372036854775807 pumps=18446744073709551615 active=-1 record=0 reason=1 control=-1\n"
 assert p.writes == 1 && p.field_calls == 0
 println("HEADLESS-BINDING-TIMEOUT-PASS cases=20")
}
'
