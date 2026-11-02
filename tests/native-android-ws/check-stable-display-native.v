// SPDX-License-Identifier: GPL-2.0-or-later
// Run production geometry/JNI bodies against deterministic syscall and JNI
// tables. Generated programs and receipts belong in a fresh external bundle.
module main

import crypto.sha256
import json2
import os

fn stable_hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn stable_function(source string, name string) !string {
	start := source.index('fn ' + name + '(') or { return error('missing function: ' + name) }
	open := start + (source[start..].index('{') or { return error('missing function body: ' + name) })
	mut depth := 0
	for index in open .. source.len {
		if source[index] == `{` { depth++ }
		if source[index] == `}` {
			depth--
			if depth == 0 { return source[start..index + 1] }
		}
	}
	return error('unterminated function: ' + name)
}

fn main() {
	assert os.args.len == 3, 'usage: check-stable-display-native REPO FRESH_EXTERNAL_OUTPUT'
	repo, out := os.real_path(os.args[1]), os.abs_path(os.args[2])
	assert !out.starts_with(repo + '/') && !os.exists(out) && !os.is_link(out)
	assert os.real_path(os.dir(out)) == os.dir(out)
	source_path := repo + '/build-support/android/nativews/stable_display.v'
	jni_path := repo + '/build-support/android/atlframework/jni.v'
	binding_path := repo + '/build-support/android/nativews/bindings.txt'
	baseline_path := '/Users/alex/.local/state/vinix/android/current-native-build-2026-11-01-resource-lock-r2/native/bindings.txt'
	assert stable_hash(baseline_path)! == '6fcfb9aff1f73a308f3c7b68f8982243179805ca488f35fba6e2b0db54c6b2b4'
	source, jni := os.read_file(source_path)!, os.read_file(jni_path)!
	binding := 'android/hardware/display/DisplayManager|getStableDisplaySize()Landroid/graphics/Point;|return ws_stable_display_size(e)\n'
	assert os.read_file(binding_path)! == os.read_file(baseline_path)! + binding, 'one appended exact binding required'
	assert source.count('module atlframework\n') == 1
	assert source.count('fn C.ioctl(i32, usize, ...) i32\n') == 1
	mut program := source.replace('@[translated]\n', '').replace('module atlframework\n', 'module main\n')
		.replace('fn C.ioctl(i32, usize, ...) i32\n', '')
	for name in ['open', 'ioctl', 'close'] { program = program.replace('C.' + name + '(', 'probe_' + name + '(') }
	program += stable_probe
	for name in ['slot', 'pending', 'cls'] { program += '\n' + stable_function(jni, name)! + '\n' }
	query := stable_function(source, 'ws_framebuffer_size')!
	mut mutations := []string{}
	for change in [query.replace('defer { C.close(fd) }', ''),
		query.replace('C.O_RDONLY | C.O_CLOEXEC', 'C.O_RDWR | C.O_CLOEXEC'),
		query.replace('C.O_RDONLY | C.O_CLOEXEC', 'C.O_RDONLY'),
		query.replace('if fd < 0', 'if fd <= 0'),
		query.replace('!= 0 { return 0, 0 }', '< -1 { return 0, 0 }'),
		query.replace('info.xres > 0x7fffffff', 'info.xres > 0xffffffff')] {
		assert change != query, 'negative control no longer applies'
		name := 'query_mutant_' + mutations.len.str()
		mut body := change.replace('fn ws_framebuffer_size(', 'fn ' + name + '(')
		for call in ['open', 'ioctl', 'close'] { body = body.replace('C.' + call + '(', 'probe_' + call + '(') }
		program += '\n' + body + '\n'
		mutations << name
	}
	program += '\nfn main() {\n check_layout()\n assert geometry_suite(ws_framebuffer_size)\n check_jni()\n'
	for name in mutations { program += ' assert !geometry_suite(' + name + '), "escaped negative control ' + name + '"\n' }
	program += ' println("STABLE-DISPLAY-NATIVE-PASS layout160 readonly geometry errors fd-lifetime fresh-point jni-exceptions 6-negative-controls")\n}\n'
	os.mkdir(out, mode: 0o700)!
	os.write_file(out + '/probe.v', program)!
	mut inputs := map[string]string{}
	for path in [source_path, jni_path, binding_path, baseline_path, os.real_path(@FILE)] { inputs[path] = stable_hash(path)! }
	os.write_file(out + '/inputs-before.json', json2.encode(inputs, prettify: true) + '\n')!
	compiler := os.real_path(os.find_abs_path_of_executable(os.getenv_opt('VINIX_V_COMPILER') or { 'v' })!)
	args := [compiler, '-w', '-n', '-enable-globals', '-no-parallel', '-cc', 'cc', '-o', out + '/probe', out + '/probe.v']
	compiled := os.exec(args)
	os.write_file(out + '/compile.log', compiled.output)!
	ran := if compiled.exit_code == 0 { os.exec([out + '/probe']) } else { os.Result{exit_code: -1} }
	os.write_file(out + '/run.log', ran.output)!
	for path, pin in inputs { assert stable_hash(path)! == pin, 'source changed during check: ' + path }
	os.write_file(out + '/receipt.json', json2.encode({
		'inputs_sha256': json2.decode[json2.Any](json2.encode(inputs))!
		'compiler': json2.Any(compiler)
		'compiler_sha256': json2.Any(stable_hash(compiler)!)
		'compile_argv': json2.decode[json2.Any](json2.encode(args))!
		'compile_exit': json2.Any(compiled.exit_code)
		'run_exit': json2.Any(ran.exit_code)
		'probe_sha256': json2.Any(stable_hash(out + '/probe.v')!)
	}, prettify: true) + '\n')!
	assert compiled.exit_code == 0, compiled.output
	assert ran.exit_code == 0, ran.output
	assert ran.output.trim_space() == 'STABLE-DISPLAY-NATIVE-PASS layout160 readonly geometry errors fd-lifetime fresh-point jni-exceptions 6-negative-controls'
	println(ran.output.trim_space())
}

