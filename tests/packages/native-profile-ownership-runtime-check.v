// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact { role string bytes u64 sha256 string }
struct Receipt { format int = 1 architecture string completed_at i64 seconds f64 scenario string = 'packages-native-ownership' artifacts []Artifact }

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn example_paths() []string {
	// The existing profile regression locates reviewed example manifests using
	// its compile-time source path. Reproduce just those six files in the guest.
	repository := os.dir(os.dir(os.dir(@FILE)))
	mut paths := []string{}
	for name in ['hello', 'counter', 'memo']! {
		for arch in ['aarch64', 'x86_64']! { paths << repository + '/examples/package-' + name + '/manifest-' + arch + '.json' }
	}
	return paths
}

fn suite() !hwhost.Suite {
	mut files := []hwhost.RootFile{}
	for path in example_paths() { files << hwhost.RootFile{ path: path.trim_left('/'), text: os.read_file(path)! } }
	mut required := ['HWTEST START packages-native-ownership',
		'NATIVE OWNERSHIP templates, partial inventories, canonicalization and late refusals retire all owned metadata PASS',
		'NATIVE OWNERSHIP independent replies survive caller retirement and close idempotently PASS',
		'NATIVE OWNERSHIP complete build preserves baseline canonical bytes and retires reply without removing published lock PASS',
		'NATIVE OWNERSHIP PROCESS native-ownership PASS', 'NATIVE OWNERSHIP PROCESS native-profile PASS',
		'PROFILE EXPORT selected profiles retain canonical saved locks after flush, moved-parent and replaced-inventory cleanup failures PASS',
		'NATIVE OWNERSHIP PROCESS profile-export PASS', 'HWTEST PASS packages-native-ownership']
	for count in 0 .. 7 { required << 'NATIVE OWNERSHIP imports=' + count.str() + ' fault=none retained=0 allocations=0' }
	for cohort in 0 .. 4 { required << 'PROFILE EXPORT native cohort ' + cohort.str() + ' 16 substitutions recovery source pins exact retry 32 descriptors PASS' }
	required << ['NATIVE OWNERSHIP imports=6 fault=duplicate retained=0 allocations=0', 'NATIVE OWNERSHIP imports=0 fault=empty retained=0 allocations=0']
	return hwhost.Suite{ name: 'package-native-ownership', guest: 'tests/packages/native-profile-ownership-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], files: files, programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/native_profile_ownership_test.v', path: 'usr/share/package-fixtures/native-ownership', flags: ['-d', 'track_heap', '-manualfree'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/native_profile_test.v', path: 'usr/share/package-fixtures/native-profile', flags: ['-manualfree'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/profile_export_test.v', path: 'usr/share/package-fixtures/profile-export', flags: ['-manualfree'] },
		], scenarios: [hwhost.Scenario{ name: 'packages-native-ownership', arches: ['aarch64', 'x86_64'],
			about: 'owned native profile metadata and replies, signed lifecycle and 64 staging substitutions in four processes', required: required,
			forbidden: ['V panic:', 'HWTEST FAIL', 'PROFILE EXPORT retry failure'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(suite()!, os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	definition := suite()!
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-native-ownership') }
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [artifact('kernel', work + '/kernel')!, artifact('guest-init', guest)!]
	for name in ['native-ownership', 'native-profile', 'profile-export']! { artifacts << artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	for path in example_paths() { artifacts << artifact('reviewed-example:' + path, root + '/' + path.trim_left('/'))! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-native-ownership', timeout: if options.timeout > 300 { options.timeout } else { 300 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-native-ownership/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check() or { eprintln(err); 2 }) }
