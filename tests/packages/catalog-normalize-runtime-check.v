// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct NormalizeArtifact { role string bytes u64 sha256 string }
struct NormalizeGuestReceipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-catalog-normalize' seconds f64 artifacts []NormalizeArtifact }

fn normalize_artifact(role string, path string) !NormalizeArtifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return NormalizeArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn normalize_suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-catalog-normalize', guest: 'tests/packages/catalog-normalize-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/catalog_normalize_test.v', path: 'usr/share/package-fixtures/catalog-normalize' },
			hwhost.Program{ source: 'tools/packages/pkgcore/catalog_test.v', path: 'usr/share/package-fixtures/catalog' },
			hwhost.Program{ source: 'tools/packages/pkgcore/composition_test.v', path: 'usr/share/package-fixtures/composition' },
			hwhost.Program{ source: 'tools/packages/pkgcore/release_test.v', path: 'usr/share/package-fixtures/release' },
		], scenarios: [hwhost.Scenario{ name: 'packages-catalog-normalize', arches: ['aarch64', 'x86_64'],
			about: 'owned catalog normalization, late refusals and unchanged composed signed releases',
			required: ['HWTEST START packages-catalog-normalize',
				'CATALOG NORMALIZE complete and refused single/64-import catalogs retire normalization and dependency-closure scratch PASS',
				'CATALOG NORMALIZE independent owned output survives retired source/results with unchanged canonical declarations and ordering PASS',
				'CATALOG NORMALIZE PROCESS catalog-normalize PASS', 'CATALOG NORMALIZE PROCESS catalog PASS',
				'CATALOG NORMALIZE PROCESS composition PASS', 'CATALOG NORMALIZE PROCESS release PASS',
				'HWTEST PASS packages-catalog-normalize'], forbidden: ['V panic:', 'HWTEST FAIL'], ending: .poweroff, timeout: 300 }]
	}
}

fn normalize_guest() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(normalize_suite(), os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	definition := normalize_suite()
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-catalog-normalize') }
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [normalize_artifact('kernel', work + '/kernel')!, normalize_artifact('guest-init', guest)!]
	for name in ['catalog-normalize', 'catalog', 'composition', 'release']! { artifacts << normalize_artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-catalog-normalize', timeout: if options.timeout > 300 { options.timeout } else { 300 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << normalize_artifact('serial-log', work + '/packages-catalog-normalize/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(NormalizeGuestReceipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(normalize_guest() or { eprintln(err); 2 }) }
