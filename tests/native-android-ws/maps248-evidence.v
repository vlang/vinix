// SPDX-License-Identifier: GPL-2.0-or-later
// Retain and audit the completed Maps248 failure, without changing its result.
module main

import compress.gzip
import crypto.sha256
import json2
import os

const maps = 'build/android-maps/'
const jar = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const jar_sha = '933fc7db4267d123a33bb1e4e064ea3b69450fd065bb4d8e4f5898b91cf842b8'
const native_sha = '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d'

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

fn copy_file(root string, from string, to string) ! {
	assert !os.is_link(from), from
	os.mkdir_all(os.dir(root + '/' + to))!
	os.cp(from, root + '/' + to)!
}

fn collect(root string) ! {
	assert !os.exists(root), 'fresh external bundle directory required'
	os.mkdir_all(os.dir(root))!
	parent := os.real_path(os.dir(root))
	assert parent != os.getwd() && !parent.starts_with(os.getwd() + '/'), 'use external state storage'
	os.mkdir_all(root)!
	for directory in [maps + 'attempt248', maps + 'identity248-inputs',
		maps + 'identity246-inputs/interrupted-before-maps',
		maps + 'framework244-action-provider/sources'] {
		for path in os.walk_ext(directory, '') { copy_file(root, path, path)! }
	}
	for path in [maps + 'attempt248-harness.log', maps + 'interact248.log',
		maps + 'framework244-action-provider/exact-sources.json.gz',
		maps + 'framework244-action-provider/framework-manifest.json',
		maps + 'framework244-action-provider/framework-manifest-live-checkout.json',
		maps + 'native236-sources.json', maps + 'native236-exact-sources.json.gz',
		maps + 'native236-source-delta.json', maps + 'native236-production-source-sha256.json',
		maps + 'native236-identity.txt', maps + 'maps-live-vm/boot.img',
		maps + 'GoogleMaps.apk', maps + 'GooglePlayServices.apk', maps + 'GooglePlayStore.apk',
		maps + 'suite239-stream', maps + 'suite239-stream.v', 'build/qemu-horizontal/bin/qemu-system-aarch64'] {
		copy_file(root, path, path)!
	}
	// The compressed snapshot contains all exact compiled source bytes; the
	// historical plain source directory has different path prefixes.
	exact := json2.decode[map[string]string](gzip.decompress(os.read_bytes(maps + 'framework244-action-provider/exact-sources.json.gz')!)!.bytestr())!
	for path, source in exact {
		assert !os.is_abs_path(path) && '..' !in path.split('/'), path
		target := root + '/exact-framework-sources/' + path
		os.mkdir_all(os.dir(target))!
		os.write_file(target, source)!
	}
	helpers := read_map(maps + 'identity248-inputs/helpers-before-run.json')!
	for path, digest in helpers {
		assert hash(path)! == digest, 'pre-run helper changed: ' + path
		copy_file(root, path, path)!
	}
	preflight := json2.decode[map[string]json2.Any](os.read_file(maps + 'identity248-inputs/preflight.json')!)!
	for path, _ in preflight['staged_runtime_sha256']!.as_map() {
		copy_file(root, maps + 'attempt244/module/' + path, 'runtime244/' + path)!
	}
	copy_file(root, '/opt/homebrew/share/qemu/edk2-aarch64-code.fd', 'infrastructure/edk2-aarch64-code.fd')!
	// UEFI variable storage is mutable. This is explicitly the state retained
	// after the run, not a reconstruction of the preflight's earlier bytes.
	copy_file(root, maps + 'maps-live-vm/efivars.fd', 'infrastructure/efivars-after-run.fd')!
	copy_file(root, 'tests/native-android-ws/maps248-evidence.v', 'audit/maps248-evidence.v')!
	os.write_file(root + '/audit/scope.txt', 'Maps248: completed startup_failed, process exit 134. Configured 180 seconds; exited early. Runtime framework244/native236, prepared before later CompoundButton changes. Parent visually inspected map-before-input.png: detailed North America map, water/land, Google Maps branding, Local Vibe and tabs. Search/layers not exercised in this run. Maps246 is an interrupted pre-launch scope without a final result. Preflight identities are historical; retained efivars-after-run.fd is mutable post-run state. No APK patch or exception-classifier changes.\n')!
	mut manifest := map[string]string{}
	for path in os.walk_ext(root, '') { manifest[path.all_after(root + '/')] = hash(path)! }
	os.write_file(root + '/sha256.json', json2.encode(manifest, prettify: true))!
	println('MAPS248-COLLECT files=${manifest.len} manifest_sha256=${hash(root + '/sha256.json')!}')
}

