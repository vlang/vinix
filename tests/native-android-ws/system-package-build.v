// SPDX-License-Identifier: GPL-2.0-or-later
// Framework329: exact sealed325 generators plus the resource-only system application identity fix.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/system-package329-framework'
const audit = '/Users/alex/.local/state/vinix/android/system-package329-framework-build-2026-10-25'
const previous = '/Users/alex/.local/state/vinix/android/maps-runtime325-framework-build-2026-10-25'
const previous_seal = '17df965baca0c030e1111a9b974410e9594b6e9ccfb814d371df6a53b0ead682'
const compiler_origin = previous + '/tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const compiler = base + '/tools/v_old276'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const input_jar = '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native315 = '/Users/alex/.local/state/vinix/android/nine-patch-tint315-native-build-2026-10-25'
const native315_seal = '09c2c82ff7feb169733c7f77fc11683f409b2114e409fe9e70a8346c277d5aee'
const native315_library = '54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab'

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
// smali/DEX, retained generated C and one disassembly allow a 500 MiB peak.
fn disk_checkpoint(label string) ! {
	argv := ['/bin/df', '-k', os.getwd()]
	raw := checked(argv)!
	lines := raw.split_into_lines().filter(it.trim_space() != '')
	assert lines.len >= 2
	fields := lines[lines.len - 1].split_any(' \t').filter(it != '')
	assert fields.len >= 4
	available := fields[3].u64()
	assert available >= 640 * 1024, 'need 640 MiB free before new build work; available KiB=' + available.str()
	write_json(base + '/disk-' + label + '.json', {
		'argv':               json2.Any(argv)
		'utc':                json2.Any(time.utc().str())
		'available_kib':      json2.Any(available)
		'estimated_peak_kib': json2.Any(500 * 1024)
		'raw':                json2.Any(raw)
	})!
}

fn clone_baseline_disassembly(pins map[string]string) ! {
	reference(pins, 'disassembled-325-sha256.json', base + '/qualified325-disassembled-sha256.json')!
	classes := json2.decode[map[string]string](os.read_file(base + '/qualified325-disassembled-sha256.json')!)!
	assert classes.len == 2068
	assert all_files(previous + '/disassembled-325')!.len == classes.len
	for relative, pin in classes {
		assert pins['disassembled-325/' + relative]! == pin, relative
		reference(pins, 'disassembled-325/' + relative, base + '/disassembled-325/' + relative)!
	}
	for name in ['disassemble-325-before.json', 'disassemble-325-receipt.json', 'disassemble-325.log'] {
		reference(pins, name, base + '/baseline-framework/' + name)!
	}
}

