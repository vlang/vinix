// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the completed Maps253 failure and audit its original classification.
module main

import compress.gzip
import crypto.sha256
import encoding.base64
import json2
import os
import time

const base = 'build/android-maps/'
const frozen_pin = '45ead4229f35061237d1f74dc9a95e71f3bb4526f6e91830dab04d24f7ada397'
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
			// APFS clones have independent inodes without duplicating boot media.
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

fn verify_frozen(root string) ! {
	assert hash(root + '/frozen-inputs.json')! == frozen_pin, 'prelaunch input freeze differs'
	assert os.read_file(root + '/source-revision.txt')!.starts_with('008e32bf91b6e33fcb4d1acad3e851147c3b039b\n')
	manifest := read_map(root + '/frozen-inputs.json')!
	assert manifest.len == 56
	for path, digest in manifest {
		assert hash(root + '/inputs/' + path)! == digest, path
	}
}

fn supplement(root string) ! {
	external(root)
	// Copy existing archived build provenance, not a reconstructed execution receipt.
	prior := os.join_path(os.dir(root), 'compound247-2026-10-24')
	assert hash(prior + '/sha256.json')! == '70e5dd4ae468ed74bf8f362f3d40e5bced9c2cbd0d5bf2757ed8bc7254ff7e20'
	manifest := read_map(prior + '/sha256.json')!
	copy_file(prior + '/sha256.json', root + '/provenance/compound247/sha256.json')!
	for path in ['source/build-native.v', 'source/build-framework.v', 'native/identity.txt',
		'native/android-native.c', 'native/androidfw_c_api.h', 'native/sqlite3.h',
		'native/stb_image.h', 'native/stb_truetype.h'] {
		assert hash(prior + '/' + path)! == manifest[path]!, path
		copy_file(prior + '/' + path, root + '/provenance/compound247/' + path)!
	}
}

fn collect(root string) ! {
	external(root)
	// Keep this phase clone-only so completed evidence can be secured with little free space.
	assert hash(root + '/frozen-inputs.json')! == frozen_pin, 'prelaunch input freeze differs'
	assert os.exists(base + 'attempt253/results.json'), 'wait for the completed result'
	assert !os.exists(root + '/run'), 'run already retained'
	special := copy_tree(base + 'attempt253', root + '/run')!
	for path in special { assert path.ends_with('qmp.sock'), path }
	os.write_file(root + '/run/omitted-special-files.json', json2.encode(special))!
	copy_file(base + 'attempt253-harness.log', root + '/run/harness.log')!
	assert copy_tree(base + 'maps253/module', root + '/runtime')!.len == 0
	copy_file(base + 'maps253/vm/boot.img', root + '/media/boot-after-run.img')!
	copy_file(base + 'maps253/vm/efivars.fd', root + '/media/efivars-after-run.fd')!
	// Verify these cloned build compilers against their receipts during the audit.
	receipt := read_map(root + '/inputs/' + base + 'maps253/launcher-build-receipt.json')!
	for key, name in {'compiler': 'v_old', 'cross_compiler': 'aarch64-linux-musl-gcc'} {
		copy_file(os.real_path(receipt[key + '_path']!), root + '/toolchain/' + name)!
	}
	copy_file(root + '/inputs/Users/alex/code/v/v', root + '/toolchain/v_production')!
	println('MAPS253 COLLECTED complete raw files, runtime, frozen compiler identities and post-run media; enrichment and audit remain required')
}

fn enrich(root string) ! {
	external(root)
	verify_frozen(root)!
	assert os.exists(root + '/run/results.json'), 'collect completed raw evidence first'
	for name in ['vinix', 'limine.conf'] {
		r := os.exec(['mcopy', '-i', root + '/media/boot-after-run.img', '::/boot/' + name, root + '/media/' + name])
		assert r.exit_code == 0, r.output
	}
	for name in ['passwd', 'group'] {
		accounts := os.exec(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + quote(root + '/media/boot-after-run.img') + ' ::/boot/initramfs.tar | tar -xOf - ./etc/' + name])
		assert accounts.exit_code == 0, accounts.output
		os.write_file(root + '/media/initramfs-' + name, accounts.output)!
	}
	supplement(root)!
	println('MAPS253 ENRICHED retained kernel, boot configuration, base account databases and original build provenance')
}

