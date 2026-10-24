// SPDX-License-Identifier: GPL-2.0-or-later
// Qualify native-only276 against the explicitly retained274 layered-mask failure.
module main

import compress.gzip
import crypto.sha256
import json2
import os

const old_root = '/Users/alex/.local/state/vinix/android/compound274-2026-10-24'
const old_manifest = '78d8d38f8e855e42cceed3054944641a622d5ceecda1cb5e826953d6bf5b9e22'
const same_jar = '1a026975748c693f11c09c7fc080f8b72c20c0638c01996f226698cc740f92f6'
const same_apk = '214421dcae1874873e58023080e7746e7e385034f71e0af9a5e56247b1b2f3ed'
const red_native = '27f1ec2604f93f55d8b3557fb7e34dc754daedde854a6041939503cb72cf12a7'
const green_native = '5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		sum.write(bytes[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }
fn pins(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }

fn catalog(root string, relative string, mut files map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		if os.is_link(path) { files[key] = 'link:' + os.readlink(path)! }
		else if os.is_dir(path) { files[key] = 'directory'; catalog(root, key, mut files)! }
		else { assert os.is_file(path), path; files[key] = hash(path)! }
	}
}

fn inventory(root string) !map[string]string { mut files := map[string]string{}; catalog(root, '', mut files)!; return files }

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
		assert os.lstat(from)!.get_filetype() == .socket
		assert from == os.abs_path('build/android-maps/compound276/run-fixed/bootstrap-fixture/qmp.sock'), from
		excluded[from] = 'closed Unix socket; endpoint has no file content'
	}
}

fn source_map(root string, count int) !map[string]string {
	exact := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + '/exact-sources.json.gz')!)!.bytestr())!
	source_pins := pins(root + '/sources.json')!
	assert exact.len == count && source_pins.len == count
	for name, text in exact { assert sha256.sum(text.bytes()).hex() == source_pins[name]!, name }
	dir := root + if os.is_dir(root + '/sources') { '/sources' } else { '/atlframework' }
	mut actual := map[string]string{}
	for path in os.walk_ext(dir, '.v') { actual[path.all_after(dir + '/')] = hash(path)! }
	assert actual == source_pins, 'actual source tree ' + dir
	return exact
}

fn retained(root string, path string) !string {
	if path.starts_with('build/android-maps/compound276/') { return root + '/prelaunch/' + path.all_after('build/android-maps/compound276/') }
	for prefix in ['/prelaunch/inputs/', '/prelaunch/closure-inputs/', '/prelaunch-external-inputs/'] {
		for input in [path, os.abs_path(path)] {
			candidate := root + prefix + input.trim_left('/')
			if os.is_file(candidate) { return candidate }
		}
	}
	return error('unretained input ' + path)
}

fn old_pin(path string, old map[string]string) ! {
	assert hash(old_root + '/' + path)! == old[path]!, 'changed archived274 input ' + path
}

