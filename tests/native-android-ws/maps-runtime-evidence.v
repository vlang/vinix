// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve and audit the Maps250/251 runtime comparison without changing its
// original classifier. Generated evidence must remain outside the repository.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/'
const jar = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

fn equal_maps(actual map[string]string, expected map[string]string) {
	assert actual.len == expected.len
	for path, value in expected { assert actual[path] or { panic('missing: ' + path) } == value, path }
}

fn inventory(root string) !map[string]string {
	mut result := map[string]string{}
	for path in os.walk_ext(root, '', hidden: true) {
		name := path.all_after(root + '/')
		if os.is_link(path) { result[name] = 'symlink:' + os.readlink(path)! }
		else if os.is_file(path) { result[name] = hash(path)! }
	}
	return result
}

fn copy_file(from string, to string) ! {
	os.mkdir_all(os.dir(to))!
	assert !os.exists(to) && !os.is_link(to), to
	if os.is_link(from) { os.symlink(os.readlink(from)!, to)! }
	else {
		assert os.is_file(from), from
		$if macos {
			// Independent APFS inodes preserve the entire bundle while avoiding
			// another physical copy of APKs and 4GiB private boot media.
			r := os.exec(['cp', '-c', from, to])
			assert r.exit_code == 0, r.output
		} $else { os.cp(from, to)! }
	}
}

fn copy_tree(from string, to string) ![]string {
	mut special := []string{}
	for path in os.walk_ext(from, '', hidden: true) {
		name := path.all_after(from + '/')
		if os.is_file(path) || os.is_link(path) { copy_file(path, to + '/' + name)! }
		else { special << name }
	}
	return special
}

fn external(root string) {
	assert os.is_abs_path(root), 'absolute external bundle directory required'
	assert root != os.getwd() && !root.starts_with(os.getwd() + '/'), 'use external state storage'
}

fn collect(root string, id string) ! {
	external(root)
	assert id in ['250', '251']
	assert os.exists(root + '/frozen-inputs.json'), 'freeze inputs before launching'
	run := base + 'attempt' + id
	assert os.exists(run + '/results.json'), 'wait for the completed result'
	assert !os.exists(root + '/runs/' + id), 'run already retained'
	for path, digest in read_map(root + '/frozen-inputs.json')! {
		assert hash(root + '/inputs/' + path)! == digest, path
	}
	special := copy_tree(run, root + '/runs/' + id)!
	// A closed QMP socket is an ephemeral IPC endpoint rather than file data.
	for path in special { assert path.ends_with('qmp.sock'), 'unexpected special file: ' + path }
	os.write_file(root + '/runs/' + id + '/omitted-special-files.json', json2.encode(special))!
	assert copy_tree(base + 'maps' + id + '/module', root + '/runtime/' + id)!.len == 0
	for name in ['GoogleMaps.apk', 'GooglePlayServices.apk', 'GooglePlayStore.apk'] {
		if !os.exists(root + '/inputs/' + base + name) { copy_file(base + name, root + '/inputs/' + base + name)! }
	}
	copy_file(base + 'maps' + id + '/vm/boot.img', root + '/media/' + id + '/boot-after-run.img')!
	copy_file(base + 'maps' + id + '/vm/efivars.fd', root + '/media/' + id + '/efivars-after-run.fd')!
	println('MAPS-RUNTIME retained completed run ' + id + '; mutable media is explicitly post-run state')
}

