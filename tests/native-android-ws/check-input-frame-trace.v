// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production diagnostic helpers and their input/traversal callers
// with deterministic time, native output and JNI adapters. No ART or guest.
module main

import os

fn trace_block(source string, name string) !string {
	start := source.index(name) or { return error('missing ' + name) }
	end := source[start..].index('\n}') or { return error('unclosed ' + name) }
	return source[start..start + end + 2]
}

// The old compiler emits signedness warnings in its builtin support too. Scope
// the strict warning to the actual production input function, without changing
// any generated declaration, assignment or call in that function.
fn trace_pointer_c(code string, path string) ! {
	mut focused := '#pragma GCC diagnostic ignored "-Wpointer-sign"\n'
	mut inside := false
	mut count := 0
	for line in code.split_into_lines() {
		if line.contains('ws_pointer(') && line.trim_space().ends_with('{') {
			focused += '#pragma GCC diagnostic push\n#pragma GCC diagnostic error "-Wpointer-sign"\n'
			inside = true
			count++
		}
		focused += line + '\n'
		if inside && line == '}' {
			focused += '#pragma GCC diagnostic pop\n'
			inside = false
		}
	}
	assert count == 1 && !inside, 'missing generated production pointer function'
	os.write_file(path, focused)!
}

fn trace_format_abis(compiler string, work string) ! {
	generated := os.exec([compiler, '-w', '-n', '-gc', 'none', '-enable-globals', '-o', work + '/probe.c', work + '/main.v'])
	assert generated.exit_code == 0, generated.output
	code := os.read_file(work + '/probe.c')!
	lines := code.split_into_lines().filter(it.contains('ANDROID-WS-') && it.contains('snprintf('))
	assert lines.len == 3, 'missing production diagnostic calls'
	cc := os.find_abs_path_of_executable('cc')!
	trace_pointer_c(code, work + '/pointer-positive.c')!
	strict := os.exec([cc, '-std=gnu11', '-fsyntax-only', '-Werror=pointer-sign', work + '/pointer-positive.c'])
	assert strict.exit_code == 0, strict.output
	for i, spelling in ['long', 'long long'] {
		mut checks := '#include <stdio.h>\n#include <stdint.h>\n#include <stdbool.h>\ntypedef ${spelling} i64;\ntypedef unsigned ${spelling} u64;\ntypedef uint32_t u32;\ntypedef int32_t i32;\n'
		for j, original in lines {
			// Replace generated identifiers only; argument casts and format strings
			// stay unchanged for both macOS and AArch64 Linux's 64-bit typedefs.
			line := original.replace('main__ws_millis()', '((i64)5000000000LL)')
				.replace('ws_millis()', '((i64)5000000000LL)')
				.replace('main__ws->surface->sequence', 'sequence')
				.replace('ws->surface->sequence', 'sequence')
				.replace('main__ws->pressed', 'pressed')
				.replace('ws->pressed', 'pressed')
				.replace('main__ws_pointer_trace_count', 'input_count')
				.replace('ws_pointer_trace_count', 'input_count')
			checks += 'void check_${j}(char *buffer, char *stage, char *outcome, i64 now, u32 sequence, u32 input_count, u32 id, i32 handled, bool exception, void *pressed, main__WsEvent *event, main__WsFrameTrace *trace) {\n${line}\n}\n'
		}
		checks = checks.replace('void check_0(', 'typedef struct { u32 kind; i32 x; i32 y; } main__WsEvent;\ntypedef struct { u64 events; } main__WsFrameTrace;\nvoid check_0(')
		path := work + '/format-' + i.str() + '.c'
		os.write_file(path, checks)!
		checked := os.exec([cc, '-std=gnu11', '-fsyntax-only', '-Wformat=2', '-Werror=format', '-Werror=pointer-sign', path])
		assert checked.exit_code == 0, '${spelling}: ${checked.output}'
	}
}

