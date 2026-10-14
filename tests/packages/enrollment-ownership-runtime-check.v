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
	kind string = 'enrollment-ownership'
	scenario string = 'packages-enrollment-ownership'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-enrollment-ownership', guest: 'tests/packages/enrollment-ownership-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/enrollment_ownership_test.v', path: 'usr/share/package-fixtures/enrollment-ownership-core' },
			hwhost.Program{ source: 'tests/packages/cache-preflight-check.v', path: 'usr/share/package-fixtures/enrollment-ownership-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-enrollment-ownership', arches: ['aarch64', 'x86_64'],
			about: 'owned enrollment inputs, independent repository reviews and signed maintenance',
			required: ['HWTEST START packages-enrollment-ownership',
				'ENROLLMENT OWNERSHIP admitted snapshot text and decoded index have independent lifetimes; publisher identity remains borrowed PASS',
				'CACHE PREFLIGHT signed service/CLI refresh rejects oversized cache before later acquisition/publication and accepts a bounded retry PASS',
				'ENROLLMENT PROCESS enrollment-ownership-core PASS', 'ENROLLMENT PROCESS enrollment-ownership-probe PASS',
				'HWTEST PASS packages-enrollment-ownership'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-enrollment-ownership-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('enrollment-ownership-core', root + 'enrollment-ownership-core')!,
			artifact('enrollment-ownership-probe', root + 'enrollment-ownership-probe')!,
			artifact('serial-log', base + '/packages-enrollment-ownership/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
