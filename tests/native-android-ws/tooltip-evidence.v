// SPDX-License-Identifier: GPL-2.0-or-later
// Qualify View tooltip state/inflation with baseline278 and unchanged276 native.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const baseline_jar = 'a1b839c77a575a40ddab8d6e264e92c9abcc9de54ae6c3dcefcc0e725c938eba'
const same_native = '5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca'
const archive276 = '/Users/alex/.local/state/vinix/android/compound276-2026-10-24'
const manifest276 = '37bfa8ec3449adf8a294e0b1f3ff3cabfa49123c228f308d9919cab7531d5fa4'
const prepared278 = '/Users/alex/.local/state/vinix/android/compound278-2026-10-25'
const manifest278 = 'aa10e659faf39ab1a9b4bf01d2dde791f4ab1fbb9eff007d71e8226fce370995'
const compound = 'build/android-maps/compound280'
const pass_markers = ['BOOTSTRAP-TOOLTIP-STATE-PASS', 'BOOTSTRAP-TOOLTIP-INFLATION-PASS', 'BOOTSTRAP-READY']
const original_runner_source = '35cd6ca68712269a32a14fe8d0e3816affdc1fb32b876675d6df390e2f5a97c3'
const original_runner_binary = '04575aa8e9b4602cb26a2013eb776c8f719543b336b1310730564975646648d6'

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

// Unlike os.walk_ext, this also checks hidden files and rejects source symlinks.
fn file_pins(root string) !map[string]string {
	mut out := map[string]string{}
	for path, digest in inventory(root)! {
		if digest == 'directory' { continue }
		assert !digest.starts_with('link:'), path
		out[path] = digest
	}
	return out
}

fn overlay_targets() map[string]string {
	return {'usr/bin/run-android': 'run-android', 'usr/bin/vinix-desktop': 'vinix-desktop',
		'usr/bin/vinix-android-calculator': 'vinix-desktop', 'usr/bin/run-android-calculator': 'popular-launcher',
		'opt/android-test/native-guest': 'guest', 'usr/bin/vinix-session': 'vinix-session'}
}

fn staged_pins(module_root string) !map[string]string {
	mut out := map[string]string{}
	for path, digest in file_pins(module_root + '/opt/vinix-android-aarch64')! {
		out['opt/vinix-android-aarch64/' + path] = digest
	}
	for target, _ in overlay_targets() { if os.is_file(module_root + '/' + target) { out[target] = hash(module_root + '/' + target)! } }
	return out
}

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
		for path, digest in file_pins(files)! { if path.ends_with('.v') { actual[path] = digest } }
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
	fixed := sources(pre + '/framework', 127)!
	mut changed := []string{}
	for path, text in fixed {
		if path !in old || old[path]! != text { changed << path }
	}
	changed.sort()
	assert changed == ['androidtools/framework_classes.v', 'androidtools/framework_view_tooltips.v']
	assert json2.decode[[]string](os.read_file(pre + '/framework/source-delta.json')!)! == changed
	registration := ' framework_view_tooltips(smali)!\n'
	classes := fixed['androidtools/framework_classes.v']!
	assert classes.count(registration) == 1 && classes.replace(registration, '') == old['androidtools/framework_classes.v']!
	patch := fixed['androidtools/framework_view_tooltips.v']!
	assert patch.count('fn framework_view_tooltips(') == 1
	for marker in ['getTooltipText()Ljava/lang/CharSequence;', 'setTooltipText(Ljava/lang/CharSequence;)V', '->vinixTooltipText:Ljava/lang/CharSequence;', 'TextUtils;->isEmpty', '0x01010534', '->obtainStyledAttributes(', '->hasValueOrEmpty(I)Z', '->getText(I)Ljava/lang/CharSequence;', '->recycle()V'] { assert patch.contains(marker), marker }
	for path in changed { assert fixed[path]! == os.read_file(pre + '/inputs/tests/native-android-tools/' + path)!, path }
	native := sources(pre + '/native', 83)!
	baseline := sources(pre + '/baseline-native', 83)!
	assert native == baseline, 'no native source change'
	assert json2.decode[[]string](os.read_file(pre + '/native/source-delta.json')!)!.len == 0
	assert hash(pre + '/native/bindings.txt')! == hash(pre + '/baseline-native/bindings.txt')!
	fixture := os.read_file(pre + '/source/tooltip-fixture.v')!
	assert fixture == os.read_file(pre + '/inputs/tests/native-android-ws/tooltip-fixture.v')!
	for marker in ['default is null', 'preserve mutable CharSequence identity', 'observe CharSequence mutation', 'per-view state isolation', 'replace text', 'null and empty clear to null', 'whitespace is not empty', 'content description remains separate', 'inherited getter during virtual Button text dispatch', 'Literal tooltip', 'Resource tooltip', 'Styled tooltip', 'defStyleRes', 'theme defStyleAttr', 'getTooltipText()'] { assert fixture.contains(marker), marker }
}