fn trace_pointer_sign_refusal(compiler string, work string) ! {
	original := os.read_file(work + '/main.v')!
	needle := "mut outcome := &char(c'ignored-kind')"
	assert original.count(needle) == 1, 'pointer-sign negative mutation must apply once'
	mutation := original.replace(needle, "mut outcome := c'ignored-kind'")
	os.write_file(work + '/main.v', mutation)!
	defer { os.write_file(work + '/main.v', original) or { panic(err) } }
	generated := os.exec([compiler, '-w', '-n', '-gc', 'none', '-enable-globals',
		'-o', work + '/pointer-mutation.c', work + '/main.v'])
	assert generated.exit_code == 0, generated.output
	cc := os.find_abs_path_of_executable('cc')!
	trace_pointer_c(os.read_file(work + '/pointer-mutation.c')!, work + '/pointer-negative.c')!
	refused := os.exec([cc, '-std=gnu11', '-fsyntax-only', '-Werror=pointer-sign', work + '/pointer-negative.c'])
	signedness_error := refused.output.contains('[-Werror,-Wpointer-sign]') ||
		refused.output.contains('[-Werror=pointer-sign]')
	assert refused.exit_code != 0 && signedness_error,
		'unsigned outcome mutation did not fail for pointer signedness: ${refused.output}'
}

fn main() {
	assert os.args.len in [1, 2], 'usage: check-input-frame-trace [REPO]'
	repo := if os.args.len == 2 { os.real_path(os.args[1]) } else { os.getwd() }
	diagnostics := os.read_file(repo + '/build-support/android/nativews/diagnostics.v')!
	views := os.read_file(repo + '/build-support/android/nativews/ws_views.v')!
	runtime := os.read_file(repo + '/build-support/android/nativews/runtime.v')!
	start := diagnostics.index('__global ws_pointer_trace_count ') or { panic('missing trace state') }
	end := diagnostics.index('\nstruct WsPixelTrace {') or { panic('missing trace end') }
	probe := diagnostics[start..end].replace('C.getenv(', 'probe_getenv(').replace('C.write(', 'probe_write(')
	work := os.join_path(os.temp_dir(), 'vinix-input-frame-trace-' + os.getpid().str())
	assert !os.exists(work)
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/main.v', trace_model + '\n' + trace_block(runtime, 'struct WsEvent {')! + '\n' + probe + '\n' +
		trace_block(views, 'fn ws_pointer(')! + '\n' + trace_block(views, 'fn ws_dispatch_traversal(')! + trace_cases)!
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { os.find_abs_path_of_executable('v')! })
	built := os.exec([compiler, '-w', '-n', '-gc', 'none', '-enable-globals', '-cc', 'cc', '-cflags', '-Wformat=2 -Werror=format -Werror=pointer-sign', '-o', work + '/probe', work + '/main.v'])
	assert built.exit_code == 0, built.output
	ran := os.exec([work + '/probe'])
	assert ran.exit_code == 0, ran.output
	assert ran.output.trim_space() == 'INPUT-FRAME-TRACE-PASS opt-in bounds independent-rates input-outcomes traversal-exceptions'
	trace_format_abis(compiler, work)!
	trace_pointer_sign_refusal(compiler, work)!
	println(ran.output.trim_space() + ' format-abis=2 pointer-mutation=rejected')
}

