// SPDX-License-Identifier: GPL-2.0-or-later
// Audit Maps256's retained UI evidence and failed result publication.
// Historical completed-run checkers retain their original stricter contracts.
module main

import compress.gzip
import crypto.sha256
import encoding.base64
import json2
import net.unix
import os
import time

const base = 'build/android-maps/'
const frozen_pin = '7b602e16397db66cb23df41e421238656d0e1d493f29e2fb71683d7c33e1fb64'
const production_pin = 'd6479d8a49f5d65c3190dfbca6e84f306d9becb4923ca89e93a678b2fe9fa5da'
const source_revision = '52d20c9ca4743379f27841b6436acc1e615a4ae7'
const jar = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const scope = 'Maps256 retained after QEMU stopped. The harness ended without results.json and reports a missing-result panic; no completed automated classification or 900-second endurance pass is inferred. The cause of result publication failure is unestablished. Manually reviewed screenshots show onboarding dismissal, a rendered map, Paris search suggestions and place details/photos, Eiffel Tower to Paris directions (19 minutes, 6.1 km), and route preview. The final next-step click has no subsequent screenshot. Account provisioning and the production credential launch path are retained; no independent post-drop process identity measurement was emitted. Some icons display placeholder squares. GPS, sign-in and voice navigation were not verified.\n'

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
	assert actual.len == expected.len, 'inventory lengths differ'
	for path, value in expected { assert actual[path] or { panic('missing: ' + path) } == value, path }
}

fn walk(root string, relative string, mut result map[string]string, omit_qmp bool, mut omitted []string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { result[key] = hash(path)! }
			.symbolic_link { result[key] = 'symlink:' + os.readlink(path)! }
			.directory {
				result[key] = 'directory'
				walk(root, key, mut result, omit_qmp, mut omitted)!
			}
			.socket {
				if !omit_qmp || name != 'qmp.sock' { return error('unexpected socket: ' + path) }
				omitted << key
			}
			else { return error('unexpected special file: ' + path) }
		}
	}
}

fn inventory(root string) !map[string]string {
	assert os.lstat(root)!.get_filetype() == .directory, root
	mut result := map[string]string{}
	mut omitted := []string{}
	walk(root, '', mut result, false, mut omitted)!
	return result
}

fn ordinary(root string, mut omitted []string) !map[string]string {
	mut result := map[string]string{}
	walk(root, '', mut result, true, mut omitted)!
	return result
}

fn regular_files(root string) !map[string]string {
	mut result := inventory(root)!
	for path, value in result.clone() {
		if value == 'directory' || value.starts_with('symlink:') { result.delete(path) }
	}
	return result
}

fn copy_file(from string, to string) ! {
	assert !os.exists(to) && !os.is_link(to), 'destination exists: ' + to
	os.mkdir_all(os.dir(to))!
	if os.lstat(from)!.get_filetype() == .symbolic_link { os.symlink(os.readlink(from)!, to)! }
	else {
		assert os.lstat(from)!.get_filetype() == .regular, from
		$if macos {
			r := os.exec(['cp', '-c', from, to])
			assert r.exit_code == 0, r.output
		} $else { os.cp(from, to)! }
	}
}

fn copy_inventory(from string, to string, entries map[string]string) ! {
	os.mkdir_all(to)!
	for path, value in entries {
		if value == 'directory' { os.mkdir_all(to + '/' + path)! }
		else { copy_file(from + '/' + path, to + '/' + path)! }
	}
	equal_maps(inventory(to)!, entries)
}

fn external(root string) {
	assert os.is_abs_path(root) && os.is_dir(root) && os.real_path(root) == root, 'existing canonical external bundle required'
	assert root != os.real_path(os.getwd()) && !root.starts_with(os.real_path(os.getwd()) + '/'), 'use external state storage'
}