fn seal(root string) ! {
	external(root)
	verify_frozen(root)!
	assert os.exists(root + '/run/results.json')
	// Confirm the live originals were not replaced between collection and seal.
	for path, digest in inventory(base + 'attempt253')! {
		assert hash(root + '/run/' + path)! == digest, 'raw file changed: ' + path
	}
	assert hash(root + '/run/harness.log')! == hash(base + 'attempt253-harness.log')!
	copy_file('tests/native-android-ws/maps253-evidence.v', root + '/audit/maps253-evidence.v')!
	assert os.exists(root + '/media/initramfs-group'), 'enrich before sealing'
	os.write_file(root + '/audit/scope.txt', 'Completed Maps253 administrator-provisioned account fixture invokes the production credential launcher. This is not a per-package identity allocator or isolation service. Original signed Maps and companion APKs and frozen247 framework/native are retained. All ordinary raw files and continuous root harness stdout are retained; omitted IPC endpoints are listed. Complete staged runtime, both actual build compiler identities and post-run private boot/firmware media are retained. The 56-file prelaunch freeze and prelaunch media hashes remain separately pinned. The actual image archive is checked against the retained runtime, including symlinks and hidden files. Account serial Base64 retains exact original and updated passwd/group bytes and hashes; the added account resolves before production launch. Frozen253 fixture/source bytes are audited, not later maintained preflight cleanup. ART native process observation and the frozen production launch path are retained; no post-drop /proc identity measurement was emitted in this run. Original startup_failed is authoritative: native main exits139 with SIGSEGV at pc0x80006d2c59c, fault0, after a Dalvik-cache warning and before backend readiness. Configured300 seconds is not endurance evidence. No onboarding, map, bridge-initialization or functional pass is inferred.\n')!
	manifest := inventory(root)!
	assert 'sha256.json' !in manifest, 'bundle already sealed'
	os.write_file(root + '/sha256.json', json2.encode(manifest, prettify: true) + '\n')!
	println('MAPS253 SEALED files=${manifest.len} manifest_sha256=${hash(root + '/sha256.json')!}')
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
	for path, digest in read_map(root + '/inputs/' + base + 'maps253/before-launch-source-identities.json')! {
		assert hash(root + '/inputs/' + path)! == digest, path
	}
	receipt := read_map(root + '/inputs/' + base + 'maps253/launcher-build-receipt.json')!
	assert hash(root + '/inputs/' + receipt['source_path']!)! == receipt['source_sha256']!
	assert hash(root + '/inputs/' + receipt['binary_path']!)! == receipt['binary_sha256']!
	assert hash(root + '/toolchain/v_old')! == receipt['compiler_sha256']!
	assert hash(root + '/toolchain/aarch64-linux-musl-gcc')! == receipt['cross_compiler_sha256']!
	assert receipt['command']!.contains('-os linux -arch arm64') && receipt['command']!.contains('-gc none')
	production := read_map(root + '/inputs/' + base + 'maps253/production-launcher-receipt.json')!
	assert production.len == 9
	for path in ['/Users/alex/code/v/v', '/opt/homebrew/bin/aarch64-linux-musl-gcc',
		'build-support/android/native-run.v', 'build-support/android/nativeapk/install.v',
		'build-support/android/nativeidentity/identity.v', base + 'run-android-identity253'] {
		assert hash(root + '/inputs/' + path)! == production[path]!, path
	}
	assert hash(root + '/toolchain/v_production')! == production['/Users/alex/code/v/v']!
	assert hash(root + '/toolchain/aarch64-linux-musl-gcc')! == production['/opt/homebrew/bin/aarch64-linux-musl-gcc']!
	assert production['command']!.contains('-os linux -arch arm64') && production['command']!.contains('-gc none')
	assert production['command']!.contains('-o build/android-maps/run-android-identity253')
	assert hash(root + '/inputs/' + base + 'run-android-identity253.receipt.json')! == hash(root + '/inputs/' + base + 'maps253/production-launcher-receipt.json')!
	prior := root + '/provenance/compound247'
	assert hash(prior + '/sha256.json')! == '70e5dd4ae468ed74bf8f362f3d40e5bced9c2cbd0d5bf2757ed8bc7254ff7e20'
	manifest := read_map(prior + '/sha256.json')!
	for path in ['source/build-native.v', 'source/build-framework.v', 'native/identity.txt',
		'native/android-native.c', 'native/androidfw_c_api.h', 'native/sqlite3.h',
		'native/stb_image.h', 'native/stb_truetype.h'] {
		assert hash(prior + '/' + path)! == manifest[path]!, path
	}
	assert os.read_file(prior + '/native/identity.txt')!.trim_space() == hash(root + '/inputs/' + base + 'compound247/native/libvinix-android-native.so')!
}