const stable_probe = r'
union Value {
mut:
 l voidptr
 i i32
 j i64
 f f32
 d f64
}
type Lookup = fn (voidptr, &char) voidptr
type Member = fn (voidptr, voidptr, &char, &char) voidptr
type ObjectCall = fn (voidptr, voidptr, voidptr, &Value) voidptr
type Check = fn (voidptr) u8
type Drop = fn (voidptr, voidptr)
type Query = fn () (i32, i32)
struct Probe {
mut:
 fd i32 = 7
 ioctl_result i32
 close_result i32
 width u32 = 1366
 height u32 = 768
 opens int
 ioctls int
 closes int
 bad bool
 pending bool
 fail int
 finds int
 methods int
 drops int
 points int
 x i32
 y i32
}
__global probe Probe
fn probe_open(path &char, flags i32) i32 {
 probe.opens++
 if unsafe { path.vstring() } != "/dev/fb0" || flags != (C.O_RDONLY | C.O_CLOEXEC) { probe.bad = true }
 return probe.fd
}
fn probe_ioctl(fd i32, request usize, info &WsDisplayScreenInfo) i32 {
 probe.ioctls++
 if fd != probe.fd || request != 0x4600 { probe.bad = true }
 unsafe {
  bytes := &u8(info)
  for i in 0 .. 160 { if bytes[i] != 0 { probe.bad = true } }
  words := &u32(info)
  for i in 0 .. 40 { words[i] = 0xa5a5a5a5 }
  words[0] = probe.width
  words[1] = probe.height
 }
 return probe.ioctl_result
}
fn probe_close(fd i32) i32 {
 probe.closes++
 if fd != probe.fd { probe.bad = true }
 return probe.close_result
}
fn check_layout() {
 mut info := WsDisplayScreenInfo{}
 assert sizeof(WsDisplayBitfield) == 12 && sizeof(WsDisplayScreenInfo) == 160
 unsafe {
  assert usize(&info.xres) - usize(&info) == 0
  assert usize(&info.yres) - usize(&info) == 4
  assert usize(&info.red) - usize(&info) == 32
  assert usize(&info.transp) - usize(&info) == 68
  assert usize(&info.nonstd) - usize(&info) == 80
  assert usize(&info.reserved) - usize(&info) == 144
 }
}
fn geometry_suite(query Query) bool {
 cases := [Probe{}, Probe{fd: -1}, Probe{fd: 0}, Probe{ioctl_result: -1},
  Probe{width: 0}, Probe{height: 0}, Probe{width: 0x80000000}, Probe{height: 0xffffffff},
  Probe{width: 0x7fffffff, height: 1}, Probe{close_result: -1}]
 for c in cases {
  probe = c
  x, y := query()
  usable := c.fd >= 0 && c.ioctl_result == 0 && c.width > 0 && c.height > 0 && c.width <= 0x7fffffff && c.height <= 0x7fffffff
  expected_x := if usable { i32(c.width) } else { 0 }
  expected_y := if usable { i32(c.height) } else { 0 }
  if probe.bad || x != expected_x || y != expected_y
   || probe.opens != 1 || probe.ioctls != int(c.fd >= 0) || probe.closes != int(c.fd >= 0) { return false }
 }
 probe = Probe{}
 for _ in 0 .. 1000 { x, y := query(); if x != 1366 || y != 768 { return false } }
 return !probe.bad && probe.opens == 1000 && probe.ioctls == 1000 && probe.closes == 1000
}
fn probe_pending(_ voidptr) u8 { return u8(probe.pending) }
fn probe_find(_ voidptr, name &char) voidptr {
 probe.finds++
 if unsafe { name.vstring() } != "android/graphics/Point" { probe.bad = true }
 if probe.fail == 1 { probe.pending = true; return unsafe { nil } }
 return voidptr(0x100)
}
fn probe_member(_ voidptr, class voidptr, name &char, signature &char) voidptr {
 probe.methods++
 if class != voidptr(0x100) || unsafe { name.vstring() } != "<init>" || unsafe { signature.vstring() } != "(II)V" { probe.bad = true }
 if probe.fail == 2 { probe.pending = true; return unsafe { nil } }
 return voidptr(0x200)
}
fn probe_point(_ voidptr, class voidptr, init voidptr, args &Value) voidptr {
 probe.points++
 if class != voidptr(0x100) || init != voidptr(0x200) || args == unsafe { nil } { probe.bad = true }
 unsafe { probe.x = args[0].i; probe.y = args[1].i }
 if probe.fail == 3 { probe.pending = true; return unsafe { nil } }
 return voidptr(0x1000 + probe.points)
}
fn probe_drop(_ voidptr, class voidptr) { probe.drops++; if class != voidptr(0x100) { probe.bad = true } }
fn check_jni() {
 mut slots := [229]voidptr{}
 slots[6] = voidptr(probe_find)
 slots[23] = voidptr(probe_drop)
 slots[30] = voidptr(probe_point)
 slots[33] = voidptr(probe_member)
 slots[228] = voidptr(probe_pending)
 mut table := unsafe { voidptr(&slots[0]) }
 e := unsafe { voidptr(&table) }
 probe = Probe{}
 first := ws_stable_display_size(e)
 second := ws_stable_display_size(e)
 assert first != unsafe { nil } && second != unsafe { nil } && first != second
 assert probe.x == 1366 && probe.y == 768 && probe.points == 2 && probe.drops == 2 && probe.closes == 2 && !probe.bad
 for c in [Probe{fd: -1}, Probe{ioctl_result: -1}, Probe{width: 0}] {
  probe = c
  assert ws_stable_display_size(e) != unsafe { nil }
  assert probe.x == 0 && probe.y == 0 && probe.points == 1 && probe.drops == 1 && !probe.bad
 }
 probe = Probe{pending: true}
 assert ws_stable_display_size(e) == unsafe { nil }
 assert probe.opens == 0 && probe.finds == 0 && probe.methods == 0 && probe.drops == 0 && probe.pending
 probe = Probe{}
 assert ws_stable_display_size(unsafe { nil }) == unsafe { nil } && probe.opens == 0
 for fail in 1 .. 4 {
  probe = Probe{fail: fail}
  assert ws_stable_display_size(e) == unsafe { nil }
  assert probe.pending && probe.closes == 1 && !probe.bad
  assert probe.drops == if fail == 1 { 0 } else { 1 }
  assert probe.points == if fail == 3 { 1 } else { 0 }
 }
}
'
