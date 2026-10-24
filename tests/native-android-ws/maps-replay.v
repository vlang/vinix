// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare a bounded replay of the retained Maps256 runtime. No APK, framework,
// native library or production launcher is rebuilt or changed.
module main

import crypto.sha256
import json2
import os
import time

const frozen_pin = '7b602e16397db66cb23df41e421238656d0e1d493f29e2fb71683d7c33e1fb64'
const base = 'build/android-maps/'

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

fn checked(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error(args[0] + ': ' + result.output) }
	return result.output
}

fn replace_once(source string, before string, after string) !string {
	if source.count(before) != 1 { return error('unexpected frozen suite source block') }
	return source.replace(before, after)
}

fn prepare(frozen string, media string) ! {
	$if prod { return error('replay preparation requires assertions; compile without -prod') }
	if hash(frozen + '/frozen-inputs.json')! != frozen_pin { return error('wrong Maps256 input pin') }
	manifest := json2.decode[map[string]string](os.read_file(frozen + '/frozen-inputs.json')!)!
	if manifest.len != 73 { return error('incomplete Maps256 input freeze') }
	for path, digest in manifest {
		if hash(frozen + '/inputs/' + path.trim_left('/'))! != digest { return error('frozen input differs: ' + path) }
	}
	for path in [base + 'GoogleMaps.apk', base + 'GooglePlayServices.apk', base + 'GooglePlayStore.apk',
		base + 'attempt244/companion-packages.json', base + 'maps-interact-bounded', 'build/android-run',
		'build/qemu-horizontal/bin/qemu-system-aarch64', 'tests/native-android-ws/maps-interact.v'] {
		if hash(path)! != manifest[path]! { return error('live replay tool or APK differs from frozen input: ' + path) }
	}
	if hash('/opt/homebrew/share/qemu/edk2-aarch64-code.fd')! != manifest['firmware.fd']! {
		return error('firmware differs from frozen input')
	}
	if os.exists(base + 'maps257') || os.exists(base + 'attempt257') { return error('fresh replay directories required') }
	// The administrator must stop the source VM before replay preparation.
	// Accept the auditor's clones or the original, stopped Maps256 media.
	original_media := os.abs_path(media) == os.abs_path(base + 'maps256/vm')
	pairs := if original_media { [['boot.img', 'boot.img'], ['efivars.fd', 'efivars.fd']] }
		else { [['boot-after-run.img', 'boot.img'], ['efivars-after-run.fd', 'efivars.fd']] }
	for pair in pairs {
		name := pair[0]
		if !os.is_file(media + '/' + name) || os.is_link(media + '/' + name) { return error('missing retained media: ' + name) }
	}
	target := base + 'maps257'
	os.mkdir_all(target + '/vm')!
	os.cp(frozen + '/inputs/' + base + 'maps256/runtime-after.json', target + '/runtime-after.json')!
	os.cp(frozen + '/inputs/tests/native-android-ws/maps-interact.v', target + '/maps-interact.v')!
	for pair in pairs {
		checked(['cp', '-c', media + '/' + pair[0], target + '/vm/' + pair[1]])!
	}
	mut source := os.read_file(frozen + '/inputs/' + base + 'suite256-resume.v')!
	original_observation := source.all_after('fn observation(').all_before('// Real companion packages')
	source = replace_once(source, 'fn main() {', 'fn main() {\n\t$if prod { eprintln("replay suite requires assertions; compile without -prod"); exit(2) }')!
	source = replace_once(source, 'validate_resume256(settings, output)!', 'validate_replay257(settings, output)!')!
	start := source.index('fn validate_resume256(') or { return error('missing frozen preflight') }
	source = source[..start] + '
fn validate_replay257(settings map[string]json2.Any, output string) ! {
 $if prod { return error("replay suite requires assertions; compile without -prod") }
 assert settings["boot_image"]!.str() == "build/android-maps/maps257/vm/boot.img"
 assert settings["applications"]!.as_array()[0].as_map()["startup_seconds"]!.int() == 240
 expected := json2.decode[map[string]string](os.read_file("build/android-maps/maps257/runtime-after.json")!)!
 assert expected.len == 109
 for path, hash in expected { assert digest("build/android-maps/maps256/module/" + path)! == hash, path }
 os.cp("build/android-maps/attempt244/companion-packages.json", output + "/companion-packages.json")!
 println("MAPS257 PREFLIGHT PASS unchanged Maps256 runtime; original classifier retained; bounded final capture")
}
'
	source = replace_once(source, ' expected := json2.decode',
		' assert digest("build/android-maps/maps257/runtime-after.json")! == "' + manifest[base + 'maps256/runtime-after.json']! + '"\n expected := json2.decode')!
	old_capture := '\tcapture := os.exec([settings[\'input_tool\']!.str(), \'screenshot\', \'--socket\', socket, \'--destination\',\n\t\tframe])'
	new_capture := '\t// Retain the original observation before capture/compression can fail.\n\tresult[\'observation_elapsed_seconds\'] = json2.Any(time.now().unix() - begin_at)\n\tresult[\'qemu_alive_before_capture\'] = json2.Any(qemu.is_alive())\n\tos.write_file(state + \'/observation-before-capture.json\', json2.encode(result, prettify: true) + \'\\n\')!\n\tprintln(\'MAPS257 observation retained before final capture\')\n\tcapture := os.exec([\'build/android-maps/maps-interact-bounded\', state, \'capture\', \'application\'])'
	source = replace_once(source, old_capture, new_capture)!
	if source.all_after('fn observation(').all_before('// Real companion packages') != original_observation {
		return error('original classification changed')
	}
	os.write_file(target + '/suite257.v', source)!
	mut config := json2.decode[map[string]json2.Any](os.read_file(frozen + '/inputs/' + base + 'attempt256.json')!)!
	config['boot_image'] = target + '/vm/boot.img'
	config['efivars'] = target + '/vm/efivars.fd'
	config['output'] = base + 'attempt257'
	mut apps := config['applications']!.as_array()
	mut app := apps[0].as_map().clone()
	app['startup_seconds'] = json2.Any(240)
	apps[0] = json2.Any(app)
	config['applications'] = json2.Any(apps)
	os.write_file(base + 'attempt257.json', json2.encode(config, prettify: true) + '\n')!
	compiler := '/Users/alex/code/v/v_old'
	argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-path',
		'build-support/android|@vlib|@vmodules', '-o', target + '/suite257', target + '/suite257.v']
	started := time.utc().str()
	build := os.exec(argv)
	os.write_file(target + '/build.log', build.output)!
	if build.exit_code != 0 { return error('suite build failed: ' + build.output) }
	self_test := checked([target + '/suite257', '--self-test'])!
	os.write_file(target + '/self-test.log', self_test)!
	mut pins := map[string]string{}
	for path in [target + '/vm/boot.img', target + '/vm/efivars.fd',
		target + '/suite257.v', target + '/suite257', base + 'attempt257.json', compiler,
		target + '/runtime-after.json', target + '/maps-interact.v',
		'build/android-run', base + 'maps-interact-bounded', 'build/qemu-horizontal/bin/qemu-system-aarch64',
		'tests/native-android-ws/maps-replay.v', frozen + '/frozen-inputs.json'] {
		pins[path] = hash(path)!
	}
	os.write_file(target + '/prelaunch-sha256.json', json2.encode(pins, prettify: true) + '\n')!
	os.write_file(target + '/build-receipt.json', json2.encode({
		'argv': json2.Any(argv), 'started_utc': json2.Any(started),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(build.exit_code),
		'compiler_sha256': json2.Any(pins[compiler]!),
		'source_sha256': json2.Any(pins[target + '/suite257.v']!),
		'binary_sha256': json2.Any(pins[target + '/suite257']!),
		'frozen256_pin': json2.Any(frozen_pin), 'base_media': json2.Any(media),
	}, prettify: true) + '\n')!
	os.write_file(target + '/scope.txt', 'Replay of stopped Maps256 runtime with a new private boot/firmware clone. Configured240 seconds is an observation limit. Original observation classifier is byte-identical. Final capture uses the retained30-second-bounded interaction driver. Preliminary observation is saved before capture and does not prove completed suite output. APK/runtime/production launcher unchanged.\n')!
	println('MAPS257 PREPARED prelaunch_pin=' + hash(target + '/prelaunch-sha256.json')!)
}

fn main() {
	if os.args.len != 3 { eprintln('usage: maps-replay MAPS256_FROZEN_DIRECTORY RETAINED_MEDIA_DIRECTORY'); exit(2) }
	prepare(os.args[1], os.args[2]) or { eprintln('MAPS257 PREPARE FAIL ' + err.msg()); exit(1) }
}