fn verify_runtime(root string) ! {
	prefix := root + '/inputs/' + base + 'maps253'
	before := read_map(prefix + '/runtime-before.json')!
	after := read_map(prefix + '/runtime-after.json')!
	equal_maps(read_map(prefix + '/archive-readback.json')!, after)
	mut regular := inventory(root + '/runtime')!
	for path, value in regular.clone() { if value.starts_with('symlink:') { regular.delete(path) } }
	equal_maps(regular, after)
	assert before.len == 106 && after.len == 109
	for path, digest in before {
		mapped := if path.starts_with('root/.local/share/vinix/android/application.apk_/') {
			path.replace('root/.local/share/vinix/android/application.apk_', 'tmp/maps253-data')
		} else if path == 'usr/bin/run-android' { 'usr/bin/run-android-original' } else { path }
		assert after[mapped]! == digest, mapped
	}
	assert after['usr/bin/run-android']! == hash(root + '/inputs/' + base + 'credential-launcher253')!
	assert after['usr/bin/run-android-identity']! == hash(root + '/inputs/' + base + 'run-android-identity253')!
	assert os.read_file(root + '/runtime/opt/android-test/credential-run')! == '253\n'
	assert after[jar]! == '73a10513135f9e264df9afdc7139c5370d67016d864be82fe0d6b2adba1f459b'
	assert after[native]! == '78893e6767c9398a7d6cb513f0f34b8536604afaa065e383f46cb98e9d003f37'
	assert after[jar]! == hash(root + '/inputs/' + base + 'compound247/framework/api-impl.jar')!
	assert after[native]! == hash(root + '/inputs/' + base + 'compound247/native/libvinix-android-native.so')!
	assert after['opt/android-test/application.apk']! == hash(root + '/inputs/' + base + 'GoogleMaps.apk')!
	for package, name in {'com.google.android.gms': 'GooglePlayServices.apk', 'com.android.vending': 'GooglePlayStore.apk'} {
		assert after['tmp/maps253-data/_installed_apks_/' + package + '.apk']! == hash(root + '/inputs/' + base + name)!
	}
}

fn quote(value string) string { return "'" + value.replace("'", "'\\''") + "'" }

