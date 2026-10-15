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
	kind string = 'collection-retirement'
	scenario string = 'packages-collection-retirement'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-collection-retirement', guest: 'tests/packages/collection-retirement-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/collection_retirement_test.v', path: 'usr/share/package-fixtures/collection-retirement-core' },
			hwhost.Program{ source: 'tools/packages/pkgcore/distribution_test.v', path: 'usr/share/package-fixtures/collection-retirement-lifecycle' },
		], scenarios: [hwhost.Scenario{ name: 'packages-collection-retirement', arches: ['aarch64', 'x86_64'],
			about: 'captured obsolete-generation retirement, retry leases and bounded descriptors',
			required: [
				'HWTEST START packages-collection-retirement',
				'COLLECTION RETIREMENT unsafe root preserves all generations, interrupted stages and cache; restored root retries PASS',
				'COLLECTION RETIREMENT changed parent refuses even with unchanged generation and lease inodes; restored parent retries PASS',
				'COLLECTION RETIREMENT ten changed nested/ancestor directories preserve data and the named lease; restored inventories retry PASS',
				'COLLECTION RETIREMENT ten post-inventory root/lease replacements refuse before deletion; restored identities retry PASS',
				'COLLECTION RETIREMENT 128-generation batch, 64-level tree, 1024 long-name files and 128 success/refusal loops pass below 32 descriptors; live lease protected PASS',
				'COLLECTION PROCESS collection-retirement-core PASS',
				'COLLECTION PROCESS collection-retirement-lifecycle PASS',
				'HWTEST PASS packages-collection-retirement'], ending: .poweroff, timeout: 600 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-collection-retirement-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('collection-retirement-core', root + 'collection-retirement-core')!,
			artifact('collection-retirement-lifecycle', root + 'collection-retirement-lifecycle')!,
			artifact('serial-log', base + '/packages-collection-retirement/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