const trace_model = '
module main
#include <stdio.h>
#include <stdint.h>
#include <alloca.h>
type C.intmax_t = i64
type C.uintmax_t = u64
fn C.alloca(usize) voidptr
fn C.snprintf(&char, usize, &char, ...) i32
struct Surface { mut: sequence u32 = 0xffffffff }
struct State {
mut:
 surface &Surface = &Surface{}
 pressed voidptr = unsafe { nil }
 activity voidptr = voidptr(1)
 dialog voidptr = unsafe { nil }
 dialog_x i32 = 10
 dialog_y i32 = 10
 dialog_width i32 = 50
 dialog_height i32 = 50
 press_time i64
 dirty bool
}
struct Probe {
mut:
 enabled bool = true
 now i64 = 5000000000
 output []string
 exception bool
 fault string
 observer bool = true
 cancel bool
 hit bool = true
 handled u8 = 1
 actions []i32
 methods []string
 refs int
 marks int
 pending_checks int
}
type WsRef = fn (voidptr, voidptr) voidptr
type Drop = fn (voidptr, voidptr)
__global ws = &State{}
__global p = Probe{}
fn probe_getenv(name &char) &char {
 assert unsafe { cstring_to_vstring(name) } == "VINIX_ANDROID_TRACE_TREE"
 return if p.enabled { c"1" } else { unsafe { nil } }
}
fn probe_write(fd i32, buffer voidptr, count usize) isize {
 assert fd == 2 && count > 0 && count < 256
 text := unsafe { cstring_to_vstring(&char(buffer)) }
 assert text.len == int(count) && text.ends_with("\n")
 p.output << text.clone()
 return isize(count)
}
fn ws_millis() i64 { return p.now }
fn pending(_ voidptr) bool { p.pending_checks++; return p.exception }
fn activity_decor(_ voidptr, _ voidptr) voidptr { return voidptr(2) }
fn ws_dialog_decor(_ voidptr, _ voidptr) voidptr { return voidptr(3) }
fn ws_hit(_ voidptr, _ voidptr, _ f32, _ f32, _ i32) voidptr {
 return if p.hit { voidptr(4) } else { unsafe { nil } }
}
fn ws_motion(_ voidptr, _ voidptr, action i32, _ i32, _ i32) u8 {
 if action in [i32(0),1] && p.enabled && ws_pointer_trace_count <= 64 {
  assert p.output.last().contains("phase=received"), "receipt must precede dispatch"
 }
 p.actions << action
 if p.fault == "motion" { p.exception = true }
 return p.handled
}
fn ws_wheel(_ voidptr, _ voidptr, _ i32) {}
fn ws_mark() { p.marks++; ws.dirty = true }
fn probe_ref(_ voidptr, value voidptr) voidptr { p.refs++; return value }
fn probe_drop(_ voidptr, _ voidptr) { p.refs-- }
fn slot(_ voidptr, index i32) voidptr {
 assert index in [i32(21),22]
 return if index == 21 { voidptr(probe_ref) } else { voidptr(probe_drop) }
}
fn get_object(_ voidptr, _ voidptr, _ &char, _ &char, _ &char) voidptr {
 assert !p.exception
 if p.fault == "observer" { p.exception = true }
 return if p.observer { voidptr(5) } else { unsafe { nil } }
}
fn call(_ voidptr, _ voidptr, _ &char, method &char, _ &char, _ voidptr) {
 assert !p.exception
 name := unsafe { cstring_to_vstring(method) }
 p.methods << name.clone()
 if p.fault == name { p.exception = true }
}
fn boolean(_ voidptr, _ voidptr, _ &char, method &char, _ &char, _ voidptr) u8 {
 assert !p.exception
 name := unsafe { cstring_to_vstring(method) }
 p.methods << name.clone()
 if p.fault == name { p.exception = true }
 return u8(p.cancel)
}
fn reset() {
 p = Probe{}
 ws = &State{}
 ws_pointer_trace_count = 0
 ws_cancel_trace = WsFrameTrace{}
 ws_accepted_trace = WsFrameTrace{}
 ws_exception_trace = WsFrameTrace{}
 ws_publication_trace = WsFrameTrace{}
}
'