fn verify_media(root string) ! {
	println('MAPS253 MEDIA-BEGIN complete actual FAT archive replay')
	media := root + '/media/boot-after-run.img'
	assert os.file_size(media) == u64(4294967296)
	assert os.file_size(root + '/media/efivars-after-run.fd') > 0
	os.setenv('COPYFILE_DISABLE', '1', true)
	listing := os.exec(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + quote(media) + ' ::/boot/qemu-runtime.tar | tar -tf -'])
	assert listing.exit_code == 0, listing.output
	assert listing.output == os.read_file(root + '/inputs/' + base + 'maps253/archive-list.txt')!
	for line in listing.output.split_into_lines() {
		for part in line.split('/') { assert !part.starts_with('._') && part != '..', line }
	}
	scratch := os.join_path(os.temp_dir(), 'vinix-maps253-${os.getpid()}-${time.now().unix()}')
	assert !os.exists(scratch)
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	extract := os.exec(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + quote(media) + ' ::/boot/qemu-runtime.tar | tar -xf - -C ' + quote(scratch)])
	assert extract.exit_code == 0, extract.output
	equal_maps(inventory(scratch)!, inventory(root + '/runtime')!)
	for name in ['vinix', 'limine.conf'] {
		r := os.exec(['mtype', '-i', media, '::/boot/' + name])
		assert r.exit_code == 0, r.output
		assert sha256.sum(r.output.bytes()).hex() == hash(root + '/media/' + name)!, name
	}
	serial := os.read_file(root + '/run/google-maps/serial.log')!
	for name in ['passwd', 'group'] {
		accounts := os.exec(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + quote(media) + ' ::/boot/initramfs.tar | tar -xOf - ./etc/' + name])
		assert accounts.exit_code == 0, accounts.output
		assert accounts.output == os.read_file(root + '/media/initramfs-' + name)!
		assert accounts.output.len > 0
		assert accounts.output == account_bytes(serial, name, 'before'), name
		for line in accounts.output.split_into_lines() {
			fields := line.split(':')
			if fields.len >= 3 { assert fields[2] != '10000', 'unexpected base account for UID10000' }
		}
		assert !os.exists(root + '/runtime/etc/' + name), 'runtime overrides initramfs accounts'
	}
	prelaunch := read_map(root + '/inputs/' + base + 'maps253/prelaunch-media-sha256.json')!
	assert prelaunch.len == 2
	assert prelaunch[base + 'maps253/vm/boot.img']! == '7641ebc4c4220afa6bc1b9861a09421c15da1d814fd8eb1ca92c656042a75ea1'
	assert prelaunch[base + 'maps253/vm/efivars.fd']! == 'f0c577062133831fe8795ad8dbcc30cc1a4b718cdba5937853ee8a52afbbc952'
	println('MAPS253 MEDIA-END complete FAT payload matches retained runtime and base accounts')
}

fn account_bytes(serial string, name string, phase string) string {
	prefix := 'MAPS253-ACCOUNT-BYTES path=/etc/' + name + ' '
	lines := serial.split_into_lines().filter(it.starts_with(prefix))
	assert lines.len == 1, prefix
	value := lines[0].trim_space().all_after(phase + '_base64=').all_before(' ')
	decoded := base64.decode(value).bytestr()
	assert base64.encode(decoded.bytes()) == value, 'account bytes must use canonical lossless Base64'
	return decoded
}

fn verify_accounts(root string, serial string) ! {
	for name, addition in {
		'passwd': 'maps253:x:10000:10000:Maps credential fixture:/tmp/maps253-home:/bin/sh\n'
		'group':  'maps253:x:10000:\n'
	} {
		before := account_bytes(serial, name, 'before')
		after := account_bytes(serial, name, 'after')
		assert before.len > 0 && before.ends_with('\n')
		assert after == before + addition, 'account provisioning must retain the exact original prefix'
		assert before == os.read_file(root + '/media/initramfs-' + name)!
		marker := 'MAPS253-ACCOUNT-DATABASE path=/etc/${name} original_bytes=${before.len} before_sha256=${sha256.sum(before.bytes()).hex()} after_sha256=${sha256.sum(after.bytes()).hex()} original_prefix=retained'
		assert serial.contains(marker), marker
		for line in before.split_into_lines() {
			fields := line.split(':')
			assert fields.len >= 3
			assert fields[0] != 'maps253' && fields[2] != '10000', 'pre-existing account collision'
		}
	}
	assert serial.contains('MAPS253-ACCOUNT-RESOLVED name=maps253 uid=10000 gid=10000 home=/tmp/maps253-home')
}

