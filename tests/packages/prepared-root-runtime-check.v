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
	scenario string = 'packages-prepared-root'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{
		name: 'package-prepared-root'
		guest: 'tests/packages/prepared-root-guest'
		module_paths: ['.', 'tools/accounts']
		programs: [
			hwhost.Program{ source: 'tests/packages/prepared-root-check.v', path: 'usr/share/package-fixtures/prepared-root-check' },
			hwhost.Program{ source: 'tools/packages/pkgcore/prepared_root_test.v', path: 'usr/share/package-fixtures/prepared-root-core' },
		]
		directories: ['tmp:1777']
		scenarios: [hwhost.Scenario{
			name: 'packages-prepared-root'
			arches: ['aarch64', 'x86_64']
			about: 'publisher root admission, captured namespace, descriptor retirement and canonical import retry'
			required: ['HWTEST START packages-prepared-root', 'Prepared root qualification passed',
				'PACKAGE PREPARED ROOT nul-alias-refusal no-output-on-refusal captured-namespace canonical-retry PASS',
				'HWTEST PASS packages-prepared-root']
			ending: .poweroff
			timeout: 120
		}]
	}
}

fn check() !int {
	args := os.args[1..]
	options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-prepared-root-' + os.getpid().str()
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
			artifact('prepared-root-check', root + 'prepared-root-check')!,
			artifact('prepared-root-core', root + 'prepared-root-core')!,
			artifact('serial-log', base + '/packages-prepared-root/serial.log')!,
		] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
