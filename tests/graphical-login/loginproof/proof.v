// SPDX-License-Identifier: GPL-2.0-or-later
// Independent admission for the direct-manager graphical login fixture.
module loginproof

import crypto.sha256
import json2
import os

pub const markers = ['HWTEST START graphical-login',
	'GRAPHICAL LOGIN fresh image exclusive registration READY',
	'GRAPHICAL LOGIN registered account and ordinary greeter PASS',
	'GRAPHICAL LOGIN wrong password creates no ordinary session PASS',
	'GRAPHICAL LOGIN first ordinary desktop private home and runtime PASS',
	'GRAPHICAL LOGIN switch stops prior session and returns ordinary greeter PASS',
	'GRAPHICAL LOGIN reauthentication resumes same process and kernel session PASS',
	'GRAPHICAL LOGIN logout reaps ordinary session and returns greeter PASS',
	'GRAPHICAL LOGIN new login has fresh process and preserved home PASS',
	'GRAPHICAL LOGIN manager cleanup reaps sessions PASS', 'HWTEST PASS graphical-login']

pub const screenshots = ['01-registration.png', '02-greeter.png', '03-refused.png',
	'04-ordinary.png', '05-switched.png', '06-resumed.png', '07-logged-out.png', '08-new-login.png']

pub fn output_names(arch string) []string {
	mut names := ['result.json', 'arguments.json', 'guest-argv.json', 'qemu-argv.json', 'inputs.json',
		'inputs-verified.json', 'input-paths.json', 'source/check.v', 'source/guest/main.v',
		'build-guest/guest', 'build-guest/guest.c', 'build-guest/build.log',
		'boot/serial.log', 'boot/initramfs.tar', 'boot/image.log', 'qemu.log', 'stage.log']
	names << screenshots
	names << if arch == 'aarch64' { ['boot/boot.img', 'boot/limine.conf'] } else {
		['boot/test.iso', 'boot/image-commands.json', 'boot/iso/iso-root/boot/limine.conf']
	}
	return names
}

pub fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut state := sha256.new()
	defer { unsafe { state.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return error('cannot read evidence file: ' + path)
		}
		if count == 0 { break }
		state.write(buffer[..count])!
	}
	bytes := state.sum([]u8{})
	defer { unsafe { bytes.free() } }
	return bytes.hex()
}