fn verify_run(root string) ! {
	rows := json2.decode[[]json2.Any](os.read_file(root + '/run/results.json')!)!
	assert rows.len == 1
	row := rows[0].as_map()
	assert row['id']!.str() == 'google-maps'
	assert row['startup_timeout_seconds']!.int() == 300 && row['startup_seconds']!.int() == 300
	assert row['functional_passed']! is json2.Null
	serial := gzip.decompress(os.read_bytes(root + '/run/google-maps/serial.log.gz')!)!.bytestr()
	assert serial == os.read_file(root + '/run/google-maps/serial.log')!
	assert sha256.sum(serial.bytes()).hex() == row['serial_sha256']!.str()
	assert hash(root + '/run/google-maps/application.png')! == row['screenshot_sha256']!.str()
	assert os.file_size(root + '/run/google-maps/network.pcap') > 24
	metadata := row['metadata']!.as_map()
	assert metadata['name']!.str() == 'com.google.android.apps.maps'
	assert metadata['versionName']!.str() == '26.42.01.997557324'
	assert metadata['signature_verification']!.str().contains('Verifies\n')
	assert hash(root + '/inputs/' + base + 'GoogleMaps.apk')! == metadata['apk_sha256']!.str()
	for companion in row['companion_packages']!.as_array() {
		item := companion.as_map()
		assert hash(root + '/inputs/' + item['apk']!.str())! == item['metadata']!.as_map()['apk_sha256']!.str()
		assert item['metadata']!.as_map()['signature_verification']!.str().contains('Verifies\n')
	}
	assert row['launcher_entered']!.bool() == serial.contains('APK-SUITE-BEGIN id=google-maps ')
	assert row['backend_ready']!.bool() == serial.contains('ANDROID-WS-READY backend=vinix-native')
	assert row['process_exited']!.bool() == serial.contains('APK-SUITE-EXIT id=google-maps ')
	assert row['native_maps_observed']!.bool() == serial.contains('APK-SUITE-MAPS id=google-maps ')
	// Recompute the frozen suite classifier without changing its marker rules.
	mut markers := []string{}
	for line in serial.split_into_lines() {
		if ['ANDROID-WS-FAIL', 'APK-SUITE-DEPENDENCY-FAIL', 'ANDROID-WS-DEPENDENCY-FAIL',
			'ANDROID-WS-PROCESS-FAIL', 'JNI DETECTED ERROR', 'NoClassDefFoundError',
			'NoSuchMethodError', 'UnsatisfiedLinkError', 'ClassNotFoundException',
			'NoSuchFieldError', 'APK-SUITE-EXIT id='].any(line.contains(it)) { markers << line.trim_space() }
	}
	assert row['failure_markers']!.as_array().map(it.str()) == markers && markers.len == 1
	expected := if !row['launcher_entered']!.bool() { 'harness_failure' }
		else if row['process_exited']!.bool() || markers.len > 0 { 'startup_failed' }
		else if row['backend_ready']!.bool() { 'window_observed' } else { 'startup_timeout' }
	assert row['outcome']!.str() == expected && expected == 'startup_failed'
	assert row['launcher_entered']!.bool() && row['native_maps_observed']!.bool()
	assert row['process_exited']!.bool() && !row['backend_ready']!.bool()
	verify_accounts(root, serial)!
	for marker in [
		'MAPS253-RUNTIME-MOUNT-ADMIN /opt/vinix-android-aarch64 /opt/vinix-android-aarch64 tmpfs ro,nosuid,nodev,wxallowed,relatime 0 0',
		'MAPS253-PRODUCTION-LAUNCH root=0,0 uid=10000 gid=10000 data=/tmp/maps253-data home=/tmp/maps253-home surface=',
		'Dalvik cache directory does not exist',
		'Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR) fault addr 0',
		'"main"', 'pc: 0x0000080006d2c59c',
		'APK-SUITE-EXIT id=google-maps code=139 native_observed=true gtk_x11_absent=true'] {
		assert serial.contains(marker), marker
	}
	harness := os.read_file(root + '/run/harness.log')!
	assert harness.contains('MAPS253 PREFLIGHT PASS original APK, frozen247 runtime')
	assert harness.contains('APK-SUITE result google-maps startup_failed')
	interaction := os.read_file(root + '/run/google-maps/interaction.log')!
	assert sha256.sum(interaction.bytes()).hex() == 'f35c675cd4e357bcf33b0d8001513dec1cddf70b1e40e109847f148a1dc16b0e'
	commands := interaction.split_into_lines()
	assert commands.len == 2
	assert commands[0].contains("BEGIN ['build/android-run', 'screenshot', '--socket',")
	assert commands[0].contains('/attempt253/google-maps/boot-progress.png\'] timeout_seconds=30 ')
	assert commands[1].contains('END exit=0 timed_out=false output_drain_capped=false ')
	for stream in ['stdout', 'stderr'] {
		assert os.read_file(root + '/run/google-maps/command-49333.' + stream + '.log')! == ''
	}
	assert hash(root + '/run/google-maps/boot-progress.png')! == 'c07bacecb4964c5b02b099756c27c70cf2e4e866abf557e7d79f73e997374757'
}