fn verify_build(root string, old map[string]string) ! {
	pre := root + '/prelaunch'
	mut full := map[string]string{}
	for directory in ['prelaunch', 'prelaunch-external-inputs'] {
		for name, value in inventory(root + '/' + directory)! { if value != 'directory' { full[directory + '/' + name] = value } }
	}
	assert full == pins(root + '/prelaunch-sha256.json')!, 'complete independent prelaunch inventory'
	for path, pin in pins(pre + '/frozen-inputs.json')! { assert hash(retained(root, path)!)! == pin, path }
	for label in ['native-generator', 'suite'] { for path, pin in pins(pre + '/' + label + '-v-files.json')! { assert hash(retained(root, path)!)! == pin, path } }
	for label, output in {'generate-native': 'native/android-native.c', 'build-native': 'native/libvinix-android-native.so', 'suite-compiler': 'suite'} {
		before := object(pre + '/' + label + '-before.json')!
		done := object(pre + '/' + label + '-receipt.json')!
		for key, value in before { if key !in ['completed_utc', 'output_sha256'] { assert done[key]! == value, key } }
		assert before['completed_utc']!.str() == '' && before['output_sha256']!.str() == ''
		assert done['attempt']!.str() == '276' && done['exit_code']!.int() == 0
		assert done['started_utc']!.str() != '' && done['completed_utc']!.str() != ''
		assert done['output_sha256']!.str() == hash(pre + '/' + output)!
		argv := done['argv']!.as_array().map(it.str())
		assert done['command_binary_sha256']!.str() == hash(retained(root, argv[0])!)!
		assert done['compiler_sha256']!.str() == hash(retained(root, '/Users/alex/code/v/v_old')!)!
		for key in ['sources', 'input_files'] { for path, pin in done[key]!.as_map() { assert hash(retained(root, path)!)! == pin.str(), path } }
	}
	assert hash(pre + '/framework/api-impl.jar')! == same_jar && hash(pre + '/apk/probe.apk')! == same_apk
	assert hash(pre + '/native/libvinix-android-native.so')! == green_native
	for kind in ['framework', 'native'] { for name in ['sources.json', 'exact-sources.json.gz'] { old_pin('prelaunch/' + kind + '/' + name, old)! } }
	assert source_map(pre + '/framework', 126)! == source_map(old_root + '/prelaunch/framework', 126)!
	native := source_map(pre + '/native', 83)!
	previous := source_map(old_root + '/prelaunch/native', 83)!
	mut changed := []string{}
	for name, text in previous { if native[name]! != text { changed << name } }
	assert changed == ['graphics.v']
	assert sha256.sum(native['graphics.v']!.bytes()).hex() == 'cb05db13887d7a019cee731b0994ce1b54b2f0619f67c2eae0fa09aeabec9739'
	old_pin('prelaunch/native/bindings.txt', old)!
	assert hash(pre + '/native/bindings.txt')! == hash(old_root + '/prelaunch/native/bindings.txt')!
	old_pin('prelaunch/source/paint-xfermode-fixture.v', old)!
	assert hash(pre + '/source/paint-xfermode-fixture.v')! == hash(old_root + '/prelaunch/source/paint-xfermode-fixture.v')!
}

fn verify_reference(root string, old map[string]string) ! {
	provenance := object(root + '/baseline-provenance.json')!
	assert provenance['archived274_manifest_sha256']!.str() == old_manifest
	assert provenance['source_sha256']!.str() == hash(root + '/baseline-provenance.v')!
	assert provenance['verified_utc']!.str() != ''
	mut source_pairs := map[string]string{}
	for kind in ['framework', 'native'] { for name in ['sources.json', 'exact-sources.json.gz'] { path := kind + '/' + name; old_pin('prelaunch/' + path, old)!; source_pairs[path] = hash(old_root + '/prelaunch/' + path)! } }
	old_pin('prelaunch/native/bindings.txt', old)!
	source_pairs['native/bindings.txt'] = hash(old_root + '/prelaunch/native/bindings.txt')!
	assert json2.decode[map[string]string](json2.encode(provenance['local274_equal_archived274']!))! == source_pairs
	paths := ['failed-attempt-sha256.json', 'run-fixed-before.json', 'run-fixed-receipt.json', 'run-fixed.log', 'run-fixed/results.json', 'run-fixed/bootstrap-fixture/serial.log', 'run-fixed/bootstrap-fixture/serial.log.gz', 'run-fixed/bootstrap-fixture/application.png', 'prelaunch/framework/api-impl.jar', 'prelaunch/native/libvinix-android-native.so', 'prelaunch/apk/probe.apk']
	mut reference := map[string]string{}
	for path in paths {
		if path != 'failed-attempt-sha256.json' { old_pin(path, old)! }
		reference[old_root + '/' + path] = hash(old_root + '/' + path)!
	}
	assert reference == pins(root + '/prelaunch/reused-baseline.json')!, 'exact retained274 fixed-side reference'
	assert reference[old_root + '/failed-attempt-sha256.json']! == old_manifest
	assert reference[old_root + '/prelaunch/framework/api-impl.jar']! == same_jar
	assert reference[old_root + '/prelaunch/apk/probe.apk']! == same_apk
	assert reference[old_root + '/prelaunch/native/libvinix-android-native.so']! == red_native
	old_pin('prelaunch/paired-initial-equality.json', old)!
	previous := pins(old_root + '/prelaunch/paired-initial-equality.json')!
	mut equality := map[string]string{}
	for name in ['boot.img', 'efivars.fd'] {
		equality['vm/' + name] = hash(root + '/prelaunch/vm-fixed/' + name)!
		assert equality['vm/' + name]! == previous['vm/' + name]!
	}
	mut names := []string{}
	for path in os.walk_ext(root + '/prelaunch/native-fixed', '').filter(os.is_file(it)) {
		name := path.all_after(root + '/prelaunch/native-fixed/')
		names << name
		if name == 'libvinix-android-native.so' { continue }
		equality['native/' + name] = hash(path)!
		old_pin('prelaunch/native-fixed/' + name, old)!
		assert equality['native/' + name]! == old['prelaunch/native-fixed/' + name]!, name
	}
	mut previous_names := os.walk_ext(old_root + '/prelaunch/native-fixed', '').filter(os.is_file(it)).map(it.all_after(old_root + '/prelaunch/native-fixed/'))
	names.sort(); previous_names.sort(); assert names == previous_names
	equality['same_apk'] = same_apk
	assert equality == pins(root + '/prelaunch/paired-initial-equality.json')!, 'complete media/runtime equality'
}

