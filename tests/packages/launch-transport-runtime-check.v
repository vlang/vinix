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
	sdk int = 1
	architecture string
	completed_at i64
	kind string = 'launch-transport-lifecycle'
	scenario string = 'packages-launch-transport'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-launch-transport', guest: 'tests/packages/launch-transport-guest',
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkglaunch/ownership_test.v', path: 'usr/share/package-fixtures/launch-transport',
				flags: ['-manualfree', '-d', 'track_heap', '-d', 'transport_guest'] },
			hwhost.Program{ source: 'tools/packages/pkglaunch/protocol_test.v', path: 'usr/share/package-fixtures/protocol' },
			hwhost.Program{ source: 'tools/packages/pkglaunch/streams_test.v', path: 'usr/share/package-fixtures/streams' },
			hwhost.Program{ source: 'tools/packages/pkgcore/command_test.v', path: 'usr/share/package-fixtures/command' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' },
		], scenarios: [hwhost.Scenario{ name: 'packages-launch-transport', arches: ['aarch64', 'x86_64'],
			about: 'owned canonical launch envelopes, receipts and wire transfers as root and UID 1000 under allocation tracking',
			required: ['HWTEST START packages-launch-transport',
				'LAUNCH TRANSPORT tracked decoding: six literal/max-count paths x1000 and 16 escaped 64-KiB requests retained 0 bytes',
				'LAUNCH TRANSPORT independent owned requests, five modes, all non-NUL byte values, 772-value envelope and escaped 64-KiB boundary PASS',
				'LAUNCH TRANSPORT tracked refusals: 33 malformed/schema/limit paths x1000 retained 0 bytes',
				'LAUNCH TRANSPORT every truncated prefix, noncanonical fields/escapes/types, NUL, argument/document/byte and envelope limits refuse with retired scratch PASS',
				'LAUNCH TRANSPORT tracked wire: six status paths x1000 and two invalid receipt paths x1000 retained 0 bytes and no descriptors',
				'LAUNCH TRANSPORT request/rights/completion roundtrips preserve nonce, literal argv, three CLOEXEC streams and 0/37/126/127/143/255 statuses PASS',
				'LAUNCH TRANSPORT tracked wire refusals: nine receipts, five request packets and read errors x1000 retained 0 bytes and no descriptors',
				'LAUNCH TRANSPORT truncated/oversized request frames, tampered/noncanonical/overlong completion and closed-descriptor errors retire scratch PASS',
				'LAUNCH TRANSPORT ACTOR root PASS', 'LAUNCH TRANSPORT ACTOR UID 1000 PASS',
				'LAUNCH TRANSPORT COMPANION protocol PASS', 'LAUNCH TRANSPORT COMPANION streams PASS', 'LAUNCH TRANSPORT COMPANION command PASS',
				'HWTEST PASS packages-launch-transport'], ending: .poweroff, timeout: 900 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-launch-transport-' + os.getpid().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir; root := base + '/guest/root/usr/share/package-fixtures/'
		mut artifacts := [kernel, artifact('guest-init', base + '/guest/init')!]
		for name in ['launch-transport', 'protocol', 'streams', 'command']! { artifacts << artifact(name, root + name)! }
		artifacts << artifact('account-session', base + '/guest/root/usr/sbin/vinix-session')!
		artifacts << artifact('serial-log', base + '/packages-launch-transport/serial.log')!
		os.write_file(base + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: artifacts }) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