pub fn strings(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

pub fn relative(name string) bool {
	return name.len > 0 && !name.starts_with('/') && !name.contains('\x00')
		&& name.split('/').all(it.len > 0 && it != '.' && it != '..')
}

pub fn verify_files(hashes map[string]string, paths map[string]string) ! {
	if hashes.len == 0 || hashes.len != paths.len { return error('evidence path and digest inventories differ') }
	for name, expected in hashes {
		if name !in paths || expected.len != 64 || expected.bytes().any(!(it >= `0` && it <= `9`) && !(it >= `a` && it <= `f`)) {
			return error('missing or malformed evidence digest: ' + name)
		}
		if digest(paths[name])! != expected { return error('evidence artifact digest differs: ' + name) }
	}
}

pub fn serial(text string) ! {
	for forbidden in ['GRAPHICAL LOGIN FAIL:', 'HWTEST FAIL', 'KERNEL PANIC', 'V panic:',
		'Assertion failed', 'FATAL EXCEPTION'] {
		if text.contains(forbidden) { return error('forbidden serial marker: ' + forbidden) }
	}
	lines := text.split_into_lines().map(it.trim_space())
	mut previous := -1
	for marker in markers {
		positions := lines.map(it == marker)
		if positions.filter(it).len != 1 { return error('missing or duplicated exact marker: ' + marker) }
		position := lines.index(marker)
		if position <= previous { return error('graphical login markers are out of order') }
		previous = position
	}
}

// Reconstruct the complete inventories independently of the receipt. Checking
// only its remaining entries would admit a jointly omitted path and digest.
fn inventory(directory string, prefix string, source_only bool, mut paths map[string]string) ! {
	for name in os.ls(directory)! {
		if name == '.git' { continue }
		path := directory + '/' + name
		if os.is_link(path) {
			if !source_only && os.is_file(path) { paths[prefix + name] = path }
		} else if os.is_dir(path) {
			inventory(path, prefix + name + '/', source_only, mut paths)!
		} else if os.is_file(path) && (!source_only || (!name.ends_with('_test.v')
			&& ['.v', '.c', '.h', '.S', '.o', '.a'].any(name.ends_with(it)))) {
			paths[prefix + name] = path
		}
	}
}

fn required_path(paths map[string]string, name string) !string {
	path := paths[name] or { return error('missing required input path: ' + name) }
	if path == '' { return error('empty required input path: ' + name) }
	return path
}

fn desktop_inventory(paths map[string]string) !map[string]string {
	root := os.real_path(@DIR + '/../../..')
	builder := root + '/tests/graphical-login/build.v'
	if paths['builder-source'] != builder { return error('desktop builder source path differs') }
	compiler := required_path(paths, 'compiler')!
	clang := required_path(paths, 'clang')!
	ui_mod := required_path(paths, 'source/ui2/v.mod')!
	stdio := required_path(paths, 'sysroot/include/stdio.h')!
	if !stdio.ends_with('/usr/include/stdio.h') { return error('desktop sysroot path differs') }
	sysroot := stdio[..stdio.len - '/usr/include/stdio.h'.len]
	mut expected := {
		'builder-source': builder
		'builder': required_path(paths, 'builder')!
		'compiler': compiler
		'compiler-v.mod': os.dir(compiler) + '/v.mod'
		'clang': clang
		'linker': required_path(paths, 'linker')!
		'find-v': root + '/build-support/find-v.sh'
	}
	for name in ['desktop', 'tools/packages', 'tools/accounts', 'compat'] {
		inventory(root + '/' + name, 'source/' + name + '/', false, mut expected)!
	}
	inventory(os.dir(ui_mod), 'source/ui2/', false, mut expected)!
	inventory(sysroot + '/usr/include', 'sysroot/include/', false, mut expected)!
	inventory(sysroot + '/usr/lib', 'sysroot/lib/', false, mut expected)!
	inventory(root + '/build-support/aarch64-cc-shim', 'shim/', false, mut expected)!
	inventory(os.dir(compiler) + '/vlib', 'vlib/', false, mut expected)!
	inventory(os.dir(compiler) + '/thirdparty', 'thirdparty/', false, mut expected)!
	return expected
}

fn account_inventory(paths map[string]string) !map[string]string {
	root := os.real_path(@DIR + '/../../..')
	stage := root + '/tools/accounts/stage.v'
	if paths['stage-source'] != stage { return error('account stager source path differs') }
	v := required_path(paths, 'compiler-v')!
	mut expected := {
		'stager': required_path(paths, 'stager')!
		'compiler-v': v
		'compiler-c': required_path(paths, 'compiler-c')!
		'compiler-v.mod': os.dir(v) + '/v.mod'
		'stage-source': stage
	}
	inventory(root + '/tools/accounts', 'accounts/', true, mut expected)!
	inventory(root + '/tools/packages', 'packages/', true, mut expected)!
	inventory(os.dir(v) + '/vlib', 'vlib/', true, mut expected)!
	inventory(os.dir(v) + '/thirdparty', 'thirdparty/', true, mut expected)!
	for name in os.ls(root + '/tools/accounts/actions')! {
		expected['action/' + name] = root + '/tools/accounts/actions/' + name
	}
	return expected
}

pub fn desktop(directory string, expected_builder string) ! {
	build := strings(directory + '/desktop-build.json')!
	paths := strings(directory + '/build-input-paths.json')!
	inputs := strings(directory + '/build-inputs.json')!
	if desktop_inventory(paths)! != paths { return error('desktop input inventory differs') }
	verify_files(inputs, paths)!
	if inputs['builder-source'] != expected_builder { return error('desktop builder differs from embedded source') }
	for required in ['app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
		if required !in build { return error('missing desktop output digest: ' + required) }
	}
	mut frozen := map[string]string{}
	inventory(directory + '/source', '', false, mut frozen)!
	if build.len != frozen.len + 6 { return error('desktop output inventory differs') }
	for name in frozen.keys() {
		if name !in build { return error('missing frozen desktop output: ' + name) }
		if 'source/' + name !in inputs { return error('unexpected frozen desktop source: ' + name) }
	}
	for name, expected in build {
		if name in ['repository-head', 'compiler'] { continue }
		if !relative(name) { return error('unsafe desktop output path') }
		path := if name.starts_with('app/') || name == 'vinix-desktop' { directory + '/' + name } else { directory + '/source/' + name }
		if digest(path)! != expected { return error('desktop output digest differs: ' + name) }
		if 'source/' + name in inputs && inputs['source/' + name] != expected {
			return error('desktop frozen source differs from captured input: ' + name)
		}
	}
	for name, expected in inputs {
		if name.starts_with('source/') && build[name['source/'.len..]] != expected {
			return error('missing or changed frozen desktop input: ' + name)
		}
	}
	if build['compiler'] != inputs['compiler'] { return error('desktop compiler binding differs') }
	argv := json2.decode[map[string][]string](os.read_file(directory + '/build-argv.json')!)!
	if argv['v'].len == 0 || argv['c'].len == 0 || argv['v'][0] != paths['compiler']
		|| argv['c'][0] != paths['clang'] {
		return error('desktop build argument compiler binding differs')
	}
}

pub fn accounts(directory string, staging string, architecture string, expected_stage string) ! {
	result := strings(directory + '/receipt/result.json')!
	if result['passed'] != 'true' || result['architecture'] != architecture { return error('account build did not pass for this architecture') }
	inputs := strings(directory + '/receipt/inputs.json')!
	paths := strings(directory + '/receipt/input-paths.json')!
	if account_inventory(paths)! != paths { return error('account input inventory differs') }
	verify_files(inputs, paths)!
	if inputs['stage-source'] != expected_stage { return error('account stager differs from embedded source') }
	outputs := strings(directory + '/receipt/outputs.json')!
	mut expected_outputs := []string{}
	for name in ['account', 'auth', 'authd', 'system', 'session'] {
		for file in [name + '.c', 'vinix-' + name, 'argv.json'] {
			key := name + '/' + file
			expected_outputs << key
			if key !in outputs { return error('missing account output digest: ' + key) }
		}
		installed := staging + '/usr/' + (if name == 'auth' { 'bin' } else { 'sbin' }) + '/vinix-' + name
		if digest(installed)! != outputs[name + '/vinix-' + name] { return error('installed account executable differs: ' + name) }
		argv := json2.decode[map[string][]string](os.read_file(directory + '/' + name + '/argv.json')!)!
		if argv['v'].len == 0 || argv['c'].len == 0 || argv['v'][0] != paths['compiler-v']
			|| argv['c'][0] != paths['compiler-c'] {
			return error('account build argument compiler binding differs')
		}
	}
	for name, expected in inputs {
		if !name.starts_with('action/') { continue }
		action := name['action/'.len..]
		key := 'installed-action/' + action
		expected_outputs << key
		if outputs[key] != expected || digest(staging + '/usr/share/vinix/actions/' + action)! != expected {
			return error('installed action differs from captured input: ' + action)
		}
	}
	if outputs.len != expected_outputs.len { return error('account output inventory differs') }
	for name, expected in outputs {
		if !relative(name) || name !in expected_outputs { return error('unexpected account output path') }
		if digest(directory + '/' + name)! != expected { return error('account output digest differs: ' + name) }
	}
}