fn verify_actual(root string, success bool, old map[string]string) !map[string]string {
	pre := root + '/prelaunch'
	base := root + '/run-fixed'
	if !success { for name in ['prelaunch/attempt.json', 'prelaunch/suite', 'prelaunch/fixed.json', 'prelaunch-sha256.json', 'run-tool/paint-xfermode-evidence', 'run-tool/paint-xfermode-evidence.v', 'run-fixed/staged-runtime-sha256.json'] { old_pin(name, old)! } }
	before := object(base + '-before.json')!
	done := object(base + '-receipt.json')!
	for key, value in before { assert done[key]! == value, key }
	configured := object(pre + '/attempt.json')!['base']!.str()
	assert configured == if success { 'build/android-maps/compound276' } else { 'build/android-maps/compound274' }
	assert done['argv']!.as_array().map(it.str()) == [configured + '/suite', configured + '/fixed.json']
	for key, path in {'suite_sha256': pre + '/suite', 'config_sha256': pre + '/fixed.json', 'external_prelaunch_inventory_sha256': root + '/prelaunch-sha256.json', 'stdout_sha256': base + '.log', 'results_sha256': base + '/results.json', 'runner_sha256': root + '/run-tool/paint-xfermode-evidence', 'runner_source_sha256': root + '/run-tool/paint-xfermode-evidence.v'} { assert done[key]!.str() == hash(path)!, key }
	assert done['exit_code']!.int() == 0 && done['started_utc']!.str() != '' && done['completed_utc']!.str() != ''
	rows := json2.decode[[]json2.Any](os.read_file(base + '/results.json')!)!
	assert rows.len == 1
	row := rows[0].as_map()
	assert row['id']!.str() == 'bootstrap-fixture' && row['launcher_entered']!.bool() && row['native_maps_observed']!.bool()
	assert row['functional_passed']! is json2.Null
	assert row['metadata']!.as_map()['apk_sha256']!.str() == same_apk && row['container_sha256']!.str() == same_apk
	assert row['startup_timeout_seconds']!.int() == 30
	serial := gzip.decompress(os.read_bytes(base + '/bootstrap-fixture/serial.log.gz')!)!.bytestr()
	assert serial == os.read_file(base + '/bootstrap-fixture/serial.log')!
	assert row['serial_sha256']!.str() == sha256.sum(serial.bytes()).hex()
	assert row['screenshot_sha256']!.str() == hash(base + '/bootstrap-fixture/application.png')!
	assert serial.contains('APK-SUITE-BEGIN id=bootstrap-fixture ') && serial.contains('BOOTSTRAP-PAINT-DST-IN-PASS')
	mut failures := []string{}
	for line in serial.split_into_lines() { if ['ANDROID-WS-FAIL', 'APK-SUITE-DEPENDENCY-FAIL', 'ANDROID-WS-DEPENDENCY-FAIL', 'ANDROID-WS-PROCESS-FAIL', 'JNI DETECTED ERROR', 'NoClassDefFoundError', 'NoSuchMethodError', 'UnsatisfiedLinkError', 'ClassNotFoundException', 'NoSuchFieldError', 'APK-SUITE-EXIT id='].any(line.contains(it)) { failures << line.trim_space() } }
	assert row['failure_markers']!.as_array().map(it.str()) == failures
	assert row['outcome']!.str() == if row['process_exited']!.bool() || failures.len > 0 { 'startup_failed' } else if row['backend_ready']!.bool() { 'window_observed' } else { 'startup_timeout' }
	if success {
		assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
		for marker in ['BOOTSTRAP-PAINT-DST-IN-LAYER-PASS', 'BOOTSTRAP-PAINT-XFERMODE-PASS', 'BOOTSTRAP-READY'] { assert serial.contains(marker), marker }
		for bad in ['java.lang.AssertionError', 'ANDROID-WS-FAIL', 'JNI DETECTED ERROR', 'APK-SUITE-EXIT id=bootstrap-fixture'] { assert !serial.contains(bad), bad }
		for failure in failures { assert failure in ['java.lang.NoSuchFieldError: no type "Lnge;" found and so no field "bB" could be found in class "Lorg/vinix/bootstrap/Main;" or its superclasses', 'Caused by: java.lang.ClassNotFoundException: nge'], failure }
		observation := object(base + '/bootstrap-fixture/observation-before-capture.json')!
		assert observation['observation_elapsed_seconds']!.int() >= 30 && observation['qemu_alive_before_capture']!.bool()
		for field in ['observation_elapsed_seconds', 'qemu_alive_before_capture'] { assert row[field]! == observation[field]! }
	} else {
		assert !row['backend_ready']!.bool() && row['process_exited']!.bool()
		assert serial.contains('Maps layered oval mask pixel=5 actual=-1127288 expected=-13408615')
		assert serial.contains('APK-SUITE-EXIT id=bootstrap-fixture code=1')
		assert !serial.contains('BOOTSTRAP-PAINT-DST-IN-LAYER-PASS') && !serial.contains('BOOTSTRAP-READY')
	}
	mut stage := map[string]string{}
	for path in os.walk_ext(base + '/module/opt/vinix-android-aarch64', '').filter(os.is_file(it)) { stage[path.all_after(base + '/module/')] = hash(path)! }
	assert stage == pins(base + '/staged-runtime-sha256.json')!, 'complete actual staged runtime'
	return stage
}