fn seal(root string) ! {
	external(root)
	for id in ['250', '251'] {
		assert os.exists(root + '/runs/' + id + '/results.json')
		// Include late root notes after the interaction driver has stopped.
		for path, digest in inventory(base + 'attempt' + id)! {
			dest := root + '/runs/' + id + '/' + path
			if !os.exists(dest) && !os.is_link(dest) { copy_file(base + 'attempt' + id + '/' + path, dest)! }
			actual := if os.is_link(dest) { 'symlink:' + os.readlink(dest)! } else { hash(dest)! }
			assert actual == digest, 'raw file changed after collection: ' + path
		}
	}
	copy_file('tests/native-android-ws/maps-runtime-evidence.v', root + '/audit/maps-runtime-evidence.v')!
	os.write_file(root + '/audit/scope.txt', 'Completed Maps250 frozen247 runtime and Maps251 credential experiment. All ordinary raw files, exact staged runtime bytes, frozen source/helper/config inputs and post-run private boot media retained. QMP socket endpoints are listed separately. Runtime archive readback inventories precede launch; boot/efivars copies are explicitly post-run. Maps250 freeze follows preflight start; Maps251 freeze precedes launch. Raw classifications remain authoritative. Root visually reviewed Maps250 onboarding Skip and the detailed North America map. Search did not succeed; no search or chip qualification is claimed. Host ENOSPC stopped the Maps250 packet dump, so network.pcap is truncated. The root harness log contains labeled tool-output excerpts, not a continuous stdout transcript. UID fixture relocates data and changes permissions; it is not production isolation or notification support.\n')!
	manifest := inventory(root)!
	assert 'sha256.json' !in manifest, 'bundle already sealed'
	os.write_file(root + '/sha256.json', json2.encode(manifest, prettify: true) + '\n')!
	println('MAPS-RUNTIME SEALED files=${manifest.len} manifest_sha256=${hash(root + '/sha256.json')!}')
}

fn verify_sources(root string) ! {
	for kind in ['framework', 'native'] {
		prefix := root + '/inputs/' + base + 'compound247/' + kind
		exact := json2.decode[map[string]string](gzip.decompress(os.read_bytes(prefix + '/exact-sources.json.gz')!)!.bytestr())!
		hashes := read_map(prefix + '/sources.json')!
		assert exact.len == if kind == 'framework' { 125 } else { 83 }
		assert exact.len == hashes.len
		for path, source in exact { assert sha256.sum(source.bytes()).hex() == hashes[path]!, path }
	}
	assert hash(root + '/inputs/' + base + 'compound247/framework/api-impl.jar')! == '73a10513135f9e264df9afdc7139c5370d67016d864be82fe0d6b2adba1f459b'
	assert hash(root + '/inputs/' + base + 'compound247/native/libvinix-android-native.so')! == '78893e6767c9398a7d6cb513f0f34b8536604afaa065e383f46cb98e9d003f37'
}

fn regular_inventory(root string) !map[string]string {
	mut values := inventory(root)!
	for path, value in values.clone() { if value.starts_with('symlink:') { values.delete(path) } }
	return values
}

fn verify_runtime(root string) ! {
	mut after250 := map[string]string{}
	for id in ['250', '251'] {
		prefix := root + '/inputs/' + base + 'maps' + id
		before := read_map(prefix + '/runtime-before.json')!
		after := read_map(prefix + '/runtime-after.json')!
		equal_maps(read_map(prefix + '/archive-readback.json')!, after)
		equal_maps(regular_inventory(root + '/runtime/' + id)!, after)
		for line in os.read_file(prefix + '/archive-list.txt')!.split_into_lines() {
			for part in line.split('/') { assert !part.starts_with('._'), line }
		}
		assert after[jar]! == '73a10513135f9e264df9afdc7139c5370d67016d864be82fe0d6b2adba1f459b'
		assert after[native]! == '78893e6767c9398a7d6cb513f0f34b8536604afaa065e383f46cb98e9d003f37'
		assert after['opt/android-test/application.apk']! == hash(root + '/inputs/' + base + 'GoogleMaps.apk')!
		data := if id == '250' { 'root/.local/share/vinix/android/application.apk_' } else { 'tmp/maps251-data' }
		for package, name in {'com.google.android.gms': 'GooglePlayServices.apk', 'com.android.vending': 'GooglePlayStore.apk'} {
			assert after[data + '/_installed_apks_/' + package + '.apk']! == hash(root + '/inputs/' + base + name)!
		}
		if id == '250' {
			assert before.len == 106 && after.len == 106
			mut changed := []string{}
			for path, digest in before { if after[path]! != digest { changed << path } }
			changed.sort()
			mut expected := [jar, native]
			expected.sort()
			assert changed == expected
			after250 = after.clone()
		} else {
			equal_maps(before, after250)
			assert after.len == 107
			for path, digest in before {
				mapped := if path.starts_with('root/.local/share/vinix/android/application.apk_/') {
					path.replace('root/.local/share/vinix/android/application.apk_', 'tmp/maps251-data')
				} else if path == 'usr/bin/run-android' { 'usr/bin/run-android-original' } else { path }
				assert after[mapped]! == digest, mapped
			}
			assert after['usr/bin/run-android']! == hash(root + '/inputs/' + base + 'credential-launcher251')!
		}
	}
}

