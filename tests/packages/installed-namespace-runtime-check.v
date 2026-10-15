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
	kind string = 'installed-namespace'
	scenario string = 'packages-installed-namespace'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-installed-namespace', guest: 'tests/packages/installed-namespace-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/installed_namespace_test.v', path: 'usr/share/package-fixtures/installed-namespace-core' },
			hwhost.Program{ source: 'tests/packages/installed-namespace-check.v', path: 'usr/share/package-fixtures/installed-namespace-lifecycle' },
		], scenarios: [hwhost.Scenario{ name: 'packages-installed-namespace', arches: ['aarch64', 'x86_64'],
			about: 'installed package namespace, ordinary launch refusal and signed offline repair',
			required: [
				'HWTEST START packages-installed-namespace',
				'INSTALLED NAMESPACE 24 app/runtime/data extra-entry, alias, mode, hard-link and missing-entry refusals bind exact repair IDs; restored trees pass without mutation PASS',
				'INSTALLED NAMESPACE generation/apps parent aliases refuse all package checks; root guest also checks package/directory/file foreign ownership PASS',
				'INSTALLED NAMESPACE ordinary launch refuses undeclared app/runtime/dependency entries before private-data creation or execution; restored administrator-owned trees verify PASS',
				'INSTALLED NAMESPACE 64-level and 1024-file inventories plus 128 successful/refused checks retire descriptors below 32 PASS',
				'INSTALLED NAMESPACE eight signed app/runtime/data namespace repairs, unchanged payload hashes, stale approvals, offline cache, rollback and uninstall PASS',
				'NAMESPACE PROCESS installed-namespace-core PASS',
				'NAMESPACE PROCESS installed-namespace-lifecycle PASS',
				'HWTEST PASS packages-installed-namespace'], ending: .poweroff, timeout: 600 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-installed-namespace-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('installed-namespace-core', root + 'installed-namespace-core')!,
			artifact('installed-namespace-lifecycle', root + 'installed-namespace-lifecycle')!,
			artifact('serial-log', base + '/packages-installed-namespace/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
