// SPDX-License-Identifier: GPL-2.0-or-later
// Fragment consumed by maps334-generate.v.
module main

fn qualify_builds() ! {
	for label in ['native-pinned', 'framework-pinned'] {
		manifest := if label == 'native-pinned' { '40b1099c58abe7fb3729ee2b48fd13d171f9ebaf70d1b83e26b5ad9f93aac163' } else { '6f3d2a9ebcffa24cb61b4a765abb866d90914e96363af241e7cd67a5387d20cf' }
		payload := if label == 'native-pinned' { 'native/libvinix-android-native.so' } else { 'framework/api-impl.jar' }
		pin := if label == 'native-pinned' { '2231ee3def626a72119cd80d646966ec5ba2fa6cd7dd74a790fe9bcb9db5869b' } else { '0229315058b2d24f1f84d886fc47b3fab6fd3b0b7cc7c32f0b9771908276d9ca' }
		ref := read_map(retained + '/' + label + '-build-readback.json')!
		if ref['manifest_sha256']! != manifest || ref['payload']! != payload || ref['payload_sha256']! != pin { return error('exact332 build readback required') }
		count := qualify_build(retained + '/' + label + '-build', manifest, payload, pin)!
		if count.str() != ref['files_checked']! { return error('complete332 build count differs') }
	}
}

fn disk_space() !string {
	text := checked(['/bin/df', '-k', '/Users/alex/.local/state/vinix/android'])!
	if text.trim_space().split_into_lines().last().fields()[3].u64() < 1536 * 1024 { return error('1536 MiB free required before preparation and launch') }
	return text
}

fn qualify_launcher() ! {
	require_pin(retained + '/launcher-build/sha256.json', launcher_manifest)!
	require_pin(retained + '/launcher-build/run-android-calculator', launcher_pin)!
	checked([retained + '/launcher-build/builder', 'check', retained + '/launcher-build', launcher_manifest])!
}

fn qualify_baseline() ! {
	root := retained + '/baseline333'
	require_pin(root + '/prelaunch-sha256.json', previous_pin)!
	equal(tree(root + '/prelaunch', true)!, read_map(root + '/prelaunch-sha256.json')!)!
}

fn media_hash(name string) !string {
	command := quote(os.find_abs_path_of_executable('mtype')!) + ' -i ' + quote(target + '/vm/boot.img') + ' ' + quote('::/boot/' + name) + ' | ' + quote(os.executable()) + ' --hash-stdin'
	return checked(['/bin/zsh', '-c', 'set -o pipefail; ' + command])!.trim_space()
}

