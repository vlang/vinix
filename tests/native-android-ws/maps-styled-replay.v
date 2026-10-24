// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare Maps261 without starting QEMU. The frozen256 classifier and identity
// remain unchanged; only the paired260 framework/native artifacts are overlaid.
module main

import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/'
const target = base + 'maps261'
const compound = base + 'compound260'
const driver = base + 'maps-interact-unique258'
const compiler = '/Users/alex/code/v/v_old'
const frozen_pin = '7b602e16397db66cb23df41e421238656d0e1d493f29e2fb71683d7c33e1fb64'
const driver_pin = 'abd2dfbb01fddc83ffffae481b5d1fcab35b9ebd279f3f47abae237b00134208'
const driver_source_pin = 'bd7ee074d8b95ad3671d184ee3ae35072171d2a22bcc476c308e464d90a5dfcc'
const jar = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'

// HASH-BEGIN
fn styled_hash(path string) !string {
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
// HASH-END

fn checked(argv []string) !string {
	r := os.exec(argv)
	if r.exit_code != 0 { return error(argv.str() + ': ' + r.output) }
	return r.output
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

fn clone(from string, to string) ! {
	if os.exists(to) || os.is_link(to) { return error('fresh clone destination required: ' + to) }
	os.mkdir_all(os.dir(to))!
	checked(['cp', '-c', '-R', '-P', from, to])!
}

// Launch pins hash executable bytes. Resolve single-file inputs while full
// historical trees above retain their original symlink entries.
fn clone_pinned_file(from string, to string) ! {
	resolved := os.real_path(from)
	if os.lstat(resolved)!.get_filetype() != .regular { return error('regular launch input required: ' + from) }
	clone(resolved, to)!
	if os.is_link(to) { return error('retained launch input must contain file bytes: ' + to) }
}

fn inventory(root string, relative string, mut entries map[string]string, regular_only bool) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = styled_hash(path)! }
			.directory {
				if !regular_only { entries[key] = 'directory' }
				inventory(root, key, mut entries, regular_only)!
			}
			.symbolic_link { if !regular_only { entries[key] = 'symlink:' + os.readlink(path)! } }
			else { return error('unexpected special file: ' + path) }
		}
	}
}

fn files(root string) !map[string]string {
	mut entries := map[string]string{}
	inventory(root, '', mut entries, true)!
	return entries
}

fn equal_maps(actual map[string]string, expected map[string]string) ! {
	if actual.len != expected.len { return error('inventory lengths differ') }
	for path, value in expected {
		if actual[path] or { '' } != value { return error('inventory differs: ' + path) }
	}
}

fn overlay_delta(before map[string]string, after map[string]string) ! {
	if before.len != 109 || after.len != 109 { return error('complete109 regular runtime files required') }
	mut changed := []string{}
	for path, value in before {
		if path !in after { return error('runtime file removed: ' + path) }
		if after[path]! != value { changed << path }
	}
	changed.sort()
	mut expected := [jar, native]
	expected.sort()
	if changed != expected { return error('only framework JAR/native overlay may differ: ' + changed.str()) }
}

fn replace_once(source string, before string, after string) !string {
	if source.count(before) != 1 { return error('unexpected frozen source block: ' + before) }
	return source.replace(before, after)
}

fn observation(source string) string {
	return source.all_after('fn observation(').all_before('// Real companion packages')
}

