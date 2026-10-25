// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production loop with controlled input, layout and rendering.
module main

import crypto.sha256
import json2
import os

const harness = r'
module main

#include <unistd.h>
fn C.usleep(u32) i32
fn C.__atomic_exchange_n(&u32, u32, i32) u32

struct Value { i i32 }
struct WsSurface {
mut:
	sequence u32
}
struct WsState {
mut:
	running bool
	dirty bool
	animated bool
	animation_last i64
	activity voidptr
	dialog voidptr
	width i32
	height i32
	dialog_width i32
	dialog_height i32
	surface &WsSurface
}

__global (
	ws &WsState
	ws_window_pending u32
	clock i64
	input_time i64
	render_time i64
	model_version int
	presented []int
	events int
	input_calls int
	frame_calls int
	render_calls int
	depth int
	pushes int
	pops int
	decor_layout bool
	dialog_layout bool
	decor_attached bool
	dialog_attached bool
	decor_width i32
	decor_height i32
	dialog_width i32
	dialog_height i32
	request_in_looper bool
	finish_in_looper bool
	finished bool
	cancel_render bool
	inject_in_render bool
	close_input bool
	queue_active bool
	pending_error string
	fault string
	lookup_calls int
)

fn ready() {
	assert pending_error == "", "JNI call while exception is pending"
	assert !finished, "JNI call after the Looper finished the activity"
}
fn pending(_ voidptr) bool { return pending_error != "" }
fn ws_millis() i64 { return clock }
fn push_frame(_ voidptr) {
	assert depth == 0
	depth++
	pushes++
}
fn pop_frame(_ voidptr) {
	assert depth == 1
	depth--
	pops++
	ws.running = false // Each case executes exactly one actual loop pass.
}
fn ws_queue_begin_pump() {
	assert !queue_active
	queue_active = true
}
fn ws_queue_end_pump() {
	assert queue_active
	queue_active = false
}
fn static_void(_ voidptr, class &char, method &char, signature &char, args voidptr) {
	ready()
	assert unsafe { cstring_to_vstring(class) } == "android/os/Looper"
	assert unsafe { cstring_to_vstring(method) } == "loop"
	assert unsafe { cstring_to_vstring(signature) } == "()V"
	assert args == unsafe { nil }
	assert queue_active
	if request_in_looper { decor_layout = true; ws.dirty = true }
	if finish_in_looper { ws.activity = unsafe { nil }; ws.running = false; finished = true }
	if fault == "looper" { pending_error = "looper identity" }
}
fn ws_failure(_ voidptr, _ &char) bool {
	assert !queue_active, "queue bracket ends before exception handling"
	return pending_error != ""
}
fn activity_decor(_ voidptr, _ voidptr) voidptr {
	ready()
	assert ws.activity != unsafe { nil }
	lookup_calls++
	if fault == "lookup-decor" { pending_error = "lookup-decor identity" }
	return unsafe { voidptr(1) }
}
fn ws_dialog_decor(_ voidptr, _ voidptr) voidptr {
	ready()
	lookup_calls++
	if fault == "lookup-dialog" { pending_error = "lookup-dialog identity" }
	return unsafe { voidptr(2) }
}
fn boolean(_ voidptr, target voidptr, class &char, method &char, signature &char, args voidptr) u8 {
	ready()
	assert unsafe { cstring_to_vstring(class) } == "android/view/View"
	name := unsafe { cstring_to_vstring(method) }
	assert name in ["isLayoutRequested", "isAttachedToWindow"]
	assert unsafe { cstring_to_vstring(signature) } == "()Z"
	assert args == unsafe { nil }
	lookup_calls++
	if target == unsafe { voidptr(1) } {
		if name == "isAttachedToWindow" {
			if fault == "attach-decor" { pending_error = "attach-decor identity" }
			return u8(decor_attached)
		}
		if fault == "layout-decor" { pending_error = "layout-decor identity" }
		return u8(decor_layout)
	}
	assert target == unsafe { voidptr(2) }
	if name == "isAttachedToWindow" {
		if fault == "attach-dialog" { pending_error = "attach-dialog identity" }
		return u8(dialog_attached)
	}
	if fault == "layout-dialog" { pending_error = "layout-dialog identity" }
	return u8(dialog_layout)
}
fn integer(_ voidptr, target voidptr, class &char, method &char, signature &char, args voidptr) i32 {
	ready()
	assert unsafe { cstring_to_vstring(class) } == "android/view/View"
	name := unsafe { cstring_to_vstring(method) }
	assert name in ["getWidth", "getHeight"]
	assert unsafe { cstring_to_vstring(signature) } == "()I"
	assert args == unsafe { nil }
	lookup_calls++
	if target == unsafe { voidptr(1) } {
		if name == "getWidth" && fault == "width-decor" { pending_error = "width-decor identity" }
		if name == "getHeight" && fault == "height-decor" { pending_error = "height-decor identity" }
		return if name == "getWidth" { decor_width } else { decor_height }
	}
	assert target == unsafe { voidptr(2) }
	if name == "getWidth" && fault == "width-dialog" { pending_error = "width-dialog identity" }
	if name == "getHeight" && fault == "height-dialog" { pending_error = "height-dialog identity" }
	return if name == "getWidth" { dialog_width } else { dialog_height }
}
fn ws_input(_ voidptr) {
	ready()
	assert !decor_layout && !dialog_layout, "hit testing needs current bounds"
	assert decor_attached && decor_width == ws.width && decor_height == ws.height
	if ws.dialog != unsafe { nil } {
		assert dialog_attached && dialog_width == ws.dialog_width && dialog_height == ws.dialog_height
	}
	input_calls++
	input_time = clock
	if close_input { ws.running = false; return }
	if fault == "input" { pending_error = "input identity"; return }
	if events > 0 {
		model_version++
		events--
		ws.dirty = true
	}
}
fn ws_frames_dispatch() {
	ready()
	frame_calls++
}
fn ws_render(_ voidptr) {
	ready()
	render_calls++
	render_time = clock
	clock += 500 // Controlled rendering cost, not a measured Maps latency.
	decor_layout = false
	dialog_layout = false
	decor_attached = true
	dialog_attached = true
	decor_width = ws.width
	decor_height = ws.height
	dialog_width = ws.dialog_width
	dialog_height = ws.dialog_height
	if fault == "render" { pending_error = "render identity"; return }
	if cancel_render { ws.dirty = true; return }
	ws.surface.sequence++
	presented << model_version
	ws.dirty = false
	if inject_in_render { events++ }
}
fn reset(sequence u32, dirty bool) {
	ws = &WsState{
		running: true
		dirty: dirty
		activity: unsafe { voidptr(1) }
		width: 480
		height: 640
		dialog_width: 300
		dialog_height: 200
		surface: &WsSurface{sequence: sequence}
	}
	ws_window_pending = 0
	clock = 100
	input_time = -1
	render_time = -1
	model_version = 0
	presented = []int{}
	events = 1
	input_calls = 0
	frame_calls = 0
	render_calls = 0
	depth = 0
	pushes = 0
	pops = 0
	decor_layout = false
	dialog_layout = false
	decor_attached = sequence > 0
	dialog_attached = true
	decor_width = 480
	decor_height = 640
	dialog_width = 300
	dialog_height = 200
	request_in_looper = false
	finish_in_looper = false
	finished = false
	cancel_render = false
	inject_in_render = false
	close_input = false
	queue_active = false
	pending_error = ""
	fault = ""
	lookup_calls = 0
}
fn balanced() {
	assert depth == 0 && pushes == 1 && pops == 1
	assert !queue_active
}
fn main() {
	$if prod { panic("requires assertions") }
	unsafe {
		reset(1, true)
		assert drive(nil) == 0
		balanced()
		assert presented == [1], "queued input must appear in this frame"
		assert input_time == 100 && render_time == 100, "input must not wait for the slow draw"
		assert input_calls == 1 && events == 0
		println("INPUT-FRAME-SAME-PASS-PASS")

		reset(1, false)
		assert drive(nil) == 0
		balanced()
		assert render_calls == 1 && presented == [1], "input invalidation must draw in the same idle pass"
		println("INPUT-FRAME-IDLE-PASS")

		reset(0, true)
		decor_layout = true
		assert drive(nil) == 0
		balanced()
		assert presented == [0] && model_version == 1
		assert input_time == 600 && input_calls == 1 && ws.dirty
		assert lookup_calls == 0, "first frame does not inspect unlaid-out views"
		println("INPUT-FRAME-FIRST-LAYOUT-PASS")

		reset(1, false)
		request_in_looper = true
		assert drive(nil) == 0
		balanced()
		assert presented == [0] && model_version == 1 && input_time == 600
		println("INPUT-FRAME-REPLACED-LAYOUT-PASS")

		reset(1, true)
		ws.dialog = voidptr(2)
		dialog_layout = true
		assert drive(nil) == 0
		balanced()
		assert presented == [0] && model_version == 1 && input_time == 600
		println("INPUT-FRAME-DIALOG-LAYOUT-PASS")

		for target in ["activity", "dialog"] {
			reset(1, true)
			if target == "activity" { decor_attached = false }
			else { ws.dialog = voidptr(2); dialog_attached = false }
			assert drive(nil) == 0
			balanced()
			assert presented == [0] && model_version == 1 && input_time == 600
		}
		println("INPUT-FRAME-ATTACHMENT-PASS")

		for dimension in ["activity-width", "activity-height", "dialog-width", "dialog-height"] {
			reset(1, true)
			ws.dialog = voidptr(2)
			match dimension {
				"activity-width" { decor_width-- }
				"activity-height" { decor_height-- }
				"dialog-width" { dialog_width-- }
				else { dialog_height-- }
			}
			assert drive(nil) == 0
			balanced()
			assert presented == [0] && model_version == 1 && input_time == 600
		}
		println("INPUT-FRAME-DIMENSIONS-PASS")

		reset(0, true)
		decor_layout = true
		cancel_render = true
		assert drive(nil) == 0
		balanced()
		assert ws.surface.sequence == 0 && presented.len == 0
		assert input_calls == 1 && model_version == 1 && ws.dirty
		println("INPUT-FRAME-CANCELED-FIRST-PASS")

		for failure in ["looper", "input", "lookup-decor", "attach-decor", "layout-decor",
			"width-decor", "height-decor", "lookup-dialog", "attach-dialog", "layout-dialog",
			"width-dialog", "height-dialog"] {
			reset(1, true)
			ws.dialog = voidptr(2)
			fault = failure
			assert drive(nil) == 1
			balanced()
			assert pending_error == failure + " identity", "original throwable stays pending"
			assert frame_calls == 0 && render_calls == 0
			assert input_calls == if failure == "input" { 1 } else { 0 }
		}
		reset(0, true)
		fault = "render"
		assert drive(nil) == 1
		balanced()
		assert pending_error == "render identity" && input_calls == 0
		println("INPUT-FRAME-EXCEPTIONS-PASS")

		reset(1, true)
		close_input = true
		assert drive(nil) == 0
		balanced()
		assert frame_calls == 0 && render_calls == 0 && input_calls == 1
		println("INPUT-FRAME-EOF-PASS")

		reset(1, true)
		finish_in_looper = true
		assert drive(nil) == 0
		balanced()
		assert lookup_calls == 0 && frame_calls == 0 && render_calls == 0 && input_calls == 0
		assert ws.activity == nil
		println("INPUT-FRAME-FINISHED-ACTIVITY-PASS")

		reset(1, true)
		inject_in_render = true
		assert drive(nil) == 0
		balanced()
		assert presented == [1] && input_calls == 1 && events == 1
		println("INPUT-FRAME-ONE-BATCH-PASS")
		println("INPUT-FRAME-HOST-PASS")
	}
}
'

