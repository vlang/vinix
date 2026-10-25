// SPDX-License-Identifier: GPL-2.0-or-later
// Framework315: exact sealed312 generators plus stateful NinePatchDrawable tint.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/nine-patch-tint315-v2-framework'
const audit = '/Users/alex/.local/state/vinix/android/nine-patch-tint315-v2-framework-build-2026-10-25'
const previous = '/Users/alex/.local/state/vinix/android/paint-text-widths312-framework-build-2026-10-25'
const previous_seal = 'c4ea45675a661c38278173945c896bc69b4ce7812d054a44e680ef8ca1e23287'
const compiler_origin = previous + '/tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const compiler = base + '/tools/v_old276'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const input_jar = '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native312 = '/Users/alex/.local/state/vinix/android/paint-text-widths312-native-build-2026-10-25'
const native312_seal = '66d1b23301a43bf29c3dbc45b1298a7e15e397c1e5addfb7648c435b560bc417'
const native312_library = '51280a48fcefd27a49ba7a9b7d9b6d226c0a164af2517d3c851ea1bf3c7cf9de'

fn selected_path(path string) string {
	return if path == '/opt/homebrew/opt/openjdk@25/bin/java' { java } else { path }
}

fn hash(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := f.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn all_files(root string) ![]string {
	assert os.lstat(root)!.get_filetype() == .directory, root
	mut files := []string{}
	for name in os.ls(root)! {
		path := root + '/' + name
		match os.lstat(path)!.get_filetype() {
			.directory { files << all_files(path)! }
			.regular { files << path }
			else { return error('nonregular build entry: ' + path) }
		}
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
	assert !os.exists(to) && !os.is_link(to), to
	os.mkdir_all(os.dir(to))!
	checked(['cp', '-c', os.real_path(from), to])!
}

fn reference(pins map[string]string, relative string, target string) ! {
	assert hash(previous + '/' + relative)! == pins[relative]!, relative
	clone_file(previous + '/' + relative, target)!
	assert hash(target)! == pins[relative]!, relative
}

// All unchanged large inputs and the audit seal use APFS clones. New generated
// smali/DEX, retained generated C and one disassembly allow a500MiB peak.
fn disk_checkpoint(label string) ! {
	argv := ['/bin/df', '-k', os.getwd()]
	raw := checked(argv)!
	lines := raw.split_into_lines().filter(it.trim_space() != '')
	assert lines.len >= 2
	fields := lines[lines.len - 1].split_any(' \t').filter(it != '')
	assert fields.len >= 4
	available := fields[3].u64()
	assert available >= 640 * 1024, 'need640MiB free before new build work; availableKiB=' + available.str()
	write_json(base + '/disk-' + label + '.json', {
		'argv':               json2.Any(argv)
		'utc':                json2.Any(time.utc().str())
		'available_kib':      json2.Any(available)
		'estimated_peak_kib': json2.Any(500 * 1024)
		'raw':                json2.Any(raw)
	})!
}

fn clone_baseline_disassembly(pins map[string]string) ! {
	reference(pins, 'disassembled-312-sha256.json', base + '/qualified312-disassembled-sha256.json')!
	classes := json2.decode[map[string]string](os.read_file(base + '/qualified312-disassembled-sha256.json')!)!
	assert classes.len > 1000
	assert all_files(previous + '/disassembled-312')!.len == classes.len
	for relative, pin in classes {
		assert pins['disassembled-312/' + relative]! == pin, relative
		reference(pins, 'disassembled-312/' + relative, base + '/disassembled-312/' + relative)!
	}
	for name in ['disassemble-312-before.json', 'disassemble-312-receipt.json', 'disassemble-312.log'] {
		reference(pins, name, base + '/baseline-framework/' + name)!
	}
}

fn reference_native312() ! {
	assert hash(native312 + '/sha256.json')! == native312_seal
	pins := json2.decode[map[string]string](os.read_file(native312 + '/sha256.json')!)!
	assert pins['native/libvinix-android-native.so']! == native312_library
	assert hash(native312 + '/native/libvinix-android-native.so')! == native312_library
	clone_file(native312 + '/sha256.json', base + '/qualified-native312-sha256.json')!
	write_json(base + '/qualified-native312-reference.json', {
		'path':            native312
		'manifest_sha256': native312_seal
		'payload':         'native/libvinix-android-native.so'
		'payload_sha256':  native312_library
		'scope':           'Sealed312 baseline native reference only; runtime pairing is supplied by a separate native315 build. Only manifest and payload pin checked here. No native sources or binary rebuilt.'
	})!
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
		'argv':                  json2.Any(argv)
		'started_utc':           json2.Any(time.utc().str())
		'completed_utc':         json2.Any('')
		'attempt':               json2.Any('315')
		'VROOT':                 json2.Any(os.getenv('VROOT'))
		'V':                     json2.Any(os.getenv('V'))
		'VINIX_V_COMPILER':      json2.Any(os.getenv('VINIX_V_COMPILER'))
		'VTMP':                  json2.Any(os.getenv('VTMP'))
		'compiler_sha256':       json2.Any(hash(compiler)!)
		'command_binary_sha256': json2.Any(hash(os.real_path(argv[0]))!)
		'input_files':           json2.decode[json2.Any](json2.encode(files))!
		'output_sha256':         json2.Any('')
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

fn freeze(classes_pin string, tint_pin string) ! {
	assert !os.exists(base) && !os.is_link(base) && !os.exists(audit) && !os.is_link(audit)
	disk_checkpoint('freeze')!
	assert hash(previous + '/sha256.json')! == previous_seal
	pins := json2.decode[map[string]string](os.read_file(previous + '/sha256.json')!)!
	clone_file(previous + '/sha256.json', base + '/qualified312-sha256.json')!
	write_json(base + '/qualified312-reference.json', {
		'path':   previous
		'sha256': previous_seal
		'scope':  'Selected sealed312 framework135 source snapshot and consumed build inputs only; no historical bundle rescan or mutation; no native rebuild.'
	})!
	for name in ['nine-patch-tint-build.v', 'nine-patch-tint-framework.v'] {
		clone_file('tests/native-android-ws/' + name, base + '/source/' + name)!
	}
	clone_file(os.executable(), base + '/tools/nine-patch-tint-build-bootstrap')!
	assert hash(compiler_origin)! == compiler_pin
	assert pins['tools/v_old276']! == compiler_pin
	reference(pins, 'tools/v_old276', compiler)!
	for name in ['sources.json', 'exact-sources.json.gz'] {
		reference(pins, 'framework/' + name, base + '/baseline-framework/' + name)!
	}
	reference(pins, 'framework/api-impl.jar', base + '/baseline-framework/api-impl.jar')!
	clone_baseline_disassembly(pins)!
	reference_native312()!
	assert hash(base + '/baseline-framework/api-impl.jar')! == '33d231c02740bbb79bdc663f1ac79e142452aadb85348bee5a5165b0a03d674f'
	old := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + '/baseline-framework/exact-sources.json.gz')!)!.bytestr())!
	old_pins := json2.decode[map[string]string](os.read_file(base + '/baseline-framework/sources.json')!)!
	assert old.len == 135 && old.len == old_pins.len
	mut exact := old.clone()
	assert hash('tests/native-android-tools/androidtools/framework_classes.v')! == classes_pin
	assert hash('tests/native-android-tools/androidtools/framework_nine_patch_tint.v')! == tint_pin
	for name in ['androidtools/framework_classes.v', 'androidtools/framework_nine_patch_tint.v'] {
		exact[name] = os.read_file('tests/native-android-tools/' + name)!
	}
	registration := ' framework_nine_patch_tint(smali)!\n'
	assert exact['androidtools/framework_classes.v']!.count(registration) == 1
	assert exact['androidtools/framework_classes.v']!.replace(registration, '') == old['androidtools/framework_classes.v']!
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
	assert delta == ['androidtools/framework_classes.v', 'androidtools/framework_nine_patch_tint.v']
	assert exact.len == 136
	write_json(base + '/framework/sources.json', source_pins)!
	write_json(base + '/framework/source-delta.json', delta)!
	os.write_file_array(base + '/framework/exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	reference(pins, 'frozen-inputs.json', base + '/qualified312-frozen-inputs.json')!
	mut inputs := map[string]string{}
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/qualified312-frozen-inputs.json')!)! {
		if path.starts_with('build-support/android/atlframework/') || path.starts_with('build/android-framework/tools/') || path in [
			input_jar,
			'/opt/homebrew/opt/openjdk@25/bin/java',
			'/usr/bin/cc',
			'/usr/bin/clang',
			'/usr/bin/zip',
		] {
			assert hash(selected_path(path))! == pin, path
			reference(pins, 'inputs/' + path.trim_left('/'), base + '/inputs/' + path.trim_left('/'))!
			inputs[path] = pin
			if path.starts_with('build/android-framework/tools/') {
				clone_file(base + '/inputs/' + path.trim_left('/'), base + '/tools/framework/' + os.file_name(path))!
			}
		}
	}
	assert inputs.len > 20
	assert inputs == json2.decode[map[string]string](os.read_file(base + '/qualified312-frozen-inputs.json')!)!
	clone_file(base + '/inputs/' + input_jar.trim_left('/'), base + '/input/api-impl.jar')!
	write_json(base + '/frozen-inputs.json', inputs)!
	write_json(base + '/java-selection.json', {
		'qualified312_path': '/opt/homebrew/opt/openjdk@25/bin/java'
		'selected_path':     java
		'sha256':            hash(java)!
		'reason':            'Homebrew opt symlink upgraded; explicitly select unchanged qualified312 launcher from retained Cellar installation.'
	})!
	reference(pins, 'framework-v-files.json', base + '/qualified312-framework-v-files.json')!
	write_json(base + '/compiler-reference.json', {
		'path':         compiler_origin
		'sha256':       compiler_pin
		'private_copy': os.abs_path(compiler)
		'VROOT':        '/Users/alex/code/v'
		'assertions':   'enabled; no -prod; -nocache -keepc -showcc -cc cc -enable-globals -cflags -O2; private VTMP retained'
	})!
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
		if os.exists(target) {
			assert hash(target)! == pins[path]!, path
		} else {
			clone_file(path, target)!
		}
	}
	assert pins.len > 0
	if framework {
		old := json2.decode[map[string]string](os.read_file(base + '/qualified312-framework-v-files.json')!)!
		for path, pin in pins {
			if path.contains('/framework/sources/') || path.ends_with('/source/nine-patch-tint-framework.v') {
				continue
			}
			assert old[path]! == pin, path
			assert hash(previous + '/closure-inputs/' + path.trim_left('/'))! == pin, path
		}
	}
	write_json(base + '/' + label + '-v-files.json', pins)!
}

