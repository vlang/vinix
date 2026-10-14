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
	kind string = 'removal-space'
	scenario string = 'packages-removal-space'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-removal-space', guest: 'tests/packages/removal-space-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/removal_space_test.v', path: 'usr/share/package-fixtures/removal-space-core' },
			hwhost.Program{ source: 'tests/packages/removal-space-fixture.v', path: 'usr/share/package-fixtures/removal-space-lifecycle' },
		], scenarios: [hwhost.Scenario{ name: 'packages-removal-space', arches: ['aarch64', 'x86_64'],
			about: 'verified retained-source uninstall estimates and offline transactional removal',
			required: ['HWTEST START packages-removal-space',
				'REMOVAL SPACE active-generation verification, shared fallback objects, missing/corrupt/linked sources, acquisition isolation and overflow PASS',
				'REMOVAL SPACE reviewed offline removal: verified retained files, no object reacquisition, reserve/fallback checks, post-preflight tamper refusal, activation/registration/data PASS',
				'REMOVAL PROCESS removal-space-core PASS', 'REMOVAL PROCESS removal-space-lifecycle PASS',
				'HWTEST PASS packages-removal-space'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-removal-space-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('removal-space-core', root + 'removal-space-core')!,
			artifact('removal-space-lifecycle', root + 'removal-space-lifecycle')!,
			artifact('serial-log', base + '/packages-removal-space/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
