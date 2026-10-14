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
	kind string = 'mirror-admission'
	scenario string = 'packages-mirror-admission'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-mirror-admission', guest: 'tests/packages/mirror-admission-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/mirror_test.v', path: 'usr/share/package-fixtures/mirror-admission-core' },
			hwhost.Program{ source: 'tools/packages/pkgcore/deployment_test.v', path: 'usr/share/package-fixtures/mirror-admission-deployment' },
		], scenarios: [hwhost.Scenario{ name: 'packages-mirror-admission', arches: ['aarch64', 'x86_64'],
			about: 'complete catalog and locked deployment mirror admission',
			required: ['HWTEST START packages-mirror-admission',
				'MIRROR ADMISSION changed staged metadata refuses before publication; verified cache survives and offline retry succeeds PASS',
				'MIRROR ADMISSION 34 late metadata/payload/mode/link/namespace refusals preserve source state, outside data and cache; no completion, clean staging and offline retry PASS',
				'MIRROR ADMISSION 128 valid and refused complete-stage scans retire descriptors under a 32-descriptor limit and restored namespace retries PASS',
				'MIRROR ADMISSION locked export binds exact captured deployment bytes through publication; changed staged lock refuses and retry preserves pins PASS',
				'MIRROR PROCESS mirror-admission-core PASS', 'MIRROR PROCESS mirror-admission-deployment PASS',
				'HWTEST PASS packages-mirror-admission'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-mirror-admission-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('mirror-admission-core', root + 'mirror-admission-core')!,
			artifact('mirror-admission-deployment', root + 'mirror-admission-deployment')!,
			artifact('serial-log', base + '/packages-mirror-admission/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