fn quote(value string) string { return "'" + value.replace("'", "'\\''") + "'" }

fn verify_media(root string, id string) ! {
	media := root + '/media/' + id + '/boot-after-run.img'
	assert os.file_size(media) == u64(4294967296)
	assert os.file_size(root + '/media/' + id + '/efivars-after-run.fd') > 0
	os.setenv('COPYFILE_DISABLE', '1', true)
	listing := os.exec(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + quote(media) + ' ::/boot/qemu-runtime.tar | tar -tf -'])
	assert listing.exit_code == 0, listing.output
	assert listing.output == os.read_file(root + '/inputs/' + base + 'maps' + id + '/archive-list.txt')!
	scratch := os.join_path(os.temp_dir(), 'vinix-maps-runtime-${os.getpid()}-${time.now().unix()}')
	assert !os.exists(scratch)
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	extract := os.exec(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + quote(media) + ' ::/boot/qemu-runtime.tar | tar -xf - -C ' + quote(scratch)])
	assert extract.exit_code == 0, extract.output
	equal_maps(inventory(scratch)!, inventory(root + '/runtime/' + id)!)
}

fn verify_run(root string, id string) ! {
	prefix := root + '/runs/' + id
	rows := json2.decode[[]json2.Any](os.read_file(prefix + '/results.json')!)!
	assert rows.len == 1
	row := rows[0].as_map()
	assert row['id']!.str() == 'google-maps'
	assert row['startup_timeout_seconds']!.int() == 180 && row['startup_seconds']!.int() == 180
	assert row['functional_passed']! is json2.Null
	serial := gzip.decompress(os.read_bytes(prefix + '/google-maps/serial.log.gz')!)!.bytestr()
	assert serial == os.read_file(prefix + '/google-maps/serial.log')!
	assert sha256.sum(serial.bytes()).hex() == row['serial_sha256']!.str()
	if 'screenshot_sha256' in row { assert hash(prefix + '/google-maps/application.png')! == row['screenshot_sha256']!.str() }
	metadata := row['metadata']!.as_map()
	assert metadata['name']!.str() == 'com.google.android.apps.maps'
	assert metadata['versionName']!.str() == '26.42.01.997557324'
	assert metadata['signature_verification']!.str().contains('Verifies\n')
	assert hash(root + '/inputs/' + base + 'GoogleMaps.apk')! == metadata['apk_sha256']!.str()
	for companion in row['companion_packages']!.as_array() {
		item := companion.as_map()
		assert hash(root + '/inputs/' + item['apk']!.str())! == item['metadata']!.as_map()['apk_sha256']!.str()
	}
	assert row['launcher_entered']!.bool() == serial.contains('APK-SUITE-BEGIN id=google-maps ')
	assert row['backend_ready']!.bool() == serial.contains('ANDROID-WS-READY backend=vinix-native')
	assert row['process_exited']!.bool() == serial.contains('APK-SUITE-EXIT id=google-maps ')
	assert row['native_maps_observed']!.bool() == serial.contains('APK-SUITE-MAPS id=google-maps ')
	mut markers := []string{}
	for line in serial.split_into_lines() {
		if ['ANDROID-WS-FAIL', 'APK-SUITE-DEPENDENCY-FAIL', 'ANDROID-WS-DEPENDENCY-FAIL',
			'ANDROID-WS-PROCESS-FAIL', 'JNI DETECTED ERROR', 'NoClassDefFoundError',
			'NoSuchMethodError', 'UnsatisfiedLinkError', 'ClassNotFoundException',
			'NoSuchFieldError', 'APK-SUITE-EXIT id='].any(line.contains(it)) { markers << line.trim_space() }
	}
	assert row['failure_markers']!.as_array().map(it.str()) == markers
	expected := if !row['launcher_entered']!.bool() { 'harness_failure' }
		else if row['process_exited']!.bool() || markers.len > 0 { 'startup_failed' }
		else if row['backend_ready']!.bool() { 'window_observed' } else { 'startup_timeout' }
	assert row['outcome']!.str() == expected
	if id == '250' {
		assert expected == 'startup_failed' && row['backend_ready']!.bool()
		assert row['native_maps_observed']!.bool() && !row['process_exited']!.bool()
		assert !serial.contains('JNI DETECTED ERROR')
		assert os.read_file(prefix + '/google-maps/interaction.log')!.contains('SKIP-CLICK')
		for name in ['onboarding.png', 'map.png', 'paris-results.png'] { assert os.file_size(prefix + '/google-maps/' + name) > 0 }
		excerpts := os.read_file(prefix + '/harness-root-excerpts.log')!
		assert excerpts.contains('not a continuously redirected harness transcript')
		assert excerpts.contains('network dump write error - stopping dump') && excerpts.contains('packet capture is truncated')
	} else {
		assert expected == 'startup_failed' && !row['backend_ready']!.bool()
		assert !row['native_maps_observed']!.bool()
		for marker in ['MAPS251-PROC-STATUS-BEGIN', 'Uid:\t10000\t10000\t10000\t10000',
			'Gid:\t10000\t10000\t10000\t10000', 'CapEff:\t0000000000000000',
			'MAPS251-UNIX-UID real=10000 effective=10000 saved=10000 gid=10000,10000,10000 groups=0 regain_root=denied write_probes=pass',
			'run-android: Operation not permitted; code: 1',
			'APK-SUITE-EXIT id=google-maps code=1 native_observed=false gtk_x11_absent=true'] {
			assert serial.contains(marker), marker
		}
	}
	println('MAPS-RUNTIME ' + id + ' raw_outcome=' + expected)
}

