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
fn suite() hwhost.Suite {
	return hwhost.Suite{
		name: 'package-admin-envelope', guest: 'tests/packages/admin-envelope-guest'
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring']
		directories: ['tmp:1777']
		programs: [
			hwhost.Program{ source: 'tools/packages/pkgadmin/ownership_test.v', path: 'usr/share/package-fixtures/admin-envelope', flags: ['-manualfree', '-d', 'track_heap'] },
			hwhost.Program{ source: 'tools/packages/pkgadmin/protocol_test.v', path: 'usr/share/package-fixtures/protocol' },
			hwhost.Program{ source: 'tools/accounts/authcore/authcore_test.v', path: 'usr/share/package-fixtures/authcore' },
			hwhost.Program{ source: 'tools/packages/pkgadmin/socket_test.v', path: 'usr/share/package-fixtures/socket' },
			hwhost.Program{ source: 'tools/accounts/authd.v', path: 'usr/sbin/vinix-authd' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' },
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
		]
		scenarios: [hwhost.Scenario{ name: 'packages-admin-envelope', arches: ['aarch64', 'x86_64'],
			about: 'owned canonical administrator requests, partial refusals and completion hash state as root and UID 1000',
			required: ['HWTEST START packages-admin-envelope',
				'ADMIN ENVELOPE 16 reviewed commands/boundaries x1000 and eight statuses retained 0 bytes PASS',
				'ADMIN ENVELOPE all 4096 truncated prefixes retained 0 bytes PASS',
				'ADMIN ENVELOPE 28 malformed/schema/limit paths x1000 retained 0 bytes PASS',
				'ADMIN ENVELOPE excess arguments, oversized encode/decode and invalid receipt construction x1000 retained 0 bytes PASS',
				'ADMIN ENVELOPE 12 invalid completion paths x1000 retained 0 bytes PASS',
				'ADMIN ENVELOPE ACTOR root PASS', 'ADMIN ENVELOPE ACTOR UID 1000 PASS',
				'ADMIN ENVELOPE COMPANION protocol PASS', 'ADMIN ENVELOPE COMPANION authcore PASS', 'ADMIN ENVELOPE COMPANION socket PASS',
				'HWTEST PASS packages-admin-envelope'], ending: .poweroff, timeout: 900 }]
	}
}
fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-admin-envelope-' + os.getpid().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		mut artifacts := [kernel, artifact('guest-init', base + '/guest/init')!]
		for name in ['admin-envelope', 'protocol', 'authcore', 'socket']! {
			artifacts << artifact(name, base + '/guest/root/usr/share/package-fixtures/' + name)!
		}
		for path in ['usr/sbin/vinix-authd', 'usr/sbin/vinix-session', 'usr/bin/vinix-package']! {
			artifacts << artifact(os.file_name(path), base + '/guest/root/' + path)!
		}
		artifacts << artifact('serial-log', base + '/packages-admin-envelope/serial.log')!
		os.write_file(base + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, artifacts: artifacts }) + '\n')!
	}
	return status
}
fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
