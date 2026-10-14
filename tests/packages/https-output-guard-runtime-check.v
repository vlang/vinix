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
	kind string = 'https-output-guard'
	scenario string = 'packages-https-output-guard'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-https-output-guard', guest: 'tests/packages/https-output-guard-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/https_output_test.v', path: 'usr/share/package-fixtures/https-output-guard-core' },
			hwhost.Program{ source: 'tests/packages/output-fixture.v', path: 'usr/share/package-fixtures/https-output-producer' },
		], scenarios: [hwhost.Scenario{ name: 'packages-https-output-guard', arches: ['aarch64', 'x86_64'],
			about: 'captured HTTPS output refuses callback mutations and retries restored partials',
			required: ['HWTEST START packages-https-output-guard',
				'HTTPS GUARD 72 fresh/resumed checkpoint and progress mutations stop before further writes; replacements survive and restored output retries PASS',
				'HTTPS GUARD 96 fresh/resumed flush interruption, storage failure and link-change cycles preserve partials and retire children/descriptors under a 32-descriptor limit PASS',
				'HTTPS OUTPUT GUARD process PASS',
				'HWTEST PASS packages-https-output-guard'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-https-output-guard-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('https-output-guard-core', root + 'https-output-guard-core')!,
			artifact('https-output-producer', root + 'https-output-producer')!,
			artifact('serial-log', base + '/packages-https-output-guard/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
