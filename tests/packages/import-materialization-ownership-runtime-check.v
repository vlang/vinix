// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct MaterializationArtifact { role string bytes u64 sha256 string }
struct MaterializationGuestReceipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-import-materialization-ownership' seconds f64 artifacts []MaterializationArtifact }

fn materialization_artifact(role string, path string) !MaterializationArtifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return MaterializationArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn materialization_suite() hwhost.Suite {
	mut required := ['HWTEST START packages-import-materialization-ownership',
				'IMPORT LOOKUP case=ordinary retained=0 allocations=0',
				'IMPORT LOOKUP case=cycle retained=0 allocations=0',
				'IMPORT LOOKUP ordinary/guest-alias/parent/40-link/FIFO paths and late refusals retire scratch and descriptors PASS',
				'IMPORT LOOKUP independent descriptors survive retired source text, path scratch and host namespace replacement PASS',
				'IMPORT LOOKUP source rechecks retire complete and refused identity/size/execute/namespace scratch PASS',
				'IMPORT LOOKUP owned restart paths preserve parent/suffix order and exact 4096-byte boundary before allocation PASS',
				'IMPORT LOOKUP PROCESS import-lookup PASS',
				'IMPORT CAPTURE retained root and guest-absolute aliases survive host namespace replacement with identical retry metadata PASS',
				'IMPORT CAPTURE 49 file identity/size/execute mutations refuse before publication; 32-descriptor cleanup and exact retry PASS',
				'IMPORT CAPTURE multi-block same-size rewrites during hashing and copying fail content comparison before publication PASS',
				'IMPORT CAPTURE directory replacement and added/removed/renamed entries refuse; guest targets survive and retries succeed PASS',
				'IMPORT CAPTURE pinned digest/execute admission, empty files, stripped special modes and canonical declarations survive exact retry PASS',
				'IMPORT CAPTURE nine injected checkpoint failures retire descriptors and private scratch before successful public retry PASS',
				'IMPORT LOOKUP PROCESS import-capture PASS', 'IMPORT LOOKUP PROCESS import-limits PASS',
				'IMPORT LOOKUP PROCESS import PASS', 'IMPORT LOOKUP PROCESS pack-source PASS',
				'IMPORT LOOKUP PROCESS catalog PASS', 'IMPORT LOOKUP PROCESS release PASS',
				'HWTEST PASS packages-import-materialization-ownership']
	for name in ['file', 'empty', 'nested', 'tree', 'alias', 'parent-alias', 'pinned', 'pin-size', 'pin-mode', 'pin-digest', 'cycle', 'special', 'opened', 'directory', 'sized', 'block', 'read', 'hashed', 'copy-block', 'copied', 'create-failure', 'parent-file']! {
		required << 'IMPORT MATERIALIZATION case=' + name + ' retained=0 allocations=0'
		required << 'IMPORT MATERIALIZATION CASE ' + name + ' PASS'
	}
	required << 'IMPORT MATERIALIZATION CASE functional PASS'
	required << 'IMPORT MATERIALIZATION PROCESS materialization PASS'
	required << 'IMPORT MATERIALIZATION multiblock/empty bytes, stripped modes, umask, unchanged parents, empty directories and native creation refusal/retry PASS'

	return hwhost.Suite{ name: 'package-import-materialization-ownership', guest: 'tests/packages/import-materialization-ownership-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/import_lookup_test.v', path: 'usr/share/package-fixtures/import-lookup', flags: ['-d', 'track_heap', '-manualfree'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/import_capture_test.v', path: 'usr/share/package-fixtures/import-capture', flags: ['-manualfree'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/import_limits_test.v', path: 'usr/share/package-fixtures/import-limits', flags: ['-manualfree'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/import_test.v', path: 'usr/share/package-fixtures/import', flags: ['-manualfree'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/pack_source_test.v', path: 'usr/share/package-fixtures/pack-source', flags: ['-manualfree'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/catalog_test.v', path: 'usr/share/package-fixtures/catalog', flags: ['-manualfree'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/release_test.v', path: 'usr/share/package-fixtures/release', flags: ['-manualfree'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/import_materialization_ownership_test.v', path: 'usr/share/package-fixtures/materialization', flags: ['-d', 'track_heap', '-manualfree'] },
		], scenarios: [hwhost.Scenario{ name: 'packages-import-materialization-ownership', arches: ['aarch64', 'x86_64'],
			about: 'owned prepared-root materialization, retained lookups/rechecks, source consistency, bounds, direct packing and signed catalog/releases',
			required: required, forbidden: ['Out of memory', '--import-lookup-baseline', 'V panic:', 'HWTEST FAIL', 'IMPORT LIMITS baseline:'], ending: .poweroff, timeout: 600 }]
	}
}

fn materialization_guest() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(materialization_suite(), os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	definition := materialization_suite()
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-import-materialization-ownership') }
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [materialization_artifact('kernel', work + '/kernel')!, materialization_artifact('guest-init', guest)!]
	for name in ['import-lookup', 'import-capture', 'import-limits', 'import', 'pack-source', 'catalog', 'release', 'materialization']! { artifacts << materialization_artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-import-materialization-ownership', timeout: if options.timeout > 600 { options.timeout } else { 600 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << materialization_artifact('serial-log', work + '/packages-import-materialization-ownership/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(MaterializationGuestReceipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(materialization_guest() or { eprintln(err); 2 }) }
