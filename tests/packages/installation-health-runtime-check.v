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
	kind string = 'installation-health'
	scenario string = 'packages-installation-health'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-installation-health', guest: 'tests/packages/installation-health-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/installed_health_test.v', path: 'usr/share/package-fixtures/installation-health-core' },
			hwhost.Program{ source: 'tests/packages/installation-health-check.v', path: 'usr/share/package-fixtures/installation-health-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-installation-health', arches: ['aarch64', 'x86_64'],
			about: 'canonical installation modes and launcher repair with Verify/rollback consistency',
			required: ['HWTEST START packages-installation-health',
				'INSTALLATION HEALTH canonical launcher/MIME bytes, independent runtime/data, permissions/type/content refusal and unchanged outside files PASS',
				'INSTALLATION HEALTH signed application/runtime/data modes and desktop registration repair, Verify and rollback consistency PASS',
				'HEALTH PROCESS installation-health-core PASS', 'HEALTH PROCESS installation-health-probe PASS',
				'HWTEST PASS packages-installation-health'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-installation-health-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('installation-health-core', root + 'installation-health-core')!,
			artifact('installation-health-probe', root + 'installation-health-probe')!,
			artifact('serial-log', base + '/packages-installation-health/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
