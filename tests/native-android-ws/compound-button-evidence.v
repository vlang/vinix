// SPDX-License-Identifier: GPL-2.0-or-later
// Audit a complete external CompoundButton regression bundle, never a partial
// export. Pin sha256.json with the digest published in the committed report.
// Build without -prod: these assertions are the audit checks.
module main

import compress.gzip
import crypto.sha256
import json2
import os

const jar_path = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native_path = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

fn exact_sources(root string, name string, count int) !map[string]string {
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + '/' + name + '/exact-sources.json.gz')!)!.bytestr())!
	hashes := read_map(root + '/' + name + '/sources.json')!
	assert sources.len == count && hashes.len == count, name
	for path, source in sources {
		assert sha256.sum(source.bytes()).hex() == hashes[path]!, name + '/' + path
	}
	return sources
}

fn verify_sources(root string) ! {
	old_framework := exact_sources(root, 'baseline-framework', 125)!
	framework := exact_sources(root, 'framework', 125)!
	mut changed := []string{}
	for path, source in framework {
		assert path in old_framework, path
		if source != old_framework[path] { changed << path }
	}
	assert changed == ['androidtools/framework_classes.v'], changed.str()
	marker := 'fn framework_check_widgets(smali string) ! {'
	old := old_framework[changed[0]]!
	fixed := framework[changed[0]]!
	assert old.count(marker) == 1 && fixed.count(marker) == 1
	assert old.all_before(marker) == fixed.all_before(marker)
	assert fixed.contains('vinixWsButtonDrawableSet:I')
	assert fixed.contains('setButtonDrawable(I)V')
	assert fixed == os.read_file(root + '/source/framework_classes.v')!
	old_native := exact_sources(root, 'baseline-native', 83)!
	native := exact_sources(root, 'native', 83)!
	changed.clear()
	for path, source in native {
		assert path in old_native, path
		if source != old_native[path] { changed << path }
	}
	changed.sort()
	assert changed == ['ws_generated.v', 'ws_views.v'], changed.str()
	generated := old_native['ws_generated.v']!
	assert generated.count('ws_draw_content(e,this)') == 1
	assert native['ws_generated.v']! == generated.replace('ws_draw_content(e,this)', 'ws_draw_content(e,this,p1)')
	assert native['ws_views.v']!.contains('fn ws_button_indicator(')
	assert native['ws_views.v']!.contains("c'draw', c'(Landroid/graphics/Canvas;)V'")
	assert native['ws_views.v']! == os.read_file(root + '/source/ws_views.v')!
	assert os.read_file(root + '/source/bindings.txt')!.contains('android/view/View|native_drawContent|ws_draw_content(e,this,p1)')
}

