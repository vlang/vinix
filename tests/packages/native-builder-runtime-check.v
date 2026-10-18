// SPDX-License-Identifier: GPL-2.0-or-later
module main
import crypto.sha256
import hwhost
import json2
import os
import time

struct BuilderArtifact { role string bytes u64 sha256 string }
struct BuilderGuestReceipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-native-builder' seconds f64 artifacts []BuilderArtifact }

fn builder_artifact(role string, path string) !BuilderArtifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return BuilderArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn builder_suite() !hwhost.Suite {
	mut required := ['HWTEST START packages-native-builder', 'HWTEST PASS packages-native-builder',
		'ELF OWNERSHIP 150 static/PIE/shared target, signature, range, interpreter and file cases; 1200 checks retain zero tracked bytes/allocations and stable descriptors PASS',
		'NATIVE OWNERSHIP templates, partial inventories, canonicalization and late refusals retire all owned metadata PASS',
		'PROFILE EXPORT selected profiles retain canonical saved locks after flush, moved-parent and replaced-inventory cleanup failures PASS']
	for mode in ['complete', 'nested', 'version', 'missing-root', 'missing-architecture', 'wrong-target', 'wrong-mode',
		'missing-notice', 'empty-notice', 'notice-directory', 'no-output-space', 'no-temp-space', 'space-error', 'created',
		'packed-1', 'packed-2', 'packed-3', 'packed-4', 'packed-5', 'packed-6', 'ready', 'import-elf', 'import-notice',
		'import-directory', 'changed-lock', 'occupied', 'raced-target', 'flush', 'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
		required << 'NATIVE BUILDER case=' + mode + ' retained=0 allocations=0'
		required << 'NATIVE BUILDER PROCESS builder case ' + mode + ' PASS'
		required << 'NATIVE BUILDER ' + mode + ' canonical retry, saved output, source and descriptor preservation PASS'
	}
	for cohort in ['0', '1', '2', '3']! {
		required << 'NATIVE BUILDER PROCESS profile-export native ' + cohort + ' PASS'
		required << 'PROFILE EXPORT native cohort ' + cohort + ' 16 substitutions recovery source pins exact retry 32 descriptors PASS'
	}
	for name in ['elf-owned', 'native-ownership', 'native-profile']! { required << 'NATIVE BUILDER PROCESS ' + name + '  PASS' }
	mut programs := []hwhost.Program{}
	for pair in [['builder', 'native_builder_ownership'], ['elf-owned', 'elf_profile_ownership'], ['native-ownership', 'native_profile_ownership'], ['native-profile', 'native_profile'], ['profile-export', 'profile_export']] {
		programs << hwhost.Program{ source: 'tools/packages/pkgcore/' + pair[1] + '_test.v', path: 'usr/share/package-fixtures/' + pair[0],
			flags: if pair[0] in ['builder', 'elf-owned', 'native-ownership']! { ['-manualfree', '-d', 'track_heap'] } else { ['-manualfree'] } }
	}
	// V canonicalizes @FILE even when the checkout is reached through a link.
	repository := os.dir(os.dir(os.dir(@FILE)))
	mut files := []hwhost.RootFile{}
	for name in ['hello', 'counter', 'memo']! { for arch in ['aarch64', 'x86_64']! {
		path := repository + '/examples/package-' + name + '/manifest-' + arch + '.json'
		files << hwhost.RootFile{ path: path.trim_left('/'), text: os.read_file(path)! }
	} }
	return hwhost.Suite{ name: 'package-native-builder', guest: 'tests/packages/native-builder-guest', module_paths: ['.', 'tools/accounts'],
		directories: ['tmp:1777'], programs: programs, files: files, scenarios: [hwhost.Scenario{ name: 'packages-native-builder',
			arches: ['aarch64', 'x86_64'], about: 'complete owned native profile calls, ELF checks, signed native lifecycle and 64 captured staging substitutions',
			required: required, forbidden: ['Out of memory', 'V panic:', 'HWTEST FAIL', 'PROFILE EXPORT retry failure'], ending: .poweroff, timeout: 600 }] }
}

fn qualify() !int {
	options := hwhost.parse_options(os.args[1..])!
	definition := builder_suite()!
	if options.help || options.list { return hwhost.run_suite(definition, os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!; host := hwhost.find_host(repository, options.arch, options.qemu)!
	hwhost.validate_scenarios(definition.scenarios)!; selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-native-builder') }
	os.mkdir_all(options.state_dir)!; work := os.real_path(options.state_dir); os.cp(options.kernel, work + '/kernel')!; hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [builder_artifact('kernel', work + '/kernel')!, builder_artifact('guest-init', guest)!]
	for name in ['builder', 'elf-owned', 'native-ownership', 'native-profile', 'profile-export']! { artifacts << builder_artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	for file in definition.files { artifacts << builder_artifact('example:' + file.path, root + '/' + file.path)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-native-builder', timeout: if options.timeout > 600 { options.timeout } else { 600 }, keep: true })
	println(hwhost.report(options.arch, outcome)); if outcome.interrupted { return 130 }; if !outcome.passed { return 1 }
	artifacts << builder_artifact('serial-log', work + '/packages-native-builder/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(BuilderGuestReceipt{ architecture: options.arch, completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(qualify() or { eprintln(err); 2 }) }
