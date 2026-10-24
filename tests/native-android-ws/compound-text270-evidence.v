// SPDX-License-Identifier: GPL-2.0-or-later
// Audit complete retained baseline266/fixed270 compound-text experiment.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const source = 'tests/native-android-ws/compound-text270-evidence.v'
const baseline_jar = '69f560aef5965acd2e4c1eba35a545dae5c8e48708695b0c747a1267d75643c3'
const baseline_native = '0a9928b59585bc7e1d6518c22a9a388f5bb99e4f43f3c0838d6c1c47588fb680'
const baseline_bindings = '782450321bb73c52331e0bdbc323641b128095a2c2c8b907649b86d3e0dafde3'
const jar_target = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native_target = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn build_prefix(pre string) !string {
	config := object(pre + '/baseline.json')!
	app := config['applications']!.as_array()[0].as_map()
	path := app['apk']!.str()
	assert path.ends_with('/apk/probe.apk')
	name := os.file_name(path.all_before_last('/apk/probe.apk'))
	assert name == 'compound270', name
	return 'build/android-maps/' + name + '/'
}

fn inventory_tree(root string, relative string, mut result map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { result[key] = hash(path)! }
			.directory { result[key] = 'directory'; inventory_tree(root, key, mut result)! }
			else { return error('unexpected non-regular bundle entry: ' + path) }
		}
	}
}

fn inventory(root string) !map[string]string {
	assert os.is_dir(root) && !os.is_link(root), root
	mut result := map[string]string{}
	inventory_tree(root, '', mut result)!
	return result
}

fn equal_maps(actual map[string]string, expected map[string]string) {
	assert actual.len == expected.len, 'inventory size differs'
	for path, digest in expected { assert actual[path] or { panic('missing: ' + path) } == digest, path }
}

fn regular_files(root string) !map[string]string {
	mut result := inventory(root)!
	for path, digest in result { if digest == 'directory' { result.delete(path) } }
	return result
}

fn exact_sources(root string, count int) !map[string]string {
	exact := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + '/exact-sources.json.gz')!)!.bytestr())!
	pins := read_map(root + '/sources.json')!
	assert exact.len == count && pins.len == count, root
	for path, text in exact { assert sha256.sum(text.bytes()).hex() == pins[path]!, path }
	return exact
}

fn block(text string, marker string) string {
	assert text.count(marker) == 1, marker
	start := text.index(marker) or { panic(marker) }
	tail := text[start..]
	end := tail.index('\n}\n') or { panic(marker) }
	return tail[..end + 3]
}

fn without_block(text string, marker string) string {
	part := block(text, marker)
	return text.replace_once(part, '')
}

fn verify_sources(pre string) ! {
	for kind, count in {'framework': 125, 'native': 83} {
		old := exact_sources(pre + '/baseline-' + kind, count)!
		fixed := exact_sources(pre + '/' + kind, count)!
		expected := if kind == 'framework' {
			['androidtools/framework_classes.v']
		} else { ['ws_views.v'] }
		mut changed := []string{}
		for path, text in old { if fixed[path]! != text { changed << path } }
		changed.sort()
		assert changed == expected, changed.str()
		assert json2.decode[[]string](os.read_file(pre + '/' + kind + '/source-delta.json')!)! == expected
		name := expected[0]
		markers := if kind == 'framework' {
			['fn framework_text_widgets(smali string) ! {', 'fn framework_check_widgets(smali string) ! {']
		} else { ['fn ws_draw_content('] }
		mut old_rest := old[name]!
		mut fixed_rest := fixed[name]!
		for marker in markers {
			old_rest = without_block(old_rest, marker)
			fixed_rest = without_block(fixed_rest, marker)
		}
		assert old_rest == fixed_rest, name
		directory := if kind == 'framework' { '/sources/' } else { '/atlframework/' }
		for path, text in fixed { assert os.read_file(pre + '/' + kind + directory + path)! == text, path }
	}
	for directory in ['baseline-native', 'native'] {
		assert hash(pre + '/' + directory + '/bindings.txt')! == baseline_bindings, directory
	}
	frozen := read_map(pre + '/frozen-inputs.json')!
	assert frozen['build-support/android/nativews/bindings.txt']! == baseline_bindings
	for path, digest in frozen {
		assert hash(pre + '/inputs/' + path.trim_left('/'))! == digest, path
	}
	for label in ['framework', 'native-generator', 'fixture', 'suite'] {
		pins := read_map(pre + '/' + label + '-v-files.json')!
		assert pins.len > 0
		for path, digest in pins { assert hash(pre + '/closure-inputs/' + path.trim_left('/'))! == digest, path }
	}
}

