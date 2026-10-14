// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct NativeArtifact { role string bytes u64 sha256 string }
struct NativeReceipt { format int = 1 architecture string completed_at i64 seconds f64 artifacts []NativeArtifact }
struct NativeInputArtifact { path string bytes u64 sha256 string }
struct NativeInputs { format int profile string version string catalog_sha256 string artifacts []NativeInputArtifact }

fn native_artifact(role string, path string) !NativeArtifact {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return NativeArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn native_suite(sandbox string) hwhost.Suite {
	files := [
		hwhost.RootFile{ path: 'etc/passwd', text: 'root:x:0:0:root:/root:/bin/sh\n' },
		hwhost.RootFile{ path: 'etc/group', text: 'root:x:0:\ntty:x:5:\n' },
		hwhost.RootFile{ path: 'etc/vinix/auth.conf', text: 'scrypt_ln = 10\n' },
	]
	binaries := [hwhost.RootBinary{ source: sandbox, path: 'usr/bin/vinix-sandbox' }]
	return hwhost.Suite{ name: 'package-native-catalog', guest: 'tests/accounts/guest',
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring'],
		programs: [hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' }],
		files: files, binaries: binaries, directories: ['run', 'home', 'var/log', 'tmp:1777'],
		scenarios: [hwhost.Scenario{ name: 'packages-native-catalog', arches: ['aarch64', 'x86_64'],
			about: 'signed six-variant native catalog with real SDK apps, update/rollback and cached reinstall', timeout: 300, ending: .poweroff,
			required: ['HWTEST START packages-native-catalog',
				'PACKAGE NATIVE CATALOG six-pinned-packages signed-review architecture notices document-grant protocols-1-2 ordinary-data PASS',
				'PACKAGE NATIVE CATALOG upgrade rollback uninstall-registration offline-cache-reinstall retained-private-data PASS',
				'HWTEST PASS packages-native-catalog'], forbidden: ['V panic:'] }] }
}

// Foreign-target executables are publisher data, not suite programs. Admit all
// twelve input pins from the builder's record before copying either closure.
fn stage_native_inputs(inputs string, root string) ![]NativeArtifact {
	record := json2.decode[NativeInputs](os.read_file(inputs + '/build.json')!)!
	if record.format != 1 || record.profile != 'native-sdk' || record.version != '1.0.0' {
		return error('expected the complete native SDK 1.0.0 build record')
	}
	mut expected := []string{}
	for architecture in ['aarch64', 'x86_64'] {
		for path in ['bin/package-hello', 'bin/counter', 'bin/memo', 'licenses/application-sdk-MIT.txt', 'licenses/v-MIT.txt', 'licenses/musl-MIT.txt'] {
			expected << 'roots/' + architecture + '/' + path
		}
	}
	mut artifacts := [native_artifact('input-build-record', inputs + '/build.json')!]
	for item in record.artifacts {
		if !item.path.starts_with('roots/') { continue } // compiler executables are recorded host tools
		if item.path !in expected || os.is_link(inputs + '/' + item.path) { return error('unexpected or duplicate native input: ${item.path}') }
		expected.delete(expected.index(item.path))
		bytes := os.read_bytes(inputs + '/' + item.path)!
		defer { unsafe { bytes.free() } }
		if u64(bytes.len) != item.bytes || sha256.sum(bytes).hex() != item.sha256 { return error('changed native input: ${item.path}') }
		destination := root + '/usr/share/native-catalog/' + item.path
		os.mkdir_all(os.dir(destination))!
		os.write_file_array(destination, bytes)!
		os.chmod(destination, if item.path.contains('/bin/') { 0o755 } else { 0o644 })!
		artifacts << native_artifact('input/' + item.path, destination)!
	}
	if expected.len != 0 { return error('native input record lacks required payloads') }
	catalog_text := os.read_file(inputs + '/lock/catalog.json')!
	if sha256.sum(catalog_text.bytes()).hex() != record.catalog_sha256 { return error('changed native catalog lock') }
	os.write_file(root + '/usr/share/native-catalog/catalog.json', catalog_text)!
	artifacts << native_artifact('input/catalog.json', root + '/usr/share/native-catalog/catalog.json')!
	return artifacts
}

fn check() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(native_suite(''), os.args[1..], @FILE) }
	inputs := os.getenv('VINIX_NATIVE_CATALOG_INPUTS')
	sandbox := os.getenv('VINIX_NATIVE_CATALOG_SANDBOX')
	if os.getenv('VINIX_HWTEST_TCG') != '1' || !os.is_file(options.kernel) || !os.is_dir(inputs)
		|| !os.is_file(sandbox) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) {
		return error('provide VINIX_HWTEST_TCG=1, VINIX_NATIVE_CATALOG_INPUTS, target VINIX_NATIVE_CATALOG_SANDBOX, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	definition := native_suite(sandbox)
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-native-catalog') }
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [native_artifact('kernel', work + '/kernel')!, native_artifact('guest-init', guest)!]
	for path in ['usr/bin/vinix-package', 'usr/bin/vinix-sandbox', 'usr/sbin/vinix-account', 'usr/sbin/vinix-session'] {
		artifacts << native_artifact(path, root + '/' + path)!
	}
	for file in definition.files { artifacts << native_artifact(file.path, root + '/' + file.path)! }
	artifacts << stage_native_inputs(inputs, root)!
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/native', timeout: if options.timeout > 300 { options.timeout } else { 300 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	for role, path in {'serial-log': 'serial.log', 'qmp-log': 'qmp.log'} { artifacts << native_artifact(role, work + '/native/' + path)! }
	os.write_file(work + '/qualification.json', json2.encode(NativeReceipt{ architecture: options.arch, completed_at: time.now().unix(),
		seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check() or { eprintln(err); 2 }) }
