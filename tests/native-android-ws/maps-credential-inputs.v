// SPDX-License-Identifier: GPL-2.0-or-later
// Verify the private credential experiment before freezing launch inputs.
// Build with -cflags -O2, without -prod: assertions are a tested precondition.
module main

import os
import crypto.sha256
import json2
import time

fn production_source(path string, experiment string) string {
	if experiment in ['255', '256'] && path.starts_with('build-support/android/') {
		snapshot := if experiment == '256' { 'native-priority256' } else { 'native-cache255' }
		return 'build/android-maps/' + snapshot + '/source/' + path.all_after('build-support/android/')
	}
	if experiment == '254' && path in ['build-support/android/native-run.v',
		'build-support/android/nativeidentity/identity.v', 'build-support/android/nativeapk/install.v'] {
		return '/Users/alex/.local/state/vinix/android/maps253-2026-10-24/inputs/' + path
	}
	return path
}

fn production_launcher(experiment string) string {
	return 'build/android-maps/run-android-identity' + if experiment in ['255', '256'] { experiment } else { '253' }
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn checked(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error(args[0] + ': ' + result.output) }
	return result.output
}

fn inventory(root string) !map[string]string {
	mut result := map[string]string{}
	for path in os.walk_ext(root, '', hidden: true) {
		if os.is_file(path) && !os.is_link(path) {
			result[path.all_after(root + '/')] = digest(path)!
		}
	}
	return result
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

fn equal_maps(left map[string]string, right map[string]string) ! {
	if left.len != right.len { return error('inventory lengths differ: ${left.len},${right.len}') }
	for path, hash in left {
		if right[path] or { '' } != hash { return error('inventory hash differs: ' + path) }
	}
}

fn verify(experiment string) ! {
	b := 'build/android-maps/'
	target := b + 'maps' + experiment
	before := read_map(target + '/runtime-before.json')!
	after := read_map(target + '/runtime-after.json')!
	equal_maps(before, read_map(b + 'maps250/runtime-after.json')!)!
	equal_maps(after, inventory(target + '/module')!)!
	if before.len != 106 || after.len != 109 { return error('unexpected runtime file counts') }
	for path, hash in before {
		mapped := if path.starts_with('root/.local/share/vinix/android/application.apk_/') {
			path.replace('root/.local/share/vinix/android/application.apk_', 'tmp/maps' + experiment + '-data')
		} else if path == 'usr/bin/run-android' {
			'usr/bin/run-android-original'
		} else {
			path
		}
		if after[mapped] or { '' } != hash { return error('baseline bytes changed: ' + path) }
	}
	for path, source in {
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar': b + 'compound247/framework/api-impl.jar'
		'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so':                  b + 'compound247/native/libvinix-android-native.so'
		'opt/android-test/application.apk':                                                  b + 'GoogleMaps.apk'
		'usr/bin/run-android':                                                               b + 'credential-launcher' + experiment
		'usr/bin/run-android-identity':                                                      production_launcher(experiment)
	} {
		if after[path] or { '' } != digest(source)! {
			return error('launch artifact differs: ' + path)
		}
	}
	if os.read_file(target + '/module/opt/android-test/credential-run')! != experiment + '\n' {
		return error('wrong credential experiment selector')
	}
	for path, hash in read_map(production_launcher(experiment) + '.receipt.json')! {
		if path.starts_with('/') || path.starts_with('build') {
			if digest(production_source(path, experiment))! != hash {
				return error('production source/compiler receipt differs: ' + path)
			}
		}
	}
	build := read_map(target + '/launcher-build-receipt.json')!
	for pair in [['compiler_path', 'compiler_sha256'],
		['cross_compiler_path', 'cross_compiler_sha256'], ['source_path', 'source_sha256'],
		['binary_path', 'binary_sha256']] {
		if digest(build[pair[0]]!)! != build[pair[1]]! {
			return error('fixture build receipt differs: ' + pair[0])
		}
	}
	if digest(target + '/sources/credential-launcher.v')! != build['source_sha256']! {
		return error('frozen fixture source differs from built source')
	}
	config := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt' + experiment + '.json')!)!
	seconds := if experiment in ['255', '256'] { 900 } else { 300 }
	if config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() != seconds
		|| config['boot_image']!.str() != target + '/vm/boot.img' {
		return error('wrong observation duration or private boot media')
	}
	listing := checked(['/bin/zsh', '-c',
		'set -o pipefail; mtype -i ' + target + '/vm/boot.img ::/boot/qemu-runtime.tar | tar -tf -'])!
	for line in listing.split_into_lines() {
		for part in line.split('/') {
			if part.starts_with('._') || part == '..' {
				return error('unexpected archive member: ' + line)
			}
		}
	}
	scratch := target + '/archive-replay'
	if os.exists(scratch) { return error('replay scratch already exists') }
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { eprintln('cleanup failed: ${err}') } }
	checked(['/bin/zsh', '-c',
		'set -o pipefail; mtype -i ' + target + '/vm/boot.img ::/boot/qemu-runtime.tar | tar -xf - -C ' + scratch])!
	actual := inventory(scratch)!
	equal_maps(after, actual)!
	equal_maps(read_map(target + '/archive-readback.json')!, actual)!
	os.write_file(target + '/assertion-enabled-readback.json', json2.encode(actual, prettify: true) + '\n')!
	os.write_file(target + '/assertion-enabled-validation.txt', time.utc().str() + ' UTC\nCompiled without -prod using -cflags -O2. Independent regular control-flow checks verified106 baseline files,109 staged/archive files, original APK, frozen247 runtime, production source/compiler/binary receipt, fixture build receipt,' + seconds.str() + 'sec private configuration and actual FAT archive readback. Assertions separately exercised by --assertion-probe.\n')!
	println('MAPS${experiment} VALIDATION PASS originals=106 archive=109 assertion_enabled=true')
}