fn verify_receipts(pre string) ! {
	build := build_prefix(pre)!
	compiler := hash(pre + '/inputs/Users/alex/code/v/v_old')!
	for label, output in {
		'build-framework-compiler': 'build-framework'
		'build-framework': 'framework/api-impl.jar'
		'generate-native': 'native/android-native.c'
		'build-native': 'native/libvinix-android-native.so'
		'fixture-compiler': 'fixture-generator'
		'fixture': 'apk/probe.apk'
		'suite-compiler': 'suite'
	} {
		before := object(pre + '/' + label + '-before.json')!
		receipt := object(pre + '/' + label + '-receipt.json')!
		assert receipt['exit_code']!.int() == 0 && receipt['compiler_sha256']!.str() == compiler
		assert before['started_utc']!.str() == receipt['started_utc']!.str()
		assert before['completed_utc']!.str() == '' && receipt['completed_utc']!.str() != ''
		assert json2.encode(before['argv']!) == json2.encode(receipt['argv']!)
		for field in ['sources', 'input_files'] {
			assert json2.encode(before[field]!) == json2.encode(receipt[field]!)
			for path, digest in receipt[field]!.as_map() {
				retained := if path.starts_with(build) { pre + '/' + path.all_after(build) } else { pre + '/inputs/' + path.trim_left('/') }
				assert hash(retained)! == digest.str(), path
			}
		}
		assert receipt['output_sha256']!.str() == hash(pre + '/' + output)!, label
		argv := receipt['argv']!.as_array().map(it.str())
		assert '-prod' !in argv
		command := if argv[0].starts_with(build) { pre + '/' + argv[0].all_after(build) } else { pre + '/inputs/' + argv[0].trim_left('/') }
		assert receipt['command_binary_sha256']!.str() == hash(command)!, label
	}
	assert os.read_file(pre + '/suite-self-test.log')!.contains('APK-SUITE-CLASSIFICATION-PASS no-window-pass-after-failure')
}

fn verify_prelaunch(root string) ! {
	mut actual := map[string]string{}
	for directory in ['prelaunch', 'prelaunch-external-inputs'] {
		for path, digest in regular_files(root + '/' + directory)! { actual[directory + '/' + path] = digest }
	}
	equal_maps(actual, read_map(root + '/prelaunch-sha256.json')!)
	pre := root + '/prelaunch'
	build := build_prefix(pre)!
	for path, digest in read_map(pre + '/prelaunch-sha256.json')! {
		retained := if path.starts_with(build) { pre + '/' + path.all_after(build) } else { root + '/prelaunch-external-inputs/' + path.trim_left('/') }
		assert hash(retained)! == digest, path
	}
	mut baseline := regular_files(pre + '/native-baseline')!
	mut fixed := regular_files(pre + '/native-fixed')!
	assert baseline.len > 20
	assert baseline['api-impl.jar']! == baseline_jar && baseline['libvinix-android-native.so']! == baseline_native
	assert fixed['api-impl.jar']! == hash(pre + '/framework/api-impl.jar')!
	assert fixed['libvinix-android-native.so']! == hash(pre + '/native/libvinix-android-native.so')!
	for name in ['api-impl.jar', 'libvinix-android-native.so'] {
		assert fixed[name]! != baseline[name]!
		baseline.delete(name); fixed.delete(name)
	}
	equal_maps(baseline, fixed)
	mut equality := map[string]string{}
	for path, digest in baseline { equality['native/' + path] = digest }
	for name in ['boot.img', 'efivars.fd'] {
		equality['vm/' + name] = hash(pre + '/vm-baseline/' + name)!
		assert equality['vm/' + name]! == hash(pre + '/vm-fixed/' + name)!, name
	}
	equality['same_apk'] = hash(pre + '/apk/probe.apk')!
	equal_maps(equality, read_map(pre + '/paired-initial-equality.json')!)
	assert os.file_size(pre + '/vm-baseline/boot.img') > 1024 * 1024
	assert os.file_size(pre + '/vm-baseline/efivars.fd') > 1024 * 1024
}

