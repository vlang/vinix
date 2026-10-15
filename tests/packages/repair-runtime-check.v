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
	kind string = 'repair'
	scenario string = 'packages-repair'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-repair', guest: 'tests/packages/repair-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/repair_test.v', path: 'usr/share/package-fixtures/repair-core' },
			hwhost.Program{ source: 'tests/packages/repair-check.v', path: 'usr/share/package-fixtures/repair-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-repair', arches: ['aarch64', 'x86_64'],
			about: 'same-version payload repair, health-bound review and offline transactional recovery',
			required: ['HWTEST START packages-repair',
				'PACKAGE REPAIR active payload hash/size/type, changed-target exclusion, sorted closure and removal/rollback isolation PASS',
				'PACKAGE REPAIR signed install/upgrade/deployment/explicit repair, reviewed corruption recovery, exact installed versions despite available updates, publisher withdrawal refusal, preserved state/data and protocol compatibility PASS',
				'REPAIR PROCESS repair-core PASS', 'REPAIR PROCESS repair-probe PASS',
				'HWTEST PASS packages-repair'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-repair-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('repair-core', root + 'repair-core')!,
			artifact('repair-probe', root + 'repair-probe')!,
			artifact('serial-log', base + '/packages-repair/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