fn suite_source(original string, runtime_pin string, boot_pin string, firmware_pin string) !string {
	mut source := replace_once(original, 'fn main() {', 'fn main() {\n\t$if prod { eprintln("styled replay requires assertions; compile without -prod"); exit(2) }')!
	source = replace_once(source, 'validate_resume256(settings, output)!', 'validate_styled261(settings, output)!')!
	start := source.index('fn validate_resume256(') or { return error('missing original preflight') }
	source = source[..start] + '
fn validate_styled261(settings map[string]json2.Any, output string) ! {
 $if prod { return error("styled replay requires assertions; compile without -prod") }
 assert settings["boot_image"]!.str() == "build/android-maps/maps261/vm/boot.img"
 assert settings["efivars"]!.str() == "build/android-maps/maps261/vm/efivars.fd"
 assert settings["applications"]!.as_array()[0].as_map()["startup_seconds"]!.int() == 240
 assert styled_hash("build/android-maps/maps261/runtime-after.json")! == "RUNTIME_PIN"
 expected := json2.decode[map[string]string](os.read_file("build/android-maps/maps261/runtime-after.json")!)!
 assert expected.len == 109
 mut count := 0
 for path in os.walk_ext("build/android-maps/maps261/module", "", hidden: true) {
  if os.is_file(path) && !os.is_link(path) {
   count++
   assert styled_hash(path)! == expected[path.all_after("build/android-maps/maps261/module/")]!, path
  }
 }
 assert count == 109
 assert styled_hash("build/android-maps/maps261/vm/boot.img")! == "BOOT_PIN"
 assert styled_hash("build/android-maps/maps261/vm/efivars.fd")! == "FIRMWARE_PIN"
 assert styled_hash("build/android-maps/maps-interact-unique258")! == "DRIVER_PIN"
 os.cp("build/android-maps/attempt244/companion-packages.json", output + "/companion-packages.json")!
 println("MAPS261 PREFLIGHT PASS109 files; only paired260 overlays; original classifier and identity256 retained")
}
'.replace('RUNTIME_PIN', runtime_pin).replace('BOOT_PIN', boot_pin).replace('FIRMWARE_PIN', firmware_pin).replace('DRIVER_PIN', driver_pin)
	source += os.read_file(@FILE)!.all_after('// HASH-BEGIN\n').all_before('// HASH-END')
	old_capture := '\tcapture := os.exec([settings[\'input_tool\']!.str(), \'screenshot\', \'--socket\', socket, \'--destination\',\n\t\tframe])'
	new_capture := '\tresult[\'observation_elapsed_seconds\'] = json2.Any(time.now().unix() - begin_at)\n\tresult[\'qemu_alive_before_capture\'] = json2.Any(qemu.is_alive())\n\tos.write_file(state + \'/observation-before-capture.json\', json2.encode(result, prettify: true) + \'\\n\')!\n\tprintln(\'MAPS261 observation retained before final capture\')\n\tcapture := os.exec([\'build/android-maps/maps-interact-unique258\', state, \'capture\', \'application\'])'
	source = replace_once(source, old_capture, new_capture)!
	source = replace_once(source, '\tqemu.run()', '\tmut start_pins := map[string]string{}\n\tfor path in [os.executable(), os.args[1], settings[\'boot_image\']!.str(), settings[\'efivars\']!.str(), settings[\'qemu\']!.str(), settings[\'firmware\']!.str(), \'build/android-maps/maps261/runtime-after.json\', \'build/android-maps/maps-interact-unique258\'] { start_pins[path] = styled_hash(path)! }\n\tos.write_file(state + \'/start-receipt.json\', json2.encode({\'recorded_before_qemu_run_utc\': json2.Any(time.utc().str()), \'qemu_argv\': json2.Any([qemu.filename, ...qemu.args]), \'sha256\': json2.decode[json2.Any](json2.encode(start_pins))!}, prettify: true) + \'\\n\')!\n\tqemu.run()')!
	if observation(source) != observation(original) || observation(original).len < 1000 {
		return error('original observation classifier changed or missing')
	}
	return source
}

// Extract before and after replacement so the actual FAT payload, including
// hidden companion files, is checked independently of the staged directory.
fn archive_readback(label string, expected map[string]string) ! {
	listing := checked(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + target + '/vm/boot.img ::/boot/qemu-runtime.tar | tar -tf -'])!
	for line in listing.split_into_lines() {
		for part in line.split('/') {
			if part == '..' || part.starts_with('._') { return error('unsafe or AppleDouble archive entry: ' + line) }
		}
		if line.starts_with('/') { return error('absolute archive entry') }
	}
	os.write_file(target + '/archive-' + label + '-list.txt', listing)!
	scratch := target + '/archive-check-' + label
	if os.exists(scratch) { return error('fresh readback scratch required') }
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { eprintln(err) } }
	checked(['/bin/zsh', '-c', 'set -o pipefail; mtype -i ' + target + '/vm/boot.img ::/boot/qemu-runtime.tar | tar -xf - -C ' + scratch])!
	actual := files(scratch)!
	equal_maps(actual, expected)!
	write_json(target + '/archive-' + label + '-readback.json', actual)!
}

