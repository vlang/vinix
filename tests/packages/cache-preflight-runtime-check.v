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
	kind string = 'cache-preflight'
	scenario string = 'packages-cache-preflight'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-cache-preflight', guest: 'tests/packages/cache-preflight-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/catalog_metadata_test.v', path: 'usr/share/package-fixtures/cache-preflight-core' },
			hwhost.Program{ source: 'tests/packages/cache-preflight-check.v', path: 'usr/share/package-fixtures/cache-preflight-probe' },
			hwhost.Program{ source: 'tools/packages/pkgcore/snapshot_decode_test.v', path: 'usr/share/package-fixtures/snapshot-decode' },
			hwhost.Program{ source: 'tools/packages/pkgcore/snapshot_schema_test.v', path: 'usr/share/package-fixtures/snapshot-schema' },
		], scenarios: [hwhost.Scenario{ name: 'packages-cache-preflight', arches: ['aarch64', 'x86_64'],
			about: 'incremental signed cache admission, early refusal and bounded service retry',
			required: ['HWTEST START packages-cache-preflight',
				'CACHE PREFLIGHT limit-minus-one and exact 8 MiB accepted; closing byte, cumulative prefix and escape expansion overflow refused PASS',
				'CACHE PREFLIGHT signed service/CLI refresh rejects oversized cache before later acquisition/publication and accepts a bounded retry PASS',
				'CACHE PROCESS cache-preflight-core PASS', 'CACHE PROCESS cache-preflight-probe PASS',
				'SNAPSHOT DECODE owned empty/growing/full 4096 records, retired source buffers, escaped keys, opaque Unicode/NUL text and legacy signature bytes preserve canonical output PASS',
				'SNAPSHOT DECODE 1000-cycle partial/schema/UTF8/duplicate refusals retire scratch; 4097 records refuse before admission PASS',
				'SNAPSHOT DECODE exact 8 MiB and limit-minus-one preserve opaque text; limit-plus-one refuses before parsing PASS',
				'SNAPSHOT DECODE 1000 absent/valid/partial/alias/FIFO/parent file reads retire scratch, preserve retained bytes and permit restored retry PASS',
				'CACHE PROCESS snapshot-decode PASS', 'CACHE PROCESS snapshot-schema PASS',
				'HWTEST PASS packages-cache-preflight'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-cache-preflight-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('cache-preflight-core', root + 'cache-preflight-core')!,
			artifact('cache-preflight-probe', root + 'cache-preflight-probe')!,
			artifact('snapshot-decode', root + 'snapshot-decode')!, artifact('snapshot-schema', root + 'snapshot-schema')!,
			artifact('serial-log', base + '/packages-cache-preflight/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
