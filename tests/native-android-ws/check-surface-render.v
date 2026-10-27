// SPDX-License-Identifier: GPL-2.0-or-later
// Execute ws_render itself against guard pages and hostile shared headers.
module main

import crypto.sha256
import json2
import os

fn render_block(source string, prefix string) !string {
	start := source.index(prefix) or { return error('missing ' + prefix) }
	end := source[start..].index('\n}') or { return error('unclosed ' + prefix) }
	return source[start..start + end + 2]
}

struct RenderCommand {
	argv   []string
	status int
	output string
}

struct RenderEvidence {
	scope           string
	source_revision string
	source_sha256   string
	runtime_sha256  string
	checker_sha256  string
	compiler        string
	compiler_sha256 string
	compile         RenderCommand
	runs            []RenderCommand
}

fn main() {
	assert os.args.len in [2, 3], 'usage: check-surface-render OUTPUT_DIR [REPO]'
	repo := if os.args.len == 3 { os.real_path(os.args[2]) } else { os.getwd() }
	work := os.abs_path(os.args[1])
	assert !os.exists(work), 'output directory must be new'
	assert work != repo && !work.starts_with(repo + '/'), 'keep generated evidence outside Git'
	os.mkdir_all(work)!
	source := os.read_file(repo + '/build-support/android/nativews/ws_views.v')!
	runtime := os.read_file(repo + '/build-support/android/nativews/runtime.v')!
	checker := os.read_file(repo + '/tests/native-android-ws/check-surface-render.v')!
	production := render_block(source, 'fn ws_render(')!
	// Adapt only TLS; real pointer arithmetic, pixel writes and C atomics stay
	// unchanged. JNI/drawing dependencies below provide deterministic outcomes.
	adapted := production.replace('C.pthread_getspecific(', 'probe_getspecific(')
		.replace('C.pthread_setspecific(', 'probe_setspecific(')
	mut program := render_model + '\n' + render_block(runtime, 'struct WsSurface {')! + '\n' + adapted
	mut names := ['production']
	for mutation in [
		production.replace('(C.__atomic_load_n(&surface.active, 2) & 1) ^ 1', 'C.__atomic_load_n(&surface.active, 2) ^ 1'),
		production.replace('usize(ws.width) * usize(ws.height) * 4', 'usize(surface.buffer_size)'),
		production.replace('if C.__atomic_load_n(&surface.reader, 2) == target { return }', ''),
	] {
		assert mutation != production, 'negative mutation no longer applies'
		name := 'mutation_' + names.len.str()
		names << name
		program += '\n' + mutation.replace('fn ws_render(', 'fn ' + name + '(')
			.replace('C.pthread_getspecific(', 'probe_getspecific(')
			.replace('C.pthread_setspecific(', 'probe_setspecific(')
	}
	program += render_cases + '\nfn main() {\n assert os.args.len == 2\n match os.args[1] {\n'
	for name in names {
		function := if name == 'production' { 'ws_render' } else { name }
		invocation := match name {
			'production' { 'render_suite(${function})' }
			'mutation_1' { 'render_case(${function}, 2, 16384, 0xffffffff, -1, true, false)' }
			'mutation_2' { 'render_case(${function}, 0, 32768, 0xffffffff, -1, true, false)' }
			else { 'render_case(${function}, 0, 16384, 1, -1, true, false)' }
		}
		program += ' "${name}" { ${invocation} }\n'
	}
	program += ' else { panic("unknown implementation") }\n }\n println("SURFACE-RENDER-PASS guarded-framebuffers cached-geometry masked-active reader-lock tls-early-exit")\n}\n'
	os.write_file(work + '/input-ws-views.v', source)!
	os.write_file(work + '/input-runtime.v', runtime)!
	os.write_file(work + '/input-checker.v', checker)!
	os.write_file(work + '/main.v', program)!
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { os.find_abs_path_of_executable('v')! })
	compile_argv := [compiler, '-w', '-n', '-enable-globals', '-cc', 'cc', '-o', work + '/probe',
		work + '/main.v']
	compiled := os.exec(compile_argv)
	os.write_file(work + '/compile.log', compiled.output)!
	assert compiled.exit_code == 0, compiled.output
	mut runs := []RenderCommand{}
	for name in names {
		argv := [work + '/probe', name]
		ran := os.exec(argv)
		os.write_file(work + '/' + name + '.log', ran.output)!
		runs << RenderCommand{argv, ran.exit_code, ran.output}
		if name == 'production' {
			assert ran.exit_code == 0 && ran.output.trim_space() == 'SURFACE-RENDER-PASS guarded-framebuffers cached-geometry masked-active reader-lock tls-early-exit', ran.output
		} else {
			assert ran.exit_code != 0, 'negative mutation escaped: ' + name
		}
	}
	revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	os.write_file(work + '/build.json', json2.encode(RenderEvidence{
		scope:           'Extracted production ws_render with real mmap/mprotect guard pages, pixel writes and C atomics; deterministic JNI/TLS adapters; no ART, concurrent reader or guest execution.'
		source_revision: revision.output.trim_space()
		source_sha256:   sha256.sum(source.bytes()).hex()
		runtime_sha256:  sha256.sum(runtime.bytes()).hex()
		checker_sha256:  sha256.sum(checker.bytes()).hex()
		compiler:        compiler
		compiler_sha256: sha256.sum(os.read_bytes(compiler)!).hex()
		compile:         RenderCommand{compile_argv, compiled.exit_code, compiled.output}
		runs:            runs
	}, prettify: true))!
	mut inventory := map[string]string{}
	for name in os.ls(work)! {
		inventory[name] = sha256.sum(os.read_bytes(work + '/' + name)!).hex()
	}
	os.write_file(work + '/sha256.json', json2.encode(inventory, prettify: true))!
	println(runs[0].output.trim_space())
	println('SURFACE-RENDER-MUTATIONS-PASS unmasked-active shared-buffer-size missing-reader-lock')
}

