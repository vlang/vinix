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
	kind string = 'rollback-transaction'
	scenario string = 'packages-rollback-transaction'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-rollback-transaction', guest: 'tests/packages/rollback-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/packages/pkgcore/rollback_test.v', path: 'usr/share/package-fixtures/rollback-core' },
			hwhost.Program{ source: 'tools/packages/pkgcore/generation_admission_test.v', path: 'usr/share/package-fixtures/generation-core' },
			hwhost.Program{ source: 'tests/packages/rollback-check.v', path: 'usr/share/package-fixtures/rollback-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-rollback-transaction', arches: ['aarch64', 'x86_64'],
			about: 'fresh rollback generations, retained-source disk admission, interrupted recovery, cleanup coherence and signed CLI lifecycle',
			required: ['HWTEST START packages-rollback-transaction',
				'ROLLBACK TRANSACTION cleanup before/after rollback retains a complete reversible history edge on both architectures PASS',
				'ROLLBACK TRANSACTION exact retained-source disk estimate and reserve refusal preserve activation, rollback and interrupted work PASS',
				'ROLLBACK TRANSACTION interrupted staging and damaged published copy preserve current; reviewed retry uses retained source without acquisition PASS',
				'ROLLBACK TRANSACTION empty and identical package sets still publish a fresh reversible generation PASS',
				'GENERATION ADMISSION rollback refuses four late changes without switching current; captured whitespace-compatible metadata retries PASS',
				'ROLLBACK CLI signed app/runtime/all-data closure, reviewed progress, offline source copies, stale approval, leases, cleanup, undo, uninstall and personal data PASS',
				'ROLLBACK PROCESS rollback-core PASS', 'ROLLBACK PROCESS generation-core PASS', 'ROLLBACK PROCESS rollback-probe PASS',
				'HWTEST PASS packages-rollback-transaction'], ending: .poweroff, timeout: 600 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-rollback-transaction-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('package-cli', base + '/guest/root/usr/bin/vinix-package')!, artifact('rollback-core', root + 'rollback-core')!, artifact('generation-core', root + 'generation-core')!,
			artifact('rollback-probe', root + 'rollback-probe')!,
			artifact('serial-log', base + '/packages-rollback-transaction/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
