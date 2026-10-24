// SPDX-License-Identifier: GPL-2.0-or-later
// Build private Maps credential experiments from the audited Maps250 runtime.
// Generated images and evidence stay in the ignored build directory.
// Compile with -cflags -O2 without -prod so the integrity assertions execute.
module main

import os
import crypto.sha256
import json2
import time

const base = 'build/android-maps/'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn production_source(path string, experiment string) string {
	if experiment in ['255', '256'] && path.starts_with('build-support/android/') {
		snapshot := if experiment == '256' { 'native-priority256' } else { 'native-cache255' }
		return base + snapshot + '/source/' + path.all_after('build-support/android/')
	}
	if experiment == '254' && path in ['build-support/android/native-run.v',
		'build-support/android/nativeidentity/identity.v', 'build-support/android/nativeapk/install.v'] {
		return '/Users/alex/.local/state/vinix/android/maps253-2026-10-24/inputs/' + path
	}
	return path
}

fn production_launcher(experiment string) string {
	return base + 'run-android-identity' + if experiment in ['255', '256'] { experiment } else { '253' }
}

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn inventory(root string) !map[string]string {
	mut hashes := map[string]string{}
	for path in os.walk_ext(root, '', hidden: true) {
		if os.is_file(path) && !os.is_link(path) {
			hashes[path.all_after(root + '/')] = digest(path)!
		}
	}
	return hashes
}

