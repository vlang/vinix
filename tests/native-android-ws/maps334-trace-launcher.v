// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic launcher built with the unmodified sealed283 compiler recorder.
module main

import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const qualified = '/Users/alex/.local/state/vinix/android/maps283-clean-launcher-2026-10-25'
const qualified_pin = '9e8256b31be97aa97c7bf8b4b353624514ea9cd7d9acfb7f7315d24c26670f10'
const compiler = '/Users/alex/code/vinix/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const source = '/Users/alex/code/vinix/tests/native-android-ws/maps334-trace-launcher.v'
const clean_pin = '4c31af25fc8621a495db1e6e722416b523bed9c0f139078fb78b7da6287ac447'
const category = 'com.google.android.apps.gmm.base.components.gmmrecyclerview.GmmRecyclerView'

fn hash(path string) !string {
	assert os.lstat(path)!.get_filetype() == .regular, path
	mut f := os.open(path)!
	defer { f.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut sum := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &sum }) == 1
	for {
		n := f.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		assert C.CC_SHA256_Update(unsafe { &sum }, buffer.data, u32(n)) == 1
	}
	mut result := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &sum }) == 1
	return result[..].hex()
}
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn pins(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }
fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }
fn clone(from string, to string) ! {
	assert !os.exists(to) && !os.is_link(to), to
	os.mkdir_all(os.dir(to))!
	r := os.exec(['cp', '-c', '-R', '-P', '-p', from, to])
	assert r.exit_code == 0, r.output
}
fn inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory { entries[key] = 'directory'; inventory(root, key, mut entries)! }
			else { return error('unexpected evidence entry: ' + path) }
		}
	}
}
fn verify_manifest(root string, seal string) ! {
	assert hash(root + '/sha256.json')! == seal, root
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	assert actual == pins(root + '/sha256.json')!, 'complete build inventory differs'
}
fn setters() string {
	return "\n\tos.setenv('VINIX_ANDROID_TRACE_TREE', '1', true)"
		+ "\n\tos.setenv('VINIX_ANDROID_TRACE_THREADS', '1', true)"
		+ "\n\tos.setenv('VINIX_ANDROID_TRACE_OBJECT_CLASS', '1', true)"
		+ "\n\tos.setenv('VINIX_ANDROID_TRACE_VIEW_ADDS', '${category}', true)"
		+ "\n\tos.setenv('VINIX_ANDROID_TRACE_VISIBILITY', '${category}', true)"
}
fn trace_source(clean string) !string {
	assert !clean.contains('VINIX_ANDROID_TRACE_') && clean.count('fn main() {') == 1
	return clean.replace('fn main() {', 'fn main() {' + setters())
}
fn stable(before map[string]string) ! { for path, pin in before { assert hash(path)! == pin, path } }
fn retain(root string, path string, pin string) ! {
	to := root + '/inputs/' + path.trim_left('/')
	if os.exists(to) { assert hash(to)! == pin, to; return }
	assert hash(path)! == pin, path
	clone(path, to)!
	assert hash(to)! == pin, to
}
fn compile_argv(root string, phase string) []string {
	return [root + '/tools/v_old276', '-nocache', '-os', 'linux', '-arch', 'arm64',
		'-cc', root + '/aarch64-linux-musl-gcc', '-gc', 'none', '-showcc', '-dump-files',
		root + '/' + phase + '-v-files.txt', '-cflags', '-O2 -D_GNU_SOURCE -static',
		'-ldflags', '-static', '-o', root + '/' + phase, root + '/source/launcher.v']
}
// Independently recompute the unmodified283 recorder's dependency schema.
fn consumed_paths(root string, phase string) ![]string {
	origin := os.read_file(root + '/build-root.txt')!.trim_space()
	mut paths := os.read_lines(root + '/' + phase + '-v-files.txt')!
	mut count := 0
	for name in os.ls(root + '/cc-records')! {
		if !name.starts_with(phase + '-') || !name.ends_with('.json') { continue }
		count++
		stem := root + '/cc-records/' + name.all_before_last('.json')
		recorded_stem := origin + '/cc-records/' + name.all_before_last('.json')
		r := object(stem + '.json')!
		assert r['exit_code']!.int() == 0 && r['build_root']!.str() == origin, name
		original := r['original_argv']!.as_array().map(it.str())
		mut argv := [os.read_file(root + '/real-gcc.txt')!.trim_space()]
		argv << original
		is_source := original.any(it.ends_with('.c'))
		probe := original.any(it in ['-M', '-MM', '-E', '-S', '-fsyntax-only'])
		if is_source && !probe { argv << ['-MD', '-MF', recorded_stem + '.d'] }
		if is_source && !probe && '-c' !in original {
			argv << '-Wl,-t'
			if r['cwd']!.str().starts_with(origin + '/') && r['cwd']!.str().contains('.v3cc.') { argv << '-save-temps=obj' }
		}
		assert argv == r['argv']!.as_array().map(it.str()), name
		deps := if os.is_file(stem + '.d') { os.read_file(stem + '.d')! } else { '' }
		mut candidates := deps.replace('\\\n', ' ').all_after(':').fields()
		for line in os.read_file(stem + '.log')!.split_into_lines() {
			path := line.trim_space()
			if path.starts_with('/') && (path.ends_with('.a') || path.ends_with('.o')) { candidates << path }
		}
		for arg in original { if !arg.starts_with('-') && (arg.ends_with('.c') || arg.ends_with('.o')) { candidates << arg } }
		mut inputs := []string{}
		for candidate in candidates {
			path := if os.is_abs_path(candidate) { candidate } else { r['cwd']!.str() + '/' + candidate }
			if path.starts_with(origin + '/') && path.contains('.v3cc.') { continue }
			if path !in inputs { inputs << path }
		}
		assert inputs == r['inputs']!.as_array().map(it.str()), name
		for _, pin in r['generated_c']!.as_map() { assert hash(stem + '.c')! == pin.str(), name }
		paths << inputs
	}
	assert count >= 3, 'missing compiler invocation records'
	paths << [origin + '/tools/v_old276', origin + '/aarch64-linux-musl-gcc']
	for _, path in pins(root + '/compile-tools.json')! { paths << path }
	return paths
}
fn freeze_consumed(root string, phase string, mut before map[string]string) ! {
	mut actual := map[string]string{}
	mut resolutions := map[string]string{}
	for path in consumed_paths(root, phase)! {
		resolved := os.real_path(path)
		if resolved !in before && phase == 'discovery' && resolved.starts_with(root + '/cache/v3_thirdparty_objs/') {
			prefix := os.file_name(resolved).all_before_last('_')
			mut expected := ''
			for frozen, pin in before {
				if frozen.starts_with(root + '/cache/v3_thirdparty_objs/') && os.file_name(frozen).all_before_last('_') == prefix { expected = pin; break }
			}
			assert expected.len == 64 && hash(resolved)! == expected, resolved
			before[resolved] = expected
			retain(root, resolved, expected)!
		}
		assert resolved in before, 'unfrozen launcher input: ' + resolved
		assert hash(resolved)! == before[resolved]!, resolved
		actual[resolved] = before[resolved]!
		resolutions[path] = resolved
	}
	assert actual.len > 100
	write_json(root + '/' + phase + '-consumed.json', actual)!
	write_json(root + '/' + phase + '-resolved-inputs.json', resolutions)!
}
fn compile(root string, phase string, mut before map[string]string) ! {
	stable(before)!
	mut r := {'argv': json2.Any(compile_argv(root, phase)), 'started_utc': json2.Any(time.utc().str()),
		'VROOT': json2.Any(os.getenv('VROOT')), 'VTMP': json2.Any(os.getenv('VTMP')),
		'input_sha256': json2.decode[json2.Any](json2.encode(before))!}
	write_json(root + '/' + phase + '-before.json', r)!
	os.setenv('VINIX_LAUNCHER_BUILD_PHASE', phase, true)
	result := os.exec(compile_argv(root, phase))
	os.write_file(root + '/' + phase + '.log', result.output)!
	print(result.output)
	r['completed_utc'] = time.utc().str()
	r['exit_code'] = json2.Any(result.exit_code)
	r['log_sha256'] = hash(root + '/' + phase + '.log')!
	if result.exit_code == 0 { r['output_sha256'] = hash(root + '/' + phase)! }
	write_json(root + '/' + phase + '-receipt.json', r)!
	assert result.exit_code == 0, phase
	stable(before)!
	freeze_consumed(root, phase, mut before)!
}
fn build(root string) ! {
	assert os.is_abs_path(root) && !os.exists(root) && !os.is_link(root), 'fresh absolute root required'
	verify_manifest(qualified, qualified_pin)!
	assert hash(compiler)! == compiler_pin
	clone(qualified, root + '/qualified283')!
	verify_manifest(root + '/qualified283', qualified_pin)!
	for name in ['aarch64-linux-musl-gcc', 'real-gcc.txt', 'compile-tools.json'] { clone(qualified + '/' + name, root + '/' + name)! }
	clone(compiler, root + '/tools/v_old276')!
	clone(source, root + '/source/maps334-trace-launcher.v')!
	clone(os.executable(), root + '/builder')!
	clean := os.read_file(qualified + '/source/launcher.v')!
	assert hash(qualified + '/source/launcher.v')! == clean_pin
	os.write_file(root + '/source/launcher.v', trace_source(clean)!)!
	os.write_file(root + '/build-root.txt', root + '\n')!
	os.mkdir_all(root + '/cc-records')!
	prior := pins(qualified + '/input-sha256.json')!
	mut before := map[string]string{}
	for path, pin in prior {
		if path.starts_with('/Users/alex/code/vinix/build/android-maps/maps283-clean-launcher/') || path == '/Users/alex/code/v/v_old' { continue }
		if path.contains('/v3_thirdparty_objs/') {
			target := root + '/cache/v3_thirdparty_objs/' + os.file_name(path)
			clone(qualified + '/inputs/' + path.trim_left('/'), target)!
			before[target] = pin
		} else { before[path] = pin }
	}
	for path in [root + '/source/launcher.v', root + '/aarch64-linux-musl-gcc', root + '/tools/v_old276',
		'/Users/alex/code/v/vlib/builtin/segfault_handler_nix.c', '/Users/alex/code/v/vlib/builtin/segfault_handler_nix.h',
		'/Users/alex/code/v/vlib/os/execute_capture_nix.c', '/Users/alex/code/v/vlib/os/execute_capture_nix.h'] {
		before[path] = hash(path)!
	}
	// Header dependencies already observed by the isolated inflater292 build.
	for relative in ['stdc-predef.h', 'stddef.h', 'bits/alltypes.h', 'errno.h', 'features.h', 'bits/errno.h', 'signal.h', 'bits/signal.h', 'stdint.h', 'bits/stdint.h', 'string.h', 'strings.h', 'unistd.h', 'bits/posix.h', 'pthread.h', 'sched.h', 'time.h', 'sys/mman.h', 'bits/mman.h', 'sys/resource.h', 'sys/time.h', 'sys/select.h', 'bits/resource.h', 'sys/ucontext.h', 'ucontext.h', 'fcntl.h', 'bits/fcntl.h', 'sys/types.h', 'endian.h'] {
		path := '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/aarch64-linux-musl/include/' + relative
		if path !in before { before[path] = hash(path)! }
	}
	for path, pin in before { retain(root, path, pin)! }
	write_json(root + '/inputs-before.json', before)!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', root + '/cache', true)
	for phase in ['discovery', 'run-android-calculator'] { compile(root, phase, mut before)! }
	write_json(root + '/input-sha256.json', before)!
	write_json(root + '/launcher-delta.json', {'qualified283_manifest': qualified_pin,
		'clean_source_sha256': clean_pin, 'trace_source_sha256': hash(root + '/source/launcher.v')!,
		'trace_binary_sha256': hash(root + '/run-android-calculator')!, 'compiler_sha256': compiler_pin,
		'exact_insertion': setters(), 'scope': 'Only five explicit diagnostic environment setters at main; unchanged child argv/polling. No native/framework build, media rewrite or guest launch.'})!
	mut entries := map[string]string{}
	inventory(root, '', mut entries)!
	write_json(root + '/sha256.json', entries)!
	check(root, hash(root + '/sha256.json')!)!
	println('MAPS334 TRACE LAUNCHER BUILD PASS seal=' + hash(root + '/sha256.json')! + ' binary=' + hash(root + '/run-android-calculator')!)
}
fn check(root string, seal string) ! {
	origin := os.read_file(root + '/build-root.txt')!.trim_space()
	verify_manifest(root, seal)!
	verify_manifest(root + '/qualified283', qualified_pin)!
	assert hash(root + '/tools/v_old276')! == compiler_pin
	assert hash(root + '/qualified283/source/launcher.v')! == clean_pin
	assert os.read_file(root + '/source/launcher.v')! == trace_source(os.read_file(root + '/qualified283/source/launcher.v')!)!
	for name in ['aarch64-linux-musl-gcc', 'real-gcc.txt', 'compile-tools.json'] { assert hash(root + '/' + name)! == hash(root + '/qualified283/' + name)!, name }
	input := pins(root + '/input-sha256.json')!
	for path, pin in input { assert hash(root + '/inputs/' + path.trim_left('/'))! == pin, path }
	for phase in ['discovery', 'run-android-calculator'] {
		before := object(root + '/' + phase + '-before.json')!
		done := object(root + '/' + phase + '-receipt.json')!
		assert before['argv']!.as_array().map(it.str()) == compile_argv(origin, phase)
		assert before['VROOT']!.str() == '/Users/alex/code/v' && before['VTMP']!.str() == origin + '/cache'
		for key in ['argv', 'started_utc', 'VROOT', 'VTMP', 'input_sha256'] { assert json2.encode(before[key]!) == json2.encode(done[key]!), key }
		assert done['completed_utc']!.str() != '' && done['exit_code']!.int() == 0
		assert done['output_sha256']!.str() == hash(root + '/' + phase)!
		assert done['log_sha256']!.str() == hash(root + '/' + phase + '.log')!
		for path, pin in before['input_sha256']!.as_map() { assert input[path]! == pin.str(), path }
		consumed := pins(root + '/' + phase + '-consumed.json')!
		resolved := pins(root + '/' + phase + '-resolved-inputs.json')!
		paths := consumed_paths(root, phase)!
		mut expected := map[string]string{}
		for path in paths { target := resolved[path]!; expected[target] = input[target]! }
		assert consumed == expected && consumed.len > 100
	}
	delta := pins(root + '/launcher-delta.json')!
	assert delta['qualified283_manifest']! == qualified_pin && delta['clean_source_sha256']! == clean_pin
	assert delta['compiler_sha256']! == compiler_pin && delta['exact_insertion']! == setters()
	assert delta['trace_source_sha256']! == hash(root + '/source/launcher.v')!
	assert delta['trace_binary_sha256']! == hash(root + '/run-android-calculator')!
	println('MAPS334 TRACE LAUNCHER CHECK PASS inputs=' + input.len.str())
}
fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	if os.args.len == 3 && os.args[1] == 'build' { build(os.args[2]) or { eprintln(err); exit(1) }; return }
	if os.args.len == 4 && os.args[1] == 'check' { check(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; return }
	eprintln('usage: maps334-trace-launcher build FRESH_ROOT | check ROOT SHA256_MANIFEST_PIN')
	exit(2)
}
