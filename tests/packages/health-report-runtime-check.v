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
	kind string = 'health-report'
	scenario string = 'packages-health-report'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-health-report', guest: 'tests/packages/health-report-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/health_test.v', path: 'usr/share/package-fixtures/health-core' },
			hwhost.Program{ source: 'tools/packages/pkgprotocol/health_test.v', path: 'usr/share/package-fixtures/health-protocol' },
			hwhost.Program{ source: 'tests/packages/health-report-check.v', path: 'usr/share/package-fixtures/health-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-health-report', arches: ['aarch64', 'x86_64'],
			about: 'complete installed integrity reports, owned bounded metadata, read-only locking, catalog independence and reviewed repair',
			required: ['HWTEST START packages-health-report',
				'HEALTH REPORT all app/runtime/data packages inspected, sorted owned provenance, namespace/payload/registration classification, empty state and no filesystem mutation PASS',
				'HEALTH PROTOCOL 4096 maximally escaped rows fit the reply bound; excess rows refuse PASS',
				'HEALTH REPORT signed service/CLI, all simultaneous app/runtime/data/launcher issues, read-only locking and retained state, trust/catalog independence, malformed state refusal, fresh offline repair and clean uninstall PASS',
				'HEALTH PROCESS health-core PASS', 'HEALTH PROCESS health-protocol PASS', 'HEALTH PROCESS health-probe PASS',
				'HWTEST PASS packages-health-report'], ending: .poweroff, timeout: 600 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-health-report-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('health-core', root + 'health-core')!, artifact('health-protocol', root + 'health-protocol')!,
			artifact('health-probe', root + 'health-probe')!,
			artifact('serial-log', base + '/packages-health-report/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