fn verify() ! {
	assert hash(compiler)! == compiler_pin
	for name in ['nine-patch-tint-build.v', 'nine-patch-tint-framework.v'] {
		assert hash('tests/native-android-ws/' + name)! == hash(base + '/source/' + name)!, name
	}
	mut baseline_classes := map[string]string{}
	for path in all_files(base + '/disassembled-312')! {
		baseline_classes[path.all_after(base + '/disassembled-312/')] = hash(path)!
	}
	assert baseline_classes == json2.decode[map[string]string](os.read_file(base + '/qualified312-disassembled-sha256.json')!)!
	assert hash(native312 + '/sha256.json')! == native312_seal
	assert hash(native312 + '/native/libvinix-android-native.so')! == native312_library
	mut sources := map[string]string{}
	for path in all_files(base + '/framework/sources')! {
		sources[path.all_after(base + '/framework/sources/')] = hash(path)!
	}
	assert sources == json2.decode[map[string]string](os.read_file(base + '/framework/sources.json')!)!
	for name in ['framework_classes.v', 'framework_nine_patch_tint.v'] {
		assert hash('tests/native-android-tools/androidtools/' + name)! == hash(base + '/framework/sources/androidtools/' + name)!, name
	}
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/frozen-inputs.json')!)! {
		assert hash(selected_path(path))! == pin, path
		assert hash(base + '/inputs/' + path.trim_left('/'))! == pin, path
		if path.starts_with('build/android-framework/tools/') {
			assert hash(base + '/tools/framework/' + os.file_name(path))! == pin, path
		}
	}
	for label in ['framework', 'build-driver'] {
		for path, pin in json2.decode[map[string]string](os.read_file(base + '/' + label + '-v-files.json')!)! {
			assert hash(path)! == pin, path
			assert hash(base + '/closure-inputs/' + path.trim_left('/'))! == pin, path
		}
	}
}

