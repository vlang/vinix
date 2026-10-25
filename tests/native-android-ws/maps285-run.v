// SPDX-License-Identifier: GPL-2.0-or-later
// Record one Maps285 launch and retain its new evidence. Historical bundles stay referenced.
module main

import crypto.sha256
import json2
import os
import time

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const base = 'build/android-maps/'
const target = base + 'maps285'
const prelaunch = '/Users/alex/.local/state/vinix/android/maps285-2026-10-25-prelaunch'
const completed = '/Users/alex/.local/state/vinix/android/maps285-2026-10-25'
const build_root = '/Users/alex/.local/state/vinix/android/maps285-run-build-final5-2026-10-25'
const prepare_build = '/Users/alex/.local/state/vinix/android/maps285-workflow-final4-2026-10-25'
const suite = target + '/suite285'
const config = base + 'attempt285.json'
const output = base + 'attempt285'
const source = 'tests/native-android-ws/maps285-run.v'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		if C.CC_SHA256_Init(unsafe { &state }) != 1 { return error('CC_SHA256_Init failed') }
		for {
			n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			if C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) != 1 { return error('CC_SHA256_Update failed') }
		}
		mut result := [32]u8{}
		if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) != 1 { return error('CC_SHA256_Final failed') }
		return result[..].hex()
	} $else {
		mut digest := sha256.new()
		defer { unsafe { digest.free() } }
		for {
			n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			if digest.write(buffer[..n])! != n { return error('SHA256 short write') }
		}
		mut result := []u8{len: 32}
		defer { unsafe { result.free() } }
		digest.checksum_into(mut result)
		return result.hex()
	}
}

fn read_map(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }
fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }

fn require_pin(path string, expected string) ! {
	if expected.len != 64 || os.lstat(path)!.get_filetype() != .regular || hash(path)! != expected {
		return error('missing or wrong pinned input: ' + path)
	}
}

fn inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory { entries[key] = 'directory'; inventory(root, key, mut entries)! }
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(path)! }
			else { return error('special file in retained closure: ' + path) }
		}
	}
}

fn equal_maps(actual map[string]string, expected map[string]string) ! {
	if actual.len != expected.len { return error('inventory length differs') }
	for key, value in expected { if actual[key] or { '' } != value { return error('inventory differs: ' + key) } }
}

fn verify_manifest(root string, name string, pin string) ! {
	require_pin(root + '/' + name, pin)!
	expected := read_map(root + '/' + name)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	actual.delete(name)
	equal_maps(actual, expected)!
}

fn retained_path(path string) string {
	return if path.starts_with(target + '/') { prelaunch + '/prelaunch/maps285/' + path.all_after(target + '/') }
		else if path == config { prelaunch + '/prelaunch/attempt285.json' }
		else { prelaunch + '/prelaunch/inputs/' + path.trim_left('/') }
}

fn verify_prepare_build() ! {
	reference := object(build_root + '/preparation-build-reference.json')!
	if reference['root']!.str() != prepare_build { return error('wrong preparation workflow reference') }
	verify_manifest(prepare_build, 'sha256.json', reference['sha256']!.str())!
	build := object(prepare_build + '/build-helper-receipt.json')!
	if build['exit_code']!.int() != 0 || build['completed_utc']!.str() == '' { return error('preparer build incomplete') }
	require_pin(prepare_build + '/maps285-prepare.v', build['source_sha256']!.str())!
	require_pin(prepare_build + '/maps285-prepare', build['output_sha256']!.str())!
	require_pin(retained_path(os.abs_path('tests/native-android-ws/maps285-prepare.v')), build['source_sha256']!.str())!
	require_pin(retained_path(os.abs_path(base + 'maps285-prepare-final4')), build['output_sha256']!.str())!
	for label, expected in {'helper-self-test': 0, 'prod-guard': 2, 'prepare': 0} {
		receipt := object(prepare_build + '/' + label + '-receipt.json')!
		for key, value in object(prepare_build + '/' + label + '-before.json')! {
			if receipt[key]! != value { return error('preparation before/done mismatch: ' + label + '/' + key) }
		}
		if receipt['exit_code']!.int() != expected || receipt['completed_utc']!.str() == '' { return error('preparer validation incomplete: ' + label) }
		if receipt['source_sha256']!.str() != build['source_sha256']!.str() { return error('preparer source differs across receipts') }
	}
	prepared := object(prepare_build + '/prepare-receipt.json')!
	references := object(target + '/references.json')!
	expected_argv := [base + 'maps285-prepare-final4', 'prepare', references['queue284_root']!.str(), references['queue284_prelaunch_sha256']!.str()]
	if prepared['argv']!.as_array().map(it.str()) != expected_argv { return error('wrong recorded preparation argv') }
	for path, pin in read_map(prepare_build + '/helper-v-files.json')! { require_pin(prepare_build + '/source-closure/' + path.trim_left('/'), pin)! }
	for path, pin in read_map(prepare_build + '/build-tools.json')! { require_pin(prepare_build + '/tools/' + path.trim_left('/'), pin)! }
}