const render_model = '
module main
import os
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.mprotect(voidptr, usize, i32) i32
fn C.getpagesize() i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)
struct WsTransform { mut: right i32 bottom i32 }
struct Draw { mut: width i32 height i32 pixels &u32 = unsafe { nil } transform WsTransform save_count i32 }
struct State {
mut:
 surface &WsSurface = unsafe { nil }
 width i32 = 64
 height i32 = 64
 activity voidptr = voidptr(1)
 canvas voidptr = voidptr(3)
 dialog voidptr = unsafe { nil }
 dirty bool = true
 animated bool = true
 animation_last i64 = 17
 layout_requests u64
}
struct Probe {
mut:
 tls voidptr = voidptr(55)
 leaves int
 calls int
 fail_call int = -1
 traversal bool = true
 exception bool
 dirty_layout bool
 draw bool
 attached int
 clips int
 publications int
 published_active u32
 published_sequence u32
}
struct Value { i i32 l voidptr }
type Render = fn (voidptr)
__global ws = &State{}
__global ws_root_draw = &Draw{}
__global ws_draw_key = u32(7)
__global rp = Probe{}
fn probe_getspecific(key u32) voidptr { assert key == 7; return rp.tls }
fn probe_setspecific(key u32, value voidptr) i32 { assert key == 7; rp.tls = value; return 0 }
fn ws_canvas_leave(previous voidptr) { rp.tls = previous; rp.leaves++ }
fn ws_path_clip_release(draw &Draw, until voidptr) {
 assert draw == ws_root_draw && until == unsafe { nil }
 assert rp.tls == voidptr(ws_root_draw)
 rp.clips++
}
fn activity_decor(e voidptr, activity voidptr) voidptr { return voidptr(4) }
fn obj(e voidptr, value voidptr, class &char, method &char, signature &char, args &Value) voidptr { return voidptr(5) }
fn ws_attach_window(e voidptr, window voidptr, decor voidptr) { rp.attached++ }
fn pending(e voidptr) bool { return rp.exception }
fn call(e voidptr, value voidptr, class &char, method &char, signature &char, args &Value) {
 rp.calls++
 if rp.calls == rp.fail_call { rp.exception = true }
 if rp.calls == 2 && rp.dirty_layout { ws.layout_requests++ }
 if rp.calls == 3 && rp.draw {
  unsafe { ws_root_draw.pixels[0] = 0x12345678; ws_root_draw.pixels[ws.width * ws.height - 1] = 0x87654321 }
 }
}
fn ws_dispatch_traversal(e voidptr, window voidptr) bool { return rp.traversal }
fn ws_trace_tree(e voidptr, decor voidptr) {}
fn ws_trace_publication() {
 rp.publications++
 rp.published_active = ws.surface.active
 rp.published_sequence = ws.surface.sequence
}
fn ws_render_dialog(e voidptr) bool { return true }
fn ws_millis() i64 { return 99 }
'