fn build() ! {
	disk_checkpoint('build')!
	verify()!
	compile_step('build-driver', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-cflags',
		'-O2', '-o', base + '/tools/nine-patch-tint-build-rebuilt',
		base + '/source/nine-patch-tint-build.v'], base + '/tools/nine-patch-tint-build-rebuilt')!
	compile_step('build-framework-compiler', [compiler, '-nocache', '-keepc', '-showcc', '-cc',
		'cc', '-enable-globals', '-cflags', '-O2', '-path', framework_paths(), '-o',
		base + '/build-framework', base + '/source/nine-patch-tint-framework.v'], base + '/build-framework')!
	mut generated_c := map[string]string{}
	for path in all_files(base)! {
		if path.ends_with('.c') && !path.contains('/inputs/') && !path.contains('/closure-inputs/') {
			generated_c[path.all_after(base + '/')] = hash(path)!
		}
	}
	assert generated_c.len >= 2, 'both V compiler outputs must retain generated C'
	write_json(base + '/generated-c-sha256.json', generated_c)!
	verify()!
	compile_step('build-framework', [base + '/build-framework'], base + '/framework/api-impl.jar')!
	verify()!
	compare_output()!
	println('FRAMEWORK315 READY jar=' + hash(base + '/framework/api-impl.jar')!)
}

