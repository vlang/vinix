// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct CaptureArtifact { role string bytes u64 sha256 string }
struct CaptureGuestReceipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-import-capture' seconds f64 artifacts []CaptureArtifact }

fn capture_artifact(role string, path string) !CaptureArtifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return CaptureArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn capture_suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-import-capture', guest: 'tests/packages/import-capture-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/import_capture_test.v', path: 'usr/share/package-fixtures/import-capture' },
			hwhost.Program{ source: 'tools/packages/pkgcore/import_limits_test.v', path: 'usr/share/package-fixtures/import-limits' },
			hwhost.Program{ source: 'tools/packages/pkgcore/import_test.v', path: 'usr/share/package-fixtures/import' },
			hwhost.Program{ source: 'tools/packages/pkgcore/pack_source_test.v', path: 'usr/share/package-fixtures/pack-source' },
			hwhost.Program{ source: 'tools/packages/pkgcore/catalog_test.v', path: 'usr/share/package-fixtures/catalog' },
			hwhost.Program{ source: 'tools/packages/pkgcore/release_test.v', path: 'usr/share/package-fixtures/release' },
		], scenarios: [hwhost.Scenario{ name: 'packages-import-capture', arches: ['aarch64', 'x86_64'],
			about: 'prepared-root source consistency, bounded imports, direct packing and signed catalog/releases',
			required: ['HWTEST START packages-import-capture',
				'IMPORT CAPTURE retained root and guest-absolute aliases survive host namespace replacement with identical retry metadata PASS',
				'IMPORT CAPTURE 49 file identity/size/execute mutations refuse before publication; 32-descriptor cleanup and exact retry PASS',
				'IMPORT CAPTURE multi-block same-size rewrites during hashing and copying fail content comparison before publication PASS',
				'IMPORT CAPTURE directory replacement and added/removed/renamed entries refuse; guest targets survive and retries succeed PASS',
				'IMPORT CAPTURE pinned digest/execute admission, empty files, stripped special modes and canonical declarations survive exact retry PASS',
				'IMPORT CAPTURE nine injected checkpoint failures retire descriptors and private scratch before successful public retry PASS',
				'IMPORT CAPTURE PROCESS import-capture PASS', 'IMPORT CAPTURE PROCESS import-limits PASS',
				'IMPORT CAPTURE PROCESS import PASS', 'IMPORT CAPTURE PROCESS pack-source PASS',
				'IMPORT CAPTURE PROCESS catalog PASS', 'IMPORT CAPTURE PROCESS release PASS',
				'HWTEST PASS packages-import-capture'], forbidden: ['V panic:', 'HWTEST FAIL', 'IMPORT LIMITS baseline:'], ending: .poweroff, timeout: 180 }]
	}
}

fn capture_guest() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(capture_suite(), os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	definition := capture_suite()
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-import-capture') }
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [capture_artifact('kernel', work + '/kernel')!, capture_artifact('guest-init', guest)!]
	for name in ['import-capture', 'import-limits', 'import', 'pack-source', 'catalog', 'release']! { artifacts << capture_artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-import-capture', timeout: if options.timeout > 180 { options.timeout } else { 180 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << capture_artifact('serial-log', work + '/packages-import-capture/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(CaptureGuestReceipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(capture_guest() or { eprintln(err); 2 }) }
