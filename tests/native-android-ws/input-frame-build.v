// SPDX-License-Identifier: GPL-2.0-or-later
// Native-only286: qualified284 sources with the reviewed input scheduling change.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/input286'
const audit = '/Users/alex/.local/state/vinix/android/input286-build-2026-10-25'
const previous = '/Users/alex/.local/state/vinix/android/compound284-2026-10-25'
const previous_seal = 'b503ca7ffa5bb81aed1a97639be94acd5a1ca80dda3895239a223b2c1962ac9a'
const compiler_origin = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const baseline_runtime_pin = '4a55617a8e2f2013c6ac51c29e8c3919a53bc269b34d4b46dffdfdc5ab17ed94'
const live_runtime = 'build-support/android/nativews/runtime.v'
const compiler = base + '/tools/v_old276'

fn hash(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := f.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn all_files(root string) ![]string {
	mut files := []string{}
	for name in os.ls(root)! {
		path := root + '/' + name
		if os.is_dir(path) { files << all_files(path)! } else if os.is_file(path) { files << path }
	}
	files.sort()
	return files
}

fn checked(argv []string) !string {
	r := os.exec(argv)
	if r.exit_code != 0 { return error(argv.str() + '\n' + r.output) }
	return r.output
}

fn write_json[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn clone_file(from string, to string) ! {
	assert !os.exists(to), to
	os.mkdir_all(os.dir(to))!
	checked(['cp', '-c', os.real_path(from), to])!
}

fn once(source string, old string, replacement string) string {
	assert source.count(old) == 1, old
	return source.replace(old, replacement)
}

// The284 input phase includes the pending check. The286 phase times only the
// branch that actually dispatches input, using the same label once per loop.
// Exact inverse substitution proves that timing adds no scheduling behavior.
fn timing(source string, add bool, early bool) string {
	looper := "\t\t\tstatic_void(e, c'android/os/Looper', c'loop', c'()V', nil)\n\t\t\tws_queue_end_pump()\n"
	mut plain := [
		'\t\tfor ws.running {\n',
		looper,
		'\t\t\tws_frames_dispatch()\n',
		'\t\t\tif ws.dirty { ws_render(e) }\n',
	]
	mut probed := [
		'\t\tfor ws.running {\n\t\t\tws_timing231_loop++\n\t\t\ttiming231_loop_start := ws_millis()\n\t\t\ttiming231_looper := ws_millis()\n',
		looper + "\t\t\tws_timing231_phase(c'looper', timing231_looper)\n",
		"\t\t\ttiming231_frames := ws_millis()\n\t\t\tws_frames_dispatch()\n\t\t\tws_timing231_phase(c'frame_callbacks', timing231_frames)\n",
		"\t\t\tif ws.dirty {\n\t\t\t\ttiming231_render := ws_millis()\n\t\t\t\tws_render(e)\n\t\t\t\tws_timing231_phase(c'render_total', timing231_render)\n\t\t\t}\n",
	]
	if early {
		plain << '\t\t\tif input_dispatched { ws_input(e) }\n'
		probed << "\t\t\tif input_dispatched {\n\t\t\t\ttiming231_input := ws_millis()\n\t\t\t\tws_input(e)\n\t\t\t\tws_timing231_phase(c'input', timing231_input)\n\t\t\t}\n"
		plain << '\t\t\tif !input_dispatched && !pending(e) { ws_input(e) }\n'
		probed << "\t\t\tif !input_dispatched && !pending(e) {\n\t\t\t\ttiming231_input := ws_millis()\n\t\t\t\tws_input(e)\n\t\t\t\tws_timing231_phase(c'input', timing231_input)\n\t\t\t}\n\t\t\tws_timing231_phase(c'loop_total', timing231_loop_start)\n"
	} else {
		plain << '\t\t\tif !pending(e) { ws_input(e) }\n'
		probed << "\t\t\ttiming231_input := ws_millis()\n\t\t\tif !pending(e) { ws_input(e) }\n\t\t\tws_timing231_phase(c'input', timing231_input)\n\t\t\tws_timing231_phase(c'loop_total', timing231_loop_start)\n"
	}
	mut text := source
	for i in 0 .. plain.len {
		text = once(text, if add { plain[i] } else { probed[i] }, if add { probed[i] } else { plain[i] })
	}
	return text
}

fn reference(pins map[string]string, relative string, target string) ! {
	assert hash(previous + '/' + relative)! == pins[relative]!, relative
	clone_file(previous + '/' + relative, target)!
}

fn compile_step(label string, argv []string, output string) !string {
	assert !argv.contains('-prod')
	assert !os.exists(base + '/' + label + '-before.json'), label
	mut files := map[string]string{}
	for path in argv.filter(os.is_file(it)) { files[path] = hash(path)! }
	mut receipt := {
		'argv': json2.Any(argv)
		'started_utc': json2.Any(time.utc().str())
		'completed_utc': json2.Any('')
		'attempt': json2.Any('286')
		'VROOT': json2.Any(os.getenv('VROOT'))
		'V': json2.Any(os.getenv('V'))
		'VINIX_V_COMPILER': json2.Any(os.getenv('VINIX_V_COMPILER'))
		'compiler_sha256': json2.Any(hash(compiler)!)
		'command_binary_sha256': json2.Any(hash(os.real_path(argv[0]))!)
		'input_files': json2.decode[json2.Any](json2.encode(files))!
		'output_sha256': json2.Any('')
	}
	write_json(base + '/' + label + '-before.json', receipt)!
	r := os.exec(argv)
	os.write_file(base + '/' + label + '.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	if r.exit_code == 0 && output != '' { receipt['output_sha256'] = hash(output)! }
	write_json(base + '/' + label + '-receipt.json', receipt)!
	if r.exit_code != 0 { return error(label + ' failed:\n' + r.output) }
	return r.output
}

fn freeze() ! {
	assert !os.exists(base) && !os.exists(audit)
	assert hash(previous + '/sha256.json')! == previous_seal
	pins := json2.decode[map[string]string](os.read_file(previous + '/sha256.json')!)!
	clone_file(previous + '/sha256.json', base + '/qualified284-sha256.json')!
	write_json(base + '/qualified284-reference.json', {'path': previous, 'sha256': previous_seal, 'scope': 'Selected native284 sources, headers, native generator closure and consumed crosscompiler inputs; no historical bundle rescan or mutation.'})!
	clone_file('tests/native-android-ws/input-frame-build.v', base + '/source/input-frame-build.v')!
	clone_file(os.executable(), base + '/tools/input-frame-build')!
	assert hash(compiler_origin)! == compiler_pin
	clone_file(compiler_origin, compiler)!
	assert hash(compiler)! == compiler_pin
	for name in ['sources.json', 'exact-sources.json.gz'] {
		reference(pins, 'prelaunch/native/' + name, base + '/baseline-native/' + name)!
	}
	old := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + '/baseline-native/exact-sources.json.gz')!)!.bytestr())!
	old_pins := json2.decode[map[string]string](os.read_file(base + '/baseline-native/sources.json')!)!
	assert old.len == old_pins.len && old.len > 80
	old_runtime := timing(old['runtime.v']!, false, false)
	assert sha256.sum(old_runtime.bytes()).hex() == baseline_runtime_pin
	assert timing(old_runtime, true, false) == old['runtime.v']!
	live := os.read_file(live_runtime)!
	assert live.contains('fn ws_input_before_render(e voidptr) bool {')
	assert live != old_runtime
	clone_file(live_runtime, base + '/source/reviewed-runtime.v')!
	mut exact := old.clone()
	exact['runtime.v'] = timing(live, true, true)
	assert timing(exact['runtime.v']!, false, true) == live
	mut source_pins := map[string]string{}
	mut delta := []string{}
	for name, source in exact {
		assert sha256.sum(old[name]!.bytes()).hex() == old_pins[name]!, name
		assert old_pins[name]! == pins['prelaunch/native/atlframework/' + name]!, name
		os.mkdir_all(base + '/native/atlframework')!
		os.write_file(base + '/native/atlframework/' + name, source)!
		source_pins[name] = sha256.sum(source.bytes()).hex()
		if source != old[name]! { delta << name }
	}
	assert delta == ['runtime.v']
	write_json(base + '/native/sources.json', source_pins)!
	write_json(base + '/native/source-delta.json', delta)!
	os.write_file_array(base + '/native/exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h', 'bindings.txt'] {
		reference(pins, 'prelaunch/native/' + name, base + '/native/' + name)!
	}
	reference(pins, 'prelaunch/frozen-inputs.json', base + '/qualified284-frozen-inputs.json')!
	mut inputs := map[string]string{}
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/qualified284-frozen-inputs.json')!)! {
		if path.contains('/aarch64-linux-musl') || path.contains('/calculator/overlay/') {
			relative := os.norm_path('prelaunch/inputs/' + path.trim_left('/'))
			assert pins[relative]! == pin, path
			target := os.norm_path(base + '/inputs/' + path.trim_left('/'))
			if os.exists(target) { assert hash(target)! == pin, path }
			else { reference(pins, relative, target)! }
			assert hash(path)! == pin, path
			inputs[path] = pin
		}
	}
	assert inputs.len > 100
	write_json(base + '/frozen-inputs.json', inputs)!
	reference(pins, 'prelaunch/crosscompiler-specs.txt', base + '/qualified284-crosscompiler-specs.txt')!
	os.write_file(base + '/crosscompiler-specs.txt', checked(['/opt/homebrew/bin/aarch64-linux-musl-gcc', '-dumpspecs'])!)!
	assert hash(base + '/crosscompiler-specs.txt')! == hash(base + '/qualified284-crosscompiler-specs.txt')!
	reference(pins, 'prelaunch/native-generator-v-files.json', base + '/qualified284-native-generator-v-files.json')!
	clone_file('build-support/find-v.sh', base + '/source/find-v.sh')!
	write_json(base + '/compiler-reference.json', {'path': compiler_origin, 'sha256': compiler_pin, 'private_copy': os.abs_path(compiler), 'VROOT': '/Users/alex/code/v', 'assertions': 'enabled; no -prod; -nocache -cc cc -cflags -O2', 'timing_scope': 'Same timing231 loop, looper, frame_callbacks and render_total probes. Input phase covers only the executed early/fallback dispatch branch; readiness JNI excluded. At most one input phase per iteration.'})!
}

