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
	kind string = 'coordination-identity'
	scenario string = 'packages-coordination-identity'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-coordination-identity', guest: 'tests/packages/coordination-identity-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/coordination_test.v', path: 'usr/share/package-fixtures/coordination-identity-core' },
			hwhost.Program{ source: 'tests/packages/cache-preflight-check.v', path: 'usr/share/package-fixtures/coordination-identity-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-coordination-identity', arches: ['aarch64', 'x86_64'],
			about: 'unique named package coordination and signed maintenance',
			required: ['HWTEST START packages-coordination-identity',
				'COORDINATION IDENTITY state reader/writer/status and launch/collection/purge refuse hard links before mutation; restored entries retry PASS',
				'COORDINATION IDENTITY captured locks reject replaced/unlinked names and captured-parent lease changes without mutating replacements; restored identities retry PASS',
				'COORDINATION IDENTITY malformed obsolete lease refuses collection before any generation/cache removal; restored lease permits collection PASS',
				'COORDINATION IDENTITY 128 repeats of six hard-link refusals retire descriptors under a 32-descriptor limit; busy writer preserves permissions and restored exclusion PASS',
				'CACHE PREFLIGHT signed service/CLI refresh rejects oversized cache before later acquisition/publication and accepts a bounded retry PASS',
				'COORDINATION PROCESS coordination-identity-core PASS', 'COORDINATION PROCESS coordination-identity-probe PASS',
				'HWTEST PASS packages-coordination-identity'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-coordination-identity-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('coordination-identity-core', root + 'coordination-identity-core')!,
			artifact('coordination-identity-probe', root + 'coordination-identity-probe')!,
			artifact('serial-log', base + '/packages-coordination-identity/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
