// SPDX-License-Identifier: GPL-2.0-or-later
// Qualify the paired XML VectorDrawable fill-rule regression over sealed276 native.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const baseline_jar = '1a026975748c693f11c09c7fc080f8b72c20c0638c01996f226698cc740f92f6'
const same_native = '5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca'
const archive276 = '/Users/alex/.local/state/vinix/android/compound276-2026-10-24'
const manifest276 = '37bfa8ec3449adf8a294e0b1f3ff3cabfa49123c228f308d9919cab7531d5fa4'
const compound = 'build/android-maps/compound278'
const pass_markers = ['BOOTSTRAP-VECTOR-FILL-RULES-PASS', 'BOOTSTRAP-VECTOR-FILL-STATE-PASS', 'BOOTSTRAP-VECTOR-LOCATION-GLYPH-PASS', 'BOOTSTRAP-READY']
const maps_proof = '/Users/alex/.local/state/vinix/android/vector-fill-maps-sourceproof-2026-10-25'
const maps_proof_manifest = '4fb9e66f8cbfe302f2cf8140572daac750e512a24029f8941c7202ea5e6d45d2'
const maps_apk = '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'

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
		assert from in ['baseline', 'fixed'].map(os.abs_path(compound + '/run-' + it + '/bootstrap-fixture/qmp.sock')), from
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
	if path.starts_with(compound + '/') { return pre + '/' + path.all_after(compound + '/') }
	for prefix in [pre + '/inputs/', pre + '/closure-inputs/', root + '/prelaunch-external-inputs/'] {
		for input in [path, os.abs_path(path)] {
			candidate := prefix + input.trim_left('/')
			if os.is_file(candidate) { return candidate }
		}
	}
	return error('missing retained input: ' + path)
}

fn verify_sources(pre string) ! {
	old := sources(pre + '/baseline-framework', 126)!
	fixed := sources(pre + '/framework', 126)!
	mut changed := []string{}
	for path, text in old {
		if fixed[path]! != text { changed << path }
	}
	changed.sort()
	assert changed == ['androidtools/framework_classes.v', 'androidtools/framework_drawables.v']
	assert json2.decode[[]string](os.read_file(pre + '/framework/source-delta.json')!)! == changed
	registration := ' framework_vector_fill_rules(smali)!\n'
	classes := fixed['androidtools/framework_classes.v']!
	assert classes.count(registration) == 1 && classes.replace(registration, '') == old['androidtools/framework_classes.v']!
	before := old['androidtools/framework_drawables.v']!
	after := fixed['androidtools/framework_drawables.v']!
	assert after.starts_with(before), 'existing drawable generators must be unchanged'
	patch := after[before.len..]
	assert patch.count('fn framework_vector_fill_rules(') == 1
	for marker in ['const/16 v0, 0xd', '->mFillRule:I', '->getInt(II)I', 'Path$FillType;->WINDING', 'Path$FillType;->EVEN_ODD', '->setFillType('] { assert patch.contains(marker), marker }
	for path in changed { assert fixed[path]! == os.read_file(pre + '/inputs/tests/native-android-tools/' + path)!, path }
	native := sources(pre + '/native', 83)!
	baseline := sources(pre + '/baseline-native', 83)!
	assert native == baseline, 'no native source change'
	assert json2.decode[[]string](os.read_file(pre + '/native/source-delta.json')!)!.len == 0
	assert hash(pre + '/native/bindings.txt')! == hash(pre + '/baseline-native/bindings.txt')!
	fixture := os.read_file(pre + '/source/vector-fill-fixture.v')!
	assert fixture == os.read_file(pre + '/inputs/tests/native-android-ws/vector-fill-fixture.v')!
	for marker in ['even_odd', 'non_zero', 'default_rule', 'opposite', 'mixed', 'transformed', 'clip_after_even_odd', 'location blue center', 'location white ring', 'cached', 'newDrawable', 'mutate', 'getDrawable(I)', 'getPixels([IIIIIII)V'] { assert fixture.contains(marker), marker }
}