fn verify_frozen(root string) ! {
	assert hash(root + '/frozen-inputs.json')! == frozen_pin, 'prelaunch input freeze differs'
	assert os.read_file(root + '/source-revision.txt')!.starts_with(source_revision + '\n')
	manifest := read_map(root + '/frozen-inputs.json')!
	assert manifest.len == 73
	for path, digest in manifest { assert hash(root + '/inputs/' + path)! == digest, path }
}

fn collect(root string) ! {
	external(root)
	verify_frozen(root)!
	for name in ['run', 'runtime', 'media', 'toolchain', 'audit'] { assert !os.exists(root + '/' + name) && !os.is_link(root + '/' + name), name }
	assert !os.exists(base + 'attempt256/results.json'), 'specific to the run without published results'
	mut omitted := []string{}
	raw := ordinary(base + 'attempt256', mut omitted)!
	runtime := inventory(base + 'maps256/module')!
	copy_inventory(base + 'attempt256', root + '/run', raw)!
	copy_inventory(base + 'maps256/module', root + '/runtime', runtime)!
	for name in ['harness', 'onboarding-driver', 'map-driver'] { copy_file(base + 'attempt256-' + name + '.log', root + '/supplemental/' + name + '.log')! }
	for name, target in {'boot.img': 'boot-after-run.img', 'efivars.fd': 'efivars-after-run.fd'} { copy_file(base + 'maps256/vm/' + name, root + '/media/' + target)! }
	receipt := read_map(root + '/inputs/' + base + 'maps256/launcher-build-receipt.json')!
	for key, name in {'compiler': 'v_old', 'cross_compiler': 'aarch64-linux-musl-gcc'} {
		path := os.real_path(receipt[key + '_path']!)
		assert hash(path)! == receipt[key + '_sha256']!, path
		copy_file(path, root + '/toolchain/' + name)!
	}
	copy_file(root + '/inputs/Users/alex/code/v/v', root + '/toolchain/v_production')!
	os.mkdir_all(root + '/audit')!
	os.write_file(root + '/audit/raw-inventory.json', json2.encode(raw, prettify: true) + '\n')!
	os.write_file(root + '/audit/omitted-special-files.json', json2.encode(omitted) + '\n')!
	mut after_omitted := []string{}
	equal_maps(ordinary(base + 'attempt256', mut after_omitted)!, raw)
	assert after_omitted == omitted
	println('MAPS256 COLLECTED all ordinary run files, supplements, runtime, private post-run media and compiler identities')
}

fn quote(value string) string { return "'" + value.replace("'", "'\\''") + "'" }

