// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os

struct Artifact { role string bytes u64 sha256 string }
struct Receipt { format int = 1 architecture string artifacts []Artifact }
fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}
fn suite(baseline bool) hwhost.Suite {
	return hwhost.Suite{
		name: 'package-admin-client', guest: 'tests/packages/admin-client-guest'
		module_paths: if baseline { ['build/package-admin-client-work/baseline', '.', 'tools/accounts', 'tools/security-events', 'tools/keyring'] } else { ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring'] }
		directories: ['tmp:1777', 'run', 'run/user']
		programs: [
			hwhost.Program{ source: if baseline { 'build/package-admin-client-work/baseline/pkgadmin/client_ownership_test.v' } else { 'tools/packages/pkgadmin/client_ownership_test.v' }, path: 'usr/share/package-fixtures/admin-client', flags: if baseline { ['-manualfree', '-d', 'track_heap', '-d', 'admin_client_guest', '-d', 'admin_client_baseline'] } else { ['-manualfree', '-d', 'track_heap', '-d', 'admin_client_guest'] } },
			hwhost.Program{ source: 'tools/packages/pkgadmin/protocol_test.v', path: 'usr/share/package-fixtures/protocol' },
			hwhost.Program{ source: 'tools/packages/pkgadmin/ownership_test.v', path: 'usr/share/package-fixtures/streams' },
			hwhost.Program{ source: 'tools/packages/pkgadmin/socket_test.v', path: 'usr/share/package-fixtures/admin-socket' },
			hwhost.Program{ source: 'tools/accounts/authd.v', path: 'usr/sbin/vinix-authd' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' },
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
		]
		scenarios: [hwhost.Scenario{ name: 'packages-admin-client', arches: ['aarch64', 'x86_64'],
			about: 'complete administrator callers, owned password/authentication inputs and approval failure cleanup',
			required: ['HWTEST START packages-admin-client',
				'ADMIN CLIENT root service and ordinary caller preserve reviewed input, passwords, status, cleanup and exact diagnostics PASS',
				'ADMIN CLIENT ACTOR root PASS', 'ADMIN CLIENT ACTOR UID 1000 PASS',
				'ADMIN CLIENT COMPANION protocol PASS', 'ADMIN CLIENT COMPANION streams PASS', 'ADMIN CLIENT COMPANION admin-socket PASS',
				'HWTEST PASS packages-admin-client'], ending: .poweroff, timeout: 900 }]
	}
}
fn check() !int {
	baseline := '--baseline' in os.args
	args := os.args[1..].filter(it != '--baseline'); options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(baseline), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-admin-client-' + os.getpid().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(baseline), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		mut artifacts := [kernel, artifact('guest-init', base + '/guest/init')!]
		for name in ['admin-client', 'protocol', 'streams', 'admin-socket']! {
			artifacts << artifact(name, base + '/guest/root/usr/share/package-fixtures/' + name)!
		}
		for path in ['usr/sbin/vinix-authd', 'usr/sbin/vinix-session', 'usr/bin/vinix-package']! {
			artifacts << artifact(os.file_name(path), base + '/guest/root/' + path)!
		}
		artifacts << artifact('serial-log', base + '/packages-admin-client/serial.log')!
		os.write_file(base + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, artifacts: artifacts }) + '\n')!
	}
	return status
}
fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