fn verify_reference(root string) ! {
	pre := root + '/prelaunch'
	assert hash(pre + '/qualified276-sha256.json')! == manifest276
	sealed := read_map(pre + '/qualified276-sha256.json')!
	reference := object(pre + '/qualified276-reference.json')!
	assert reference['root']!.str() == archive276 && reference['manifest_sha256']!.str() == manifest276
	assert reference['checked_utc']!.str() != ''
	mut consumed := map[string]string{}
	for kind in ['framework', 'native'] {
		for name in ['sources.json', 'exact-sources.json.gz'] {
			path := kind + '/' + name
			consumed[path] = hash(pre + '/baseline-' + path)!
		}
	}
	for path, local in {'framework/api-impl.jar': 'native-baseline/api-impl.jar', 'framework/framework-manifest.json': 'baseline-framework/framework-manifest.json', 'native/libvinix-android-native.so': 'native/libvinix-android-native.so', 'native/bindings.txt': 'native/bindings.txt', 'native/androidfw_c_api.h': 'native/androidfw_c_api.h', 'native/sqlite3.h': 'native/sqlite3.h', 'native/stb_image.h': 'native/stb_image.h', 'native/stb_truetype.h': 'native/stb_truetype.h'} { consumed[path] = hash(pre + '/' + local)! }
	assert consumed == json2.decode[map[string]string](json2.encode(reference['consumed']!))!
	for path, digest in consumed { assert digest == sealed['prelaunch/' + path]!, path }
	assert consumed['framework/api-impl.jar']! == baseline_jar && consumed['native/libvinix-android-native.so']! == same_native
	// Retain only this small historical input, pinned by the complete sealed276
	// manifest. The new suite's raw outcome classifier must remain byte-identical.
	old_suite := root + '/reference276/suite.v'
	assert hash(old_suite)! == sealed['prelaunch/source/suite.v']!
	old_text := os.read_file(old_suite)!
	new_text := os.read_file(pre + '/source/suite.v')!
	marker := 'fn observation('
	end := '// Real companion packages'
	assert old_text.contains(marker) && new_text.contains(marker)
	assert old_text.all_after(marker).all_before(end) == new_text.all_after(marker).all_before(end), 'raw classifier changed'
}

fn verify_maps_sourceproof(root string) ! {
	proof := root + '/maps-sourceproof'
	assert hash(proof + '/sha256.json')! == maps_proof_manifest
	mut actual := inventory(proof)!
	for path, value in actual.clone() { if value == 'directory' || path == 'sha256.json' { actual.delete(path) } }
	assert actual == read_map(proof + '/sha256.json')!, 'complete Maps sourceproof'
	inputs := read_map(proof + '/inputs.json')!
	assert inputs['apk_sha256']! == maps_apk
	assert hash(root + '/maps-sourceproof-inputs/GoogleMaps.apk')! == maps_apk
	assert inputs['aapt2_sha256']! == hash(retained_input(root, 'build/android-native-ws/aapt2')!)!
	assert inputs['java_sha256']! == hash(retained_input(root, '/opt/homebrew/opt/openjdk@25/bin/java')!)!
	assert read_map(proof + '/classes.json')! == {'Lamnv;': 'classes2.dex', 'Lpam;': 'classes.dex', 'Lpaw;': 'classes.dex'}
	owner := os.read_file(proof + '/smali/paw.smali')!
	assert owner.contains('.super Lpam;') && owner.contains('0x7f08036a') && owner.contains('0x7f0808eb')
	resources := os.read_file(proof + '/resource-excerpts.txt')!
	for marker in ['0x7f08036a drawable/center_location', 'res/m5z.xml type=XML', '0x7f0808eb drawable/location_not_granted', 'res/TF3.xml type=XML'] { assert resources.contains(marker), marker }
	location := os.read_file(proof + '/m5z-xmltree.txt')!
	assert location.count('E: path') == 3
	assert location.contains('fillColor(0x01010404)=#ff0f53ff')
	white := location.all_after('E: path (line=4)')
	for marker in ['fillColor(0x01010404)=#ffffffff', 'fillType(0x0101051e)=1', 'M17.25,12C17.25,14.899', 'ZM15.75,12C15.75,14.071'] { assert white.contains(marker), marker }
	disabled := os.read_file(proof + '/TF3-xmltree.txt')!
	paths := disabled.split_into_lines().filter(it.contains('pathData(0x01010405)='))
	assert paths.len == 3 && paths[0].all_after('="').all_before('" (Raw:').count('M') == 8, 'location_not_granted has eight designed outer segments'
}

