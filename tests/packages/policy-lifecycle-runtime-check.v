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
	kind string = 'organization-policy-lifecycle'
	scenario string = 'packages-policy-lifecycle'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-policy-lifecycle', guest: 'tests/packages/policy-lifecycle-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/policy_lifecycle_test.v', path: 'usr/share/package-fixtures/policy-lifecycle' },
			hwhost.Program{ source: 'tools/packages/pkgcore/policy_test.v', path: 'usr/share/package-fixtures/policy' },
			hwhost.Program{ source: 'tools/packages/pkgcore/coordination_test.v', path: 'usr/share/package-fixtures/coordination' },
			hwhost.Program{ source: 'tools/packages/pkgcore/atomic_test.v', path: 'usr/share/package-fixtures/atomic' },
		], scenarios: [hwhost.Scenario{ name: 'packages-policy-lifecycle', arches: ['aarch64', 'x86_64'],
			about: 'owned policy review/apply, unchanged legacy identity, atomic saves, directory and lock refusals',
			required: ['HWTEST START packages-policy-lifecycle',
				'POLICY LIFECYCLE both architectures, independent fresh/installed results, exact legacy fingerprints/wire bytes, full 4096 bounds and unchanged no-op state PASS',
				'POLICY LIFECYCLE alternating changed apply pairs retire scratch; permission denial crosses dependency cycles, explicit firmware/licenses persist, only configuration changes PASS',
				'POLICY LIFECYCLE configuration/state/proposal/stale/ownership/directory/lock/busy refusals retire scratch, preserve activation and permit restored retry PASS',
				'POLICY LIFECYCLE oversized review refused before response cloning; configuration, proposal and installed generation unchanged PASS',
				'POLICY PROCESS policy-lifecycle PASS', 'POLICY PROCESS policy PASS', 'POLICY PROCESS coordination PASS', 'POLICY PROCESS atomic PASS',
				'HWTEST PASS packages-policy-lifecycle'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-policy-lifecycle-' + os.getpid().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir; root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('policy-lifecycle', root + 'policy-lifecycle')!,
			artifact('policy', root + 'policy')!, artifact('coordination', root + 'coordination')!, artifact('atomic', root + 'atomic')!,
			artifact('serial-log', base + '/packages-policy-lifecycle/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