struct Receipt {
	runtime_sha256  string
	runner_sha256   string
	compiler_sha256 string
	build_argv      []string
	build_exit      int
	run_exit        int
}

fn main() {
	$if prod {
		panic('requires assertions; compile without -prod')
	}
	repo := os.real_path(os.dir(@FILE) + '/../..')
	mut runtime_path := repo + '/build-support/android/nativews/runtime.v'
	mut out := repo + '/tests/native-android-ws/results/input-frame-check'
	for arg in os.args[1..] {
		if arg.starts_with('runtime=') {
			runtime_path = os.abs_path(arg.all_after('runtime='))
		} else if arg.starts_with('out=') {
			out = os.abs_path(arg.all_after('out='))
		} else {
			panic('usage: input-frame-check [runtime=RUNTIME_V] [out=OUTPUT_DIR]')
		}
	}
	if os.exists(out) || os.is_link(out) { panic('fresh output directory required: ' + out) }
	runtime := os.read_file(runtime_path)!
	assert runtime.count('\t\tfor ws.running {\n') == 1
	assert runtime.count('\n\t\t// Closing the WS pipe') == 1
	loop := runtime.all_after('\t\tfor ws.running {\n').all_before('\n\t\t// Closing the WS pipe')
	assert loop.ends_with('\t\t}')
	mut helper := ''
	marker := 'fn ws_input_layout_ready(e voidptr, decor voidptr, width i32, height i32) bool {'
	if runtime.contains(marker) {
		assert runtime.count(marker) == 1
		assert runtime.count('fn ws_input_before_render(e voidptr) bool {') == 1
		assert runtime.count('\nfn ws_static_int(') == 1
		helper = marker + runtime.all_after(marker).all_before('\nfn ws_static_int(') + '\n'
	}
	os.mkdir_all(out + '/src')!
	os.write_file(out + '/src/main.v', harness)!
	os.write_file(out + '/src/actual_loop.v', 'module main\n' + helper +
		'\nfn drive(e voidptr) i32 {\nunsafe {\nfor ws.running {\n' + loop + '\nreturn 0\n}\n}\n')!
	os.write_file(out + '/runtime.v.txt', runtime)!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { @VEXE }
	argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-enable-globals', '-gc', 'none',
		'-o', out + '/host', out + '/src']
	build := os.exec(argv)
	os.write_file(out + '/build.log', build.output)!
	print(build.output)
	mut run_exit := -1
	if build.exit_code == 0 {
		run := os.exec([out + '/host'])
		os.write_file(out + '/run.log', run.output)!
		print(run.output)
		run_exit = run.exit_code
	}
	receipt := Receipt{
		runtime_sha256:  sha256.sum(runtime.bytes()).hex()
		runner_sha256:   sha256.sum(os.read_bytes(@FILE)!).hex()
		compiler_sha256: sha256.sum(os.read_bytes(compiler)!).hex()
		build_argv:      argv
		build_exit:      build.exit_code
		run_exit:        run_exit
	}
	os.write_file(out + '/receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	if build.exit_code != 0 { exit(build.exit_code) }
	exit(run_exit)
}