fn check(root string, pinned string) ! {
	assert pinned.len == 64 && hash(root + '/sha256.json')! == pinned, 'manifest differs from report'
	manifest := read_map(root + '/sha256.json')!
	mut actual := inventory(root)!
	actual.delete('sha256.json')
	equal_maps(actual, manifest)
	for path in manifest.keys() { assert path != '' && !os.is_abs_path(path) && '..' !in path.split('/'), path }
	for path, digest in read_map(root + '/frozen-inputs.json')! { assert hash(root + '/inputs/' + path)! == digest, path }
	verify_sources(root)!
	verify_runtime(root)!
	for id in ['250', '251'] {
		println('MAPS-RUNTIME MEDIA-BEGIN id=' + id)
		verify_media(root, id)!
		println('MAPS-RUNTIME MEDIA-END id=' + id + ' scratch-removed=true')
		verify_run(root, id)!
	}
	assert os.read_file(root + '/audit/maps-runtime-evidence.v')! == os.read_file(@FILE)!
	println('MAPS-RUNTIME-EVIDENCE PASS complete retained comparison; original raw classifications preserved; no functional pass inferred')
}

fn main() {
	$if prod {
		eprintln('Refusing -prod: this compiler removes assertions; use -cflags -O2.')
		exit(2)
	}
	if os.args.len == 4 && os.args[1] == 'collect' { collect(os.args[2], os.args[3])!; return }
	if os.args.len == 3 && os.args[1] == 'seal' { seal(os.args[2])!; return }
	if os.args.len == 4 && os.args[1] == 'check' { check(os.args[2], os.args[3])!; return }
	panic('usage: maps-runtime-evidence collect EXTERNAL_BUNDLE 250|251 | seal BUNDLE | check BUNDLE MANIFEST_SHA256')
}