fn main() {
	$if prod {
		panic('build maps-credential-image without -prod; integrity assertions must execute')
	}
	assert os.args.len == 2, 'usage: maps-credential-image 251|252|253|254|255|256'
	experiment := os.args[1]
	assert experiment in ['251', '252', '253', '254', '255', '256']
	target := base + 'maps' + experiment
	helper := base + 'credential-launcher' + experiment
	os.setenv('COPYFILE_DISABLE', '1', true)
	assert !os.exists(target)
	os.mkdir_all(target + '/vm')!
	os.mkdir_all(target + '/module')!
	os.mkdir_all(target + '/sources')!
	for name in ['credential-launcher.v', 'maps-credential-image.v'] {
		os.cp('tests/native-android-ws/' + name, target + '/sources/' + name)!
	}
	compiler := '/Users/alex/code/v/v_old'
	compile_args := [compiler, '-nocache', '-os', 'linux', '-arch', 'arm64', '-cc',
		'aarch64-linux-musl-gcc', '-gc', 'none', '-cflags', '-D_GNU_SOURCE -static', '-ldflags',
		'-static', '-o', helper, 'tests/native-android-ws/credential-launcher.v']
	compile_result := os.exec(compile_args)
	assert compile_result.exit_code == 0, compile_result.output
	assert digest('tests/native-android-ws/credential-launcher.v')! == digest(target + '/sources/credential-launcher.v')!
	cc_result := os.exec(['/bin/zsh', '-c', 'command -v aarch64-linux-musl-gcc'])
	assert cc_result.exit_code == 0, cc_result.output
	cross_compiler := cc_result.output.trim_space()
	build_receipt := {
		'command':               compile_args.join(' ')
		'compiler_path':         compiler
		'compiler_sha256':       digest(compiler)!
		'cross_compiler_path':   cross_compiler
		'cross_compiler_sha256': digest(cross_compiler)!
		'source_path':           'tests/native-android-ws/credential-launcher.v'
		'source_sha256':         digest(target + '/sources/credential-launcher.v')!
		'binary_path':           helper
		'binary_sha256':         digest(helper)!
		'output':                compile_result.output
	}
	os.write_file(target + '/launcher-build-receipt.json', json2.encode(build_receipt,
		prettify: true
	) + '\n')!
	os.write_file(target + '/launcher-build-arguments.json', json2.encode(compile_args,
		prettify: true
	) + '\n')!
	checked(['cp', '-c', base + 'maps-live-vm/boot.img', target + '/vm/boot.img'])
	os.cp(base + 'maps-live-vm/efivars.fd', target + '/vm/efivars.fd')!
	checked(['cp', '-cR', base + 'maps250/module/.', target + '/module/'])
	before := inventory(target + '/module')!
	expected := json2.decode[map[string]string](os.read_file(base + 'maps250/runtime-after.json')!)!
	assert before.len == expected.len
	for name, hash in expected {
		assert before[name]! == hash, name
	}
	jar := 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
	native := 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
	assert before[jar]! == digest(base + 'compound247/framework/api-impl.jar')!
	assert before[native]! == digest(base + 'compound247/native/libvinix-android-native.so')!
	assert before['opt/android-test/application.apk']! == digest(base + 'GoogleMaps.apk')!
	os.mv(target + '/module/usr/bin/run-android', target + '/module/usr/bin/run-android-original')!
	os.cp(helper, target + '/module/usr/bin/run-android')!
	os.chmod(target + '/module/usr/bin/run-android', 0o755)!
	os.mkdir_all(target + '/module/tmp')!
	os.chmod(target + '/module/tmp', 0o1777)!
	os.mv(target + '/module/root/.local/share/vinix/android/application.apk_', target + '/module/tmp/maps' + experiment + '-data')!
	if experiment != '251' {
		os.write_file(target + '/module/opt/android-test/credential-run', experiment + '\n')!
	}
	if experiment in ['253', '254', '255', '256'] {
		production := production_launcher(experiment)
		receipt := json2.decode[map[string]string](os.read_file(production + '.receipt.json')!)!
		for path, hash in receipt {
			if path.starts_with('/') || path.starts_with('build') {
				assert digest(production_source(path, experiment))! == hash, path
			}
		}
		os.cp(production, target + '/module/usr/bin/run-android-identity')!
		os.chmod(target + '/module/usr/bin/run-android-identity', 0o755)!
		os.cp(production + '.receipt.json', target + '/production-launcher-receipt.json')!
		os.cp(production_source('build-support/android/native-run.v', experiment), target + '/sources/native-run.v')!
		os.cp(production_source('build-support/android/nativeidentity/identity.v', experiment), target + '/sources/nativeidentity.v')!
		os.cp(production_source('build-support/android/nativeapk/install.v', experiment), target + '/sources/nativeapk-install.v')!
		if experiment in ['255', '256'] {
			for path, _ in receipt {
				if path.starts_with('build-support/') {
					destination := target + '/sources/production/' + path
					os.mkdir_all(os.dir(destination))!
					os.cp(production_source(path, experiment), destination)!
				}
			}
		}
	}
	after := inventory(target + '/module')!
	assert after.len == before.len + if experiment in ['253', '254', '255', '256'] {
		3
	} else if experiment == '252' {
		2
	} else {
		1
	}
	for name, hash in before {
		mapped := if name.starts_with('root/.local/share/vinix/android/application.apk_/') {
			name.replace('root/.local/share/vinix/android/application.apk_', 'tmp/maps' + experiment + '-data')
		} else if name == 'usr/bin/run-android' {
			'usr/bin/run-android-original'
		} else {
			name
		}
		assert after[mapped]! == hash, mapped
	}
	assert after['usr/bin/run-android']! == digest(helper)!
	if experiment != '251' {
		assert os.read_file(target + '/module/opt/android-test/credential-run')! == experiment + '\n'
	}
	if experiment in ['253', '254', '255', '256'] {
		assert after['usr/bin/run-android-identity']! == digest(production_launcher(experiment))!
	}
	os.write_file(target + '/runtime-before.json', json2.encode(before, prettify: true) + '\n')!
	os.write_file(target + '/runtime-after.json', json2.encode(after, prettify: true) + '\n')!
	checked(['/bin/zsh', '-c',
		'set -o pipefail; tar --format=ustar -b 1 -C ' + target + '/module -cf - . | mcopy -o -i ' + target + '/vm/boot.img - ::/boot/qemu-runtime.tar'])
	// Read the actual FAT archive back, including hidden companion payloads.
	listing := os.exec(['/bin/zsh', '-c',
		'set -o pipefail; mtype -i ' + target + '/vm/boot.img ::/boot/qemu-runtime.tar | tar -tf -'])
	assert listing.exit_code == 0, listing.output
	for line in listing.output.split_into_lines() {
		for part in line.split('/') {
			assert !part.starts_with('._'), line
		}
	}
	os.write_file(target + '/archive-list.txt', listing.output)!
	os.mkdir_all(target + '/archive-check')!
	checked(['/bin/zsh', '-c',
		'set -o pipefail; mtype -i ' + target + '/vm/boot.img ::/boot/qemu-runtime.tar | tar -xf - -C ' + target + '/archive-check'])
	actual := inventory(target + '/archive-check')!
	assert actual.len == after.len
	for name, hash in after {
		assert actual[name]! == hash, name
	}
	os.write_file(target + '/archive-readback.json', json2.encode(actual, prettify: true) + '\n')!
	os.rmdir_all(target + '/archive-check')!
	mut config := json2.decode[map[string]json2.Any](os.read_file(base + 'attempt248.json')!)!
	config['boot_image'] = target + '/vm/boot.img'
	config['efivars'] = target + '/vm/efivars.fd'
	config['output'] = base + 'attempt' + experiment
	if experiment in ['253', '254', '255', '256'] {
		mut applications := config['applications']!.as_array().clone()
		mut application := applications[0].as_map().clone()
		application['startup_seconds'] = if experiment in ['255', '256'] { 900 } else { 300 }
		applications[0] = application
		config['applications'] = applications
	}
	os.write_file(base + 'attempt' + experiment + '.json', json2.encode(config, prettify: true) + '\n')!
	suite := os.read_file(base + 'suite248-resume.v')!
	marker := 'fn validate_resume248(settings map[string]json2.Any, output string) ! {'
	assert suite.count(marker) == 1
	validation := 'fn validate_resume' + experiment + '(settings map[string]json2.Any, output string) ! {\n' +
		' $if prod { panic("build credential suite without -prod; integrity assertions must execute") }\n' +
		' assert settings["boot_image"]!.str() == "' + target + '/vm/boot.img"\n' +
		' expected := json2.decode[map[string]string](os.read_file("' + target + '/runtime-after.json")!)!\n' +
		' for path, hash in expected { assert digest("' + target + '/module/" + path)! == hash, path }\n' +
		' os.cp("build/android-maps/attempt244/companion-packages.json", output + "/companion-packages.json")!\n' +
		' println("MAPS' + experiment + ' PREFLIGHT PASS original APK, frozen247 runtime, isolated real UID10000 fixture; original classifier retained")\n}\n'
	os.write_file(base + 'suite' + experiment + '-resume.v', suite.all_before(marker).replace('validate_resume248', 'validate_resume' + experiment) + validation)!
	mount_scope := if experiment in ['253', '254', '255', '256'] {
		' Administrator self-binds the dedicated runtime and remounts it read-only,nosuid,nodev,strictatime,wxallowed before production identity activation; advertised mount policy is verified as root and executable paths are checked to stay inside this attachment.'
	} else if experiment == '252' {
		' Administrator self-binds the dedicated runtime and remounts it read-only,nosuid,nodev,strictatime,wxallowed before dropping UID; advertised mount policy is verified before and after drop.'
	} else {
		''
	}
	identity_scope := if experiment in ['253', '254', '255', '256'] {
		' Administrator wrapper prepares owned data/home and real passwd/group account, retaining exact original database bytes in serial provenance. It executes the production ' + os.base(production_launcher(experiment)) + ' launcher as root with explicit identity settings; production launcher drops and verifies real/effective/saved Unix UID/GID10000, capabilities, groups and no_new_privs and requires the real account before and after drop. Wrapper does not drop credentials. Configured observation is ' + if experiment in ['255', '256'] { '900sec.' } else { '300sec.' }
	} else {
		' UID fixture genuinely drops real/effective/saved Unix UID/GID10000.'
	}
	diagnostic_scope := if experiment == '254' {
		' Root spectator enabled for at most15sec, publishing bounded ART mappings/status snapshots. Production253 launcher and its frozen source retained unchanged. This run diagnoses the existing crash; no ART cache preparation is added.'
	} else if experiment == '255' {
		' Root spectator disabled. Production launcher prepares the app-owned ART cache; configured duration is not an observed endurance result.'
	} else if experiment == '256' {
		' Root spectator disabled. Production launcher prepares the app-owned ART cache and admits Android application thread priorities before dropping credentials; configured duration is not an observed endurance result.'
	} else { '' }
	os.write_file(target + '/scope.txt', time.utc().str() + ' UTC\nPrivate clone of original Maps244/248 boot image. Frozen247 jar/native inherited from fully inventoried Maps250 staging. Launcher wrapper added, original launcher renamed, companion data moved to /tmp/maps' + experiment + '-data; all original regular-file bytes retained, including unchanged Google APK.' + identity_scope + mount_scope + diagnostic_scope + ' This is not a production app isolation or notification implementation. Actual FAT archive read back with hidden files inventoried and AppleDouble rejected.\n')!
	mut identities := map[string]string{}
	for path in ['tests/native-android-ws/credential-launcher.v',
		'tests/native-android-ws/maps-credential-image.v', target + '/sources/credential-launcher.v',
		target + '/sources/maps-credential-image.v', helper, base + 'attempt' + experiment + '.json'] {
		identities[path] = digest(path)!
	}
	if experiment in ['253', '254', '255', '256'] {
		for path in [production_launcher(experiment), target + '/production-launcher-receipt.json',
			target + '/sources/native-run.v', target + '/sources/nativeidentity.v',
			target + '/sources/nativeapk-install.v'] {
			identities[path] = digest(path)!
		}
	}
	os.write_file(target + '/before-launch-source-identities.json', json2.encode(identities,
		prettify: true
	) + '\n')!
	println('MAPS' + experiment + ' PREPARED actual archive regular files=' + actual.len.str() + '; exact original-byte mapping verified')
}