fn verify_inputs(root string) ! {
	pre := root + '/prelaunch'
	mut retained := read_map(root + '/prelaunch-sha256.json')!
	// The original preparation used os.walk_ext, which skips hidden directories.
	// This one .local input was already frozen and independently pinned before
	// either run. Preserve the original manifest and require its exact omission.
	hidden_input := archive276 + '/sha256.json'
	hidden_key := 'prelaunch/inputs/' + hidden_input.trim_left('/')
	assert hidden_key !in retained
	assert read_map(pre + '/frozen-inputs.json')![hidden_input]! == manifest276
	retained[hidden_key] = manifest276
	mut actual := map[string]string{}
	for name in ['prelaunch', 'prelaunch-external-inputs'] {
		for path, digest in inventory(root + '/' + name)! {
			if digest != 'directory' { actual[name + '/' + path] = digest }
		}
	}
	assert actual == retained, 'complete retained prelaunch inventory'
	for path, digest in read_map(pre + '/frozen-inputs.json')! { assert hash(pre + '/inputs/' + path.trim_left('/'))! == digest, path }
	for label in ['framework', 'fixture', 'suite'] {
		for path, digest in read_map(pre + '/' + label + '-v-files.json')! {
			assert hash(pre + '/closure-inputs/' + path.trim_left('/'))! == digest, path
		}
	}
	outputs := {'build-framework-compiler': 'build-framework', 'build-framework': 'framework/api-impl.jar', 'fixture-compiler': 'fixture-generator', 'fixture': 'apk/probe.apk', 'suite-compiler': 'suite'}
	compiler := '/Users/alex/code/v/v_old'
	framework_paths := compound + '/framework/sources|tests/host-policy|tests/linuxkpi|tests/native-generators|tests/native-guest-tools|build-support|tools|@vlib|@vmodules'
	commands := {
		'build-framework-compiler': [compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-cflags', '-O2', '-path', framework_paths, '-o', compound + '/build-framework', compound + '/build-framework.v']
		'build-framework': [compound + '/build-framework']
		'fixture-compiler': [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', compound + '/fixture-generator', compound + '/source/vector-fill-fixture.v']
		'fixture': [compound + '/fixture-generator', compound + '/apk']
		'suite-compiler': [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-path', compound + '/suite-support|@vlib|@vmodules', '-o', compound + '/suite', compound + '/source/suite.v']
	}
	for label, output in outputs {
		receipt := object(pre + '/' + label + '-receipt.json')!
		before := object(pre + '/' + label + '-before.json')!
		for key, value in before { if key !in ['completed_utc', 'output_sha256'] { assert receipt[key]! == value, label + ':' + key } }
		assert before['completed_utc']!.str() == '' && before['output_sha256']!.str() == ''
		assert receipt['exit_code']!.int() == 0 && receipt['attempt']!.str() == '278' && receipt['VINIX_COMPOUND_ATTEMPT']!.str() == '278', label
		assert receipt['output_sha256']!.str() == hash(pre + '/' + output)!, label
		assert receipt['started_utc']!.str() != '' && receipt['completed_utc']!.str() != ''
		argv := receipt['argv']!.as_array().map(it.str())
		assert argv == commands[label]!, label + ': unexpected build command'
		mut expected_sources := map[string]string{}
		for path in argv.filter(it.ends_with('.v')) { expected_sources[path] = hash(retained_input(root, path)!)! }
		assert json2.decode[map[string]string](json2.encode(receipt['sources']!))! == expected_sources, label + ': exact source inputs'
		assert receipt['compiler_sha256']!.str() == hash(pre + '/inputs/Users/alex/code/v/v_old')!
		for field in ['input_files', 'sources'] {
			for path, value in receipt[field]!.as_map() { assert value.str() == hash(retained_input(root, path)!)!, label + ':' + path }
		}
		command := receipt['argv']!.as_array()[0].str()
		assert receipt['command_binary_sha256']!.str() == hash(retained_input(root, command)!)!, label
		assert receipt['input_files']!.as_map()[command]!.str() == receipt['command_binary_sha256']!.str(), label
	}
	for name in ['generate-native', 'build-native'] { assert !os.exists(pre + '/' + name + '-receipt.json'), 'native was reused, not rebuilt' }
	assert hash(pre + '/native-baseline/api-impl.jar')! == baseline_jar
	assert hash(pre + '/native-baseline/libvinix-android-native.so')! == same_native
	assert hash(pre + '/native-fixed/libvinix-android-native.so')! == same_native
	assert hash(pre + '/native/libvinix-android-native.so')! == same_native
	assert hash(pre + '/framework/api-impl.jar')! != baseline_jar
	assert hash(pre + '/native-fixed/api-impl.jar')! == hash(pre + '/framework/api-impl.jar')!
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
			if name != 'api-impl.jar' { files[name] = hash(path)! }
		}
		common[mode] = files
	}
	assert common['baseline'] == common['fixed']
	for path, digest in common['baseline'] { equality['native/' + path] = digest }
	assert equality == read_map(pre + '/paired-initial-equality.json')!, 'complete paired equality map'
	mut configs := map[string]map[string]json2.Any{}
	for mode in ['baseline', 'fixed'] {
		mut config := object(pre + '/' + mode + '.json')!
		apps := config['applications']!.as_array()
		assert apps.len == 1
		app := apps[0].as_map()
		assert app['id']!.str() == 'bootstrap-fixture' && app['package']!.str() == 'org.vinix.bootstrap'
		assert app['startup_seconds']!.int() == 30
		assert app['apk']!.str() == os.abs_path(compound + '/apk/probe.apk')
		assert app['source']!.str() == os.abs_path(compound + '/source/vector-fill-fixture.v')
		for field, suffix in {'boot_image': 'vm-' + mode + '/boot.img', 'efivars': 'vm-' + mode + '/efivars.fd', 'native_dir': 'native-' + mode, 'output': 'run-' + mode} {
			assert config[field]!.str() == os.abs_path(compound + '/' + suffix), field
			config.delete(field)
		}
		configs[mode] = config
	}
	assert configs['baseline'] == configs['fixed'], 'paired configuration difference outside private media/runtime/output'
}

fn verify_runs(root string) ! {
	pre := root + '/prelaunch'
	for suffix in ['', '.v'] { assert hash(root + '/checker-r1-failed/vector-fill-evidence' + suffix)! == hash(root + '/run-tool/vector-fill-evidence' + suffix)! }
	assert hash(root + '/checker/compiler')! == hash(retained_input(root, '/Users/alex/code/v/v_old')!)!
	assert hash(root + '/checker/vector-fill-evidence')! == hash(os.executable())!, 'use the retained corrected checker'
	compile_before := object(root + '/checker/compile-before.json')!
	compile_done := object(root + '/checker/compile-receipt.json')!
	for key, value in compile_before { assert compile_done[key]! == value, key }
	assert compile_done['exit_code']!.int() == 0 && compile_done['completed_utc']!.str() != ''
	assert compile_done['argv']!.as_array().map(it.str()) == ['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', root + '/checker/vector-fill-evidence', root + '/checker/vector-fill-evidence.v']
	assert compile_done['compiler_sha256']!.str() == hash(root + '/checker/compiler')!
	assert compile_done['source_sha256']!.str() == hash(root + '/checker/vector-fill-evidence.v')!
	assert compile_done['builder_source_sha256']!.str() == hash(root + '/checker/build-revision.v')!
	assert compile_done['output_sha256']!.str() == hash(root + '/checker/vector-fill-evidence')!
	assert compile_done['stdout_sha256']!.str() == hash(root + '/checker/compile.log')!
	failed_seal := object(root + '/checker-r1-failed/seal-failure-receipt.json')!
	assert failed_seal['argv']!.as_array().map(it.str()) == ['build/android-maps/vector-fill-evidence', 'seal', root]
	assert failed_seal['exit_code']!.int() == 1
	assert failed_seal['diagnostic']!.str() == "tests/native-android-ws/vector-fill-evidence.v:187: FAIL: fn main.verify_inputs: assert actual == retained, 'complete retained prelaunch inventory'"
	assert failed_seal['diagnostic_sha256']!.str() == hash(root + '/checker-r1-failed/seal-failure-diagnostic.log')!
	assert os.read_file(root + '/checker-r1-failed/seal-failure-diagnostic.log')! == failed_seal['diagnostic']!.str() + '\n'
	assert failed_seal['runner_sha256']!.str() == hash(root + '/checker-r1-failed/vector-fill-evidence')!
	assert failed_seal['runner_source_sha256']!.str() == hash(root + '/checker-r1-failed/vector-fill-evidence.v')!
	jar := 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
	native := 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
	mut stages := map[string]map[string]string{}
	for mode in ['baseline', 'fixed'] {
		base := root + '/run-' + mode
		before := object(base + '-before.json')!
		receipt := object(base + '-receipt.json')!
		for key, value in before { assert receipt[key]! == value, mode + ':' + key }
		assert before['argv']!.as_array().map(it.str()) == [compound + '/suite', compound + '/' + mode + '.json']
		assert receipt['suite_sha256']!.str() == hash(pre + '/suite')!
		assert receipt['config_sha256']!.str() == hash(pre + '/' + mode + '.json')!
		assert receipt['external_prelaunch_inventory_sha256']!.str() == hash(root + '/prelaunch-sha256.json')!
		assert receipt['runner_sha256']!.str() == hash(root + '/run-tool/vector-fill-evidence')!
		assert receipt['runner_source_sha256']!.str() == hash(root + '/run-tool/vector-fill-evidence.v')!
		assert receipt['stdout_sha256']!.str() == hash(base + '.log')!
		assert receipt['results_sha256']!.str() == hash(base + '/results.json')!
		assert receipt['exit_code']!.int() == 0 && receipt['started_utc']!.str() != '' && receipt['completed_utc']!.str() != ''
		rows := json2.decode[[]json2.Any](os.read_file(base + '/results.json')!)!
		assert rows.len == 1
		row := rows[0].as_map()
		assert row['id']!.str() == 'bootstrap-fixture' && row['launcher_entered']!.bool() && row['native_maps_observed']!.bool()
		assert row['metadata']!.as_map()['apk_sha256']!.str() == hash(pre + '/apk/probe.apk')!
		assert row['container_sha256']!.str() == hash(pre + '/apk/probe.apk')!
		serial := gzip.decompress(os.read_bytes(base + '/bootstrap-fixture/serial.log.gz')!)!.bytestr()
		assert serial == os.read_file(base + '/bootstrap-fixture/serial.log')!
		assert sha256.sum(serial.bytes()).hex() == row['serial_sha256']!.str()
		assert hash(base + '/bootstrap-fixture/application.png')! == row['screenshot_sha256']!.str()
		assert row['startup_timeout_seconds']!.int() == 30
		assert serial.contains('APK-SUITE-BEGIN id=bootstrap-fixture ')
		assert row['functional_passed']! is json2.Null
		assert row['backend_ready']!.bool() == serial.contains('ANDROID-WS-READY backend=vinix-native')
		assert row['process_exited']!.bool() == serial.contains('APK-SUITE-EXIT id=bootstrap-fixture ')
		assert row['native_maps_observed']!.bool() == serial.contains('APK-SUITE-MAPS id=bootstrap-fixture ')
		mut failures := []string{}
		for line in serial.split_into_lines() {
			if ['ANDROID-WS-FAIL', 'APK-SUITE-DEPENDENCY-FAIL', 'ANDROID-WS-DEPENDENCY-FAIL', 'ANDROID-WS-PROCESS-FAIL', 'JNI DETECTED ERROR', 'NoClassDefFoundError', 'NoSuchMethodError', 'UnsatisfiedLinkError', 'ClassNotFoundException', 'NoSuchFieldError', 'APK-SUITE-EXIT id='].any(line.contains(it)) { failures << line.trim_space() }
		}
		assert row['failure_markers']!.as_array().map(it.str()) == failures
		assert row['outcome']!.str() == if row['process_exited']!.bool() || failures.len > 0 { 'startup_failed' } else if row['backend_ready']!.bool() { 'window_observed' } else { 'startup_timeout' }
		if mode == 'baseline' {
			assert !row['backend_ready']!.bool() && row['process_exited']!.bool() && row['outcome']!.str() == 'startup_failed'
			assert serial.contains('java.lang.AssertionError: Vector fill: even_odd center x=12 y=12 actual=-13408615 expected=0')
			assert serial.contains('APK-SUITE-EXIT id=bootstrap-fixture code=1')
			for marker in pass_markers { assert !serial.contains(marker), marker }
		} else {
			assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
			for marker in pass_markers { assert serial.contains(marker), marker }
			for bad in ['java.lang.AssertionError', 'ANDROID-WS-FAIL', 'JNI DETECTED ERROR', 'APK-SUITE-EXIT id=bootstrap-fixture'] { assert !serial.contains(bad), bad }
			for failure in row['failure_markers']!.as_array() {
				line := failure.str()
				assert line in ['java.lang.NoSuchFieldError: no type "Lnge;" found and so no field "bB" could be found in class "Lorg/vinix/bootstrap/Main;" or its superclasses', 'Caused by: java.lang.ClassNotFoundException: nge'], line
			}
			observation := object(base + '/bootstrap-fixture/observation-before-capture.json')!
			assert observation['observation_elapsed_seconds']!.int() >= 30 && observation['qemu_alive_before_capture']!.bool()
			for field in ['observation_elapsed_seconds', 'qemu_alive_before_capture'] { assert row[field]! == observation[field]!, field }
		}
		stages[mode] = read_map(base + '/staged-runtime-sha256.json')!
		mut actual_stage := map[string]string{}
		for path in os.walk_ext(base + '/module/opt/vinix-android-aarch64', '').filter(os.is_file(it)) { actual_stage[path.all_after(base + '/module/')] = hash(path)! }
		assert actual_stage == stages[mode], 'complete staged runtime map'
		assert stages[mode][jar] == if mode == 'baseline' { baseline_jar } else { hash(pre + '/framework/api-impl.jar')! }
		assert stages[mode][native]! == same_native
	}
	assert stages['baseline'].len == stages['fixed'].len
	for path, digest in stages['baseline'] { if path != jar { assert stages['fixed'][path]! == digest, path } }
}

fn verify(root string) ! { verify_inputs(root)!; verify_reference(root)!; verify_sources(root + '/prelaunch')!; verify_maps_sourceproof(root)!; verify_runs(root)! }

fn run_pair(base string, mode string) ! {
	assert mode in ['baseline', 'fixed'] && !os.exists(base + '/run-' + mode + '/results.json')
	tool := base + '/run-tool'
	if !os.exists(tool) {
		os.mkdir_all(tool)!
		os.cp(@FILE, tool + '/vector-fill-evidence.v')!
		os.cp(os.executable(), tool + '/vector-fill-evidence')!
	}
	assert hash(@FILE)! == hash(tool + '/vector-fill-evidence.v')!
	assert hash(os.executable())! == hash(tool + '/vector-fill-evidence')!
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
	println('VECTOR-FILL-RUN ' + mode + ' complete; raw results retained')
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert os.args.len in [3, 4], 'run BASE MODE | retain BASE BUNDLE | seal BUNDLE | check BUNDLE MANIFEST_SHA256'
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
		for pair in [[archive276 + '/prelaunch/source/suite.v', root + '/reference276/suite.v'], [os.abs_path(@FILE), root + '/checker/vector-fill-evidence.v'], [os.executable(), root + '/checker/vector-fill-evidence'], ['/Users/alex/code/v/v_old', root + '/checker/compiler']] { clone_tree(pair[0], pair[1], mut excluded)! }
		clone_tree(maps_proof, root + '/maps-sourceproof', mut excluded)!
		clone_tree(os.abs_path('build/android-maps/GoogleMaps.apk'), root + '/maps-sourceproof-inputs/GoogleMaps.apk', mut excluded)!
		os.write_file(root + '/excluded-special-files.json', json2.encode(excluded, prettify: true) + '\n')!
		println('VECTOR-FILL-EVIDENCE RETAINED')
		return
	}
	root := os.real_path(os.args[2])
	assert os.is_abs_path(root) && !root.starts_with(os.getwd() + '/')
	if os.args[1] == 'seal' {
		assert os.args.len == 3 && !os.exists(root + '/sha256.json')
		verify(root)!
		os.write_file(root + '/sha256.json', json2.encode(inventory(root)!, prettify: true) + '\n')!
		println('VECTOR-FILL-EVIDENCE SEALED ' + hash(root + '/sha256.json')!)
	} else {
		assert os.args[1] == 'check' && os.args.len == 4
		assert hash(root + '/sha256.json')! == os.args[3], 'manifest pin mismatch'
		mut actual := inventory(root)!
		actual.delete('sha256.json')
		assert actual == read_map(root + '/sha256.json')!, 'complete inventory required'
		verify(root)!
		println('VECTOR-FILL-EVIDENCE PASS baseline276 evenOdd hole failure; fixed278 XML fill rules, state copies and location glyph; same APK/native, JAR-only delta and bounded30s; complete retained closure')
	}
}
