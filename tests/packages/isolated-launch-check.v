// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact { role string bytes u64 sha256 string }
struct Receipt { format int = 1 architecture string completed_at i64 platform string = 'qemu-tcg' scenario string = 'packages-isolated-launch' seconds f64 artifacts []Artifact }

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite(repository string, sandbox string) !hwhost.Suite {
	action := if repository == '' { '' } else { os.read_file(repository + '/tools/accounts/actions/packages-launch')! }
	return hwhost.Suite{
		name: 'package-isolated-launch'
		guest: 'tests/accounts/guest'
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring']
		programs: [hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/accounts/authd.v', path: 'usr/sbin/vinix-authd' },
			hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' }]
		binaries: [hwhost.RootBinary{ source: sandbox, path: 'usr/bin/vinix-sandbox' }]
		files: [hwhost.RootFile{ path: 'etc/passwd', text: 'root:x:0:0:root:/root:/bin/sh\n' },
			hwhost.RootFile{ path: 'etc/group', text: 'root:x:0:\ntty:x:5:\n' },
			hwhost.RootFile{ path: 'etc/vinix/auth.conf', text: 'scrypt_ln = 10\n' },
			hwhost.RootFile{ path: 'usr/share/vinix/actions/packages-launch', text: action }]
		directories: ['run', 'home', 'var/log', 'tmp:1777']
		scenarios: [hwhost.Scenario{ name: 'packages-isolated-launch', arches: ['aarch64', 'x86_64'],
			about: 'ordinary administrator and standard-user application launches with zero account groups and retained standard streams',
			required: ['HWTEST START packages-isolated-launch',
				'PACKAGE ISOLATED account-admin-standard own-identity groups-zero literal-argv stdin-stdout-stderr exit-code private-data PASS',
				'PACKAGE ISOLATED native-window terminal-tty geometry input trust-and-payload-refusal audit clean-runtime PASS',
				'PACKAGE DOCUMENTS ordinary-admin-standard regular-and-alias read-write outside-denied special-target-refusal before-data clean-runtime PASS',
				'PACKAGE PURGE installed-root-refusal live-uninstalled-lease retained-data safe-links nested-fifo idempotent-own-account PASS',
				'HWTEST PASS packages-isolated-launch'], forbidden: ['V panic:'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(suite('', '')!, os.args[1..], @FILE) }
	sandbox := os.getenv('VINIX_ISOLATED_SANDBOX')
	if os.getenv('VINIX_HWTEST_TCG') != '1' || !os.is_file(options.kernel) || !os.is_file(sandbox)
		|| options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) {
		return error('provide VINIX_HWTEST_TCG=1, VINIX_ISOLATED_SANDBOX, a target --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	definition := suite(repository, sandbox)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-isolated-launch') }
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
	for role, path in {'kernel': kernel, 'guest-init': guest, 'package-service': root + '/usr/bin/vinix-package',
		'authentication-service': root + '/usr/sbin/vinix-authd', 'account-manager': root + '/usr/sbin/vinix-account',
		'session-runner': root + '/usr/sbin/vinix-session', 'sandbox': root + '/usr/bin/vinix-sandbox',
		'launch-action': root + '/usr/share/vinix/actions/packages-launch'} { artifacts << artifact(role, path)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: kernel, guest: guest, extras: root,
		state: work + '/packages-isolated-launch', timeout: if options.timeout > 300 { options.timeout } else { 300 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-isolated-launch/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check() or { eprintln(err); 2 }) }