fn external_path(root string) ! {
	if !os.is_abs_path(root) || os.is_link(root) { return error('absolute external state directory required') }
	if !os.is_dir(os.dir(root)) { return error('external parent directory must exist') }
	resolved := os.real_path(os.dir(root)) + '/' + os.file_name(root)
	repo := os.real_path(os.getwd())
	if resolved == repo || resolved.starts_with(repo + '/') { return error('state directory must be outside checkout') }
}

fn check_external(root string, pin string) ! {
	external_path(root)!
	if pin.len != 64 || styled_hash(root + '/prelaunch-sha256.json')! != pin { return error('wrong external inventory pin') }
	mut actual := map[string]string{}
	inventory(root + '/prelaunch', '', mut actual, false)!
	equal_maps(actual, read_map(root + '/prelaunch-sha256.json')!)!
	println('MAPS261 PRELAUNCH CHECK PASS entries=' + actual.len.str())
}

fn prepare(frozen string, media string, external string) ! {
	external_path(external)!
	if os.exists(target) || os.exists(base + 'attempt261') || os.exists(external) || os.exists(base + 'attempt261.json') {
		return error('fresh Maps261 and external destinations required; partial evidence is preserved')
	}
	if styled_hash(frozen + '/frozen-inputs.json')! != frozen_pin { return error('wrong Maps256 input pin') }
	inputs := read_map(frozen + '/frozen-inputs.json')!
	if inputs.len != 73 { return error('complete73 frozen inputs required') }
	for path, digest in inputs {
		if styled_hash(frozen + '/inputs/' + path.trim_left('/'))! != digest { return error('frozen input differs: ' + path) }
	}
	for path in [base + 'GoogleMaps.apk', base + 'GooglePlayServices.apk', base + 'GooglePlayStore.apk', base + 'run-android-identity256', base + 'attempt244/companion-packages.json', 'build/android-run', 'build/qemu-horizontal/bin/qemu-system-aarch64'] {
		if styled_hash(path)! != inputs[path]! { return error('original APK, identity or tool differs: ' + path) }
	}
	if styled_hash('/opt/homebrew/share/qemu/edk2-aarch64-code.fd')! != inputs['firmware.fd']! { return error('original QEMU firmware differs') }
	if styled_hash(driver)! != driver_pin || styled_hash('tests/native-android-ws/maps-interact.v')! != driver_source_pin { return error('wrong unique258 capture driver') }
	for label in ['build-framework-compiler', 'build-framework', 'generate-native', 'build-native', 'fixture-compiler', 'fixture'] {
		receipt := json2.decode[map[string]json2.Any](os.read_file(compound + '/' + label + '-receipt.json')!)!
		if receipt['exit_code']!.int() != 0 || receipt['completed_utc']!.str() == '' || !os.is_file(compound + '/' + label + '-before.json') { return error('incomplete paired260 build: ' + label) }
		artifact := if label == 'build-framework' { compound + '/framework/api-impl.jar' }
			else if label == 'build-native' { compound + '/native/libvinix-android-native.so' } else { '' }
		if artifact != '' && styled_hash(artifact)! != receipt['output_sha256']!.str() { return error('260 artifact differs from completed build receipt: ' + label) }
	}
	for kind, count in {'framework': 125, 'native': 83} {
		sources := read_map(compound + '/' + kind + '/sources.json')!
		if sources.len != count { return error('incomplete frozen260 sources') }
		directory := if kind == 'framework' { '/sources/' } else { '/atlframework/' }
		for path, digest in sources { if styled_hash(compound + '/' + kind + directory + path)! != digest { return error('260 source differs: ' + path) } }
	}
	before := read_map(frozen + '/inputs/' + base + 'maps256/runtime-after.json')!
	equal_maps(files(base + 'maps256/module')!, before)!
	if os.abs_path(media) !in [os.abs_path(base + 'maps257/vm'), os.abs_path(base + 'maps256/vm')] { return error('stopped Maps257/256 media required') }
	mut media_before := map[string]string{}
	for name in ['boot.img', 'efivars.fd'] {
		path := media + '/' + name
		if !os.is_file(path) || os.is_link(path) { return error('regular private media required') }
		media_before[name] = styled_hash(path)!
	}
	os.setenv('COPYFILE_DISABLE', '1', true)
	os.mkdir_all(target + '/vm')!
	write_json(target + '/source-media-before.json', media_before)!
	clone(base + 'maps256/module', target + '/module')!
	for name in ['boot.img', 'efivars.fd'] {
		clone(media + '/' + name, target + '/vm/' + name)!
		if styled_hash(target + '/vm/' + name)! != media_before[name]! { return error('initial media clone differs: ' + name) }
	}
	equal_maps(files(target + '/module')!, before)!
	write_json(target + '/runtime-before.json', before)!
	archive_readback('before', before)!
	os.cp(compound + '/framework/api-impl.jar', target + '/module/' + jar)!
	os.cp(compound + '/native/libvinix-android-native.so', target + '/module/' + native)!
	after := files(target + '/module')!
	overlay_delta(before, after)!
	write_json(target + '/runtime-after.json', after)!
	checked(['/bin/zsh', '-c', 'set -o pipefail; tar --format=ustar -b 1 -C ' + target + '/module -cf - . | mcopy -o -i ' + target + '/vm/boot.img - ::/boot/qemu-runtime.tar'])!
	archive_readback('after', after)!
	for name, digest in media_before { if styled_hash(media + '/' + name)! != digest { return error('source media changed during preparation') } }
	boot_pin := styled_hash(target + '/vm/boot.img')!
	firmware_pin := styled_hash(target + '/vm/efivars.fd')!
	if firmware_pin != media_before['efivars.fd']! { return error('firmware clone differs') }
	original := os.read_file(frozen + '/inputs/' + base + 'suite256-resume.v')!
	os.write_file(target + '/suite261.v', suite_source(original, styled_hash(target + '/runtime-after.json')!, boot_pin, firmware_pin)!)!
	mut config := json2.decode[map[string]json2.Any](os.read_file(frozen + '/inputs/' + base + 'attempt256.json')!)!
	config['boot_image'] = target + '/vm/boot.img'
	config['efivars'] = target + '/vm/efivars.fd'
	config['output'] = base + 'attempt261'
	mut apps := config['applications']!.as_array()
	mut app := apps[0].as_map().clone()
	app['startup_seconds'] = json2.Any(240)
	apps[0] = json2.Any(app)
	config['applications'] = json2.Any(apps)
	write_json(base + 'attempt261.json', config)!
	os.mkdir_all(target + '/sources/nativeapk')!
	clone(frozen + '/inputs/build-support/android/nativeapk/install.v', target + '/sources/nativeapk/install.v')!
	argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-path', target + '/sources|@vlib|@vmodules', '-o', target + '/suite261', target + '/suite261.v']
	cc := os.find_abs_path_of_executable('cc')!
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'compiler_sha256': json2.Any(styled_hash(compiler)!), 'source_sha256': json2.Any(styled_hash(target + '/suite261.v')!), 'nativeapk_source_sha256': json2.Any(styled_hash(target + '/sources/nativeapk/install.v')!), 'cc_path': json2.Any(cc), 'cc_sha256': json2.Any(styled_hash(cc)!)}
	write_json(target + '/build-before.json', receipt)!
	build := os.exec(argv)
	os.write_file(target + '/build.log', build.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(build.exit_code)
	if build.exit_code == 0 { receipt['binary_sha256'] = styled_hash(target + '/suite261')! }
	write_json(target + '/build-receipt.json', receipt)!
	if build.exit_code != 0 { return error('suite build failed: ' + build.output) }
	os.write_file(target + '/self-test.log', checked([target + '/suite261', '--self-test'])!)!
	os.write_file(target + '/scope.txt', 'Prepared, not launched. Private stopped-media clone.109 original regular runtime files, exactly two paired260 overlay differences, actual FAT archive read back before/after. Original signed APKs and production identity256 remain fixed. Configured240 seconds is an observation limit. Original classifier is byte-identical. Preliminary observation precedes bounded unique258 final capture. Chip checkbox overlays are the visual target; suggestion circles remain separate. Start receipt is written immediately before QEMU starts. Driver build receipt was recorded after compilation, not before.\n')!
	mut pins := map[string]string{}
	for path in [target + '/vm/boot.img', target + '/vm/efivars.fd', target + '/suite261.v', target + '/suite261', target + '/runtime-before.json', target + '/runtime-after.json', base + 'attempt261.json', compiler, cc, os.executable(), @FILE, driver, 'tests/native-android-ws/maps-interact.v', 'build/android-run', 'build/qemu-horizontal/bin/qemu-system-aarch64', config['aapt2']!.str(), config['apksigner']!.str(), config['java']!.str(), config['firmware']!.str()] { pins[path] = styled_hash(path)! }
	for path in [base + 'GoogleMaps.apk', base + 'GooglePlayServices.apk', base + 'GooglePlayStore.apk', base + 'run-android-identity256', base + 'attempt244/companion-packages.json'] { pins[path] = styled_hash(path)! }
	write_json(target + '/prelaunch-sha256.json', pins)!
	mut resolved_inputs := map[string]string{}
	for path, _ in pins { resolved_inputs[path] = os.real_path(path) }
	write_json(target + '/launch-file-sources.json', resolved_inputs)!
	write_json(target + '/preparation-receipt.json', {'completed_before_launch_utc': time.utc().str(), 'source_revision': checked(['git', 'rev-parse', 'HEAD'])!.trim_space(), 'base_media': os.abs_path(media), 'frozen256_pin': frozen_pin, 'prelaunch_pin': styled_hash(target + '/prelaunch-sha256.json')!})!
	clone(target, external + '/prelaunch/replica/' + target)!
	// Paired fixture VMs have separate retention. Select their immutable build
	// provenance here so no running guest media or QMP socket is copied.
	for name in ['framework', 'native', 'inputs', 'source', 'closure-inputs', 'failed-path-compile',
		'build-framework', 'build-framework.v', 'frozen-inputs.json', 'path-repair-receipt.json',
		'framework-v-files.json', 'framework-v-files.txt', 'native-generator-v-files.json',
		'native-generator-v-files.txt', 'fixture-v-files.json', 'fixture-v-files.txt'] {
		if name in ['failed-path-compile', 'path-repair-receipt.json'] && !os.exists(compound + '/' + name) { continue }
		clone(compound + '/' + name, external + '/prelaunch/replica/' + compound + '/' + name)!
	}
	for label in ['build-framework-compiler', 'build-framework', 'generate-native', 'build-native', 'fixture-compiler', 'fixture'] {
		for suffix in ['-before.json', '-receipt.json', '.log'] { clone(compound + '/' + label + suffix, external + '/prelaunch/replica/' + compound + '/' + label + suffix)! }
	}
	clone(frozen + '/inputs', external + '/prelaunch/frozen256/inputs')!
	clone(frozen + '/frozen-inputs.json', external + '/prelaunch/frozen256/frozen-inputs.json')!
	clone(frozen + '/source-revision.txt', external + '/prelaunch/frozen256/source-revision.txt')!
	for path, digest in pins {
		if path.starts_with(target + '/') { continue }
		clone_pinned_file(path, external + '/prelaunch/replica/' + path.trim_left('/'))!
		if styled_hash(path)! != digest { return error('live launch input changed during retention: ' + path) }
	}
	unique_evidence := '/Users/alex/.local/state/vinix/android/maps-interact-unique258-2026-10-24'
	if styled_hash(unique_evidence + '/sha256.json')! != 'ccf1c4eeff9011d560bef1bfc1e63929f78f7169d2ac697e98459a8975fb5d95' { return error('wrong unique258 build evidence pin') }
	clone(unique_evidence, external + '/prelaunch/unique258-evidence')!
	mut retained := map[string]string{}
	inventory(external + '/prelaunch', '', mut retained, false)!
	for path, digest in pins { if retained['replica/' + path.trim_left('/')]! != digest { return error('retained launch pin differs: ' + path) } }
	for path, digest in inputs { if retained['frozen256/inputs/' + path.trim_left('/')]! != digest { return error('retained original input differs: ' + path) } }
	if retained['replica/' + compound + '/framework/api-impl.jar']! != after[jar]!
		|| retained['replica/' + compound + '/native/libvinix-android-native.so']! != after[native]! { return error('retained260 artifacts differ from runtime') }
	mut retained_unique := map[string]string{}
	for path, digest in retained {
		if path.starts_with('unique258-evidence/') && path != 'unique258-evidence/sha256.json' { retained_unique[path.all_after('unique258-evidence/')] = digest }
	}
	equal_maps(retained_unique, read_map(unique_evidence + '/sha256.json')!)!
	write_json(external + '/prelaunch-sha256.json', retained)!
	println('MAPS261 PREPARED external=' + external + ' prelaunch_pin=' + styled_hash(external + '/prelaunch-sha256.json')!)
}

