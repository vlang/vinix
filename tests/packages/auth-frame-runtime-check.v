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
		name: 'package-auth-frame', guest: 'tests/packages/auth-frame-guest'
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring']
		directories: ['tmp:1777']
		programs: [
			hwhost.Program{ source: 'tools/accounts/authproto/ownership_test.v', path: 'usr/share/package-fixtures/auth-frame', flags: ['-manualfree', '-d', 'track_heap', '-d', 'auth_frame_guest'] },
			hwhost.Program{ source: 'tools/accounts/authproto/proto_test.v', path: 'usr/share/package-fixtures/protocol' },
			hwhost.Program{ source: 'tools/accounts/authcore/authcore_test.v', path: 'usr/share/package-fixtures/authcore' },
			hwhost.Program{ source: 'tools/accounts/authclient/root_peer_test.v', path: 'usr/share/package-fixtures/root-peer' },
			hwhost.Program{ source: 'tools/accounts/authd.v', path: 'usr/sbin/vinix-authd' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' },
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
		]
		scenarios: [hwhost.Scenario{ name: 'packages-auth-frame', arches: ['aarch64', 'x86_64'],
			about: 'owned bounded authentication frames and malformed stream recovery as root and UID 1000',
			required: ['HWTEST START packages-auth-frame',
				'AUTH FRAME owned text counts 0..12 and independent maximum binary frames x1000 retained 0 bytes PASS',
				'AUTH FRAME every prefix and 16 malformed/trailing cases, oversized late field and excess count x1000 retained 0 bytes PASS',
				'AUTH FRAME maximum binary wire roundtrips x1000 retained 0 bytes and no descriptors PASS',
				'AUTH FRAME eight interrupted stream positions, three malformed wire paths and invalid-descriptor reads/writes x1000 retained 0 bytes and no descriptors PASS',
				'AUTH FRAME ACTOR root PASS', 'AUTH FRAME ACTOR UID 1000 PASS',
				'AUTH FRAME COMPANION protocol PASS', 'AUTH FRAME COMPANION authcore PASS',
				'AUTH FRAME ordinary peer receives no authentication secret PASS', 'HWTEST PASS packages-auth-frame'], ending: .poweroff, timeout: 900 }]
	}
}
fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-auth-frame-' + os.getpid().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		mut artifacts := [kernel, artifact('guest-init', base + '/guest/init')!]
		for name in ['auth-frame', 'protocol', 'authcore', 'root-peer']! {
			artifacts << artifact(name, base + '/guest/root/usr/share/package-fixtures/' + name)!
		}
		for path in ['usr/sbin/vinix-authd', 'usr/sbin/vinix-session', 'usr/bin/vinix-package']! {
			artifacts << artifact(os.file_name(path), base + '/guest/root/' + path)!
		}
		artifacts << artifact('serial-log', base + '/packages-auth-frame/serial.log')!
		os.write_file(base + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, artifacts: artifacts }) + '\n')!
	}
	return status
}
fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
