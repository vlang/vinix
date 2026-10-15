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
	kind string = 'reviewed-cleanup'
	scenario string = 'packages-reviewed-cleanup'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-reviewed-cleanup', guest: 'tests/packages/reviewed-cleanup-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/packages/pkgcore/cleanup_test.v', path: 'usr/share/package-fixtures/cleanup-core' },
			hwhost.Program{ source: 'tools/packages/pkgprotocol/cleanup_test.v', path: 'usr/share/package-fixtures/cleanup-protocol' },
			hwhost.Program{ source: 'tests/packages/cleanup-check.v', path: 'usr/share/package-fixtures/cleanup-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-reviewed-cleanup', arches: ['aarch64', 'x86_64'],
			about: 'reviewed obsolete generation retirement, ordinary root-owned readers, stale approvals and signed real CLI retention',
			required: ['HWTEST START packages-reviewed-cleanup',
				'REVIEWED CLEANUP both architectures, offline/revoked catalog independence, retained active/rollback/live leases, cache, stages and personal data PASS',
				'REVIEWED CLEANUP stale configuration/activation/set/root/parent/lease/busy/release approvals and damaged rollback/unsafe roots refuse before removal PASS',
				'REVIEWED CLEANUP ordinary UID 1000 reads root-owned state with identical approval; foreign nested inventory refuses before any deletion and restored inventory retries PASS',
				'CLEANUP PROTOCOL strict bounded metadata, retained generation refusal and 1000 owned decode cycles PASS',
				'CLEANUP CLI signed install/three upgrades, leased-generation review, stale refusal, offline apply, current/rollback/cache/stage/data retention and empty retry PASS',
				'CLEANUP PROCESS cleanup-core PASS', 'CLEANUP PROCESS cleanup-protocol PASS', 'CLEANUP PROCESS cleanup-probe PASS',
				'HWTEST PASS packages-reviewed-cleanup'], ending: .poweroff, timeout: 600 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-reviewed-cleanup-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('package-cli', base + '/guest/root/usr/bin/vinix-package')!, artifact('cleanup-core', root + 'cleanup-core')!, artifact('cleanup-protocol', root + 'cleanup-protocol')!,
			artifact('cleanup-probe', root + 'cleanup-probe')!,
			artifact('serial-log', base + '/packages-reviewed-cleanup/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