fn verify_runs(root string) ! {
	mut apks := []string{}
	mut staged := map[string]map[string]string{}
	for mode in ['baseline', 'fixed'] {
		base := root + '/run-' + mode
		rows := json2.decode[[]json2.Any](os.read_file(base + '/results.json')!)!
		assert rows.len == 1, mode
		row := rows[0].as_map()
		assert row['id']!.str() == 'bootstrap-fixture'
		serial := gzip.decompress(os.read_bytes(base + '/bootstrap-fixture/serial.log.gz')!)!.bytestr()
		assert sha256.sum(serial.bytes()).hex() == row['serial_sha256']!.str(), mode
		assert hash(base + '/bootstrap-fixture/application.png')! == row['screenshot_sha256']!.str(), mode
		assert row['launcher_entered']!.bool() && row['native_maps_observed']!.bool(), mode
		apks << row['metadata']!.as_map()['apk_sha256']!.str()
		assert serial.contains('APK-SUITE-BEGIN id=bootstrap-fixture '), mode
		assert serial.contains('COMPOUND-BUTTON-DEFAULTS-PASS'), mode
		if mode == 'baseline' {
			assert row['outcome']!.str() == 'startup_failed' && row['process_exited']!.bool()
			assert serial.contains('java.lang.AssertionError: CompoundButton measured width or bitmap indicator pixel')
			assert serial.contains('APK-SUITE-EXIT id=bootstrap-fixture code=1')
			assert !serial.contains('COMPOUND-BUTTON-NULL-PASS')
			assert !serial.contains('BOOTSTRAP-COMPOUND-BUTTON-PASS')
		} else {
			assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
			assert row['startup_seconds']!.int() == 30 && row['startup_timeout_seconds']!.int() == 30
			assert serial.contains('COMPOUND-BUTTON-NULL-PASS')
			assert serial.contains('BOOTSTRAP-COMPOUND-BUTTON-PASS') && serial.contains('BOOTSTRAP-READY')
			for failure in ['java.lang.AssertionError', 'ANDROID-WS-FAIL', 'JNI DETECTED ERROR',
				'APK-SUITE-EXIT id=bootstrap-fixture'] {
				assert !serial.contains(failure), failure
			}
			failures := row['failure_markers']!.as_array()
			assert row['outcome']!.str() == if failures.len == 0 {
				'window_observed'
			} else {
				'startup_failed'
			}
			// The inherited diagnostic probes an optional Maps class even in
			// this tiny fixture. Preserve the raw classifier's failure result.
			for failure in failures {
				line := failure.str()
				assert (line.contains('NoSuchFieldError:') && line.contains('Lnge;') && line.contains('Lorg/vinix/bootstrap/Main;')) || line == 'Caused by: java.lang.ClassNotFoundException: nge', line
			}
		}
		config := json2.decode[map[string]json2.Any](os.read_file(root + '/' + mode + '.json')!)!
		assert config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 30
		staged[mode] = read_map(base + '/staged-runtime-sha256.json')!
		assert staged[mode].len in [6, 7]
		for required in [jar_path, native_path, 'usr/bin/run-android', 'usr/bin/run-android-calculator',
			'usr/bin/vinix-desktop', 'opt/android-test/native-guest'] {
			assert required in staged[mode], mode + '/' + required
		}
		for path, digest in staged[mode] {
			assert hash(base + '/module/' + path)! == digest, mode + '/' + path
		}
	}
	assert apks[0] == apks[1] && apks[0].len == 64, 'same signed APK required'
	assert apks[0] == hash(root + '/fixture/probe.apk')!
	assert staged['baseline'][jar_path] == '933fc7db4267d123a33bb1e4e064ea3b69450fd065bb4d8e4f5898b91cf842b8'
	assert staged['baseline'][native_path] == '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d'
	assert staged['fixed'][jar_path] == hash(root + '/framework/api-impl.jar')!
	assert staged['fixed'][native_path] == hash(root + '/native/libvinix-android-native.so')!
	assert staged['fixed'][jar_path] != staged['baseline'][jar_path]
	assert staged['fixed'][native_path] != staged['baseline'][native_path]
	for path, digest in staged['baseline'] {
		assert path in staged['fixed'], path
		if path !in [jar_path, native_path] {
			assert digest == staged['fixed'][path], path
		}
	}
}

fn main() {
	$if prod {
		eprintln('compound-button-evidence requires assertions; build without -prod')
		exit(2)
	}
	if os.args.len != 4 || os.args[1] != 'check' {
		panic('usage: compound-button-evidence check BUNDLE SHA256_OF_sha256.json')
	}
	root := os.real_path(os.args[2])
	assert os.args[3].len == 64
	assert hash(root + '/sha256.json')! == os.args[3], 'bundle manifest digest differs from report'
	manifest := read_map(root + '/sha256.json')!
	assert manifest.len > 20, 'complete bundle required'
	for path, digest in manifest {
		assert path != '' && !os.is_abs_path(path) && '..' !in path.split('/'), path
		assert digest.len == 64 && hash(root + '/' + path)! == digest, path
	}
	for path in os.walk_ext(root, '') {
		name := path.all_after(root + '/')
		if name != 'sha256.json' {
			assert name in manifest, 'unlisted bundle file: ' + name
		}
	}
	verify_sources(root)!
	verify_runs(root)!
	println('COMPOUND-BUTTON-EVIDENCE PASS same signed APK; baseline explicit-null failure; fixed defaults/null/static custom drawable bounds and bitmap pixels/restoration/resource zero/subclass/negative intrinsic sizes; 30-second bounded guest observation. Raw classifier retained.')
}
