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
	kind string = 'state-preflight'
	scenario string = 'packages-state-preflight'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-state-preflight', guest: 'tests/packages/state-preflight-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/generation_metadata_test.v', path: 'usr/share/package-fixtures/state-preflight-core' },
			hwhost.Program{ source: 'tests/packages/state-preflight-check.v', path: 'usr/share/package-fixtures/state-preflight-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-state-preflight', arches: ['aarch64', 'x86_64'],
			about: 'generation metadata byte limits before review, acquisition and publication',
			required: ['HWTEST START packages-state-preflight',
				'STATE PREFLIGHT exact metadata byte boundary, reader round-trip and future generation counter width PASS',
				'STATE PREFLIGHT signed service/CLI reviews and transactions reject oversized metadata before cleanup/download/staging; active state, trust and recovery data survive; bounded retry PASS',
				'STATE PROCESS state-preflight-core PASS', 'STATE PROCESS state-preflight-probe PASS',
				'HWTEST PASS packages-state-preflight'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-state-preflight-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('state-preflight-core', root + 'state-preflight-core')!,
			artifact('state-preflight-probe', root + 'state-preflight-probe')!,
			artifact('serial-log', base + '/packages-state-preflight/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