fn freeze(experiment string, root string) ! {
	if os.exists(root) { return error('freeze destination already exists') }
	verify(experiment)!
	os.mkdir_all(root + '/inputs')!
	b := 'build/android-maps/'
	mut paths := ['tests/native-android-ws/maps-credential-inputs.v',
		'tests/native-android-ws/maps-interact.v', 'tests/native-android-ws/credential-launcher.v',
		'tests/native-android-ws/maps-credential-image.v', b + 'maps-credential-inputs',
		b + 'maps-interact-bounded', b + 'credential-launcher' + experiment,
		b + 'suite' + experiment + '-resume', b + 'suite' + experiment + '-resume.v',
		b + 'attempt' + experiment + '.json', 'build/android-run',
		'build/qemu-horizontal/bin/qemu-system-aarch64', b + 'attempt244/companion-packages.json',
		b + 'GoogleMaps.apk', b + 'GooglePlayServices.apk', b + 'GooglePlayStore.apk',
		b + 'compound247/prepare-maps250.v', b + 'compound247/verify-maps250.v']
	for path, _ in read_map(production_launcher(experiment) + '.receipt.json')! {
		if path.starts_with('/') || path.starts_with('build') { paths << path }
	}
	paths << production_launcher(experiment) + '.receipt.json'
	if experiment in ['255', '256'] {
		snapshot := if experiment == '256' { 'native-priority256' } else { 'native-cache255' }
		for path in os.walk_ext(b + snapshot + '/source', '.v', hidden: true) {
			paths << path
		}
	}
	for path in os.walk_ext(b + 'maps' + experiment, '', hidden: true) {
		if !path.contains('/module/') && !path.contains('/vm/') && os.is_file(path) && !os.is_link(path) {
			paths << path
		}
	}
	for kind in ['framework', 'native'] {
		for name in ['sources.json', 'exact-sources.json.gz', 'source-delta.json'] {
			paths << b + 'compound247/' + kind + '/' + name
		}
	}
	paths << b + 'compound247/framework/framework-manifest.json'
	paths << b + 'compound247/framework/api-impl.jar'
	paths << b + 'compound247/native/libvinix-android-native.so'
	mut hashes := map[string]string{}
	for path in paths {
		if path in hashes { continue }
		source := production_source(path, experiment)
		if !os.is_file(source) { return error('missing frozen input: ' + source) }
		dest := root + '/inputs/' + path.trim_left('/')
		os.mkdir_all(os.dir(dest))!
		before := digest(source)!
		checked(['cp', '-c', source, dest])!
		if digest(dest)! != before || digest(source)! != before {
			return error('input changed during freeze: ' + path)
		}
		hashes[path] = before
	}
	firmware := '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'
	checked(['cp', '-c', firmware, root + '/inputs/firmware.fd'])!
	hashes['firmware.fd'] = digest(root + '/inputs/firmware.fd')!
	os.write_file(root + '/frozen-inputs.json', json2.encode(hashes, prettify: true) + '\n')!
	os.write_file(root + '/source-revision.txt', checked(['git', 'rev-parse', 'HEAD'])!.trim_space() + '\n' + time.utc().str() + ' UTC\nMaps' + experiment + ' freeze precedes launch. Frozen247 source maps identify the compiled framework/native runtime. Actual FAT archive replay uses enabled checks; original signed APKs and production source/compiler identities retained. Boot media is not copied or hashed by this input freeze; post-run media and raw outputs must be retained separately.\n')!
	println('MAPS${experiment} INPUTS-FROZEN ' + root + ' files=${hashes.len} manifest_sha256=' + digest(root + '/frozen-inputs.json')!)
}

fn main() {
	$if prod {
		panic('do not compile credential validation with -prod: it disables assertions')
	}
	if os.args.len == 2 && os.args[1] == '--assertion-probe' {
		assert false, 'credential assertion probe must fail'
		return
	}
	if os.args.len != 3 || os.args[1] !in ['253', '254', '255', '256'] {
		panic('usage: maps-credential-inputs 253|254|255|256 EXTERNAL-DIR')
	}
	freeze(os.args[1], os.args[2]) or {
		eprintln('MAPS-CREDENTIAL-INPUTS-FAIL: ${err}')
		exit(1)
	}
}