const render_cases = '
fn render_case(render Render, active u32, size u32, reader u32, fail_call int, traversal bool, draw bool) {
 unsafe {
  assert sizeof(WsSurface) == 48
  page := usize(C.getpagesize())
  bytes := usize(64 * 64 * 4)
  length := usize(48) + bytes * 2
  usable := (length + page - 1) / page * page
  total := usable + page * 2
  mapping := C.mmap(nil, total, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANON, -1, 0)
  assert mapping != voidptr(-1)
  defer { assert C.munmap(mapping, total) == 0 }
  assert C.mprotect(mapping, page, C.PROT_NONE) == 0
  assert C.mprotect(voidptr(usize(mapping) + page + usable), page, C.PROT_NONE) == 0
  start := usize(mapping) + page
  C.memset(voidptr(start), 0xa5, usable)
  // End the exact framebuffer mapping at the trailing guard page. A canary
  // covers the sub-page prefix immediately preceding its immutable header.
  surface := &WsSurface(start + usable - length)
  *surface = WsSurface{
   magic: 0xdeadbeef version: 99 header_size: 4096 width: 0xffffffff
   height: 1 stride: 0xffffffff format: 77 active: active reader: reader
   sequence: 0xffffffff buffer_size: size reserved: 0xffffffff
  }
  ws = &State{surface:surface}
  ws_root_draw = &Draw{}
  rp = Probe{fail_call:fail_call, traversal:traversal, draw:draw, dirty_layout:true}
  target := (active & 1) ^ 1
  blocked := reader == target
  completed := !blocked && fail_call < 0 && traversal
  render(nil)
  // Rendering may publish only these two fields; hostile metadata stays
  // hostile, proving that sanitizing the fixture did not mask the bug.
  assert surface.magic == 0xdeadbeef && surface.version == 99 && surface.header_size == 4096
  assert surface.width == 0xffffffff && surface.height == 1 && surface.stride == 0xffffffff
  assert surface.format == 77 && surface.reader == reader && surface.buffer_size == size && surface.reserved == 0xffffffff
  assert surface.active == if completed { target } else { active }
  assert surface.sequence == if completed { u32(0) } else { u32(0xffffffff) }
  assert rp.publications == if completed { 1 } else { 0 }
  if completed { assert rp.published_active == target && rp.published_sequence == 0 }
  assert rp.tls == voidptr(55)
  assert rp.leaves == if blocked { 0 } else { 1 }
  assert rp.attached == if blocked { 0 } else { 1 }
  assert rp.clips == if blocked { 0 } else { 1 }
  assert ws.animation_last == if completed { i64(99) } else { i64(17) }
  if !blocked {
   assert usize(ws_root_draw.pixels) == usize(surface) + 48 + usize(target) * bytes
   assert ws_root_draw.width == 64 && ws_root_draw.height == 64
   assert ws_root_draw.transform.right == 64 && ws_root_draw.transform.bottom == 64
  }
  for at := start; at < usize(surface); at++ { assert *(&u8(at)) == 0xa5 }
  for buffer in 0 .. 2 {
   pixels := &u32(usize(surface) + 48 + usize(buffer) * bytes)
   for i in 0 .. 4096 {
    expected := if blocked || u32(buffer) != target { u32(0xa5a5a5a5) }
     else if draw && completed && i == 0 { u32(0x12345678) }
     else if draw && completed && i == 4095 { u32(0x87654321) }
     else { u32(0xfffafafa) }
    assert pixels[i] == expected
   }
  }
 }
}
fn render_suite(render Render) {
 for active in [u32(0), 1, 2, 3, 0xfffffffe, 0xffffffff] {
  for size in [u32(0), 1, 16384, 32768, 0xffffffff] {
   render_case(render, active, size, 0xffffffff, -1, true, true)
  }
  target := (active & 1) ^ 1
  render_case(render, active, 0xffffffff, target, -1, true, true)
  render_case(render, active, 0, target ^ 1, -1, true, true)
 }
 // Exercise deferred TLS restoration and publication ordering on JNI and
 // traversal failure after the exact same production buffer clear.
 for fail_call in [1, 2, 3] { render_case(render, 0xffffffff, 1, 0xffffffff, fail_call, true, false) }
 render_case(render, 2, 0xffffffff, 0xffffffff, -1, false, false)
}
'
