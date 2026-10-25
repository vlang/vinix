// SPDX-License-Identifier: GPL-2.0-or-later
// Framework-only296b: selected sealed290 sources plus native Path operation integration.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/framework296b'
const audit = '/Users/alex/.local/state/vinix/android/path-ops296b-framework-build-2026-10-25'
const previous = '/Users/alex/.local/state/vinix/android/inflater-trace290-build-2026-10-25'
const previous_seal = '63050cca1e3b6c263e6cdb77774d517437dda869db7caa5bbfb71bbdc7292138'
const compiler_origin = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const compiler = base + '/tools/v_old276'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const input_jar = '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'

fn selected_path(path string) string {
	return if path == '/opt/homebrew/opt/openjdk@25/bin/java' { java } else { path }
}

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

fn reference(pins map[string]string, relative string, target string) ! {
	assert hash(previous + '/' + relative)! == pins[relative]!, relative
	clone_file(previous + '/' + relative, target)!
}

fn framework_paths() string {
	return base + '/framework/sources|tests/host-policy|tests/linuxkpi|tests/native-generators|tests/native-guest-tools|build-support|tools|@vlib|@vmodules'
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
		'attempt': json2.Any('296b')
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
	clone_file(previous + '/sha256.json', base + '/qualified290-sha256.json')!
	write_json(base + '/qualified290-reference.json', {'path': previous, 'sha256': previous_seal, 'scope': 'Selected sealed290 framework129 source snapshot and consumed build inputs only; no historical bundle rescan or mutation; no native rebuild.'})!
	for name in ['path-op-build.v', 'path-op-framework.v'] {
		clone_file('tests/native-android-ws/' + name, base + '/source/' + name)!
	}
	clone_file(os.executable(), base + '/tools/path-op-build-bootstrap')!
	assert hash(compiler_origin)! == compiler_pin
	clone_file(compiler_origin, compiler)!
	for name in ['sources.json', 'exact-sources.json.gz'] {
		reference(pins, 'framework/' + name, base + '/baseline-framework/' + name)!
	}
	reference(pins, 'framework/api-impl.jar', base + '/baseline-framework/api-impl.jar')!
	assert hash(base + '/baseline-framework/api-impl.jar')! == '50fe71a5719b74fb4fe0cfd0531213b216cad87ee87fc78e5cb348f38237b232'
	old := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + '/baseline-framework/exact-sources.json.gz')!)!.bytestr())!
	old_pins := json2.decode[map[string]string](os.read_file(base + '/baseline-framework/sources.json')!)!
	assert old.len == 129 && old.len == old_pins.len
	mut exact := old.clone()
	for name in ['androidtools/framework_paths.v', 'androidtools/framework_path_ops.v'] {
		exact[name] = os.read_file('tests/native-android-tools/' + name)!
	}
	registration := ' text = framework_path_ops(text)!\n'
	assert exact['androidtools/framework_paths.v']!.count(registration) == 1
	assert exact['androidtools/framework_paths.v']!.replace(registration, '') == old['androidtools/framework_paths.v']!
	mut source_pins := map[string]string{}
	mut delta := []string{}
	for name, source in exact {
		if name in old {
			assert sha256.sum(old[name]!.bytes()).hex() == old_pins[name]!, name
			assert old_pins[name]! == pins['framework/sources/' + name]!, name
			assert hash(previous + '/framework/sources/' + name)! == old_pins[name]!, name
		}
		os.mkdir_all(os.dir(base + '/framework/sources/' + name))!
		os.write_file(base + '/framework/sources/' + name, source)!
		source_pins[name] = sha256.sum(source.bytes()).hex()
		if name !in old || source != old[name]! { delta << name }
	}
	delta.sort()
	assert delta == ['androidtools/framework_path_ops.v', 'androidtools/framework_paths.v']
	assert exact.len == 130
	write_json(base + '/framework/sources.json', source_pins)!
	write_json(base + '/framework/source-delta.json', delta)!
	os.write_file_array(base + '/framework/exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	reference(pins, 'frozen-inputs.json', base + '/qualified290-frozen-inputs.json')!
	mut inputs := map[string]string{}
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/qualified290-frozen-inputs.json')!)! {
		if path.starts_with('build-support/android/atlframework/') || path.starts_with('build/android-framework/tools/') || path in [input_jar, '/opt/homebrew/opt/openjdk@25/bin/java', '/usr/bin/cc', '/usr/bin/clang', '/usr/bin/zip'] {
			assert hash(selected_path(path))! == pin, path
			reference(pins, 'inputs/' + path.trim_left('/'), base + '/inputs/' + path.trim_left('/'))!
			inputs[path] = pin
			if path.starts_with('build/android-framework/tools/') { clone_file(path, base + '/tools/framework/' + os.file_name(path))! }
		}
	}
	assert inputs.len > 20
	clone_file(base + '/inputs/' + input_jar.trim_left('/'), base + '/input/api-impl.jar')!
	write_json(base + '/frozen-inputs.json', inputs)!
	write_json(base + '/java-selection.json', {'qualified290_path': '/opt/homebrew/opt/openjdk@25/bin/java', 'selected_path': java, 'sha256': hash(java)!, 'reason': 'Homebrew opt symlink upgraded; explicitly select unchanged qualified290 launcher from retained Cellar installation.'})!
	reference(pins, 'framework-v-files.json', base + '/qualified290-framework-v-files.json')!
	write_json(base + '/compiler-reference.json', {'path': compiler_origin, 'sha256': compiler_pin, 'private_copy': os.abs_path(compiler), 'VROOT': '/Users/alex/code/v', 'assertions': 'enabled; no -prod; -nocache -cc cc -enable-globals -cflags -O2'})!
}

