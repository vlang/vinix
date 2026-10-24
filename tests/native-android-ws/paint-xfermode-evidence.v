// SPDX-License-Identifier: GPL-2.0-or-later
// Complete fresh274 bundle retention and qualification; historical auditors stay unchanged.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const baseline_jar = '305f04316f617fa26ca84d74d8a1693f90a0a3ffdada0936f9bb18d3cc5a5f75'
const baseline_native = '6e92d8d95ae6b0cddf082f34ed33209bf6d49e04463b3af8354b12bb1bf80989'

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

fn read_map(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }
fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }

fn catalog(root string, relative string, mut out map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		if os.is_link(path) { out[key] = 'link:' + os.readlink(path)! }
		else if os.is_dir(path) { out[key] = 'directory'; catalog(root, key, mut out)! }
		else { assert os.is_file(path), path; out[key] = hash(path)! }
	}
}

fn inventory(root string) !map[string]string { mut out := map[string]string{}; catalog(root, '', mut out)!; return out }

fn clone_tree(from string, to string, mut excluded map[string]string) ! {
	assert !os.exists(to) && !os.is_link(to), to
	if os.is_link(from) { os.symlink(os.readlink(from)!, to)!; return }
	if os.is_dir(from) {
		os.mkdir_all(to)!
		for name in os.ls(from)! { clone_tree(from + '/' + name, to + '/' + name, mut excluded)! }
	} else if os.is_file(from) {
		os.mkdir_all(os.dir(to))!
		r := os.exec(['cp', '-c', from, to])
		assert r.exit_code == 0, r.output
	} else {
		assert os.lstat(from)!.get_filetype() == .socket, from
		assert from in ['baseline', 'fixed'].map(os.abs_path('build/android-maps/compound274/run-' + it + '/bootstrap-fixture/qmp.sock')), from
		excluded[from] = 'closed Unix socket; endpoint has no file content'
	}
}

fn sources(root string, count int) !map[string]string {
	exact := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + '/exact-sources.json.gz')!)!.bytestr())!
	pins := read_map(root + '/sources.json')!
	assert exact.len == count && pins.len == count
	for path, source in exact { assert sha256.sum(source.bytes()).hex() == pins[path]!, path }
	if !os.file_name(root).starts_with('baseline-') {
		files := root + if os.is_dir(root + '/sources') { '/sources' } else { '/atlframework' }
		mut actual := map[string]string{}
		for path in os.walk_ext(files, '.v') { actual[path.all_after(files + '/')] = hash(path)! }
		assert actual == pins, files
	}
	return exact
}

fn retained_input(root string, path string) !string {
	pre := root + '/prelaunch'
	if path.starts_with('build/android-maps/compound274/') { return pre + '/' + path.all_after('build/android-maps/compound274/') }
	for prefix in [pre + '/inputs/', pre + '/closure-inputs/', root + '/prelaunch-external-inputs/'] {
		candidate := prefix + path.trim_left('/')
		if os.is_file(candidate) { return candidate }
	}
	return error('missing retained input: ' + path)
}

fn verify_sources(pre string) ! {
	old := sources(pre + '/baseline-framework', 125)!
	fixed := sources(pre + '/framework', 126)!
	for path, text in old {
		expected := if path == 'androidtools/framework_classes.v' { text.replace(' framework_paint_filters(smali)!\n', ' framework_paint_filters(smali)!\n framework_paint_xfermodes(smali)!\n') } else { text }
		assert fixed[path]! == expected, path
	}
	assert 'androidtools/framework_paint_xfermodes.v' !in old
	assert fixed['androidtools/framework_paint_xfermodes.v']! == os.read_file(pre + '/inputs/tests/native-android-tools/androidtools/framework_paint_xfermodes.v')!
	native := sources(pre + '/native', 83)!
	baseline := sources(pre + '/baseline-native', 83)!
	mut changed := []string{}
	for path, text in baseline { if text != native[path]! { changed << path } }
	changed.sort()
	assert changed == ['bitmaps.v', 'graphics.v', 'ws_generated.v']
	assert native['graphics.v']! == baseline['graphics.v']!.replace('\tfilter_color u32\n', '\tfilter_color u32\n\txfer_mode    i32 = 3 // PorterDuff.Mode.SRC_OVER\n')
	setter := "\n@[export: 'Java_android_graphics_Paint_native_1set_1xfermode__JI']\nfn ws_xfermode_native_set(e voidptr, this voidptr, p0 i64, p1 i32) {\n    unsafe {\n (&WsPaint(p0)).xfer_mode = p1\n }\n}\n"
	assert native['ws_generated.v']! == baseline['ws_generated.v']! + setter
	row := 'android/graphics/Paint|native_set_xfermode|(&WsPaint(p0)).xfer_mode = p1\n'
	bindings := os.read_file(pre + '/native/bindings.txt')!
	assert bindings.count(row) == 1 && bindings.replace(row, '') == os.read_file(pre + '/baseline-native/bindings.txt')!
	before := baseline['bitmaps.v']!
	after := native['bitmaps.v']!
	marker := 'fn ws_draw_bitmap_region('
	comment := '// DST_IN uses the bitmap\'s alpha as a mask for pixels already on the target.\n'
	assert before.all_before(marker) == after.all_before(comment)
	draw := '\t\tdraw := ws_draw_state()\n'
	blend := '\t\t\t\tws_blend(column, row, color, 255)\n'
	expected := (marker + before.all_after(marker)).replace(draw, draw + '\t\txfer_mode := if paint_pointer == 0 { i32(3) } else { (&WsPaint(paint_pointer)).xfer_mode }\n').replace(blend, '\t\t\t\tif xfer_mode == 6 { ws_bitmap_dst_in(column, row, color >> 24) }\n\t\t\t\telse { ws_blend(column, row, color, 255) }\n')
	assert marker + after.all_after(marker) == expected
	assert after == os.read_file(pre + '/inputs/build-support/android/nativews/bitmaps.v')!
}