fn verify_run_receipt(root string, mode string, row map[string]json2.Any) ! {
	pre := root + '/prelaunch'
	done := root + '/completed'
	build := build_prefix(pre)!
	before := object(done + '/run-' + mode + '-before.json')!
	receipt := object(done + '/run-' + mode + '-receipt.json')!
	assert before['argv']!.as_array().map(it.str()) == [build + 'suite', build + mode + '.json']
	assert json2.encode(before['argv']!) == json2.encode(receipt['argv']!)
	for field in ['started_utc', 'suite_sha256', 'config_sha256', 'external_prelaunch_inventory_sha256'] {
		assert before[field]!.str() != '' && before[field]!.str() == receipt[field]!.str(), field
	}
	assert receipt['completed_utc']!.str() != '' && receipt['exit_code']!.int() == 0
	assert receipt['suite_sha256']!.str() == hash(pre + '/suite')!
	assert hash(done + '/suite')! == receipt['suite_sha256']!.str()
	assert receipt['config_sha256']!.str() == hash(pre + '/' + mode + '.json')!
	assert hash(done + '/' + mode + '.json')! == receipt['config_sha256']!.str()
	assert receipt['external_prelaunch_inventory_sha256']!.str() == hash(root + '/prelaunch-sha256.json')!
	log := done + '/run-' + mode + '.log'
	assert receipt['stdout_sha256']!.str() == hash(log)!
	assert os.read_file(log)!.contains('APK-SUITE result bootstrap-fixture ' + row['outcome']!.str())
	config := object(pre + '/' + mode + '.json')!
	output := config['output']!.str()
	assert output.ends_with('/' + build + 'run-' + mode)
	assert row['serial_log']!.str() == output + '/bootstrap-fixture/serial.log.gz'
	assert row['screenshot']!.str() == output + '/bootstrap-fixture/application.png'
	app := config['applications']!.as_array()[0].as_map()
	assert row['apk']!.str() == app['apk']!.str() && row['staged_apk']!.str() == app['apk']!.str()
	assert row['source']!.str() == app['source']!.str()
}

fn verify_runs(root string) ! {
	pre := root + '/prelaunch'
	done := root + '/completed'
	build := build_prefix(pre)!
	apk := hash(pre + '/apk/probe.apk')!
	assert hash(done + '/apk/probe.apk')! == apk
	original := os.read_file(pre + '/source/suite239-stream-original.v')!
	generated := os.read_file(pre + '/source/suite.v')!
	classifier := original.all_after('fn observation(').all_before('// Real companion packages')
	assert classifier.len > 1000 && classifier == generated.all_after('fn observation(').all_before('// Real companion packages')
	mut staged := map[string]map[string]string{}
	mut signatures := []string{}
	for mode in ['baseline', 'fixed'] {
		config := object(pre + '/' + mode + '.json')!
		app := config['applications']!.as_array()[0].as_map()
		assert app['startup_seconds']!.int() == 30
		assert app['apk']!.str().ends_with(build + 'apk/probe.apk')
		rows := json2.decode[[]json2.Any](os.read_file(done + '/run-' + mode + '/results.json')!)!
		assert rows.len == 1
		row := rows[0].as_map()
		verify_run_receipt(root, mode, row)!
		assert row['id']!.str() == 'bootstrap-fixture' && row['functional_passed']! is json2.Null
		assert row['launcher_entered']!.bool() && row['native_maps_observed']!.bool()
		assert row['startup_timeout_seconds']!.int() == 30
		metadata := row['metadata']!.as_map()
		assert metadata['apk_sha256']!.str() == apk && metadata['name']!.str() == 'org.vinix.bootstrap'
		signature := metadata['signature_verification']!.str()
		assert signature.contains('Verifies') && signature.contains('Signer #1 certificate SHA-256 digest:')
		signatures << signature
		run := done + '/run-' + mode + '/bootstrap-fixture'
		serial := gzip.decompress(os.read_bytes(run + '/serial.log.gz')!)!.bytestr()
		assert sha256.sum(serial.bytes()).hex() == row['serial_sha256']!.str()
		assert hash(run + '/application.png')! == row['screenshot_sha256']!.str()
		assert serial.contains('APK-SUITE-BEGIN id=bootstrap-fixture ')
		if mode == 'baseline' {
			assert row['process_exited']!.bool() && row['outcome']!.str() == 'startup_failed'
			assert serial.contains('java.lang.AssertionError: Compound text: Button constructor invokes overload actual=0 expected=1')
			for method in ['equal', 'dispatch', 'run'] { assert serial.contains('TextProbe.' + method), method }
			assert serial.contains('APK-SUITE-EXIT id=bootstrap-fixture code=1')
			for marker in ['TEXT-OVERLOAD-DISPATCH-PASS', 'COMPOUND-GRAVITY-PASS', 'STYLED-COMPOUND-TEXT-PASS', 'COMPOUND-TEXT-PASS', 'READY'] {
				assert !serial.contains('BOOTSTRAP-' + marker), marker
			}
		} else {
			assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
			assert row['observation_elapsed_seconds']!.i64() >= 30 && row['qemu_alive_before_capture']!.bool()
			for marker in ['TEXT-OVERLOAD-DISPATCH-PASS', 'COMPOUND-GRAVITY-PASS', 'STYLED-COMPOUND-TEXT-PASS', 'COMPOUND-TEXT-PASS'] {
				assert serial.contains('BOOTSTRAP-' + marker), marker
			}
			assert serial.contains('BOOTSTRAP-READY') && !serial.contains('java.lang.AssertionError')
			assert !serial.contains('JNI DETECTED ERROR') && !serial.contains('ANDROID-WS-FAIL')
			assert !serial.contains('APK-SUITE-EXIT id=bootstrap-fixture')
			failures := row['failure_markers']!.as_array().map(it.str())
			assert row['outcome']!.str() == if failures.len == 0 { 'window_observed' } else { 'startup_failed' }
			for line in failures {
				assert line in [
					'java.lang.NoSuchFieldError: no type "Lnge;" found and so no field "bB" could be found in class "Lorg/vinix/bootstrap/Main;" or its superclasses',
					'Caused by: java.lang.ClassNotFoundException: nge',
				], line
			}
		}
		module_root := done + '/run-' + mode + '/module'
		staged[mode] = regular_files(module_root)!
		assert staged[mode]![jar_target]! == hash(pre + '/native-' + mode + '/api-impl.jar')!
		assert staged[mode]![native_target]! == hash(pre + '/native-' + mode + '/libvinix-android-native.so')!
		for name, target in {'run-android': 'usr/bin/run-android', 'vinix-desktop': 'usr/bin/vinix-desktop', 'guest': 'opt/android-test/native-guest', 'popular-launcher': 'usr/bin/run-android-calculator'} {
			assert staged[mode]![target]! == hash(pre + '/native-' + mode + '/' + name)!, target
		}
	}
	assert signatures[0] == signatures[1]
	mut baseline := staged['baseline']!.clone()
	mut fixed := staged['fixed']!.clone()
	for path in [jar_target, native_target] { baseline.delete(path); fixed.delete(path) }
	equal_maps(baseline, fixed)
}