fn check(root string, pinned string) ! {
	assert pinned.len == 64 && hash(root + '/sha256.json')! == pinned, 'manifest differs from report'
	manifest := read_map(root + '/sha256.json')!
	mut actual := inventory(root)!
	actual.delete('sha256.json')
	equal_maps(actual, manifest)
	for path in manifest.keys() { assert path != '' && !os.is_abs_path(path) && '..' !in path.split('/'), path }
	verify_frozen(root)!
	verify_sources(root)!
	verify_runtime(root)!
	verify_run(root)!
	verify_media(root)!
	assert os.read_file(root + '/audit/maps253-evidence.v')! == os.read_file(@FILE)!
	println('MAPS253-EVIDENCE PASS complete retained failure; original startup_failed preserved; no functional pass inferred')
}

fn negative(root string, pinned string) ! {
	external(root)
	assert hash(root + '/sha256.json')! == pinned
	directory := root + '-negative'
	assert !os.exists(directory), 'use a fresh negative audit directory'
	copy_file(root + '/sha256.json', directory + '/partial/sha256.json')!
	partial := os.exec([os.executable(), 'check', directory + '/partial', pinned])
	assert partial.exit_code != 0 && partial.output.contains('actual.len == expected.len'), partial.output
	os.write_file(directory + '/partial.log', partial.output)!
	wrong_pin := os.exec([os.executable(), 'check', root, '0'.repeat(64)])
	assert wrong_pin.exit_code != 0 && wrong_pin.output.contains('manifest differs from report'), wrong_pin.output
	os.write_file(directory + '/wrong-pin.log', wrong_pin.output)!
	prior_pin := os.exec([os.executable(), 'check', root, '1019ba4d587bb0cc5890038edcd56f09ef8fc6a1119e4483addaf7eb6c556fd3'])
	assert prior_pin.exit_code != 0 && prior_pin.output.contains('manifest differs from report'), prior_pin.output
	os.write_file(directory + '/prior-pin.log', prior_pin.output)!
	os.write_file(directory + '/scope.txt', 'Assertion-enabled auditor rejects a manifest-only partial bundle with the correct pin, and the complete corrected bundle with an all-zero or superseded pre-correction manifest pin.\n')!
	println('MAPS253-NEGATIVE PASS partial bundle, wrong pin and superseded pin rejected')
}

fn main() {
	$if prod { eprintln('Maps253 evidence auditing requires assertions; compile without -prod'); exit(2) }
	if os.args.len == 3 && os.args[1] == 'collect' { collect(os.args[2])!; return }
	if os.args.len == 3 && os.args[1] == 'enrich' { enrich(os.args[2])!; return }
	if os.args.len == 3 && os.args[1] == 'supplement' { supplement(os.args[2])!; return }
	if os.args.len == 3 && os.args[1] == 'seal' { seal(os.args[2])!; return }
	if os.args.len == 4 && os.args[1] == 'check' { check(os.args[2], os.args[3])!; return }
	if os.args.len == 4 && os.args[1] == 'negative' { negative(os.args[2], os.args[3])!; return }
	panic('usage: maps253-evidence collect EXTERNAL_BUNDLE | enrich BUNDLE | supplement BUNDLE | seal BUNDLE | check|negative BUNDLE MANIFEST_SHA256')
}
