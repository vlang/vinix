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
	kind string = 'deployment-snapshot'
	scenario string = 'packages-deployment-snapshot'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-deployment-snapshot', guest: 'tests/packages/deployment-snapshot-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/packages/pkgcore/deployment_snapshot_test.v', path: 'usr/share/package-fixtures/snapshot-core' },
			hwhost.Program{ source: 'tests/packages/deployment-snapshot-check.v', path: 'usr/share/package-fixtures/snapshot-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-deployment-snapshot', arches: ['aarch64', 'x86_64'],
			about: 'exact installed metadata snapshots, offline/revoked provenance, ordinary readers and authenticated reproduction',
			required: ['HWTEST START packages-deployment-snapshot',
				'DEPLOYMENT SNAPSHOT exact sorted roots, shared runtime/all-data closure, metadata/provenance/sequence pins, offline revoked policy independence and no mutation on both architectures PASS',
				'DEPLOYMENT SNAPSHOT independently owned closeable documents and invalid/duplicate/missing/excess roots refusal PASS',
				'DEPLOYMENT SNAPSHOT fresh empty read without initialization, writer exclusion and malformed state refusal PASS',
				'DEPLOYMENT SNAPSHOT ordinary UID 1000 reads exact root-owned metadata without administrator authorization PASS',
				'DEPLOYMENT SNAPSHOT CLI preserves withdrawn installed app/runtime/all-data pins offline with revoked policy, refuses missing roots and unauthenticated apply, and reproduces exact versions from newly authenticated media PASS',
				'SNAPSHOT PROCESS snapshot-core PASS', 'SNAPSHOT PROCESS snapshot-probe PASS',
				'HWTEST PASS packages-deployment-snapshot'], ending: .poweroff, timeout: 600 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-deployment-snapshot-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('package-cli', base + '/guest/root/usr/bin/vinix-package')!, artifact('snapshot-core', root + 'snapshot-core')!,
			artifact('snapshot-probe', root + 'snapshot-probe')!,
			artifact('serial-log', base + '/packages-deployment-snapshot/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
