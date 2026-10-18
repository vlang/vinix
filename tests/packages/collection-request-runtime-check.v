// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import os

fn main() {
	definition := hwhost.Suite{name: 'package-collection-request', guest: 'tests/packages/collection-request-guest', module_paths: ['.', 'tools/accounts'],
		programs: [
			hwhost.Program{source: 'tools/packages/pkgcore/collection_request_test.v', path: 'usr/share/package-fixtures/request', flags: ['-manualfree', '-d', 'track_heap', '-d', 'collection_request_native']},
			hwhost.Program{source: 'tools/packages/pkgcore/collection_retirement_test.v', path: 'usr/share/package-fixtures/retirement', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_collection_retirement_releases_owned_scratch']},
			hwhost.Program{source: 'tools/packages/pkgcore/collection_limit_test.v', path: 'usr/share/package-fixtures/limit', flags: ['-manualfree']},
			hwhost.Program{source: 'tools/packages/pkgcore/service_test.v', path: 'usr/share/package-fixtures/service', flags: ['-manualfree']}],
		directories: ['tmp:1777'], scenarios: [hwhost.Scenario{name: 'packages-collection-request', arches: ['aarch64', 'x86_64'],
			about: 'Owned complete collection calls, protected retained payloads and leases, bounded descriptors and unchanged signed maintenance', ending: .poweroff, timeout: 900,
			required: ['HWTEST START packages-collection-request', 'HWTEST PASS packages-collection-request',
				'COLLECTION REQUEST 48 selected cases with 8 measured calls each PASS',
				'COLLECTION RETIREMENT 128 successful removals and 128 refusals retain zero removal-helper allocations PASS',
				'Package collection: 128 obsolete generations under RLIMIT_NOFILE=32; live lease preserved then retired'],
			forbidden: ['V panic:', 'HWTEST FAIL', 'Out of memory']}]}
	exit(hwhost.run_suite(definition, os.args[1..], @FILE))
}