fn enrich(root string) ! {
	external(root)
	verify_frozen(root)!
	for name in ['vinix', 'limine.conf'] {
		r := os.exec(['mcopy', '-i', root + '/media/boot-after-run.img', '::/boot/' + name, root + '/media/' + name])
		assert r.exit_code == 0, r.output
	}
	for name in ['passwd', 'group'] {
		r := os.exec(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + quote(root + '/media/boot-after-run.img') + ' ::/boot/initramfs.tar | tar -xOf - ./etc/' + name])
		assert r.exit_code == 0, r.output
		os.write_file(root + '/media/initramfs-' + name, r.output)!
	}
	println('MAPS256 ENRICHED kernel, boot configuration and original base account databases')
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
	prefix := root + '/inputs/' + base
	for path, digest in read_map(prefix + 'maps256/before-launch-source-identities.json')! { assert hash(root + '/inputs/' + path)! == digest, path }
	receipt := read_map(prefix + 'maps256/launcher-build-receipt.json')!
	assert hash(root + '/inputs/' + receipt['source_path']!)! == receipt['source_sha256']!
	assert hash(root + '/inputs/' + receipt['binary_path']!)! == receipt['binary_sha256']!
	assert hash(root + '/toolchain/v_old')! == receipt['compiler_sha256']!
	assert hash(root + '/toolchain/aarch64-linux-musl-gcc')! == receipt['cross_compiler_sha256']!
	production := read_map(prefix + 'maps256/production-launcher-receipt.json')!
	assert production.len == 12
	for path, digest in production { if path.starts_with('/') || path.starts_with('build') { assert hash(root + '/inputs/' + path)! == digest, path } }
	assert hash(prefix + 'run-android-identity256.receipt.json')! == hash(prefix + 'maps256/production-launcher-receipt.json')!
	assert hash(root + '/toolchain/v_production')! == production['/Users/alex/code/v/v']!
	assert production['/opt/homebrew/bin/aarch64-linux-musl-gcc']! == hash(root + '/toolchain/aarch64-linux-musl-gcc')!
	assert hash(prefix + 'run-android-identity256')! == production_pin
	build := json2.decode[map[string]json2.Any](os.read_file(prefix + 'native-priority256/build-receipt.json')!)!
	before := json2.decode[map[string]json2.Any](os.read_file(prefix + 'native-priority256/before-build.json')!)!
	assert build['started']!.str() == before['started']!.str() && before['completed']!.str() == ''
	assert build['completed']!.str() > build['started']!.str() && build['exit_code']!.int() == 0
	assert build['argv']! == before['argv']! && build['sources']! == before['sources']! && build['tools']! == before['tools']!
	assert build['output_sha256']!.str() == production_pin && before['output_sha256']!.str() == ''
	argv := build['argv']!.as_array().map(it.str())
	assert '-prod' !in argv && argv.last().ends_with('/native-priority256/source/native-run.v')
	assert argv.join(' ') == production['command']!
	assert build['sources']!.as_map().len == 4
	for path, digest in build['sources']!.as_map() {
		assert hash(root + '/inputs/' + path)! == digest.str(), path
		assert hash(prefix + 'native-priority256/source/' + path.all_after('build-support/android/'))! == digest.str(), path
		assert hash(prefix + 'maps256/sources/production/' + path)! == digest.str(), path
	}
	for path, digest in build['tools']!.as_map() { assert hash(root + '/inputs/' + path)! == digest.str(), path }
}

fn verify_runtime(root string) ! {
	prefix := root + '/inputs/' + base + 'maps256'
	before := read_map(prefix + '/runtime-before.json')!
	after := read_map(prefix + '/runtime-after.json')!
	equal_maps(read_map(prefix + '/archive-readback.json')!, after)
	equal_maps(read_map(prefix + '/assertion-enabled-readback.json')!, after)
	equal_maps(regular_files(root + '/runtime')!, after)
	assert before.len == 106 && after.len == 109
	for path, digest in before {
		mapped := if path.starts_with('root/.local/share/vinix/android/application.apk_/') { path.replace('root/.local/share/vinix/android/application.apk_', 'tmp/maps256-data') }
			else if path == 'usr/bin/run-android' { 'usr/bin/run-android-original' } else { path }
		assert after[mapped]! == digest, mapped
	}
	assert after['usr/bin/run-android']! == hash(root + '/inputs/' + base + 'credential-launcher256')!
	assert after['usr/bin/run-android-identity']! == production_pin
	assert os.read_file(root + '/runtime/opt/android-test/credential-run')! == '256\n'
	assert after[jar]! == '73a10513135f9e264df9afdc7139c5370d67016d864be82fe0d6b2adba1f459b'
	assert after[native]! == '78893e6767c9398a7d6cb513f0f34b8536604afaa065e383f46cb98e9d003f37'
	assert after[jar]! == hash(root + '/inputs/' + base + 'compound247/framework/api-impl.jar')!
	assert after[native]! == hash(root + '/inputs/' + base + 'compound247/native/libvinix-android-native.so')!
	assert after['opt/android-test/application.apk']! == hash(root + '/inputs/' + base + 'GoogleMaps.apk')!
	for package, name in {'com.google.android.gms': 'GooglePlayServices.apk', 'com.android.vending': 'GooglePlayStore.apk'} { assert after['tmp/maps256-data/_installed_apks_/' + package + '.apk']! == hash(root + '/inputs/' + base + name)! }
}