fn verify_reference(root string) ! {
	pre := root + '/prelaunch'
	assert hash(pre + '/prepared278-sha256.json')! == manifest278
	prepared := read_map(pre + '/prepared278-sha256.json')!
	reference := object(pre + '/prepared278-reference.json')!
	assert reference['root']!.str() == prepared278 && reference['manifest_sha256']!.str() == manifest278
	assert reference['checked_utc']!.str() != ''
	assert reference['scope']!.str() == 'completed278 build/prelaunch provenance; runtime qualification is separate'
	mut consumed := map[string]string{}
	for kind in ['framework', 'native'] {
		for name in ['sources.json', 'exact-sources.json.gz'] {
			path := kind + '/' + name
			consumed[path] = hash(pre + '/baseline-' + path)!
		}
	}
	for path, local in {'framework/api-impl.jar': 'native-baseline/api-impl.jar', 'framework/framework-manifest.json': 'baseline-framework/framework-manifest.json', 'native/libvinix-android-native.so': 'native/libvinix-android-native.so', 'native/bindings.txt': 'native/bindings.txt', 'native/androidfw_c_api.h': 'native/androidfw_c_api.h', 'native/sqlite3.h': 'native/sqlite3.h', 'native/stb_image.h': 'native/stb_image.h', 'native/stb_truetype.h': 'native/stb_truetype.h', 'qualified276-reference.json': 'qualified276-reference.json', 'qualified276-sha256.json': 'qualified276-sha256.json'} { consumed[path] = hash(pre + '/' + local)! }
	assert consumed == json2.decode[map[string]string](json2.encode(reference['consumed']!))!
	for path, digest in consumed { assert digest == prepared['prelaunch/' + path]!, path }
	assert consumed['framework/api-impl.jar']! == baseline_jar && consumed['native/libvinix-android-native.so']! == same_native
	assert hash(pre + '/qualified276-sha256.json')! == manifest276
	sealed := read_map(pre + '/qualified276-sha256.json')!
	qualified := object(pre + '/qualified276-reference.json')!
	assert qualified['root']!.str() == archive276 && qualified['manifest_sha256']!.str() == manifest276
	for path, digest in consumed { if path.starts_with('native/') { assert digest == sealed['prelaunch/' + path]!, path } }
	for path, source in sources(pre + '/native', 83)! {
		assert sha256.sum(source.bytes()).hex() == sealed['prelaunch/native/atlframework/' + path]!, path
	}
	// The frozen278 inventory establishes build provenance only. The present
	// pair independently qualifies tooltip behavior; preserve its raw classifier.
	old_suite := root + '/reference278/suite.v'
	assert hash(old_suite)! == prepared['prelaunch/source/suite.v']!
	old_text := os.read_file(old_suite)!
	new_text := os.read_file(pre + '/source/suite.v')!
	marker := 'fn observation('
	end := '// Real companion packages'
	assert old_text.contains(marker) && new_text.contains(marker)
	assert old_text.all_after(marker).all_before(end) == new_text.all_after(marker).all_before(end), 'raw classifier changed'
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
	for path, digest in read_map(pre + '/prelaunch-sha256.json')! {
		assert hash(retained_input(root, path)!)! == digest, path
	}
	for path, digest in read_map(pre + '/frozen-inputs.json')! { assert hash(pre + '/inputs/' + path.trim_left('/'))! == digest, path }
	for label in ['framework', 'fixture', 'suite'] {
		pins := read_map(pre + '/' + label + '-v-files.json')!
		mut listed := os.read_lines(pre + '/' + label + '-v-files.txt')!.filter(it.ends_with('.v'))
		mut keys := pins.keys()
		listed.sort()
		keys.sort()
		assert listed == keys, label + ': complete compiler source closure'
		for path, digest in pins {
			assert hash(pre + '/closure-inputs/' + path.trim_left('/'))! == digest, path
		}
	}
	outputs := {'build-framework-compiler': 'build-framework', 'build-framework': 'framework/api-impl.jar', 'fixture-compiler': 'fixture-generator', 'fixture': 'apk/probe.apk', 'suite-compiler': 'suite', 'suite-self-test': ''}
	compiler := '/Users/alex/code/v/v_old'
	framework_paths := compound + '/framework/sources|tests/host-policy|tests/linuxkpi|tests/native-generators|tests/native-guest-tools|build-support|tools|@vlib|@vmodules'
	commands := {
		'build-framework-compiler': [compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-cflags', '-O2', '-path', framework_paths, '-o', compound + '/build-framework', compound + '/build-framework.v']
		'build-framework': [compound + '/build-framework']
		'fixture-compiler': [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', compound + '/fixture-generator', compound + '/source/tooltip-fixture.v']
		'fixture': [compound + '/fixture-generator', compound + '/apk']
		'suite-compiler': [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-path', compound + '/suite-support|@vlib|@vmodules', '-o', compound + '/suite', compound + '/source/suite.v']
		'suite-self-test': [compound + '/suite', '--self-test']
	}
	for label, output in outputs {
		receipt := object(pre + '/' + label + '-receipt.json')!
		before := object(pre + '/' + label + '-before.json')!
		for key, value in before { if key !in ['completed_utc', 'output_sha256'] { assert receipt[key]! == value, label + ':' + key } }
		assert before['completed_utc']!.str() == '' && before['output_sha256']!.str() == ''
		assert receipt['exit_code']!.int() == 0 && receipt['attempt']!.str() == '280' && receipt['VINIX_COMPOUND_ATTEMPT']!.str() == '280', label
		assert receipt['output_sha256']!.str() == if output == '' { '' } else { hash(pre + '/' + output)! }, label
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
	assert os.read_file(pre + '/suite-self-test.log')!.trim_space() == 'APK-SUITE-CLASSIFICATION-PASS no-window-pass-after-failure'
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
		for name, digest in file_pins(pre + '/native-' + mode)! {
			if name != 'api-impl.jar' { files[name] = digest }
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
		assert app['source']!.str() == os.abs_path(compound + '/source/tooltip-fixture.v')
		for field, suffix in {'boot_image': 'vm-' + mode + '/boot.img', 'efivars': 'vm-' + mode + '/efivars.fd', 'native_dir': 'native-' + mode, 'output': 'run-' + mode} {
			assert config[field]!.str() == os.abs_path(compound + '/' + suffix), field
			config.delete(field)
		}
		configs[mode] = config
	}
	assert configs['baseline'] == configs['fixed'], 'paired configuration difference outside private media/runtime/output'
}

fn verify_checker(root string, name string, current bool) ! {
	dir := root + '/' + name
	assert hash(dir + '/compiler')! == hash(retained_input(root, '/Users/alex/code/v/v_old')!)!
	if current { assert hash(dir + '/tooltip-evidence')! == hash(os.executable())!, 'use the retained checker' }
	compile_before := object(dir + '/compile-before.json')!
	compile_done := object(dir + '/compile-receipt.json')!
	for key, value in compile_before { assert compile_done[key]! == value, key }
	assert compile_done['exit_code']!.int() == 0 && compile_done['completed_utc']!.str() != ''
	assert compile_before['started_utc']!.str() != ''
	assert compile_done['argv']!.as_array().map(it.str()) == [dir + '/compiler', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', dir + '/tooltip-evidence', dir + '/tooltip-evidence.v']
	assert compile_done['compiler_sha256']!.str() == hash(dir + '/compiler')!
	assert compile_done['source_sha256']!.str() == hash(dir + '/tooltip-evidence.v')!
	assert compile_done['output_sha256']!.str() == hash(dir + '/tooltip-evidence')!
	assert compile_done['stdout_sha256']!.str() == hash(dir + '/compile.log')!
}

fn verify_rejection(root string) ! {
	before := object(root + '/qualification-rejected-before.json')!
	done := object(root + '/qualification-rejected-receipt.json')!
	for key, value in before { assert done[key]! == value, key }
	assert before['argv']!.as_array().map(it.str()) == [root + '/checker/tooltip-evidence', 'seal', root]
	assert before['checker_sha256']!.str() == hash(root + '/checker/tooltip-evidence')!
	assert before['checker_source_sha256']!.str() == original_runner_source
	assert before['prelaunch_inventory_sha256']!.str() == hash(root + '/prelaunch-sha256.json')!
	for mode in ['baseline', 'fixed'] {
		assert before[mode + '_receipt_sha256']!.str() == hash(root + '/run-' + mode + '-receipt.json')!
	}
	assert before['started_utc']!.str() != '' && done['completed_utc']!.str() != ''
	assert done['exit_code']!.int() != 0 && done['stdout_sha256']!.str() == hash(root + '/qualification-rejected.log')!
	log := os.read_file(root + '/qualification-rejected.log')!
	assert log.contains('Assertion failed') && log.contains("row['backend_ready']")
	assert !os.exists(root + '/sha256.json'), 'failed280 must not carry a positive seal'
}

fn verify_runs(root string, failed280 bool) ! {
	pre := root + '/prelaunch'
	assert hash(root + '/checker/tooltip-evidence.v')! == hash(root + '/run-tool/tooltip-evidence.v')!
	verify_checker(root, 'checker', !failed280)!
	if failed280 {
		assert hash(root + '/run-tool/tooltip-evidence.v')! == original_runner_source
		assert hash(root + '/run-tool/tooltip-evidence')! == original_runner_binary
		verify_checker(root, 'failure-checker', true)!
		verify_rejection(root)!
	}
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
		assert receipt['runner_sha256']!.str() == hash(root + '/run-tool/tooltip-evidence')!
		assert receipt['runner_source_sha256']!.str() == hash(root + '/run-tool/tooltip-evidence.v')!
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
		observation := object(base + '/bootstrap-fixture/observation-before-capture.json')!
		for field, value in observation { assert row[field]! == value, mode + ':' + field }
		if mode == 'baseline' {
			assert !row['backend_ready']!.bool() && row['process_exited']!.bool() && row['outcome']!.str() == 'startup_failed'
			assert serial.contains('java.lang.NoSuchMethodError:') && serial.contains('getTooltipText()Ljava/lang/CharSequence;')
			assert serial.contains('Landroid/view/View;') && serial.contains('TooltipProbe.state(')
			assert serial.contains('APK-SUITE-EXIT id=bootstrap-fixture code=1')
			for marker in pass_markers { assert !serial.contains(marker), marker }
		} else if failed280 {
			assert !row['backend_ready']!.bool() && row['process_exited']!.bool() && row['outcome']!.str() == 'startup_failed'
			assert serial.count(pass_markers[0]) == 1
			for marker in pass_markers[1..] { assert !serial.contains(marker), marker }
			assert serial.count('java.lang.AssertionError: present attribute invokes override once') == 1
			assert serial.contains('org.vinix.bootstrap.TooltipProbe.inflation(Unknown Source:102)')
			assert serial.count('APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true') == 1
			state := serial.index(pass_markers[0]) or { return error('missing failed280 state marker') }
			failure := serial.index('java.lang.AssertionError: present attribute invokes override once') or { return error('missing failed280 assertion') }
			exit_index := serial.index('APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true') or { return error('missing failed280 exit') }
			assert state < failure && failure < exit_index, 'failed280 marker order'
			assert failures == ['ANDROID-WS-FAIL start activity', 'APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true']
			assert observation['observation_elapsed_seconds']!.int() == 5 && observation['qemu_alive_before_capture']!.bool()
		} else {
			assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
			mut previous := -1
			for marker in pass_markers {
				assert serial.count(marker) == 1, marker
				index := serial.index(marker) or { return error('missing marker: ' + marker) }
				assert index > previous, 'fixture marker order'
				previous = index
			}
			for bad in ['java.lang.AssertionError', 'ANDROID-WS-FAIL', 'JNI DETECTED ERROR', 'APK-SUITE-EXIT id=bootstrap-fixture'] { assert !serial.contains(bad), bad }
			for failure in row['failure_markers']!.as_array() {
				line := failure.str()
				assert line in ['java.lang.NoSuchFieldError: no type "Lnge;" found and so no field "bB" could be found in class "Lorg/vinix/bootstrap/Main;" or its superclasses', 'Caused by: java.lang.ClassNotFoundException: nge'], line
			}
			assert observation['observation_elapsed_seconds']!.int() >= 30 && observation['qemu_alive_before_capture']!.bool()
		}
		stages[mode] = read_map(base + '/staged-runtime-sha256.json')!
		assert staged_pins(base + '/module')! == stages[mode], 'complete staged runtime map'
		for target, source in overlay_targets() {
			if source == 'vinix-session' && !os.is_file(pre + '/native-' + mode + '/' + source) { continue }
			assert stages[mode][target]! == hash(pre + '/native-' + mode + '/' + source)!, target
		}
		assert stages[mode][jar] == if mode == 'baseline' { baseline_jar } else { hash(pre + '/framework/api-impl.jar')! }
		assert stages[mode][native]! == same_native
	}
	assert stages['baseline'].len == stages['fixed'].len
	for path, digest in stages['baseline'] { if path != jar { assert stages['fixed'][path]! == digest, path } }
}

fn verify(root string, failed280 bool) ! {
	for path, reason in read_map(root + '/excluded-special-files.json')! {
		assert path in ['baseline', 'fixed'].map(os.abs_path(compound + '/run-' + it + '/bootstrap-fixture/qmp.sock')), path
		assert reason == 'closed Unix socket; endpoint has no file content'
		assert !os.exists(root + '/' + path.all_after(os.abs_path(compound) + '/'))
	}
	verify_inputs(root)!
	verify_reference(root)!
	verify_sources(root + '/prelaunch')!
	verify_runs(root, failed280)!
}

fn run_pair(base string, mode string) ! {
	assert base == compound && mode in ['baseline', 'fixed']
	assert !os.exists(base + '/run-' + mode) && !os.exists(base + '/run-' + mode + '-before.json')
	assert !os.exists(base + '/run-' + mode + '-receipt.json') && !os.exists(base + '/run-' + mode + '.log')
	tool := base + '/run-tool'
	if !os.exists(tool) {
		os.mkdir_all(tool)!
		os.cp(@FILE, tool + '/tooltip-evidence.v')!
		os.cp(os.executable(), tool + '/tooltip-evidence')!
	}
	assert hash(@FILE)! == hash(tool + '/tooltip-evidence.v')!
	assert hash(os.executable())! == hash(tool + '/tooltip-evidence')!
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
		stage := staged_pins(prefix + '/module')!
		os.write_file(prefix + '/staged-runtime-sha256.json', json2.encode(stage, prettify: true) + '\n')!
	}
	os.write_file(prefix + '-receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	assert r.exit_code == 0, r.output
	println('TOOLTIP-RUN ' + mode + ' complete; raw results retained')
}

fn compile_checker(root string, name string) ! {
	dir := root + '/' + name
	argv := [dir + '/compiler', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', dir + '/tooltip-evidence', dir + '/tooltip-evidence.v']
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'compiler_sha256': json2.Any(hash(argv[0])!), 'source_sha256': json2.Any(hash(argv.last())!)}
	os.write_file(dir + '/compile-before.json', json2.encode(receipt, prettify: true) + '\n')!
	r := os.exec(argv)
	os.write_file(dir + '/compile.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	receipt['stdout_sha256'] = hash(dir + '/compile.log')!
	if r.exit_code == 0 { receipt['output_sha256'] = hash(dir + '/tooltip-evidence')! }
	os.write_file(dir + '/compile-receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	assert r.exit_code == 0, r.output
	assert receipt['source_sha256']!.str() == hash(argv.last())!
	assert receipt['compiler_sha256']!.str() == hash(argv[0])!
}

fn archive_failed(root string) ! {
	assert !os.exists(root + '/sha256.json') && !os.exists(root + '/failed-sha256.json')
	assert !os.exists(root + '/failure-checker') && !os.exists(root + '/qualification-rejected-receipt.json')
	assert hash(root + '/checker/tooltip-evidence.v')! == original_runner_source
	argv := [root + '/checker/tooltip-evidence', 'seal', root]
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()),
		'checker_sha256': json2.Any(hash(argv[0])!), 'checker_source_sha256': json2.Any(original_runner_source),
		'prelaunch_inventory_sha256': json2.Any(hash(root + '/prelaunch-sha256.json')!)}
	for mode in ['baseline', 'fixed'] { receipt[mode + '_receipt_sha256'] = hash(root + '/run-' + mode + '-receipt.json')! }
	os.write_file(root + '/qualification-rejected-before.json', json2.encode(receipt, prettify: true) + '\n')!
	r := os.exec(argv)
	os.write_file(root + '/qualification-rejected.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	receipt['stdout_sha256'] = hash(root + '/qualification-rejected.log')!
	os.write_file(root + '/qualification-rejected-receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	verify_rejection(root)!
	mut excluded := map[string]string{}
	clone_tree(os.abs_path(@FILE), root + '/failure-checker/tooltip-evidence.v', mut excluded)!
	clone_tree(root + '/checker/compiler', root + '/failure-checker/compiler', mut excluded)!
	assert excluded.len == 0
	compile_checker(root, 'failure-checker')!
	sealed := os.exec([root + '/failure-checker/tooltip-evidence', 'seal-failed', root])
	assert sealed.exit_code == 0, sealed.output
	print(sealed.output)
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert os.args.len in [3, 4], 'run BASE MODE | retain BASE BUNDLE | seal BUNDLE | check BUNDLE PIN | archive-failed BUNDLE | check-failed BUNDLE PIN'
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
		for pair in [[prepared278 + '/prelaunch/source/suite.v', root + '/reference278/suite.v'], [os.abs_path(@FILE), root + '/checker/tooltip-evidence.v'], ['/Users/alex/code/v/v_old', root + '/checker/compiler']] { clone_tree(pair[0], pair[1], mut excluded)! }
		compile_checker(root, 'checker')!
		os.write_file(root + '/excluded-special-files.json', json2.encode(excluded, prettify: true) + '\n')!
		println('TOOLTIP-EVIDENCE RETAINED')
		return
	}
	root := os.real_path(os.args[2])
	assert os.is_abs_path(root) && !root.starts_with(os.getwd() + '/')
	if os.args[1] == 'archive-failed' { assert os.args.len == 3; archive_failed(root)!; return }
	if os.args[1] == 'seal-failed' {
		assert os.args.len == 3 && !os.exists(root + '/failed-sha256.json')
		verify(root, true)!
		os.write_file(root + '/failed-sha256.json', json2.encode(inventory(root)!, prettify: true) + '\n')!
		println('TOOLTIP-EVIDENCE ARCHIVED; UNQUALIFIED ' + hash(root + '/failed-sha256.json')!)
		return
	}
	if os.args[1] == 'check-failed' {
		assert os.args.len == 4 && hash(root + '/failed-sha256.json')! == os.args[3], 'failed manifest pin mismatch'
		mut actual := inventory(root)!
		actual.delete('failed-sha256.json')
		assert actual == read_map(root + '/failed-sha256.json')!, 'complete failed inventory required'
		verify(root, true)!
		println('TOOLTIP-EVIDENCE INTEGRITY VERIFIED; UNQUALIFIED baseline278 missing API; fixed280 statePASS then exact XML callback assertion/exit1')
		return
	}
	if os.args[1] == 'seal' {
		assert os.args.len == 3 && !os.exists(root + '/sha256.json')
		verify(root, false)!
		os.write_file(root + '/sha256.json', json2.encode(inventory(root)!, prettify: true) + '\n')!
		println('TOOLTIP-EVIDENCE SEALED ' + hash(root + '/sha256.json')!)
	} else {
		assert os.args[1] == 'check' && os.args.len == 4
		assert hash(root + '/sha256.json')! == os.args[3], 'manifest pin mismatch'
		mut actual := inventory(root)!
		actual.delete('sha256.json')
		assert actual == read_map(root + '/sha256.json')!, 'complete inventory required'
		verify(root, false)!
		println('TOOLTIP-EVIDENCE PASS baseline278 getTooltipText NoSuchMethodError; fixed280 tooltip state/inflation and alive30; same APK/native, JAR-only delta; complete retained closure; raw outcomes preserved')
	}
}