// The same gate serves check and run, before any suite invocation.
fn gate(prelaunch_pin string, build_pin string) !map[string]string {
	verify_manifest(build_root, 'sha256.json', build_pin)!
	require_pin(source, hash(build_root + '/maps285-run.v')!)!
	require_pin(os.executable(), hash(build_root + '/maps285-run')!)!
	require_pin(prelaunch + '/prelaunch-sha256.json', prelaunch_pin)!
	expected := read_map(prelaunch + '/prelaunch-sha256.json')!
	mut retained := map[string]string{}
	inventory(prelaunch + '/prelaunch', '', mut retained)!
	equal_maps(retained, expected)!
	require_pin(target + '/prelaunch-sha256.json', expected['maps285/prelaunch-sha256.json']!)!
	mut pins := read_map(target + '/prelaunch-sha256.json')!
	// Control maps are consumed as inputs too; their retained bytes define the gate.
	for name in ['staging-tools.json', 'module-after-typed.json', 'references.json', 'build-receipt.json', 'preparation-receipt.json'] {
		path := target + '/' + name
		pins[path] = expected['maps285/' + name]!
		require_pin(path, pins[path]!)!
	}
	for path, pin in pins {
		// Original launch paths may be symlinks; independent retained copies contain bytes.
		if hash(path)! != pin { return error('live launch input changed: ' + path) }
		require_pin(retained_path(path), pin)!
	}
	typed := module_tree(target + '/module')!
	equal_maps(typed, read_map(target + '/module-after-typed.json')!)!
	settings := object(config)!
	staging_tools := read_map(target + '/staging-tools.json')!
	for name in ['unzip', 'cp'] {
		selected := os.find_abs_path_of_executable(name)!
		if selected !in staging_tools || hash(selected)! != staging_tools[selected]! {
			return error('changed PATH selection for launch/retention tool: ' + name)
		}
	}
	if settings['output']!.str() != output || settings['boot_image']!.str() != target + '/vm/boot.img'
		|| settings['efivars']!.str() != target + '/vm/efivars.fd'
		|| settings['applications']!.as_array()[0].as_map()['startup_seconds']!.int() != 600 { return error('wrong Maps285 configuration') }
	build := object(target + '/build-receipt.json')!
	if build['exit_code']!.int() != 0 || '-prod' in build['argv']!.as_array().map(it.str())
		|| build['binary_sha256']!.str() != pins[suite]! { return error('suite build mismatch or assertions disabled') }
	verify_prepare_build()!
	return pins
}

fn module_tree(root string) !map[string]string {
	mut tree := map[string]string{}
	inventory(root, '', mut tree)!
	for path in tree.keys() { tree['@mode:' + path] = (os.lstat(root + '/' + path)!.mode & 0o7777).str() }
	return tree
}

fn clone(from string, to string) ! {
	if os.exists(to) || os.is_link(to) { return error('fresh retained path required: ' + to) }
	os.mkdir_all(os.dir(to))!
	cp := os.find_abs_path_of_executable('cp')!
	require_pin(os.real_path(cp), read_map(target + '/staging-tools.json')![cp]!)!
	r := os.exec([cp, '-c', '-R', '-P', from, to])
	if r.exit_code != 0 { return error('retention failed: ' + r.output) }
}

// Copy every result byte; omit only QMP sockets, recording each omission explicitly.
fn retain_results(from string, to string, relative string, mut omissions []string) ! {
	os.mkdir_all(to)!
	for name in os.ls(from)! {
		input := from + '/' + name
		key := if relative == '' { name } else { relative + '/' + name }
		match os.lstat(input)!.get_filetype() {
			.regular { clone(input, to + '/' + name)! }
			.directory { retain_results(input, to + '/' + name, key, mut omissions)! }
			.symbolic_link { os.symlink(os.readlink(input)!, to + '/' + name)! }
			.socket {
				if name != 'qmp.sock' { return error('unexpected result socket: ' + key) }
				omissions << key
			}
			else { return error('unexpected result artifact: ' + key) }
		}
	}
}