fn verify_sources(root string) ! {
	base := root + '/' + maps
	framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + 'framework244-action-provider/exact-sources.json.gz')!)!.bytestr())!
	manifest := json2.decode[map[string]json2.Any](os.read_file(base + 'framework244-action-provider/framework-manifest.json')!)!
	assert manifest['output_sha256']!.str() == jar_sha
	sources := manifest['sources']!.as_map()
	assert framework.len == 113 && sources.len == 113
	for path, source in framework {
		assert sha256.sum(source.bytes()).hex() == sources[path]!.str(), path
		assert source == os.read_file(root + '/exact-framework-sources/' + path)!, path
	}
	native_sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + 'native236-exact-sources.json.gz')!)!.bytestr())!
	hashes := read_map(base + 'native236-sources.json')!
	assert native_sources.len == 83 && hashes.len == 83
	for path, source in native_sources {
		assert sha256.sum(source.bytes()).hex() == hashes[path]!, path
	}
}

fn verify_runtime(root string) ! {
	base := root + '/' + maps
	assert os.read_file(base + 'identity248-inputs/preflight.json')! == os.read_file(base + 'attempt248/resume-preflight.json')!
	assert hash(base + 'identity248-inputs/preflight.json')! == os.read_file(base + 'identity248-inputs/preflight-sha256.txt')!.trim_space()
	preflight := json2.decode[map[string]json2.Any](os.read_file(base + 'attempt248/resume-preflight.json')!)!
	archive := preflight['archive_runtime_sha256']!.as_map()
	staged := preflight['staged_runtime_sha256']!.as_map()
	assert archive.len == 7 && staged.len == 7
	for path, digest in staged {
		assert digest.str() == archive[path]!.str(), path
		assert hash(root + '/runtime244/' + path)! == digest.str(), path
	}
	assert staged[jar]!.str() == jar_sha && staged[native]!.str() == native_sha
	assert hash(base + 'maps-live-vm/boot.img')! == preflight['boot_image_sha256']!.str()
	assert os.file_size(base + 'maps-live-vm/boot.img') == u64(preflight['boot_image_size']!.i64())
	inputs := preflight['pre_run_sha256']!.as_map()
	for path in [maps + 'suite239-stream', 'build/qemu-horizontal/bin/qemu-system-aarch64'] {
		assert hash(root + '/' + path)! == inputs[path]!.str(), path
	}
	assert hash(base + 'identity248-inputs/vinix')! == inputs['boot/vinix']!.str()
	assert hash(base + 'identity248-inputs/limine.conf')! == inputs['boot/limine.conf']!.str()
	assert hash(root + '/infrastructure/edk2-aarch64-code.fd')! == inputs['/opt/homebrew/share/qemu/edk2-aarch64-code.fd']!.str()
	for path, digest in read_map(base + 'identity248-inputs/helpers-before-run.json')! {
		assert hash(root + '/' + path)! == digest, path
	}
}