fn verify_inputs(root string) ! {
	pre := root + '/prelaunch'
	retained := read_map(root + '/prelaunch-sha256.json')!
	mut actual := map[string]string{}
	for name in ['prelaunch', 'prelaunch-external-inputs'] {
		for path, digest in inventory(root + '/' + name)! {
			if digest != 'directory' { actual[name + '/' + path] = digest }
		}
	}
	assert actual == retained, 'complete retained prelaunch inventory'
	for path, digest in read_map(pre + '/frozen-inputs.json')! { assert hash(pre + '/inputs/' + path.trim_left('/'))! == digest, path }
	for label in ['framework', 'native-generator', 'fixture', 'suite'] {
		for path, digest in read_map(pre + '/' + label + '-v-files.json')! {
			assert hash(pre + '/closure-inputs/' + path.trim_left('/'))! == digest, path
		}
	}
	outputs := {'build-framework-compiler': 'build-framework', 'build-framework': 'framework/api-impl.jar', 'generate-native': 'native/android-native.c', 'build-native': 'native/libvinix-android-native.so', 'fixture-compiler': 'fixture-generator', 'fixture': 'apk/probe.apk', 'suite-compiler': 'suite'}
	for label, output in outputs {
		receipt := object(pre + '/' + label + '-receipt.json')!
		before := object(pre + '/' + label + '-before.json')!
		for key, value in before { if key !in ['completed_utc', 'output_sha256'] { assert receipt[key]! == value, label + ':' + key } }
		assert before['completed_utc']!.str() == '' && before['output_sha256']!.str() == ''
		assert receipt['exit_code']!.int() == 0 && receipt['attempt']!.str() == '274', label
		assert receipt['output_sha256']!.str() == hash(pre + '/' + output)!, label
		assert receipt['started_utc']!.str() != '' && receipt['completed_utc']!.str() != ''
		assert receipt['compiler_sha256']!.str() == hash(pre + '/inputs/Users/alex/code/v/v_old')!
		for field in ['input_files', 'sources'] {
			for path, value in receipt[field]!.as_map() { assert value.str() == hash(retained_input(root, path)!)!, label + ':' + path }
		}
		command := receipt['argv']!.as_array()[0].str()
		assert receipt['command_binary_sha256']!.str() == hash(retained_input(root, command)!)!, label
	}
	assert hash(pre + '/native-baseline/api-impl.jar')! == baseline_jar
	assert hash(pre + '/native-baseline/libvinix-android-native.so')! == baseline_native
	mut equality := {'same_apk': hash(pre + '/apk/probe.apk')!}
	for name in ['boot.img', 'efivars.fd'] {
		equality['vm/' + name] = hash(pre + '/vm-baseline/' + name)!
		assert equality['vm/' + name]! == hash(pre + '/vm-fixed/' + name)!
	}
	mut common := map[string]map[string]string{}
	for mode in ['baseline', 'fixed'] {
		mut files := map[string]string{}
		for path in os.walk_ext(pre + '/native-' + mode, '').filter(os.is_file(it)) {
			name := path.all_after(pre + '/native-' + mode + '/')
			if name !in ['api-impl.jar', 'libvinix-android-native.so'] { files[name] = hash(path)! }
		}
		common[mode] = files
	}
	assert common['baseline'] == common['fixed']
	for path, digest in common['baseline'] { equality['native/' + path] = digest }
	assert equality == read_map(pre + '/paired-initial-equality.json')!, 'complete paired equality map'
}

