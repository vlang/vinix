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
	kind string = 'deployment-save'
	scenario string = 'packages-deployment-save'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-deployment-save', guest: 'tests/packages/deployment-save-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/packages/pkgcore/deployment_save_test.v', path: 'usr/share/package-fixtures/save-core' },
			hwhost.Program{ source: 'tools/packages/pkgcore/atomic_new_test.v', path: 'usr/share/package-fixtures/atomic-new' },
			hwhost.Program{ source: 'tools/packages/pkgprotocol/deployment_saved_test.v', path: 'usr/share/package-fixtures/save-protocol' },
			hwhost.Program{ source: 'tests/packages/deployment-snapshot-check.v', path: 'usr/share/package-fixtures/save-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-deployment-save', arches: ['aarch64', 'x86_64'],
			about: 'new-file installed snapshot publication, exact receipts, failure/race safety and ordinary owned exports',
			required: ['HWTEST START packages-deployment-save',
				'DEPLOYMENT SAVE exact sorted installed app/runtime/all-data metadata, subset closure, generation/digest receipt, offline revoked policy and no source mutation on both architectures PASS',
				'DEPLOYMENT SAVE malformed roots/paths/state and busy writers refuse before output; existing files preserved, temporary cleanup and fresh empty observation PASS',
				'NEW METADATA existing file/alias/dangling/FIFO/directory/hardlink destinations refuse without replacement or blocking PASS',
				'NEW METADATA checkpoint/write/space/flush failures, destination races, mode/parent/final substitutions, cleanup and saved-file retry refusal PASS',
				'NEW METADATA concurrent publishers admit exactly one complete file with canonical final mode and no temporary leftovers PASS',
				'DEPLOYMENT SAVED PROTOCOL complete typed fields, duplicate/unknown keys, numeric/path/count/digest bounds and independent closeable strings PASS',
				'DEPLOYMENT SAVE ordinary UID 1000 saves exact root-owned installed metadata into an owned relative destination without administrator authorization PASS',
				'DEPLOYMENT SAVE CLI new-file durable export, exact receipt and withdrawn/offline/revoked metadata, existing-file preservation and authenticated reproduction PASS',
				'SAVE PROCESS save-core PASS', 'SAVE PROCESS atomic-new PASS', 'SAVE PROCESS save-protocol PASS', 'SAVE PROCESS save-probe PASS',
				'HWTEST PASS packages-deployment-save'], ending: .poweroff, timeout: 600 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-deployment-save-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('package-cli', base + '/guest/root/usr/bin/vinix-package')!, artifact('save-core', root + 'save-core')!,
			artifact('atomic-new', root + 'atomic-new')!, artifact('save-protocol', root + 'save-protocol')!, artifact('save-probe', root + 'save-probe')!,
			artifact('serial-log', base + '/packages-deployment-save/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