// Compare actual output DEX, not just generator inputs or preassembly smali.
fn compare_output() ! {
	compile_step('disassemble-315', [java, '-cp', base + '/tools/framework/*', 'org.jf.baksmali.Main',
		'disassemble', '--jobs', '2', base + '/framework/api-impl.jar', '-o',
		base + '/disassembled-315'], '')!
	mut old := map[string]string{}
	mut fixed := map[string]string{}
	for path in all_files(base + '/disassembled-312')! {
		old[path.all_after(base + '/disassembled-312/')] = hash(path)!
	}
	for path in all_files(base + '/disassembled-315')! {
		fixed[path.all_after(base + '/disassembled-315/')] = hash(path)!
	}
	assert old == json2.decode[map[string]string](os.read_file(base + '/qualified312-disassembled-sha256.json')!)!
	mut changed := []string{}
	mut added := []string{}
	for path, pin in fixed {
		if path !in old {
			added << path
		} else if old[path]! != pin {
			changed << path
		}
	}
	for path, _ in old {
		assert path in fixed, 'unexpected removed class: ' + path
	}
	changed.sort()
	added.sort()
	assert changed == ['android/graphics/drawable/NinePatchDrawable.smali'], changed.str()
	assert added == []string{}, added.str()
	write_json(base + '/disassembled-312-sha256.json', old)!
	write_json(base + '/disassembled-315-sha256.json', fixed)!
	write_json(base + '/output-class-delta.json', {
		'changed': changed
		'added':   added
		'removed': []string{}
	})!
}

fn seal() ! {
	assert !os.exists(audit) && !os.is_link(audit)
	os.mkdir_all(audit)!
	mut pins := map[string]string{}
	for path in all_files(base)! {
		relative := path.all_after(base + '/')
		clone_file(path, audit + '/' + relative)!
		pins[relative] = hash(audit + '/' + relative)!
		assert pins[relative]! == hash(path)!, path
	}
	write_json(audit + '/sha256.json', pins)!
	assert all_files(audit)!.len == pins.len + 1
	for relative, pin in pins {
		assert hash(audit + '/' + relative)! == pin, relative
	}
	println('FRAMEWORK315 AUDIT ' + audit + ' seal=' + hash(audit + '/sha256.json')!)
}

fn main() {
	$if prod {
		panic('requires assertions; compile without -prod')
	}
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', os.abs_path(compiler), true)
	os.setenv('VINIX_V_COMPILER', os.abs_path(compiler), true)
	os.setenv('VTMP', os.abs_path(base + '/generated-c'), true)
	if os.args.len == 2 && os.args[1] == 'build' {
		build() or {
			eprintln(err)
			exit(1)
		}
		seal() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	assert os.args.len == 4 && os.args[1] == 'freeze', 'nine-patch-tint-build freeze CLASSES_SHA256 TINT_SHA256 | build'
	assert os.args[2].len == 64 && os.args[3].len == 64
	freeze(os.args[2], os.args[3]) or {
		eprintln(err)
		exit(1)
	}
	closure('framework', base + '/source/nine-patch-tint-framework.v', true) or {
		eprintln(err)
		exit(1)
	}
	closure('build-driver', base + '/source/nine-patch-tint-build.v', false) or {
		eprintln(err)
		exit(1)
	}
	verify() or {
		eprintln(err)
		exit(1)
	}
	println('FRAMEWORK315 FROZEN source-pins=' + hash(base + '/framework/sources.json')!)
}