fn verify_host(root string) ! {
	pins := read_map(root + '/prelaunch/native/sources.json')!
	for mode in ['normal', 'asan'] {
		base := root + '/host/' + mode
		lines := os.read_lines(base + '/source-sha256.txt')!
		assert lines.len == 6
		mut names := []string{}
		for line in lines {
			parts := line.fields()
			assert parts.len == 2 && parts[0] == pins[parts[1]]!
			assert parts[1] !in names
			names << parts[1]
			assert hash(base + '/' + parts[1] + '.txt')! == parts[0]
		}
		names.sort()
		assert names == ['affine.v', 'bitmaps.v', 'canvases.v', 'graphics.v', 'path_clipping.v', 'paths.v']
		log := os.read_file(base + '/run.log')!
		assert log.contains('PAINT-XFERMODE-HOST PASS all')
		assert !log.contains('AddressSanitizer') && !log.contains('Assertion failed')
	}
}

fn verify_runs(root string) ! {
	pre := root + '/prelaunch'
	jar := 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
	native := 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
	mut stages := map[string]map[string]string{}
	for mode in ['baseline', 'fixed'] {
		base := root + '/run-' + mode
		before := object(base + '-before.json')!
		receipt := object(base + '-receipt.json')!
		for key, value in before { assert receipt[key]! == value, mode + ':' + key }
		assert before['argv']!.as_array().map(it.str()) == ['build/android-maps/compound274/suite', 'build/android-maps/compound274/' + mode + '.json']
		assert receipt['suite_sha256']!.str() == hash(pre + '/suite')!
		assert receipt['config_sha256']!.str() == hash(pre + '/' + mode + '.json')!
		assert receipt['external_prelaunch_inventory_sha256']!.str() == hash(root + '/prelaunch-sha256.json')!
		assert receipt['runner_sha256']!.str() == hash(root + '/run-tool/paint-xfermode-evidence')!
		assert receipt['runner_source_sha256']!.str() == hash(root + '/run-tool/paint-xfermode-evidence.v')!
		assert receipt['stdout_sha256']!.str() == hash(base + '.log')!
		assert receipt['results_sha256']!.str() == hash(base + '/results.json')!
		assert receipt['exit_code']!.int() == 0 && receipt['started_utc']!.str() != '' && receipt['completed_utc']!.str() != ''
		rows := json2.decode[[]json2.Any](os.read_file(base + '/results.json')!)!
		assert rows.len == 1
		row := rows[0].as_map()
		assert row['id']!.str() == 'bootstrap-fixture' && row['launcher_entered']!.bool() && row['native_maps_observed']!.bool()
		assert row['metadata']!.as_map()['apk_sha256']!.str() == hash(pre + '/apk/probe.apk')!
		serial := gzip.decompress(os.read_bytes(base + '/bootstrap-fixture/serial.log.gz')!)!.bytestr()
		assert sha256.sum(serial.bytes()).hex() == row['serial_sha256']!.str()
		assert hash(base + '/bootstrap-fixture/application.png')! == row['screenshot_sha256']!.str()
		assert row['startup_timeout_seconds']!.int() == 30
		assert serial.contains('APK-SUITE-BEGIN id=bootstrap-fixture ')
		assert row['functional_passed']! is json2.Null
		mut failures := []string{}
		for line in serial.split_into_lines() {
			if ['ANDROID-WS-FAIL', 'APK-SUITE-DEPENDENCY-FAIL', 'ANDROID-WS-DEPENDENCY-FAIL', 'ANDROID-WS-PROCESS-FAIL', 'JNI DETECTED ERROR', 'NoClassDefFoundError', 'NoSuchMethodError', 'UnsatisfiedLinkError', 'ClassNotFoundException', 'NoSuchFieldError', 'APK-SUITE-EXIT id='].any(line.contains(it)) { failures << line.trim_space() }
		}
		assert row['failure_markers']!.as_array().map(it.str()) == failures
		assert row['outcome']!.str() == if row['process_exited']!.bool() || failures.len > 0 { 'startup_failed' } else if row['backend_ready']!.bool() { 'window_observed' } else { 'startup_timeout' }
		if mode == 'baseline' {
			assert row['process_exited']!.bool() && row['outcome']!.str() == 'startup_failed'
			assert serial.contains('java.lang.AssertionError: direct pixel=0')
			assert serial.contains('APK-SUITE-EXIT id=bootstrap-fixture code=1')
			assert !serial.contains('BOOTSTRAP-PAINT-DST-IN-PASS')
		} else {
			assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
			for marker in ['PAINT-DST-IN', 'PAINT-DST-IN-LAYER', 'PAINT-XFERMODE'] { assert serial.contains('BOOTSTRAP-' + marker + '-PASS'), marker }
			assert serial.contains('BOOTSTRAP-READY')
			for bad in ['java.lang.AssertionError', 'ANDROID-WS-FAIL', 'JNI DETECTED ERROR', 'APK-SUITE-EXIT id=bootstrap-fixture'] { assert !serial.contains(bad), bad }
			for failure in row['failure_markers']!.as_array() {
				line := failure.str()
				assert line in ['java.lang.NoSuchFieldError: no type "Lnge;" found and so no field "bB" could be found in class "Lorg/vinix/bootstrap/Main;" or its superclasses', 'Caused by: java.lang.ClassNotFoundException: nge'], line
			}
			observation := object(base + '/bootstrap-fixture/observation-before-capture.json')!
			assert observation['observation_elapsed_seconds']!.int() >= 30 && observation['qemu_alive_before_capture']!.bool()
		}
		stages[mode] = read_map(base + '/staged-runtime-sha256.json')!
		mut actual_stage := map[string]string{}
		for path in os.walk_ext(base + '/module/opt/vinix-android-aarch64', '').filter(os.is_file(it)) { actual_stage[path.all_after(base + '/module/')] = hash(path)! }
		assert actual_stage == stages[mode], 'complete staged runtime map'
		assert stages[mode][jar] == if mode == 'baseline' { baseline_jar } else { hash(pre + '/framework/api-impl.jar')! }
		assert stages[mode][native] == if mode == 'baseline' { baseline_native } else { hash(pre + '/native/libvinix-android-native.so')! }
	}
	assert stages['baseline'].len == stages['fixed'].len
	for path, digest in stages['baseline'] { if path !in [jar, native] { assert stages['fixed'][path]! == digest, path } }
}