fn verify_run(root string) ! {
	base := root + '/' + maps + 'attempt248'
	rows := json2.decode[[]json2.Any](os.read_file(base + '/results.json')!)!
	assert rows.len == 1
	row := rows[0].as_map()
	assert row['id']!.str() == 'google-maps' && row['outcome']!.str() == 'startup_failed'
	assert row['launcher_entered']!.bool() && row['backend_ready']!.bool()
	assert row['native_maps_observed']!.bool() && row['process_exited']!.bool()
	assert row['startup_timeout_seconds']!.int() == 180 && row['startup_seconds']!.int() == 180
	assert row['functional_passed']! is json2.Null
	assert row['failure_markers']!.as_array().len > 0
	serial := gzip.decompress(os.read_bytes(base + '/google-maps/serial.log.gz')!)!.bytestr()
	assert serial == os.read_file(base + '/google-maps/serial.log')!
	assert sha256.sum(serial.bytes()).hex() == row['serial_sha256']!.str()
	assert hash(base + '/google-maps/application.png')! == row['screenshot_sha256']!.str()
	for marker in ['APK-SUITE-BEGIN id=google-maps ', 'APK-SUITE-MAPS ',
		'ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent',
		'JNI DETECTED ERROR IN APPLICATION: JNI NewDirectByteBuffer called with pending exception java.lang.IllegalStateException: Bridge not initialized yet.',
		'ClearcutJniBridge.create()', 'ValidationJni.nativeValidate()',
		'APK-SUITE-EXIT id=google-maps code=134 native_observed=true gtk_x11_absent=true'] {
		assert serial.contains(marker), marker
	}
	ready := serial.index('ANDROID-WS-READY') or { panic('readiness marker missing') }
	exit_at := serial.index('APK-SUITE-EXIT id=google-maps code=134') or { panic('exit marker missing') }
	assert ready < exit_at
	metadata := row['metadata']!.as_map()
	assert metadata['versionName']!.str() == '26.42.01.997557324'
	assert metadata['signature_verification']!.str().contains('Verifies\n')
	assert hash(root + '/' + maps + 'GoogleMaps.apk')! == metadata['apk_sha256']!.str()
	for companion in row['companion_packages']!.as_array() {
		item := companion.as_map()
		assert hash(root + '/' + item['apk']!.str())! == item['metadata']!.as_map()['apk_sha256']!.str()
	}
	for name in ['map-before-input.png', 'map-probe.png', 'initial.png', 'waiting.png', 'network.pcap'] {
		assert os.file_size(base + '/google-maps/' + name) > 0, name
	}
	assert os.read_file(base + '/google-maps/manual-timeline.log')!.contains('MAP-COLOR-DETECTED')
	interrupted := root + '/' + maps + 'identity246-inputs/interrupted-before-maps'
	scope := json2.decode[map[string]json2.Any](os.read_file(interrupted + '/scope.json')!)!
	assert scope['scope']!.str().contains('no final result')
	for path, digest in json2.decode[map[string]string](scope['files_sha256']!.str())! {
		assert hash(interrupted + '/' + path)! == digest, path
	}
	assert !os.read_file(interrupted + '/serial.log')!.contains('ANDROID-WS-READY')
}

fn main() {
	if os.args.len == 3 && os.args[1] == 'collect' { collect(os.args[2])!; return }
	if os.args.len != 4 || os.args[1] != 'check' {
		panic('usage: maps248-evidence collect EXTERNAL_BUNDLE | check BUNDLE SHA256_OF_sha256.json')
	}
	root := os.real_path(os.args[2])
	assert os.args[3].len == 64 && hash(root + '/sha256.json')! == os.args[3], 'manifest differs from report'
	manifest := read_map(root + '/sha256.json')!
	assert manifest.len > 150, 'complete bundle required'
	for path, digest in manifest {
		assert path != '' && !os.is_abs_path(path) && '..' !in path.split('/'), path
		assert digest.len == 64 && hash(root + '/' + path)! == digest, path
	}
	for path in os.walk_ext(root, '') {
		name := path.all_after(root + '/')
		if name != 'sha256.json' { assert name in manifest, 'unlisted file: ' + name }
	}
	verify_sources(root)!
	verify_runtime(root)!
	verify_run(root)!
	println('MAPS248-EVIDENCE PASS: complete retained failure; signed Maps26.42; framework244/native236; ready/map observed before JNI abort134; original startup_failed classifier; Maps246 interrupted without result.')
}
