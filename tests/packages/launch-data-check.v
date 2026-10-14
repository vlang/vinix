// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct DataArtifact { role string bytes u64 sha256 string }
struct DataReceipt { format int = 1 architecture string completed_at i64 seconds f64 artifacts []DataArtifact }

fn data_artifact(role string, path string) !DataArtifact {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return DataArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn data_suite(repository string, sandbox string) !hwhost.Suite {
	return hwhost.Suite{
		name: 'package-launch-data', guest: 'tests/accounts/guest'
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring']
		programs: [hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/accounts/authd.v', path: 'usr/sbin/vinix-authd' },
			hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' },
			hwhost.Program{ source: 'tests/packages/launch-data-probe.v', path: 'usr/share/package-fixtures/launch-data-probe' }]
		binaries: [hwhost.RootBinary{ source: sandbox, path: 'usr/bin/vinix-sandbox' }]
		files: [hwhost.RootFile{ path: 'etc/passwd', text: 'root:x:0:0:root:/root:/bin/sh\n' },
			hwhost.RootFile{ path: 'etc/group', text: 'root:x:0:\ntty:x:5:\n' },
			hwhost.RootFile{ path: 'etc/vinix/auth.conf', text: 'scrypt_ln = 10\n' },
			hwhost.RootFile{ path: 'usr/share/vinix/actions/packages-launch', text: if repository == '' { '' } else { os.read_file(repository + '/tools/accounts/actions/packages-launch')! } }]
		directories: ['run', 'home', 'var/log', 'tmp:1777']
		scenarios: [hwhost.Scenario{ name: 'packages-launch-data', arches: ['aarch64', 'x86_64'],
			about: 'ordinary-account application data preparation, unsafe entries, retained data and clean purge', timeout: 180, ending: .poweroff,
			required: ['HWTEST START packages-launch-data',
				'PACKAGE LAUNCH DATA ordinary-admin-standard aliases-special-files-ownership-shared-modes refused-before-probe targets-preserved PASS',
				'PACKAGE LAUNCH DATA sdk-private-data-tmp retained-relaunch-offline-reinstall own-account-purge PASS',
				'HWTEST PASS packages-launch-data'], forbidden: ['V panic:'] }]
	}
}

fn check() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(data_suite('', '')!, os.args[1..], @FILE) }
	sandbox := os.getenv('VINIX_LAUNCH_DATA_SANDBOX')
	if os.getenv('VINIX_HWTEST_TCG') != '1' || !os.is_file(sandbox) || !os.is_file(options.kernel)
		|| options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) {
		return error('provide VINIX_HWTEST_TCG=1, VINIX_LAUNCH_DATA_SANDBOX, a target --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	definition := data_suite(repository, sandbox)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-launch-data') }
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := []DataArtifact{}
	for role, path in {'kernel': work + '/kernel', 'guest-init': guest, 'package-service': root + '/usr/bin/vinix-package',
		'authentication-service': root + '/usr/sbin/vinix-authd', 'account-manager': root + '/usr/sbin/vinix-account',
		'session-runner': root + '/usr/sbin/vinix-session', 'sandbox': root + '/usr/bin/vinix-sandbox',
		'application-probe': root + '/usr/share/package-fixtures/launch-data-probe',
		'launch-action': root + '/usr/share/vinix/actions/packages-launch'} { artifacts << data_artifact(role, path)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-launch-data', timeout: if options.timeout > 180 { options.timeout } else { 180 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << data_artifact('serial-log', work + '/packages-launch-data/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(DataReceipt{ architecture: options.arch, completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check() or { eprintln(err); 2 }) }