fn verify(root string) ! { verify_inputs(root)!; verify_sources(root + '/prelaunch')!; verify_host(root)!; verify_runs(root)! }

fn run_pair(base string, mode string) ! {
	assert mode in ['baseline', 'fixed'] && !os.exists(base + '/run-' + mode + '/results.json')
	tool := base + '/run-tool'
	if !os.exists(tool) {
		os.mkdir_all(tool)!
		os.cp(@FILE, tool + '/paint-xfermode-evidence.v')!
		os.cp(os.executable(), tool + '/paint-xfermode-evidence')!
	}
	assert hash(@FILE)! == hash(tool + '/paint-xfermode-evidence.v')!
	assert hash(os.executable())! == hash(tool + '/paint-xfermode-evidence')!
	root := object(base + '/attempt.json')!['audit']!.str()
	argv := [base + '/suite', base + '/' + mode + '.json']
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'suite_sha256': json2.Any(hash(argv[0])!), 'config_sha256': json2.Any(hash(argv[1])!), 'external_prelaunch_inventory_sha256': json2.Any(hash(root + '/prelaunch-sha256.json')!)}
	receipt['runner_sha256'] = hash(os.executable())!
	receipt['runner_source_sha256'] = hash(@FILE)!
	prefix := base + '/run-' + mode
	os.write_file(prefix + '-before.json', json2.encode(receipt, prettify: true) + '\n')!
	r := os.exec(argv)
	os.write_file(prefix + '.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	receipt['stdout_sha256'] = hash(prefix + '.log')!
	assert receipt['suite_sha256']!.str() == hash(argv[0])! && receipt['config_sha256']!.str() == hash(argv[1])!
	assert receipt['external_prelaunch_inventory_sha256']!.str() == hash(root + '/prelaunch-sha256.json')!
	if r.exit_code == 0 {
		receipt['results_sha256'] = hash(prefix + '/results.json')!
		mut stage := map[string]string{}
		for path in os.walk_ext(prefix + '/module/opt/vinix-android-aarch64', '').filter(os.is_file(it)) { stage[path.all_after(prefix + '/module/')] = hash(path)! }
		os.write_file(prefix + '/staged-runtime-sha256.json', json2.encode(stage, prettify: true) + '\n')!
	}
	os.write_file(prefix + '-receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	assert r.exit_code == 0, r.output
	println('PAINT-XFERMODE-RUN ' + mode + ' complete; raw results retained')
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert os.args.len in [3, 4], 'run BASE MODE | retain BASE BUNDLE | seal BUNDLE | check BUNDLE MANIFEST_SHA256 | archive-failure BUNDLE | check-failure BUNDLE MANIFEST_SHA256'
	if os.args[1] == 'run' { assert os.args.len == 4; run_pair(os.args[2], os.args[3])!; return }
	if os.args[1] == 'retain' {
		assert os.args.len == 4
		base := os.real_path(os.args[2])
		root := os.real_path(os.args[3])
		assert root == os.args[3] && !root.starts_with(os.real_path(os.getwd()) + '/') && os.is_dir(root + '/prelaunch')
		mut excluded := map[string]string{}
		for name in ['run-baseline', 'run-fixed', 'vm-baseline', 'vm-fixed', 'run-tool'] { clone_tree(base + '/' + name, root + '/' + name, mut excluded)! }
		for mode in ['baseline', 'fixed'] {
			for suffix in ['-before.json', '-receipt.json', '.log'] { clone_tree(base + '/run-' + mode + suffix, root + '/run-' + mode + suffix, mut excluded)! }
		}
		for mode in ['normal', 'asan'] {
			path := 'tests/native-android-ws/results/paint-xfermode-host' + if mode == 'asan' { '-asan' } else { '' }
			clone_tree(os.abs_path(path), root + '/host/' + mode, mut excluded)!
		}
		for pair in [[os.abs_path(@FILE), root + '/checker/paint-xfermode-evidence.v'], [os.executable(), root + '/checker/paint-xfermode-evidence'], ['/Users/alex/code/v/v_old', root + '/checker/compiler']] { clone_tree(pair[0], pair[1], mut excluded)! }
		os.write_file(root + '/excluded-special-files.json', json2.encode(excluded, prettify: true) + '\n')!
		println('PAINT-XFERMODE-EVIDENCE RETAINED')
		return
	}
	root := os.real_path(os.args[2])
	assert os.is_abs_path(root) && !root.starts_with(os.getwd() + '/')
	if os.args[1] in ['archive-failure', 'check-failure'] {
		// Integrity of this failed attempt is separate from positive qualification.
		assert !os.exists(root + '/sha256.json')
		serial := os.read_file(root + '/run-fixed/bootstrap-fixture/serial.log')!
		assert serial.contains('BOOTSTRAP-PAINT-DST-IN-PASS')
		assert serial.contains('Maps layered oval mask pixel=5 actual=-1127288 expected=-13408615')
		assert serial.contains('APK-SUITE-EXIT id=bootstrap-fixture code=1')
		assert !serial.contains('BOOTSTRAP-READY')
		manifest := root + '/failed-attempt-sha256.json'
		if os.args[1] == 'archive-failure' {
			assert os.args.len == 3 && !os.exists(manifest)
			os.write_file(manifest, json2.encode(inventory(root)!, prettify: true) + '\n')!
			println('PAINT-XFERMODE FAILED ATTEMPT ARCHIVED; UNQUALIFIED ' + hash(manifest)!)
		} else {
			assert os.args.len == 4 && hash(manifest)! == os.args[3]
			mut actual := inventory(root)!
			actual.delete('failed-attempt-sha256.json')
			assert actual == read_map(manifest)!, 'complete failed-attempt inventory required'
			println('PAINT-XFERMODE FAILED ATTEMPT INTEGRITY VERIFIED; UNQUALIFIED')
		}
		return
	}
	if os.args[1] == 'seal' {
		assert os.args.len == 3 && !os.exists(root + '/sha256.json')
		verify(root)!
		os.write_file(root + '/sha256.json', json2.encode(inventory(root)!, prettify: true) + '\n')!
		println('PAINT-XFERMODE-EVIDENCE SEALED ' + hash(root + '/sha256.json')!)
	} else {
		assert os.args[1] == 'check' && os.args.len == 4
		assert hash(root + '/sha256.json')! == os.args[3], 'manifest pin mismatch'
		mut actual := inventory(root)!
		actual.delete('sha256.json')
		assert actual == read_map(root + '/sha256.json')!, 'complete inventory required'
		verify(root)!
		println('PAINT-XFERMODE-EVIDENCE PASS baseline272 direct pixel failure; fixed274 JNI masks, layer reuse and source-over restoration; same APK and bounded30s; complete retained closure')
	}
}