const trace_cases = '
fn main() {
 reset()
 p.enabled = false
 for _ in 0 .. 70 {
  event := WsEvent{kind:2}
  id := ws_trace_pointer_begin(&event)
  ws_trace_pointer_end(&event, id, c"dispatched", 1, true)
  ws_trace_traversal(true, false)
  ws_trace_publication()
 }
 assert p.output.len == 0 && ws_pointer_trace_count == 0
 assert ws_cancel_trace.events == 0 && ws_publication_trace.events == 0
 reset()
 for _ in 0 .. 3 {
  ws_trace_traversal(true, false)
  ws_trace_traversal(false, false)
  ws_trace_traversal(false, true)
  ws_trace_publication()
 }
 assert p.output.len == 12
 assert p.output.all(it.contains("mono_ms=5000000000 sequence=4294967295"))
 p.now += 29999
 ws_trace_traversal(true, false)
 ws_trace_traversal(false, false)
 ws_trace_traversal(false, true)
 ws_trace_publication()
 assert p.output.len == 12
 p.now++
 ws.surface.sequence = 0
 ws_trace_traversal(true, false)
 ws_trace_traversal(false, false)
 ws_trace_traversal(false, true)
 ws_trace_publication()
 assert p.output.len == 16 && p.output[12..].all(it.contains("sequence=0 events=5"))
 assert p.output[12].contains("stage=predraw-cancel")
 assert p.output[13].contains("stage=traversal-accepted")
 assert p.output[14].contains("stage=traversal-exception")
 assert p.output[15].contains("stage=published")
 reset()
 for i in 0 .. 66 {
  movement := WsEvent{kind:1}
  assert ws_trace_pointer_begin(&movement) == 0
  event := WsEvent{kind:if i % 2 == 0 { u32(2) } else { u32(3) }, x:-7, y:600}
  id := ws_trace_pointer_begin(&event)
  assert id == if i < 64 { u32(i + 1) } else { u32(0) }
  ws_trace_pointer_end(&event, id, c"dispatched", 1, true)
 }
 assert p.output.len == 128 && ws_pointer_trace_count == 64 && p.pending_checks == 0
 assert p.output[0].contains("event=1 phase=received kind=2 mono_ms=5000000000 sequence=4294967295 x=-7 y=600 capture=0")
 assert p.output[127].contains("event=64 phase=dispatched kind=3") && p.output[127].contains("handled=1 exception=1")
 // Execute the unchanged input decisions, including ignored UP and failures.
 reset()
 ws_pointer(voidptr(1), &WsEvent{kind:2, x:20, y:30})
 assert p.actions == [i32(0)] && p.refs == 1 && ws.pressed == voidptr(2)
 ws_pointer(voidptr(1), &WsEvent{kind:3, x:20, y:30})
 assert p.actions == [i32(0),1] && p.refs == 0 && ws.pressed == unsafe { nil }
 assert p.output.len == 4 && p.output[3].contains("handled=1 exception=0")
 ws_pointer(voidptr(1), &WsEvent{kind:3})
 assert p.output.last().contains("phase=no-capture") && p.output.last().contains("handled=-1")
 assert p.actions.len == 2
 for reason in ["outside-dialog", "no-target", "not-handled", "motion"] {
  reset()
  if reason == "outside-dialog" { ws.dialog = voidptr(3) }
  if reason == "no-target" { p.hit = false }
  if reason == "not-handled" { p.handled = 0 }
  if reason == "motion" { p.fault = "motion" }
  ws_pointer(voidptr(1), &WsEvent{kind:2})
  assert p.output.len == 2
  assert p.output.last().contains(if reason in ["outside-dialog", "no-target"] { "phase=" + reason } else { "phase=dispatched" })
  assert p.exception == (reason == "motion")
  if reason == "not-handled" { assert p.refs == 0 && p.output.last().contains("handled=0") }
  if reason == "motion" { assert p.output.last().contains("exception=1") }
 }
 reset()
 p.enabled = false
 ws_pointer(voidptr(1), &WsEvent{kind:2})
 ws_pointer(voidptr(1), &WsEvent{kind:3})
 assert p.output.len == 0 && p.pending_checks == 0 && p.actions == [i32(0),1]
 for fault in ["", "cancel", "none", "observer", "dispatchOnGlobalLayout", "dispatchOnPreDraw", "dispatchOnDraw"] {
  reset()
  p.fault = fault
  p.observer = fault != "none"
  p.cancel = fault == "cancel"
  result := ws_dispatch_traversal(voidptr(1), voidptr(2))
  exception := fault in ["observer", "dispatchOnGlobalLayout", "dispatchOnPreDraw", "dispatchOnDraw"]
  assert result == (!exception && fault != "cancel") && p.exception == exception
  assert ws.dirty == (fault == "cancel") && p.output.len == 1
  stage := if exception { "traversal-exception" } else if fault == "cancel" { "predraw-cancel" } else { "traversal-accepted" }
  assert p.output[0].contains("stage=" + stage)
  if fault == "cancel" { assert p.methods == ["dispatchOnGlobalLayout", "dispatchOnPreDraw"] }
  if fault == "" { assert p.methods == ["dispatchOnGlobalLayout", "dispatchOnPreDraw", "dispatchOnDraw"] }
 }
 println("INPUT-FRAME-TRACE-PASS opt-in bounds independent-rates input-outcomes traversal-exceptions")
}
'
