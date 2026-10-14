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
	kind string = 'publisher-recovery'
	scenario string = 'packages-publisher-recovery'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-publisher-recovery', guest: 'tests/packages/publisher-recovery-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/trust_recovery_test.v', path: 'usr/share/package-fixtures/trust-recovery' },
			hwhost.Program{ source: 'tests/packages/publisher-recovery-check.v', path: 'usr/share/package-fixtures/publisher-recovery' },
		], scenarios: [hwhost.Scenario{ name: 'packages-publisher-recovery', arches: ['aarch64', 'x86_64'],
			about: 'recorded invalid-key cache retirement, reviewed replacement/re-enrollment and retained replay floors',
			required: ['HWTEST START packages-publisher-recovery',
				'TRUST RECOVERY exact disabled identity/digest/sequence and complete index required PASS',
				'TRUST RECOVERY valid retired keys still require authenticated signatures PASS',
				'TRUST RECOVERY empty refresh preserves retired and independent replay floors PASS',
				'RECOVERY PROCESS trust-recovery PASS',
				'PUBLISHER RECOVERY reviewed key replacement: exact retired floor retained; stale review/live tamper/old rollback refused; upgrade/uninstall/data PASS',
				'PUBLISHER RECOVERY revocation/re-enrollment: exact retired floor retained; stale review/live tamper/old rollback refused; upgrade/uninstall/data PASS',
				'Publisher cache recovery qualification passed', 'RECOVERY PROCESS publisher-recovery PASS',
				'HWTEST PASS packages-publisher-recovery'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-publisher-recovery-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('trust-recovery', root + 'trust-recovery')!,
			artifact('publisher-recovery', root + 'publisher-recovery')!,
			artifact('serial-log', base + '/packages-publisher-recovery/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