fn verify(root string) ! {
	verify_prelaunch(root)!
	verify_sources(root + '/prelaunch')!
	verify_receipts(root + '/prelaunch')!
	verify_runs(root)!
	assert hash(root + '/audit/compound-text270-evidence')! == hash(os.executable())!
	audit := object(root + '/audit/compile-receipt.json')!
	before := object(root + '/audit/compile-before.json')!
	assert audit['exit_code']!.int() == 0 && audit['started_utc']!.str() == before['started_utc']!.str()
	assert audit['completed_utc']!.str() != ''
	for field in ['source_sha256', 'compiler_sha256'] { assert audit[field]!.str() == before[field]!.str() }
	assert audit['source_sha256']!.str() == hash(root + '/audit/compound-text270-evidence.v')!
	assert audit['compiler_sha256']!.str() == hash(root + '/audit/compiler')!
	assert audit['output_sha256']!.str() == hash(root + '/audit/compound-text270-evidence')!
	assert json2.encode(audit['argv']!) == json2.encode(before['argv']!)
	assert '-prod' !in audit['argv']!.as_array().map(it.str())
}

fn check(root string, pin string) ! {
	assert hash(root + '/sha256.json')! == pin, 'manifest pin mismatch'
	expected := read_map(root + '/sha256.json')!
	assert expected.len > 1000, 'complete bundle required'
	for path in expected.keys() { assert path != '' && !os.is_abs_path(path) && path.split('/').all(it != '..' && it != '' && it != '.'), path }
	mut actual := inventory(root)!
	actual.delete('sha256.json')
	equal_maps(actual, expected)
	verify(root)!
	println('COMPOUND-TEXT-EVIDENCE PASS entries=${expected.len} baseline266 fails text dispatch; fixed270 runtime passes; original classification retained')
}