fn account_bytes(serial string, name string, phase string) string {
	prefix := 'MAPS256-ACCOUNT-BYTES path=/etc/' + name + ' '
	lines := serial.split_into_lines().filter(it.starts_with(prefix))
	assert lines.len == 1, prefix
	value := lines[0].trim_space().all_after(phase + '_base64=').all_before(' ')
	decoded := base64.decode(value).bytestr()
	assert base64.encode(decoded.bytes()) == value
	return decoded
}

fn verify_accounts(root string, serial string) ! {
	for name, addition in {'passwd': 'maps256:x:10000:10000:Maps credential fixture:/tmp/maps256-home:/bin/sh\n', 'group': 'maps256:x:10000:\n'} {
		before := account_bytes(serial, name, 'before')
		after := account_bytes(serial, name, 'after')
		assert before.len > 0 && before.ends_with('\n') && after == before + addition
		assert before == os.read_file(root + '/media/initramfs-' + name)!
		assert serial.contains('MAPS256-ACCOUNT-DATABASE path=/etc/${name} original_bytes=${before.len} before_sha256=${sha256.sum(before.bytes()).hex()} after_sha256=${sha256.sum(after.bytes()).hex()} original_prefix=retained')
		for line in before.split_into_lines() {
			fields := line.split(':')
			assert fields.len >= 3 && fields[0] != 'maps256' && fields[2] != '10000'
		}
		assert !os.exists(root + '/runtime/etc/' + name)
	}
	assert serial.contains('MAPS256-ACCOUNT-RESOLVED name=maps256 uid=10000 gid=10000 home=/tmp/maps256-home')
}

fn verify_run(root string) ! {
	assert !os.exists(root + '/run/results.json') && !os.exists(root + '/run/google-maps/serial.log.gz')
	equal_maps(inventory(root + '/run')!, read_map(root + '/audit/raw-inventory.json')!)
	omitted := json2.decode[[]string](os.read_file(root + '/audit/omitted-special-files.json')!)!
	assert omitted.len <= 1 && omitted.all(it == 'google-maps/qmp.sock')
	serial := os.read_file(root + '/run/google-maps/serial.log')!
	for marker in ['APK-SUITE-BEGIN id=google-maps backend=vinix-ws', 'ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent', 'MAPS256-RUNTIME-MOUNT-ADMIN /opt/vinix-android-aarch64 /opt/vinix-android-aarch64 tmpfs ro,nosuid,nodev,wxallowed,relatime 0 0', 'MAPS256-PRODUCTION-LAUNCH root=0,0 uid=10000 gid=10000 data=/tmp/maps256-data home=/tmp/maps256-home surface='] { assert serial.contains(marker), marker }
	for marker in ['APK-SUITE-EXIT id=google-maps', 'No permission to set thread priority', 'JNI DETECTED ERROR', 'Fatal signal 11'] { assert !serial.contains(marker), marker }
	verify_accounts(root, serial)!
	harness := os.read_file(root + '/supplemental/harness.log')!
	assert harness.contains('MAPS256 PREFLIGHT PASS original APK, frozen247 runtime')
	assert harness.contains('terminating on signal 15') && harness.contains('V panic: failed to open file') && harness.contains('/attempt256/results.json')
	assert !harness.contains('APK-SUITE result google-maps')
	config := json2.decode[map[string]json2.Any](os.read_file(root + '/inputs/' + base + 'attempt256.json')!)!
	assert config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 900
	assert config['output']!.str() == base + 'attempt256'
	interaction := os.read_file(root + '/run/google-maps/interaction.log')!
	for marker in ["'input', 'type', 'Paris'", "'input', 'type', 'Eiffel Tower'", "'input', 'click', '184', '695'", "'input', 'click', '566', '683'", 'SKIP-CLICK'] { assert interaction.contains(marker), marker }
	assert !interaction.contains('timed_out=true') && !interaction.contains('output_drain_capped=true')
	for line in interaction.split_into_lines() {
		if line.contains(' BEGIN [') {
			for stream in ['stdout', 'stderr'] {
				path := line.all_after(stream + '=').all_before(' ')
				assert path.starts_with(os.getwd() + '/' + base + 'attempt256/google-maps/'), path
				assert os.lstat(root + '/run/google-maps/' + os.file_name(path))!.get_filetype() == .regular
			}
		}
	}
	for name in ['onboarding', 'after-skip', 'map', 'search-open', 'search-ready', 'paris-query', 'paris-result', 'directions-open', 'origin-suggestions', 'route-first', 'route-preview'] {
		bytes := os.read_bytes(root + '/run/google-maps/' + name + '.png')!
		assert bytes.len > 1000 && bytes[..8] == [u8(137), 80, 78, 71, 13, 10, 26, 10], name
	}
	assert os.file_size(root + '/run/google-maps/network.pcap') > 24
	assert os.read_file(root + '/supplemental/onboarding-driver.log')!.contains('SKIP-CLICK')
	assert os.read_file(root + '/supplemental/map-driver.log')!.contains('PIXEL-PROBE-PRESENTED map; screenshot requires visual review')
}