fn verify_host(root string) ! {
	for mode in ['fixed', 'fixed-asan', 'old'] {
		path := root + '/host/' + mode
		lines := os.read_lines(path + '/source-sha256.txt')!
		assert lines.len == 6
		source_pins := pins(if mode == 'old' { old_root + '/prelaunch/native/sources.json' } else { root + '/prelaunch/native/sources.json' })!
		mut names := []string{}
		for line in lines {
			words := line.fields(); assert words.len == 2 && words[1] !in names
			names << words[1]
			assert words[0] == source_pins[words[1]]! && words[0] == hash(path + '/' + words[1] + '.txt')!
		}
		names.sort(); assert names == ['affine.v', 'bitmaps.v', 'canvases.v', 'graphics.v', 'path_clipping.v', 'paths.v']
		log := os.read_file(path + '/run.log')!
		if mode == 'old' { assert log.contains('FAIL: fn main.fractional_rectangles') && log.contains('message: inward pixel (0,1)') }
		else {
			for marker in ['argb-alpha-grid', 'alpha-only-source-target', 'opaque-surface', 'affine-path-quad-clip', 'source-over-alias-clone', 'fractional-rect-center-samples', 'maps-oval-layer-grid', 'all'] { assert log.contains('PAINT-XFERMODE-HOST PASS ' + marker) }
			assert !log.contains('AddressSanitizer') && !log.contains('FAIL:')
			for line in os.read_lines(path + '/evidence-sha256.txt')! { words := line.fields(); assert words.len == 2 && hash(path + '/' + words[1])! == words[0] }
		}
	}
}

