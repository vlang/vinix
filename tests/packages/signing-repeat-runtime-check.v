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
	kind string = 'publisher-input'
	scenario string = 'packages-signing-repeat'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{
		name: 'package-signing-repeat'
		guest: 'tests/packages/signing-repeat-guest'
		module_paths: ['.', 'tools/accounts']
		programs: [
			hwhost.Program{ source: 'tools/packages/signing/signing_test.v', path: 'usr/share/package-fixtures/signing-reference' },
			hwhost.Program{ source: 'tools/packages/pkgcore/publisher_workspace_test.v', path: 'usr/share/package-fixtures/publisher-workspace-batch' },
			hwhost.Program{ source: 'tests/packages/signing-repeat-check.v', path: 'usr/share/package-fixtures/signing-repeat' },
		]
		directories: ['tmp:1777']
		scenarios: [hwhost.Scenario{
			name: 'packages-signing-repeat'
			arches: ['aarch64', 'x86_64']
			about: 'reference signatures, batched publisher assertions and 32 publications in one process'
			required: ['HWTEST START packages-signing-repeat',
				'SIGNING PROCESS signing-reference PASS', 'SIGNING PROCESS publisher-workspace-batch PASS',
				'SIGNING REPEAT 16/16 identical publication and verification PASS',
				'PACKAGE SIGNING REPEAT 32 publications one-process canonical-bytes PASS',
				'SIGNING PROCESS signing-repeat PASS', 'HWTEST PASS packages-signing-repeat']
			ending: .poweroff
			timeout: 300
		}]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-signing-repeat-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [
			kernel, artifact('guest-init', base + '/guest/init')!,
			artifact('signing-reference', root + 'signing-reference')!,
			artifact('publisher-workspace-batch', root + 'publisher-workspace-batch')!,
			artifact('signing-repeat', root + 'signing-repeat')!,
			artifact('serial-log', base + '/packages-signing-repeat/serial.log')!,
		] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