fn verify_media(root string) ! {
	println('MAPS256 MEDIA-BEGIN complete actual FAT archive replay')
	media := root + '/media/boot-after-run.img'
	assert os.file_size(media) == u64(4294967296) && os.file_size(root + '/media/efivars-after-run.fd') == u64(67108864)
	os.setenv('COPYFILE_DISABLE', '1', true)
	listing := os.exec(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + quote(media) + ' ::/boot/qemu-runtime.tar | tar -tf -'])
	assert listing.exit_code == 0, listing.output
	assert listing.output == os.read_file(root + '/inputs/' + base + 'maps256/archive-list.txt')!
	for line in listing.output.split_into_lines() { for part in line.split('/') { assert !part.starts_with('._') && part != '..', line } }
	scratch := os.join_path(os.temp_dir(), 'vinix-maps256-${os.getpid()}-${time.now().unix()}')
	assert !os.exists(scratch)
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	extract := os.exec(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + quote(media) + ' ::/boot/qemu-runtime.tar | tar -xf - -C ' + quote(scratch)])
	assert extract.exit_code == 0, extract.output
	equal_maps(inventory(scratch)!, inventory(root + '/runtime')!)
	for name in ['vinix', 'limine.conf'] {
		r := os.exec(['mtype', '-i', media, '::/boot/' + name])
		assert r.exit_code == 0 && sha256.sum(r.output.bytes()).hex() == hash(root + '/media/' + name)!, name
	}
	for name in ['passwd', 'group'] {
		r := os.exec(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + quote(media) + ' ::/boot/initramfs.tar | tar -xOf - ./etc/' + name])
		assert r.exit_code == 0 && r.output == os.read_file(root + '/media/initramfs-' + name)!, name
	}
	prelaunch := read_map(root + '/inputs/' + base + 'maps256/prelaunch-media-sha256.json')!
	assert prelaunch.len == 2
	assert prelaunch[base + 'maps256/vm/boot.img']! == 'a6f7a5307c604aed57d9e190ea719b2c6a00ae6cbe062ff0d6a41c7430a517aa'
	assert prelaunch[base + 'maps256/vm/efivars.fd']! == 'f0c577062133831fe8795ad8dbcc30cc1a4b718cdba5937853ee8a52afbbc952'
	println('MAPS256 MEDIA-END actual FAT payload matches complete retained runtime and base accounts')
}

