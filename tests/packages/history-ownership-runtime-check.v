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
	kind string = 'history-ownership'
	scenario string = 'packages-history-ownership'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-history-ownership', guest: 'tests/packages/history-ownership-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/history_ownership_test.v', path: 'usr/share/package-fixtures/history-ownership-core' },
			hwhost.Program{ source: 'tests/packages/cache-preflight-check.v', path: 'usr/share/package-fixtures/history-ownership-probe' },
			hwhost.Program{ source: 'tools/packages/pkgcore/history_decode_test.v', path: 'usr/share/package-fixtures/history-decode' },
			hwhost.Program{ source: 'tools/packages/pkgcore/history_schema_test.v', path: 'usr/share/package-fixtures/history-schema' },
		], scenarios: [hwhost.Scenario{ name: 'packages-history-ownership', arches: ['aarch64', 'x86_64'],
			about: 'independent replay history ownership, lifetime bounds and signed maintenance',
			required: ['HWTEST START packages-history-ownership',
				'HISTORY OWNERSHIP migrated expired snapshots produce independent replay records and survive input retirement PASS',
				'CACHE PREFLIGHT signed service/CLI refresh rejects oversized cache before later acquisition/publication and accepts a bounded retry PASS',
				'HISTORY PROCESS history-ownership-core PASS', 'HISTORY PROCESS history-ownership-probe PASS',
				'HISTORY DECODE owned empty/growing/full 4096 identities, distinct keys per ID, u64 maximum, escaped keys and exact canonical writer bytes PASS',
				'HISTORY DECODE 1000-cycle partial/schema/numeric/UTF8/duplicate refusals and 4097-record/8-MiB bounds retire all owned scratch PASS',
				'HISTORY DECODE 1000 absent/valid/partial/alias/FIFO consumer and publisher reads retire scratch, preserve retained bytes and permit restored retry PASS',
				'HISTORY PROCESS history-decode PASS', 'HISTORY PROCESS history-schema PASS',
				'HWTEST PASS packages-history-ownership'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-history-ownership-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('history-ownership-core', root + 'history-ownership-core')!,
			artifact('history-ownership-probe', root + 'history-ownership-probe')!,
			artifact('history-decode', root + 'history-decode')!, artifact('history-schema', root + 'history-schema')!,
			artifact('serial-log', base + '/packages-history-ownership/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
