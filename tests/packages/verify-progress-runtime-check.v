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
	kind string = 'verify-progress'
	scenario string = 'packages-verify-progress'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-verify-progress', guest: 'tests/packages/verify-progress-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/verify_test.v', path: 'usr/share/package-fixtures/verify-progress-core' },
			hwhost.Program{ source: 'tests/packages/verify-progress-check.v', path: 'usr/share/package-fixtures/verify-progress-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-verify-progress', arches: ['aarch64', 'x86_64'],
			about: 'read-only verification progress, completion and failure semantics',
			required: ['HWTEST START packages-verify-progress',
				'VERIFY PROGRESS payload/launcher identity, compatible counters, empty state and no completion on byte/mode/registration failure PASS',
				'VERIFY PROGRESS signed service/CLI, read-only locking/state, compatible frames, legacy text/JSON, offline catalog independence and payload/mode/launcher failure recovery PASS',
				'VERIFY PROCESS verify-progress-core PASS', 'VERIFY PROCESS verify-progress-probe PASS',
				'HWTEST PASS packages-verify-progress'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-verify-progress-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('verify-progress-core', root + 'verify-progress-core')!,
			artifact('verify-progress-probe', root + 'verify-progress-probe')!,
			artifact('serial-log', base + '/packages-verify-progress/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
