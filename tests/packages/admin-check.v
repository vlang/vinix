// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact { role string bytes u64 sha256 string }
struct Receipt { format int = 1 architecture string completed_at i64 platform string = 'qemu-tcg' scenario string = 'packages-admin' seconds f64 artifacts []Artifact }

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite(repository string) !hwhost.Suite {
	action := if repository == '' { '' } else { os.read_file(repository + '/tools/accounts/actions/packages-change')! }
	return hwhost.Suite{
		name: 'package-administrator'
		guest: 'tests/accounts/guest'
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring']
		programs: [hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/accounts/authd.v', path: 'usr/sbin/vinix-authd' },
			hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' }]
		files: [hwhost.RootFile{ path: 'etc/passwd', text: 'root:x:0:0:root:/root:/bin/sh\n' },
			hwhost.RootFile{ path: 'etc/group', text: 'root:x:0:\ntty:x:5:\n' },
			hwhost.RootFile{ path: 'etc/vinix/auth.conf', text: 'scrypt_ln = 10\n' },
			hwhost.RootFile{ path: 'usr/share/vinix/actions/packages-change', text: action }]
		directories: ['run', 'home', 'var/log', 'tmp:1777']
		scenarios: [hwhost.Scenario{ name: 'packages-admin', arches: ['aarch64', 'x86_64'],
			about: 'reviewed package administration from an ordinary administrator through authenticated peer-bound progress transport',
			required: ['HWTEST START packages-admin',
				'PACKAGE RESOLVER chain-4096 dense-cycle-512 explicit-search-limit bounded-iterative PASS',
				'PACKAGE RESOLVER current-cause dependency-path bounded-diagnostic PASS',
				'PACKAGE RESOLVER installed-preference single-choice late-version-backtracking PASS',
				'PACKAGE REMOVAL implicit-transitive requested-blocker batch-roots borrowed-state PASS',
				'PACKAGE INDEX signed-duplicate missing-declaration null-array typed-counter refusal preserves-catalog-trust-state canonical-retry PASS',
				'PACKAGE ADMIN ordinary-admin password-required peer-bound reviewed-install progress stale-refusal no-launch PASS',
				'PACKAGE METADATA ordinary-admin-standard complete-package-trust-history-offline-lock typed-flags nested-refusal read-only PASS',
				'PACKAGE DEPLOYMENT bounded-reader formats-1-2 owned-fields malformed-refusal read-only PASS',
				'PACKAGE VIEW ordinary-admin-standard complete-catalog installed-launch-fields typed-flags nested-refusal read-only PASS',
				'PACKAGE POLICY ordinary-admin-standard public-read complete-impact literal-path password-role stale-file-refusal atomic-policy-only reload clean-runtime PASS',
				'PACKAGE ADMIN reviewed-remove rollback trust-revocation root-state audit no-password-log clean-runtime PASS', 'HWTEST PASS packages-admin'],
			forbidden: ['V panic:', 'FAIL: fn main.qualify_package_admin'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(suite('')!, os.args[1..], @FILE) }
	if os.getenv('VINIX_HWTEST_TCG') != '1' || !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) {
		return error('provide VINIX_HWTEST_TCG=1, a target --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	definition := suite(repository)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-admin') }
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
		'session-runner': root + '/usr/sbin/vinix-session', 'administration-action': root + '/usr/share/vinix/actions/packages-change'} { artifacts << artifact(role, path)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: kernel, guest: guest, extras: root,
		state: work + '/packages-admin', timeout: if options.timeout > 300 { options.timeout } else { 300 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-admin/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check() or { eprintln(err); 2 }) }