fn prepare(native_root string, native_manifest string, native_pin string,
	framework_root string, framework_manifest string, jar_pin string) ! {
	for path in [target, config, output, retained] {
		if os.exists(path) || os.is_link(path) { return error('fresh334 destination required: ' + path) }
	}
	space := disk_space()!
	qualify_runner_build()!
	if native_root != '/Users/alex/.local/state/vinix/android/layout-request332-native-build-2026-10-25'
		|| native_manifest != '40b1099c58abe7fb3729ee2b48fd13d171f9ebaf70d1b83e26b5ad9f93aac163'
		|| native_pin != '2231ee3def626a72119cd80d646966ec5ba2fa6cd7dd74a790fe9bcb9db5869b'
		|| framework_root != '/Users/alex/.local/state/vinix/android/layout-request332-framework-build-2026-10-25'
		|| framework_manifest != '6f3d2a9ebcffa24cb61b4a765abb866d90914e96363af241e7cd67a5387d20cf'
		|| jar_pin != '0229315058b2d24f1f84d886fc47b3fab6fd3b0b7cc7c32f0b9771908276d9ca' { return error('exact unchanged Native332 and Framework332 required') }
	require_pin(previous + '/prelaunch-sha256.json', previous_pin)!
	equal(tree(previous + '/prelaunch', true)!, read_map(previous + '/prelaunch-sha256.json')!)!
	require_pin(launcher_root + '/sha256.json', launcher_manifest)!
	require_pin(launcher_root + '/run-android-calculator', launcher_pin)!
	checked([launcher_root + '/builder', 'check', launcher_root, launcher_manifest])!
	require_pin(compiler, compiler_pin)!
	require_pin(driver, 'abd2dfbb01fddc83ffffae481b5d1fcab35b9ebd279f3f47abae237b00134208')!
	os.mkdir_all(retained)!
	os.write_file(retained + '/disk-before-preparation.txt', space)!
	for label in ['native-pinned', 'framework-pinned'] {
		clone(previous + '/' + label + '-build', retained + '/' + label + '-build')!
		clone(previous + '/' + label + '-build-readback.json', retained + '/' + label + '-build-readback.json')!
	}
	qualify_builds()!
	clone(previous + '/prelaunch', retained + '/baseline333/prelaunch')!
	clone(previous + '/prelaunch-sha256.json', retained + '/baseline333/prelaunch-sha256.json')!
	qualify_baseline()!
	clone(launcher_root, retained + '/launcher-build')!
	qualify_launcher()!
	clone(previous_tree + '/module', target + '/module')!
	before := read_map(previous_tree + '/runtime-after.json')!
	equal(tree(target + '/module', false)!, before)!
	equal(tree(target + '/module', true)!, read_map(previous_tree + '/module-after-typed.json')!)!
	if before.len != 109 || before[native]! != native_pin || before[jar]! != jar_pin || before[launcher]! != '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0' { return error('complete109 qualified333 runtime required') }
	os.cp(launcher_root + '/run-android-calculator', target + '/module/' + launcher)!
	os.chmod(target + '/module/' + launcher, 0o755)!
	mut after := before.clone()
	after[launcher] = launcher_pin
	equal(tree(target + '/module', false)!, after)!
	mut typed := read_map(previous_tree + '/module-after-typed.json')!
	typed[launcher] = launcher_pin
	equal(tree(target + '/module', true)!, typed)!
	write_json(target + '/runtime-before.json', before)!
	write_json(target + '/runtime-after.json', after)!
	write_json(target + '/module-after-typed.json', typed)!
	clone(previous_tree + '/vm', target + '/vm')!
	mut media := map[string]string{}
	for name in ['vinix', 'initramfs.tar', 'qemu-runtime.tar'] { media[name] = media_hash(name)! }
	if media['qemu-runtime.tar']! != '1c6988d1f3d3844425f0e8cbb49a878b3a16f2a270b4eb3852c71dfaa8fe200e' { return error('qualified333 embedded runtime required') }
	old_conf := checked(['mtype', '-i', target + '/vm/boot.img', '::/boot/limine.conf'])!
	if old_conf.count('module_path:') != 2 || !old_conf.ends_with('    module_path: boot():/boot/qemu-runtime.tar\n') { return error('expected initramfs then runtime boot order') }
	os.write_file(target + '/limine-before.conf', old_conf)!
	os.write_file(target + '/limine-after.conf', old_conf + '    module_path: boot():/boot/maps334-diagnostics.tar\n')!
	os.mkdir_all(target + '/overlay/usr/bin')!
	clone(target + '/module/' + launcher, target + '/overlay/' + launcher)!
	if receipt('overlay-archive', ['tar', '--format=ustar', '-b', '1', '-C', target + '/overlay', '-cf', target + '/maps334-diagnostics.tar', launcher])! != 0 { return error('overlay archive failed') }
	if checked(['tar', '-tf', target + '/maps334-diagnostics.tar'])! != launcher + '\n' { return error('only one launcher tar member allowed') }
	os.mkdir_all(target + '/overlay-readback')!
	checked(['tar', '-xf', target + '/maps334-diagnostics.tar', '-C', target + '/overlay-readback'])!
	equal(tree(target + '/overlay-readback', true)!, tree(target + '/overlay', true)!)!
	for item in ['maps334-diagnostics.tar', 'limine-after.conf'] {
		name := if item == 'limine-after.conf' { 'limine.conf' } else { item }
		if receipt('stage-' + name, ['mcopy', '-o', '-i', target + '/vm/boot.img', target + '/' + item, '::/boot/' + name])! != 0 { return error('small overlay media staging failed') }
	}
	if media_hash('maps334-diagnostics.tar')! != hash(target + '/maps334-diagnostics.tar')! || media_hash('limine.conf')! != hash(target + '/limine-after.conf')! { return error('FAT overlay readback differs') }
	for name, pin in media { if media_hash(name)! != pin { return error('base boot member changed: ' + name) } }
	write_json(retained + '/base-media-unchanged.json', media)!
	original := os.read_file(previous_tree + '/suite333.v')!
	mut suite_text := original.replace('validate_styled333', 'validate_styled334').replace('MAPS333', 'MAPS334').replace('build/android-maps/maps333/', 'build/android-maps/maps334/')
	suite_text = once(suite_text, hash(previous_tree + '/runtime-after.json')!, hash(target + '/runtime-after.json')!)!
	suite_text = once(suite_text, hash(previous_tree + '/vm/boot.img')!, hash(target + '/vm/boot.img')!)!
	suite_text = once(suite_text, 'framework/native/clean launcher overlays', 'unchanged framework/native; explicit diagnostic launcher overlay')!
	if classifier(suite_text)! != classifier(original)! { return error('original observation changed') }
	os.write_file(target + '/suite334.v', suite_text)!
	clone(previous_tree + '/sources', target + '/sources')!
	mut settings := object(previous + '/prelaunch/inputs/' + config.replace('334', '333'))!
	settings['boot_image'] = target + '/vm/boot.img'
	settings['efivars'] = target + '/vm/efivars.fd'
	settings['output'] = output
	if settings['applications']!.as_array()[0].as_map()['startup_seconds']!.int() != 600 { return error('expected600 seconds') }
	write_json(config, settings)!
	closure(target + '/suite334.v', target + '/sources|@vlib|@vmodules', 'suite')!
	closure(source, '@vlib|@vmodules', 'runner')!
	if receipt('suite-build', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-path', target + '/sources|@vlib|@vmodules', '-o', target + '/suite334', target + '/suite334.v'])! != 0 { return error('suite compilation failed') }
	if receipt('suite-self-test', [target + '/suite334', '--self-test'])! != 0 { return error('suite classifier self-test failed') }
	mut pins := map[string]string{}
	for path in [target + '/suite334.v', target + '/suite334', target + '/runtime-before.json', target + '/runtime-after.json', target + '/module-after-typed.json', config,
		target + '/vm/boot.img', target + '/vm/efivars.fd', compiler, source, os.executable(), driver,
		settings['aapt2']!.str(), settings['apksigner']!.str(), settings['java']!.str(), settings['firmware']!.str(), settings['qemu']!.str(), settings['input_tool']!.str(), base + 'attempt244/companion-packages.json',
		retained + '/launcher-build/sha256.json', retained + '/launcher-build/builder', retained + '/baseline333/prelaunch-sha256.json'] {
		pins[os.abs_path(path)] = hash(path)!
	}
	for name in ['cp', 'tar', 'mcopy', 'mtype', 'zsh', 'unzip', 'cc'] { path := os.find_abs_path_of_executable(name)!; pins[path] = hash(path)! }
	for app in settings['applications']!.as_array() {
		entry := app.as_map()
		pins[entry['apk']!.str()] = hash(entry['apk']!.str())!
		for companion in entry['companion_apks']!.as_array() { path := companion.as_map()['apk']!.str(); pins[path] = hash(path)! }
	}
	for label in ['suite', 'runner'] {
		for path, pin in read_map(retained + '/' + label + '-v-files.json')! {
			require_pin(path, pin)!
			require_pin(retained + '/' + label + '-closure/' + path.trim_left('/'), pin)!
		}
	}
	write_json(target + '/launch-pins.json', pins)!
	clone(target, retained + '/prelaunch/maps334')!
	for path in pins.keys() {
		if !path.starts_with(os.abs_path(target) + '/') { clone_bytes(path, retained + '/prelaunch/inputs/' + path.trim_left('/'))! }
	}
	write_json(retained + '/references.json', {
		'maps333_prelaunch_root': previous
		'maps333_prelaunch_manifest_sha256': previous_pin
		'launcher_build_root': launcher_root
		'launcher_build_manifest_sha256': launcher_manifest
		'launcher_sha256': launcher_pin
		'changed_runtime_entry': launcher
		'unchanged_runtime_entries': '108'
		'native_sha256': native_pin
		'framework_sha256': jar_pin
		'source_revision': checked(['git', 'rev-parse', 'HEAD'])!.trim_space()
		'classifier_sha256': sha256.sum(classifier(original)!.bytes()).hex()
		'scope': 'Diagnostic launcher only; same109 runtime, native/framework, identity256 and600second observation; ordered final boot module, original kernel/initramfs/runtime unchanged.'
	})!
	clone(outer_build, retained + '/runner-build')!
	os.write_file(retained + '/disk-after-preparation.txt', disk_space()!)!
	write_json(retained + '/prelaunch-sha256.json', tree(retained + '/prelaunch', true)!)!
	println('MAPS334 PREPARED launch-pins=' + hash(target + '/launch-pins.json')! + ' prelaunch=' + hash(retained + '/prelaunch-sha256.json')!)
}

fn gate(pin string, prelaunch_pin string) ! {
	require_pin(target + '/launch-pins.json', pin)!
	require_pin(retained + '/prelaunch-sha256.json', prelaunch_pin)!
	equal(tree(retained + '/prelaunch', true)!, read_map(retained + '/prelaunch-sha256.json')!)!
	for path, expected in read_map(target + '/launch-pins.json')! { require_pin(path, expected)! }
	equal(tree(target + '/module', true)!, read_map(target + '/module-after-typed.json')!)!
	qualify_runner_build()!
	qualify_builds()!
	qualify_baseline()!
	qualify_launcher()!
}