fn closure(label string, source string, framework bool) ! {
	mut argv := [compiler, '-print-v-files']
	if framework { argv << ['-enable-globals', '-path', framework_paths()] }
	argv << source
	listing := compile_step(label + '-closure', argv, '')!
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		pins[path] = hash(path)!
		target := base + '/closure-inputs/' + path.trim_left('/')
		if os.exists(target) { assert hash(target)! == pins[path]!, path }
		else { clone_file(path, target)! }
	}
	assert pins.len > 0
	if framework {
		old := json2.decode[map[string]string](os.read_file(base + '/qualified290-framework-v-files.json')!)!
		for path, pin in pins {
			if path.contains('/framework/sources/') || path.ends_with('/source/path-op-framework.v') { continue }
			assert old[path]! == pin, path
			assert hash(previous + '/closure-inputs/' + path.trim_left('/'))! == pin, path
		}
	}
	write_json(base + '/' + label + '-v-files.json', pins)!
}

fn verify() ! {
	assert hash(compiler)! == compiler_pin
	mut sources := map[string]string{}
	for path in all_files(base + '/framework/sources')! { sources[path.all_after(base + '/framework/sources/')] = hash(path)! }
	assert sources == json2.decode[map[string]string](os.read_file(base + '/framework/sources.json')!)!
	for name in ['framework_paths.v', 'framework_path_ops.v'] {
		assert hash('tests/native-android-tools/androidtools/' + name)! == hash(base + '/framework/sources/androidtools/' + name)!, name
	}
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/frozen-inputs.json')!)! {
		assert hash(selected_path(path))! == pin, path
		assert hash(base + '/inputs/' + path.trim_left('/'))! == pin, path
		if path.starts_with('build/android-framework/tools/') { assert hash(base + '/tools/framework/' + os.file_name(path))! == pin, path }
	}
	for label in ['framework', 'build-driver'] {
		for path, pin in json2.decode[map[string]string](os.read_file(base + '/' + label + '-v-files.json')!)! {
			assert hash(path)! == pin, path
			assert hash(base + '/closure-inputs/' + path.trim_left('/'))! == pin, path
		}
	}
}

fn build() ! {
	verify()!
	compile_step('build-driver', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', base + '/tools/path-op-build-rebuilt', base + '/source/path-op-build.v'], base + '/tools/path-op-build-rebuilt')!
	compile_step('build-framework-compiler', [compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-cflags', '-O2', '-path', framework_paths(), '-o', base + '/build-framework', base + '/source/path-op-framework.v'], base + '/build-framework')!
	verify()!
	compile_step('build-framework', [base + '/build-framework'], base + '/framework/api-impl.jar')!
	verify()!
	compare_output()!
	println('FRAMEWORK296b READY jar=' + hash(base + '/framework/api-impl.jar')!)
}

// Compare actual output DEX, not just generator inputs or preassembly smali.
fn compare_output() ! {
	for mode in ['290', '296b'] {
		jar := base + if mode == '290' { '/baseline-framework/api-impl.jar' } else { '/framework/api-impl.jar' }
		compile_step('disassemble-' + mode, [java, '-cp', base + '/tools/framework/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', jar, '-o', base + '/disassembled-' + mode], '')!
	}
	mut old := map[string]string{}
	mut fixed := map[string]string{}
	for path in all_files(base + '/disassembled-290')! { old[path.all_after(base + '/disassembled-290/')] = hash(path)! }
	for path in all_files(base + '/disassembled-296b')! { fixed[path.all_after(base + '/disassembled-296b/')] = hash(path)! }
	mut changed := []string{}
	mut added := []string{}
	for path, pin in fixed {
		if path !in old { added << path }
		else if old[path]! != pin { changed << path }
	}
	for path, _ in old { assert path in fixed, 'unexpected removed class: ' + path }
	changed.sort()
	added.sort()
	assert changed == ['android/graphics/Path.smali'], changed.str()
	assert added == []string{}, added.str()
	write_json(base + '/disassembled-290-sha256.json', old)!
	write_json(base + '/disassembled-296b-sha256.json', fixed)!
	write_json(base + '/output-class-delta.json', {'changed': changed, 'added': added, 'removed': []string{}})!
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
	println('FRAMEWORK296b AUDIT ' + audit + ' seal=' + hash(audit + '/sha256.json')!)
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', os.abs_path(compiler), true)
	os.setenv('VINIX_V_COMPILER', os.abs_path(compiler), true)
	freeze() or { eprintln(err); exit(1) }
	closure('framework', base + '/source/path-op-framework.v', true) or { eprintln(err); exit(1) }
	closure('build-driver', base + '/source/path-op-build.v', false) or { eprintln(err); exit(1) }
	build() or { eprintln(err); exit(1) }
	seal() or { eprintln(err); exit(1) }
}