fn seal(root string) ! {
	external(root)
	verify_frozen(root)!
	verify_sources(root)!
	verify_runtime(root)!
	verify_run(root)!
	verify_media(root)!
	copy_file(@FILE, root + '/audit/maps256-evidence.v')!
	os.write_file(root + '/audit/scope.txt', scope)!
	manifest := inventory(root)!
	assert 'sha256.json' !in manifest
	os.write_file(root + '/sha256.json', json2.encode(manifest, prettify: true) + '\n')!
	println('MAPS256 SEALED entries=${manifest.len} manifest_sha256=${hash(root + '/sha256.json')!}')
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
	assert os.read_file(root + '/audit/maps256-evidence.v')! == os.read_file(@FILE)!
	assert os.read_file(root + '/audit/scope.txt')! == scope
	println('MAPS256-EVIDENCE PASS complete retained run and manual UI artifacts; no automated outcome or endurance pass inferred')
}

fn negative(root string, pinned string) ! {
	external(root)
	assert hash(root + '/sha256.json')! == pinned
	directory := root + '-negative'
	assert !os.exists(directory), 'fresh negative audit directory required'
	copy_file(root + '/sha256.json', directory + '/partial/sha256.json')!
	partial := os.exec([os.executable(), 'check', directory + '/partial', pinned])
	assert partial.exit_code != 0 && partial.output.contains('inventory lengths differ'), partial.output
	os.write_file(directory + '/partial.log', partial.output)!
	wrong_pin := os.exec([os.executable(), 'check', root, '0'.repeat(64)])
	assert wrong_pin.exit_code != 0 && wrong_pin.output.contains('manifest differs from report'), wrong_pin.output
	os.write_file(directory + '/wrong-pin.log', wrong_pin.output)!
	println('MAPS256-NEGATIVE PASS authentic partial bundle and wrong pin rejected')
}

fn tree_test(root string) ! {
	assert os.is_abs_path(root) && !os.exists(root)
	os.mkdir_all(root + '/source/nested/empty')!
	os.write_file(root + '/source/.hidden', 'retained\n')!
	os.symlink('missing', root + '/source/dangling')!
	mut socket := unix.listen_stream(root + '/source/nested/qmp.sock', unix.ListenOptions{})!
	mut omitted := []string{}
	entries := ordinary(root + '/source', mut omitted)!
	assert omitted == ['nested/qmp.sock']
	copy_inventory(root + '/source', root + '/copy', entries)!
	assert os.read_file(root + '/copy/.hidden')! == 'retained\n' && os.readlink(root + '/copy/dangling')! == 'missing'
	assert os.is_dir(root + '/copy/nested/empty')
	socket.close()!
	fifo := os.exec(['mkfifo', root + '/source/nested/qmp.sock'])
	assert fifo.exit_code == 0, fifo.output
	mut rejected := false
	_ := ordinary(root + '/source', mut omitted) or { rejected = true; map[string]string{} }
	assert rejected, 'FIFO must be rejected before copying'
	os.rm(root + '/source/nested/qmp.sock')!
	mut other := unix.listen_stream(root + '/source/other.sock', unix.ListenOptions{})!
	rejected = false
	_ := ordinary(root + '/source', mut omitted) or { rejected = true; map[string]string{} }
	assert rejected, 'unexpected socket must be rejected'
	other.close()!
	println('MAPS256-TREE PASS actual qmp socket omitted; FIFO/other socket rejected; hidden file, dangling link and empty directory retained')
}

fn main() {
	$if prod { eprintln('Maps256 evidence auditing requires assertions; compile without -prod'); exit(2) }
	if os.args.len == 3 {
		match os.args[1] {
			'collect' { collect(os.args[2])! }
			'enrich' { enrich(os.args[2])! }
			'seal' { seal(os.args[2])! }
			'--tree-self-test' { tree_test(os.args[2])! }
			else { panic('unknown action') }
		}
		return
	}
	if os.args.len == 4 && os.args[1] == 'check' { check(os.args[2], os.args[3])!; return }
	if os.args.len == 4 && os.args[1] == 'negative' { negative(os.args[2], os.args[3])!; return }
	panic('usage: maps256-evidence collect|enrich|seal EXTERNAL_BUNDLE | check|negative BUNDLE MANIFEST_SHA256 | --tree-self-test FRESH_EXTERNAL_DIR')
}