fn verify(root string) ! {
	assert hash(old_root + '/failed-attempt-sha256.json')! == old_manifest
	old := pins(old_root + '/failed-attempt-sha256.json')!
	verify_build(root, old)!
	verify_reference(root, old)!
	previous := verify_actual(old_root, false, old)!
	fixed := verify_actual(root, true, old)!
	assert previous.len == fixed.len
	native := 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
	jar := 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
	assert previous[native]! == red_native && fixed[native]! == green_native
	assert previous[jar]! == same_jar && fixed[jar]! == same_jar
	for path, pin in previous { if path != native { assert fixed[path]! == pin, path } }
	verify_host(root)!
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert os.args.len in [3, 4], 'retain BASE BUNDLE | seal BUNDLE | check BUNDLE MANIFEST_SHA256'
	root := os.real_path(if os.args[1] == 'retain' { os.args[3] } else { os.args[2] })
	assert os.is_abs_path(root) && root != os.real_path(os.getwd()) && !root.starts_with(os.real_path(os.getwd()) + '/') && os.is_dir(root + '/prelaunch')
	if os.args[1] == 'retain' {
		assert os.args.len == 4 && root == os.args[3]
		base := os.real_path(os.args[2])
		mut excluded := map[string]string{}
		for name in ['run-fixed', 'vm-fixed', 'run-tool'] { clone_tree(base + '/' + name, root + '/' + name, mut excluded)! }
		for suffix in ['-before.json', '-receipt.json', '.log'] { clone_tree(base + '/run-fixed' + suffix, root + '/run-fixed' + suffix, mut excluded)! }
		for name in ['baseline-provenance.json', 'baseline-provenance.v'] { clone_tree(base + '/' + name, root + '/' + name, mut excluded)! }
		for mode in ['fixed', 'fixed-asan', 'old'] { clone_tree(os.abs_path('tests/native-android-ws/results/xfermode276-rect-' + mode), root + '/host/' + mode, mut excluded)! }
		for pair in [[os.abs_path(@FILE), root + '/checker/canvas-center-evidence.v'], [os.executable(), root + '/checker/canvas-center-evidence'], ['/Users/alex/code/v/v_old', root + '/checker/compiler']] { clone_tree(pair[0], pair[1], mut excluded)! }
		os.write_file(root + '/excluded-special-files.json', json2.encode(excluded, prettify: true) + '\n')!
		println('CANVAS-CENTER276 RETAINED; baseline is archived274 fixed-side run')
	} else if os.args[1] == 'seal' {
		assert os.args.len == 3 && !os.exists(root + '/sha256.json')
		verify(root)!
		os.write_file(root + '/sha256.json', json2.encode(inventory(root)!, prettify: true) + '\n')!
		println('CANVAS-CENTER276 SEALED ' + hash(root + '/sha256.json')!)
	} else {
		assert os.args[1] == 'check' && os.args.len == 4 && hash(root + '/sha256.json')! == os.args[3]
		mut actual := inventory(root)!
		actual.delete('sha256.json')
		assert actual == pins(root + '/sha256.json')!, 'complete276 bundle inventory'
		verify(root)!
		println('CANVAS-CENTER276 PASS native-only center bounds; retained274 layer failure to fresh276 full JNI markers/alive30s; same signed APK/JAR')
	}
}
