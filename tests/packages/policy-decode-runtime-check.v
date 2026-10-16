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
	kind string = 'organization-policy-decoding'
	scenario string = 'packages-policy-decode'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-policy-decode', guest: 'tests/packages/policy-decode-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/policy_decode_test.v', path: 'usr/share/package-fixtures/policy-decode' },
			hwhost.Program{ source: 'tools/packages/pkgcore/policy_test.v', path: 'usr/share/package-fixtures/policy' },
			hwhost.Program{ source: 'tools/packages/pkgcore/configuration_observation_test.v', path: 'usr/share/package-fixtures/configuration-observation' },
		], scenarios: [hwhost.Scenario{ name: 'packages-policy-decode', arches: ['aarch64', 'x86_64'],
			about: 'bounded organization policy documents/reviews, unchanged reviewed administration and configuration defaults',
			required: ['HWTEST START packages-policy-decode',
				'POLICY DECODE both architectures, owned independent file documents/reviews, repeated close, exact writer bytes and full 4096 bounds PASS',
				'POLICY DECODE strict declarations preserve legacy defaults, optional pin ranges, canonical settings, empty permissions and full u64 generations; borrowed validation retires scratch PASS',
				'POLICY DECODE every truncated prefix and required/schema/UTF8/number/late-row/semantic refusal retires scratch PASS',
				'POLICY DECODE exact 8 MiB, 4096 collections/rows and 4096-byte diagnostics accepted; metadata/collection/grant/string/disclosure overflow refused PASS',
				'POLICY PROCESS policy-decode PASS', 'POLICY PROCESS policy PASS', 'POLICY PROCESS configuration-observation PASS',
				'HWTEST PASS packages-policy-decode'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-policy-decode-' + os.getpid().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir; root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('policy-decode', root + 'policy-decode')!,
			artifact('policy', root + 'policy')!, artifact('configuration-observation', root + 'configuration-observation')!,
			artifact('serial-log', base + '/packages-policy-decode/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