fn copy_file(from string, to string) ! {
	assert os.is_file(from) && !os.is_link(from), from
	assert !os.exists(to) && !os.is_link(to), to
	os.mkdir_all(os.dir(to))!
	$if macos {
		result := os.exec(['cp', '-c', from, to])
		assert result.exit_code == 0, result.output
	} $else { os.cp(from, to)! }
}

fn freeze_auditor(root string) ! {
	copy_file(source, root + '/audit/compound-text270-evidence.v')!
	copy_file(os.executable(), root + '/audit/compound-text270-evidence')!
	for name in ['compiler', 'compile-before.json', 'compile-receipt.json', 'compile.log'] {
		copy_file(os.dir(os.executable()) + '/' + name, root + '/audit/' + name)!
	}
}

fn execute() ! {
	$if prod { return error('evidence checker requires assertions; compile without -prod') }
	assert os.args.len in [3, 4], 'usage: compound-text270-evidence compile AUDIT_BUILD | preflight|seal BUNDLE | check|negative BUNDLE MANIFEST_SHA256'
	root := os.args[2].trim_right('/')
	assert os.is_abs_path(root) && os.abs_path(root) == root && !os.is_link(root)
	assert os.real_path(os.dir(root)) == os.dir(root), 'canonical parent required'
	assert root != os.getwd() && !root.starts_with(os.getwd() + '/'), 'external state required'
	match os.args[1] {
		'preflight' {
			assert os.args.len == 3
			verify_prelaunch(root)!
			verify_sources(root + '/prelaunch')!
			verify_receipts(root + '/prelaunch')!
			println('COMPOUND-TEXT-EVIDENCE PREFLIGHT PASS retained prelaunch inputs, sources, build receipts and paired equality')
		}
		'compile' {
			assert os.args.len == 3 && !os.exists(root)
			os.mkdir_all(root)!
			compiler := '/Users/alex/code/v/v_old'
			copy_file(compiler, root + '/compiler')!
			argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', root + '/compound-text270-evidence', source]
			mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'source_sha256': json2.Any(hash(source)!), 'compiler_sha256': json2.Any(hash(compiler)!)}
			os.write_file(root + '/compile-before.json', json2.encode(receipt, prettify: true) + '\n')!
			result := os.exec(argv)
			os.write_file(root + '/compile.log', result.output)!
			receipt['exit_code'] = json2.Any(result.exit_code)
			receipt['completed_utc'] = time.utc().str()
			assert hash(source)! == receipt['source_sha256']!.str() && hash(compiler)! == receipt['compiler_sha256']!.str()
			if result.exit_code == 0 { receipt['output_sha256'] = hash(root + '/compound-text270-evidence')! }
			os.write_file(root + '/compile-receipt.json', json2.encode(receipt, prettify: true) + '\n')!
			assert result.exit_code == 0, result.output
			println('COMPOUND-TEXT-EVIDENCE COMPILED ' + receipt['output_sha256']!.str())
		}
		'seal' {
			assert os.args.len == 3 && !os.exists(root + '/sha256.json')
			freeze_auditor(root)!
			verify(root)!
			os.write_file(root + '/sha256.json', json2.encode(inventory(root)!, prettify: true) + '\n')!
			println('COMPOUND-TEXT-EVIDENCE SEALED manifest_sha256=' + hash(root + '/sha256.json')!)
		}
		'check' { assert os.args.len == 4; check(root, os.args[3])! }
		'negative' {
			assert os.args.len == 4 && hash(root + '/sha256.json')! == os.args[3]
			wrong := os.exec([os.executable(), 'check', root, '0'.repeat(64)])
			assert wrong.exit_code != 0 && wrong.output.contains('manifest pin mismatch'), wrong.output
			scratch := root + '-negative'
			assert !os.exists(scratch) && !os.is_link(scratch), 'fresh scratch required'
			copy_file(root + '/sha256.json', scratch + '/sha256.json')!
			copy_file(root + '/prelaunch-sha256.json', scratch + '/prelaunch-sha256.json')!
			partial := os.exec([os.executable(), 'check', scratch, os.args[3]])
			assert partial.exit_code != 0 && partial.output.contains('inventory size differs'), partial.output
			os.write_file(scratch + '/wrong-pin.log', wrong.output)!
			os.write_file(scratch + '/partial.log', partial.output)!
			println('COMPOUND-TEXT-EVIDENCE NEGATIVE PASS wrong pin and authentic partial bundle rejected')
		}
		else { return error('unknown action') }
	}
}

fn main() { execute() or { eprintln('COMPOUND-TEXT-EVIDENCE FAIL ${err}'); exit(1) } }
