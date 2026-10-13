// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact { role string bytes u64 sha256 string }
struct Receipt {
	format int = 1
	architecture string
	completed_at i64
	platform string = 'qemu-tcg'
	scenario string = 'packages-context'
	seconds f64
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite(repository string, architecture string, sandbox string) !hwhost.Suite {
	manifest := if repository == '' { '' } else { os.read_file(repository + '/examples/package-hello/manifest-' + architecture + '.json')! }
	mut programs := [
		hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
		hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
		hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' },
	]
	mut binaries := [hwhost.RootBinary{ source: sandbox, path: 'usr/bin/vinix-sandbox' }]
	example := os.getenv('VINIX_CONTEXT_EXAMPLE')
	if example == '' { programs << hwhost.Program{ source: 'examples/package-hello/main.v', path: 'usr/share/context-fixtures/package-hello' } }
	else { binaries << hwhost.RootBinary{ source: example, path: 'usr/share/context-fixtures/package-hello' } }
	return hwhost.Suite{
		name: 'package-sdk-context'
		guest: 'tests/accounts/guest'
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring']
		programs: programs
		binaries: binaries
		files: [
			hwhost.RootFile{ path: 'etc/passwd', text: 'root:x:0:0:root:/root:/bin/sh\n' },
			hwhost.RootFile{ path: 'etc/group', text: 'root:x:0:\ntty:x:5:\n' },
			hwhost.RootFile{ path: 'etc/vinix/auth.conf', text: 'scrypt_ln = 10\n' },
			hwhost.RootFile{ path: 'usr/share/context-fixtures/manifest.json', text: manifest },
		]
		directories: ['run', 'home', 'var/log', 'tmp:1777']
		scenarios: [hwhost.Scenario{
			name: 'packages-context'
			arches: ['aarch64', 'x86_64']
			about: 'native SDK context/example, admitted provenance, upgrade/rollback and leased running snapshot'
			required: ['HWTEST START packages-context',
				'PACKAGE CONTEXT native-sdk-example ordinary-identity explicit-document-grants installed-provenance ambient-forgery-refusal PASS',
				'PACKAGE CONTEXT new-launch-upgrade rollback old-snapshot-reload leased-runtime-uninstall-gc retained-user-data PASS',
				'HWTEST PASS packages-context']
			ending: .poweroff
			forbidden: ['V panic:', 'FAIL: fn main.qualify_package_context']
			timeout: 300
		}]
	}
}

fn check() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(suite('', 'aarch64', '')!, os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir)
		|| os.is_link(options.state_dir) { return error('provide --kernel and a new --state-dir') }
	if os.getenv('VINIX_HWTEST_TCG') != '1' { return error('this qualification requires VINIX_HWTEST_TCG=1') }
	repository := hwhost.find_root(@FILE)!
	definition := suite(repository, options.arch, os.getenv('VINIX_CONTEXT_SANDBOX'))!
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select the packages-context scenario') }
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	kernel := work + '/kernel'
	os.cp(options.kernel, kernel)!
	hwhost.watch_interrupts()
	guest_dir := work + '/guest'
	guest := hwhost.build_program(host, repository + '/' + definition.guest, guest_dir, 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, guest_dir)!
	mut artifacts := []Artifact{}
	for role, path in {'kernel': kernel, 'sandbox': root + '/usr/bin/vinix-sandbox', 'guest-init': guest,
		'package-service': root + '/usr/bin/vinix-package', 'account-manager': root + '/usr/sbin/vinix-account',
		'session-runner': root + '/usr/sbin/vinix-session', 'native-sdk-example': root + '/usr/share/context-fixtures/package-hello',
		'example-manifest': root + '/usr/share/context-fixtures/manifest.json'} { artifacts << artifact(role, path)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: kernel, guest: guest, extras: root,
		state: work + '/packages-context', timeout: if options.timeout > 300 { options.timeout } else { 300 }, keep: true,
		failures_only: options.failures_only })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-context/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check() or { eprintln(err); 2 }) }