fn reference_native315() ! {
	assert hash(native315 + '/sha256.json')! == native315_seal
	pins := json2.decode[map[string]string](os.read_file(native315 + '/sha256.json')!)!
	assert pins['native/libvinix-android-native.so']! == native315_library
	assert hash(native315 + '/native/libvinix-android-native.so')! == native315_library
	clone_file(native315 + '/sha256.json', base + '/qualified-native315-sha256.json')!
	write_json(base + '/qualified-native315-reference.json', {
		'path':            native315
		'manifest_sha256': native315_seal
		'payload':         'native/libvinix-android-native.so'
		'payload_sha256':  native315_library
		'scope':           'Exact sealed315 native runtime reference, reused unchanged with framework329. Only manifest and payload pin checked here. No native sources or binary rebuilt.'
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
		'attempt':               json2.Any('329')
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

fn freeze(signatures_pin string) ! {
	assert !os.exists(base) && !os.is_link(base) && !os.exists(audit) && !os.is_link(audit)
	disk_checkpoint('freeze')!
	assert hash(previous + '/sha256.json')! == previous_seal
	pins := json2.decode[map[string]string](os.read_file(previous + '/sha256.json')!)!
	clone_file(previous + '/sha256.json', base + '/qualified325-sha256.json')!
	write_json(base + '/qualified325-reference.json', {
		'path':   previous
		'sha256': previous_seal
		'scope':  'Selected sealed325 framework 138-source snapshot and consumed build inputs only; no historical bundle rescan or mutation; no native rebuild.'
	})!
	for name in ['system-package-build.v', 'system-package-framework.v'] {
		clone_file('tests/native-android-ws/' + name, base + '/source/' + name)!
	}
	clone_file(os.executable(), base + '/tools/system-package-build-bootstrap')!
	assert hash(compiler_origin)! == compiler_pin
	assert pins['tools/v_old276']! == compiler_pin
	reference(pins, 'tools/v_old276', compiler)!
	for name in ['sources.json', 'exact-sources.json.gz'] {
		reference(pins, 'framework/' + name, base + '/baseline-framework/' + name)!
	}
	reference(pins, 'framework/api-impl.jar', base + '/baseline-framework/api-impl.jar')!
	clone_baseline_disassembly(pins)!
	reference_native315()!
	assert hash(base + '/baseline-framework/api-impl.jar')! == '181743124944671e934bc6003f6915511f3b43aabd060842e793309b8d988cfa'
	old := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + '/baseline-framework/exact-sources.json.gz')!)!.bytestr())!
	old_pins := json2.decode[map[string]string](os.read_file(base + '/baseline-framework/sources.json')!)!
	assert old.len == 138 && old.len == old_pins.len
	mut exact := old.clone()
	assert hash('tests/native-android-tools/androidtools/framework_signatures.v')! == signatures_pin
	exact['androidtools/framework_signatures.v'] = os.read_file('tests/native-android-tools/androidtools/framework_signatures.v')!
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
	assert delta == ['androidtools/framework_signatures.v']
	assert exact.len == 138
	write_json(base + '/framework/sources.json', source_pins)!
	write_json(base + '/framework/source-delta.json', delta)!
	os.write_file_array(base + '/framework/exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	reference(pins, 'frozen-inputs.json', base + '/qualified325-frozen-inputs.json')!
	mut inputs := map[string]string{}
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/qualified325-frozen-inputs.json')!)! {
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
	assert inputs == json2.decode[map[string]string](os.read_file(base + '/qualified325-frozen-inputs.json')!)!
	clone_file(base + '/inputs/' + input_jar.trim_left('/'), base + '/input/api-impl.jar')!
	write_json(base + '/frozen-inputs.json', inputs)!
	write_json(base + '/java-selection.json', {
		'qualified325_path': '/opt/homebrew/opt/openjdk@25/bin/java'
		'selected_path':     java
		'sha256':            hash(java)!
		'reason':            'Homebrew opt symlink upgraded; explicitly select unchanged qualified325 launcher from retained Cellar installation.'
	})!
	reference(pins, 'framework-v-files.json', base + '/qualified325-framework-v-files.json')!
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
		old := json2.decode[map[string]string](os.read_file(base + '/qualified325-framework-v-files.json')!)!
		for path, pin in pins {
			if path.contains('/framework/sources/') || path.ends_with('/source/system-package-framework.v') {
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
	for name in ['system-package-build.v', 'system-package-framework.v'] {
		assert hash('tests/native-android-ws/' + name)! == hash(base + '/source/' + name)!, name
	}
	mut baseline_classes := map[string]string{}
	for path in all_files(base + '/disassembled-325')! {
		baseline_classes[path.all_after(base + '/disassembled-325/')] = hash(path)!
	}
	assert baseline_classes == json2.decode[map[string]string](os.read_file(base + '/qualified325-disassembled-sha256.json')!)!
	assert hash(native315 + '/sha256.json')! == native315_seal
	assert hash(native315 + '/native/libvinix-android-native.so')! == native315_library
	mut sources := map[string]string{}
	for path in all_files(base + '/framework/sources')! {
		sources[path.all_after(base + '/framework/sources/')] = hash(path)!
	}
	assert sources == json2.decode[map[string]string](os.read_file(base + '/framework/sources.json')!)!
	for name in ['framework_signatures.v'] {
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
		'-O2', '-o', base + '/tools/system-package-build-rebuilt', base + '/source/system-package-build.v'], base + '/tools/system-package-build-rebuilt')!
	compile_step('build-framework-compiler', [compiler, '-nocache', '-keepc', '-showcc', '-cc',
		'cc', '-enable-globals', '-cflags', '-O2', '-path', framework_paths(), '-o',
		base + '/build-framework', base + '/source/system-package-framework.v'], base + '/build-framework')!
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
	println('FRAMEWORK329 READY jar=' + hash(base + '/framework/api-impl.jar')!)
}

// Compare actual output DEX, not just generator inputs or preassembly smali.
fn compare_output() ! {
	compile_step('disassemble-329', [java, '-cp', base + '/tools/framework/*', 'org.jf.baksmali.Main',
		'disassemble', '--jobs', '2', base + '/framework/api-impl.jar', '-o',
		base + '/disassembled-329'], '')!
	mut old := map[string]string{}
	mut fixed := map[string]string{}
	for path in all_files(base + '/disassembled-325')! {
		old[path.all_after(base + '/disassembled-325/')] = hash(path)!
	}
	for path in all_files(base + '/disassembled-329')! {
		fixed[path.all_after(base + '/disassembled-329/')] = hash(path)!
	}
	assert old == json2.decode[map[string]string](os.read_file(base + '/qualified325-disassembled-sha256.json')!)!
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
	assert old.len == 2068 && fixed.len == 2068
	assert changed == ['android/atl/ATLLoadedApp.smali'], changed.str()
	assert added.len == 0, added.str()
	assert old.len - changed.len == 2067
	write_json(base + '/disassembled-325-sha256.json', old)!
	write_json(base + '/disassembled-329-sha256.json', fixed)!
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
	println('FRAMEWORK329 AUDIT ' + audit + ' seal=' + hash(audit + '/sha256.json')!)
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
	assert os.args.len == 3 && os.args[1] == 'freeze', 'system-package-build freeze SIGNATURES_SHA256 | build'
	for pin in os.args[2..] {
		assert pin.len == 64
	}
	freeze(os.args[2]) or {
		eprintln(err)
		exit(1)
	}
	closure('framework', base + '/source/system-package-framework.v', true) or {
		eprintln(err)
		exit(1)
	}
	closure('build-driver', base + '/source/system-package-build.v', false) or {
		eprintln(err)
		exit(1)
	}
	verify() or {
		eprintln(err)
		exit(1)
	}
	println('FRAMEWORK329 FROZEN source-pins=' + hash(base + '/framework/sources.json')!)
}