fn launch(prelaunch_pin string, build_pin string) !int {
	pins := gate(prelaunch_pin, build_pin)!
	if os.exists(completed) || os.is_link(completed) || os.exists(output) || os.is_link(output) {
		return error('fresh Maps285 execution/output paths required')
	}
	os.setenv('COPYFILE_DISABLE', '1', true)
	os.mkdir_all(completed + '/execution')!
	clone(build_root, completed + '/runner-build')!
	clone(prepare_build, completed + '/preparation-build')!
	clone(prelaunch, completed + '/prelaunch')!
	for path, pin in pins { if hash(path)! != pin { return error('input changed before launch: ' + path) } }
	argv := [suite, config]
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()),
		'working_directory': json2.Any(os.getwd()), 'preparation_source_revision': object(target + '/preparation-receipt.json')!['source_revision']!,
		'PATH': json2.Any(os.getenv('PATH')), 'unzip_path': json2.Any(os.find_abs_path_of_executable('unzip')!),
		'runner_source_sha256': json2.Any(hash(source)!), 'runner_binary_sha256': json2.Any(hash(os.executable())!),
		'suite_source_sha256': json2.Any(pins[target + '/suite285.v']!), 'suite_binary_sha256': json2.Any(pins[suite]!),
		'config_sha256': json2.Any(pins[config]!), 'prelaunch_manifest_sha256': json2.Any(prelaunch_pin),
		'runner_build_manifest_sha256': json2.Any(build_pin), 'launch_pins_sha256': json2.Any(hash(target + '/prelaunch-sha256.json')!),
		'observation_seconds': json2.Any(600), 'output_capture': json2.Any('entire combined stdout/stderr from os.exec; no truncation')}
	write_json(completed + '/execution/launch-before.json', receipt)!
	// os.exec merges stdout/stderr into one drained pipe and waits for process exit.
	r := os.exec(argv)
	os.write_file(completed + '/execution/launch.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = r.exit_code
	receipt['combined_output_sha256'] = hash(completed + '/execution/launch.log')!
	receipt['combined_output_bytes'] = r.output.len
	write_json(completed + '/execution/launch-receipt.json', receipt)!
	mut omissions := []string{}
	if os.is_dir(output) { retain_results(output, completed + '/results/attempt285', '', mut omissions)! }
	write_json(completed + '/execution/omitted-sockets.json', omissions)!
	clone(target + '/vm', completed + '/postrun-vm')!
	clone(config, completed + '/postrun-config.json')!
	mut postrun := map[string]string{}
	for path, pin in pins {
		postrun[path] = hash(path)!
		if !path.starts_with(target + '/vm/') && postrun[path]! != pin { return error('non-media launch input changed during run: ' + path) }
	}
	write_json(completed + '/execution/postrun-inputs.json', postrun)!
	typed := module_tree(target + '/module')!
	equal_maps(typed, read_map(target + '/module-after-typed.json')!)!
	write_json(completed + '/references.json', object(target + '/references.json')!)!
	mut manifest := map[string]string{}
	inventory(completed, '', mut manifest)!
	write_json(completed + '/sha256.json', manifest)!
	println('MAPS285 RECORDED exit=' + r.exit_code.str() + '; manifest=' + hash(completed + '/sha256.json')!)
	return r.exit_code
}

fn self_test() ! {
	root := os.join_path(os.temp_dir(), 'maps285-gate-' + os.getpid().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/input', 'pinned bytes')!
	write_json(root + '/sha256.json', {'input': hash(root + '/input')!})!
	manifest_pin := hash(root + '/sha256.json')!
	verify_manifest(root, 'sha256.json', manifest_pin)!
	mut rejected := false
	verify_manifest(root, 'sha256.json', '0'.repeat(64)) or { rejected = true }
	assert rejected, 'wrong pin must reject before process creation'
	os.rm(root + '/input')!
	rejected = false
	verify_manifest(root, 'sha256.json', manifest_pin) or { rejected = true }
	assert rejected, 'missing input must reject before process creation'
	rejected = false
	gate('0'.repeat(64), '0'.repeat(64)) or { rejected = true }
	assert rejected && !os.exists(completed + '/execution/launch-before.json')
	r := os.exec([os.executable(), '--capture-probe'])
	assert r.exit_code == 7 && r.output.contains('stdout-first\n') && r.output.contains('stderr-last\n')
	assert r.output.count('capture-payload\n') == 20000, 'complete merged output required'
	println('MAPS285 RUNNER SELF-TEST PASS wrong/missing pins reject before launch; full merged output retained')
}

fn main() {
	$if prod { eprintln('Maps285 recording requires assertions'); exit(2) }
	if os.args.len == 2 && os.args[1] == '--capture-probe' {
		println('stdout-first')
		for _ in 0 .. 20000 { println('capture-payload') }
		eprintln('stderr-last')
		exit(7)
	}
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len == 4 && os.args[1] == 'check' {
		gate(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
		println('MAPS285 INPUT GATE PASS; no VM launched')
		return
	}
	if os.args.len == 4 && os.args[1] == 'run' { exit(launch(os.args[2], os.args[3]) or { eprintln(err); 1 }) }
	eprintln('usage: maps285-run --self-test | check|run PRELAUNCH_SHA256 RUNNER_BUILD_SHA256')
	exit(2)
}
