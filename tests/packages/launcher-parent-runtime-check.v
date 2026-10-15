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
	kind string = 'launcher-parent'
	scenario string = 'packages-launcher-parent'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-launcher-parent', guest: 'tests/packages/launcher-parent-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/packages/pkgcore/registration_parent_test.v', path: 'usr/share/package-fixtures/launcher-core' },
			hwhost.Program{ source: 'tools/packages/pkgcore/health_test.v', path: 'usr/share/package-fixtures/health-core' },
			hwhost.Program{ source: 'tests/packages/launcher-parent-check.v', path: 'usr/share/package-fixtures/launcher-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-launcher-parent', arches: ['aarch64', 'x86_64'],
			about: 'captured launcher parents and contents, ordinary launch refusal, health classification and signed offline repair',
			required: ['HWTEST START packages-launcher-parent',
				'LAUNCHER PARENTS identical external launchers through share/application aliases refuse Verify, classify health and bind repairs; restored parents pass PASS',
				'LAUNCHER PARENTS 24 captured/opened/read root, parent and leaf identity/mode mutations refuse PASS',
				'LAUNCHER PARENTS ordinary launch refuses damaged registration before private data or execution; restored administrator-owned launchers verify; guest root checks foreign ownership PASS',
				'LAUNCHER CLI four signed shared-parent repairs preserve app/runtime/data manifests and provenance, cache recovery, retained generations and clean uninstall PASS',
				'HEALTH REPORT all app/runtime/data packages inspected, sorted owned provenance, namespace/payload/registration classification, empty state and no filesystem mutation PASS',
				'LAUNCHER PROCESS launcher-core PASS', 'LAUNCHER PROCESS health-core PASS', 'LAUNCHER PROCESS launcher-probe PASS',
				'HWTEST PASS packages-launcher-parent'], ending: .poweroff, timeout: 600 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-launcher-parent-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('package-cli', base + '/guest/root/usr/bin/vinix-package')!, artifact('launcher-core', root + 'launcher-core')!, artifact('health-core', root + 'health-core')!,
			artifact('launcher-probe', root + 'launcher-probe')!,
			artifact('serial-log', base + '/packages-launcher-parent/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
