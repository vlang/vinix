// SPDX-License-Identifier: GPL-2.0-or-later
// Stage a fresh diagnostic VM from available media and current build outputs.
module main
import json2
import os
import crypto.sha256

#include <sys/clonefile.h>
fn C.clonefile(&char, &char, int) int

fn command(args []string) ! {
	if os.system_args(args) != 0 { return error('command failed: ' + args.join(' ')) }
}

fn stage(parent string, framework string, native string, root string) ! {
	if os.exists(root) { return error('fresh output required') }
	os.mkdir_all(root)!
	for name in ['boot.img', 'efivars.fd'] {
		if C.clonefile((parent + '/' + name).str, (root + '/' + name).str, 0) != 0 { return error('media clone failed') }
	}
	runtime := root + '/payload/opt/vinix-android-aarch64/usr/lib/'
	java := runtime + 'java/dex/android_translation_layer/'
	os.mkdir_all(java)!
	os.mkdir_all(runtime + 'art')!
	for name in ['api-impl.jar', 'classes.dex'] { os.cp(framework + '/' + name, java + name)! }
	os.cp(native + '/native/libvinix-android-native.so', runtime + 'art/libvinix-android-native.so')!
	os.chmod(runtime + 'art/libvinix-android-native.so', 0o755)!
	// Describe the files actually selected for this deployment, rather than
	// requiring artifacts from a historical build to still exist.
	mut deployment := json2.decode[map[string]json2.Any](os.read_file(parent + '/payload/opt/vinix-maps-account/build.json')!)!
	mut inputs := deployment['inputs_sha256']!.as_map()
	for relative in ['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/classes.dex'] {
		inputs['/' + relative] = json2.Any(sha256.sum(os.read_bytes(root + '/payload/' + relative)!).hex())
	}
	deployment['inputs_sha256'] = json2.Any(inputs)
	if boot := os.getenv_opt('VINIX_CURRENT_CORE_LIBART') {
		relative := '/opt/vinix-android-aarch64/usr/lib/java/dex/art/core-libart-hostdex.jar'
		os.mkdir_all(os.dir(root + '/payload' + relative))!
		os.cp(boot, root + '/payload' + relative)!
		inputs[relative] = json2.Any(sha256.sum(os.read_bytes(boot)!).hex())
		deployment['inputs_sha256'] = json2.Any(inputs)
	}
	os.mkdir_all(root + '/payload/opt/vinix-maps-account')!
	os.write_file(root + '/payload/opt/vinix-maps-account/build.json', json2.encode(deployment))!
	if fixture := os.getenv_opt('VINIX_CURRENT_API_FIXTURE') {
		runner := os.getenv_opt('VINIX_CURRENT_API_RUNNER') or { return error('fixture requires VINIX_CURRENT_API_RUNNER') }
		os.mkdir_all(root + '/payload/opt/current-api')!
		os.cp(fixture, root + '/payload/opt/current-api/probe.apk')!
		os.cp(runner, root + '/payload/opt/current-api/run')!
		os.chmod(root + '/payload/opt/current-api/run', 0o755)!
	}
	if fixture := os.getenv_opt('VINIX_CURRENT_LOADER_FIXTURE') {
		os.mkdir_all(root + '/payload/opt/current-api')!
		os.cp(fixture, root + '/payload/opt/current-api/loader.apk')!
	}
	if probe := os.getenv_opt('VINIX_CURRENT_STORAGE_WATCH') {
		os.mkdir_all(root + '/payload/opt/current-api')!
		os.cp(probe, root + '/payload/opt/current-api/storage-watch')!
		os.chmod(root + '/payload/opt/current-api/storage-watch', 0o755)!
	}
	os.setenv('COPYFILE_DISABLE', '1', true)
	command(['/usr/bin/tar', '-cf', root + '/maps-current.tar', '-C', root + '/payload', 'opt'])!
	config := os.read_file(parent + '/limine-after.conf')! + '    module_path: boot():/boot/maps-current.tar\n'
	os.write_file(root + '/limine-after.conf', config)!
	command(['/opt/homebrew/bin/mcopy', '-i', root + '/boot.img', root + '/maps-current.tar', '::/boot/maps-current.tar'])!
	command(['/opt/homebrew/bin/mcopy', '-o', '-i', root + '/boot.img', root + '/limine-after.conf', '::/boot/limine.conf'])!
	launch := json2.decode[map[string]json2.Any](os.read_file(parent + '/launch.json')!)!
	args := launch['argv']!.as_array().map(it.str().replace(parent, root))
	os.write_file(root + '/launch-argv.json', json2.encode(args))!
	os.write_file(root + '/build.json', json2.encode({'parent': parent, 'framework': framework, 'native': native}))!
	println('MAPS-CURRENT-STAGED ' + root)
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--start' {
		root := os.abs_path(os.args[2])
		if os.exists(root + '/qemu.pid') { eprintln('VM already launched'); exit(1) }
		args := json2.decode[[]string](os.read_file(root + '/launch-argv.json')!)!
		command(args) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 5 { eprintln('usage: maps-current-guest PARENT_VM FRAMEWORK NATIVE FRESH_ROOT'); exit(2) }
	stage(os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3]), os.abs_path(os.args[4])) or { eprintln(err); exit(1) }
}