fn self_test(original string) ! {
	generated := suite_source(os.read_file(original)!, 'runtime', 'boot', 'firmware')!
	assert generated.contains('startup_seconds"]!.int() == 240')
	assert generated.contains('start-receipt.json') && generated.contains('observation-before-capture.json')
	preliminary := generated.index('observation-before-capture.json') or { return error('missing preliminary observation') }
	capture := generated.index("capture := os.exec(['build/android-maps/maps-interact-unique258'") or { return error('missing bounded final capture') }
	assert preliminary < capture
	mut before := map[string]string{}
	for i in 0 .. 107 { before['fixture-' + i.str()] = 'same' }
	before[jar] = 'old'
	before[native] = 'old'
	mut after := before.clone()
	after[jar] = 'new'
	after[native] = 'new'
	overlay_delta(before, after)!
	after['fixture-0'] = 'wrong'
	mut rejected := false
	overlay_delta(before, after) or { rejected = true }
	assert rejected
	fixture := os.temp_dir() + '/maps261-inventory-selftest-' + time.now().unix_micro().str()
	os.mkdir_all(fixture + '/prelaunch/empty')!
	os.write_file(fixture + '/prelaunch/fixture.txt', 'retained evidence\n')!
	os.symlink('fixture.txt', fixture + '/prelaunch/link')!
	clone_pinned_file(fixture + '/prelaunch/link', fixture + '/retained-file')!
	assert !os.is_link(fixture + '/retained-file')
	assert styled_hash(fixture + '/retained-file')! == styled_hash(fixture + '/prelaunch/fixture.txt')!
	mut fixture_map := map[string]string{}
	inventory(fixture + '/prelaunch', '', mut fixture_map, false)!
	write_json(fixture + '/prelaunch-sha256.json', fixture_map)!
	fixture_pin := styled_hash(fixture + '/prelaunch-sha256.json')!
	check_external(fixture, fixture_pin)!
	mut wrong_pin_rejected := false
	check_external(fixture, '0'.repeat(64)) or { wrong_pin_rejected = true }
	assert wrong_pin_rejected
	os.mv(fixture + '/prelaunch/fixture.txt', fixture + '/removed-fixture.txt')!
	mut partial_rejected := false
	check_external(fixture, fixture_pin) or { partial_rejected = true }
	assert partial_rejected
	os.mv(fixture + '/removed-fixture.txt', fixture + '/prelaunch/fixture.txt')!
	os.write_file(fixture + '/prelaunch/fixture.txt', 'altered! evidence\n')!
	mut changed_rejected := false
	check_external(fixture, fixture_pin) or { changed_rejected = true }
	assert changed_rejected
	scratch := base + 'maps261-helper-selftest-' + time.now().unix_micro().str()
	os.mkdir_all(scratch)!
	os.write_file(scratch + '/suite261.v', generated)!
	build := os.exec([compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-path',
		'build-support/android|@vlib|@vmodules', '-o', scratch + '/suite261', scratch + '/suite261.v'])
	os.write_file(scratch + '/build.log', build.output)!
	if build.exit_code != 0 { return error('generated suite build failed: ' + build.output) }
	os.write_file(scratch + '/suite-self-test.log', checked([scratch + '/suite261', '--self-test'])!)!
	println('MAPS261 HELPER SELF-TEST PASS original classifier preserved; exact2 delta enforced')
	println('MAPS261 HELPER NEGATIVE PASS wrong pin, incomplete inventory and changed bytes; fixture=' + fixture)
	println('MAPS261 HELPER GENERATED-SUITE SELF-TEST PASS ' + scratch)
}

fn main() {
	$if prod { eprintln('styled replay preparation/checking requires assertions; compile without -prod'); exit(2) }
	if os.args.len == 3 && os.args[1] == '--self-test' { self_test(os.args[2]) or { eprintln(err); exit(1) }; return }
	if os.args.len == 2 && os.args[1] == '--assertion-probe' { assert false, 'assertion probe must fail'; return }
	if os.args.len == 4 && os.args[1] == 'check' { check_external(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; return }
	if os.args.len != 5 || os.args[1] != 'prepare' { eprintln('usage: maps-styled-replay prepare FROZEN256 STOPPED_MEDIA EXTERNAL; check EXTERNAL PIN; --self-test ORIGINAL_SUITE'); exit(2) }
	prepare(os.args[2], os.args[3], os.args[4]) or { eprintln('MAPS261 PREPARE FAIL ' + err.msg()); exit(1) }
}