fn closure(label string, source string, compare_previous bool) ! {
	listing := compile_step(label + '-closure', [compiler, '-print-v-files', source], '')!
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		pins[path] = hash(path)!
		target := base + '/closure-inputs/' + path.trim_left('/')
		if os.exists(target) { assert hash(target)! == pins[path]!, path }
		else { clone_file(path, target)! }
	}
	assert pins.len > 0
	if compare_previous {
		assert pins == json2.decode[map[string]string](os.read_file(base + '/qualified284-native-generator-v-files.json')!)!
	}
	write_json(base + '/' + label + '-v-files.json', pins)!
}

fn verify() ! {
	assert hash(compiler)! == compiler_pin
	assert hash(live_runtime)! == hash(base + '/source/reviewed-runtime.v')!, 'live runtime changed during build'
	assert timing(os.read_file(base + '/native/atlframework/runtime.v')!, false, true) == os.read_file(live_runtime)!
	mut sources := map[string]string{}
	for path in all_files(base + '/native/atlframework')! {
		sources[path.all_after(base + '/native/atlframework/')] = hash(path)!
	}
	assert sources == json2.decode[map[string]string](os.read_file(base + '/native/sources.json')!)!
	previous_pins := json2.decode[map[string]string](os.read_file(base + '/qualified284-sha256.json')!)!
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h', 'bindings.txt'] {
		assert hash(base + '/native/' + name)! == previous_pins['prelaunch/native/' + name]!, name
	}
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/frozen-inputs.json')!)! {
		assert hash(path)! == pin, path
		assert hash(os.norm_path(base + '/inputs/' + path.trim_left('/')))! == pin, path
	}
	for label in ['native-generator', 'build-driver'] {
		for path, pin in json2.decode[map[string]string](os.read_file(base + '/' + label + '-v-files.json')!)! {
			assert hash(path)! == pin, path
			assert hash(base + '/closure-inputs/' + path.trim_left('/'))! == pin, path
		}
	}
}

fn build() ! {
	verify()!
	compile_step('build-driver', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', base + '/tools/input-frame-build-rebuilt', base + '/source/input-frame-build.v'], base + '/tools/input-frame-build-rebuilt')!
	assert hash('tests/native-android-ws/input-frame-build.v')! == hash(base + '/source/input-frame-build.v')!
	compile_step('generate-native', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', 'run', 'tests/linuxkpi/generate_module.v', base + '/native/atlframework', base + '/native/android-native.c', '--arch', 'arm64'], base + '/native/android-native.c')!
	verify()!
	runtime := base + '/inputs/build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	compile_step('build-native', ['/opt/homebrew/bin/aarch64-linux-musl-gcc', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-I' + base + '/native', '-Wl,-z,max-page-size=65536', '-Wl,--allow-shlib-undefined', base + '/native/android-native.c', runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed', runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm', '-o', base + '/native/libvinix-android-native.so'], base + '/native/libvinix-android-native.so')!
	verify()!
	println('INPUT286 BUILT native=' + hash(base + '/native/libvinix-android-native.so')!)
}

fn seal() ! {
	assert !os.exists(audit)
	os.mkdir_all(audit)!
	mut pins := map[string]string{}
	for path in all_files(base)! {
		relative := path.all_after(base + '/')
		clone_file(path, audit + '/' + relative)!
		pins[relative] = hash(audit + '/' + relative)!
		assert pins[relative]! == hash(path)!, path
	}
	write_json(audit + '/sha256.json', pins)!
	println('INPUT286 AUDIT ' + audit + ' seal=' + hash(audit + '/sha256.json')!)
}

fn main() {
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', os.abs_path(compiler), true)
	os.setenv('VINIX_V_COMPILER', os.abs_path(compiler), true)
	freeze() or { eprintln(err); exit(1) }
	closure('native-generator', 'tests/linuxkpi/generate_module.v', true) or { eprintln(err); exit(1) }
	closure('build-driver', base + '/source/input-frame-build.v', false) or { eprintln(err); exit(1) }
	build() or { eprintln(err); exit(1) }
	seal() or { eprintln(err); exit(1) }
}
