// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import os

fn main() {
	definition := hwhost.Suite{name: 'package-collection-stress', guest: 'tests/packages/collection-stress-guest', module_paths: ['.', 'tools/accounts', 'tests/packages'],
		programs: [
			hwhost.Program{source: 'tools/packages/pkgcore/collection_request_test.v', path: 'usr/share/package-fixtures/request', flags: ['-manualfree', '-d', 'track_heap', '-d', 'collection_request_stress']},
			hwhost.Program{source: 'tools/packages/pkgcore/collection_retirement_test.v', path: 'usr/share/package-fixtures/retirement-0', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_collection_refuses_writable_obsolete_roots_before_any_retirement']},
			hwhost.Program{source: 'tools/packages/pkgcore/collection_retirement_test.v', path: 'usr/share/package-fixtures/retirement-1', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_collection_binds_removal_to_the_captured_generation_parent']},
			hwhost.Program{source: 'tools/packages/pkgcore/collection_retirement_test.v', path: 'usr/share/package-fixtures/retirement-2', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_collection_rechecks_inventory_directories_and_retains_lease_on_failure']},
			hwhost.Program{source: 'tools/packages/pkgcore/collection_retirement_test.v', path: 'usr/share/package-fixtures/retirement-3', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_collection_rechecks_root_and_lease_after_inventory_before_deletion']},
			hwhost.Program{source: 'tools/packages/pkgcore/collection_retirement_test.v', path: 'usr/share/package-fixtures/retirement-4', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_collection_retires_deep_wide_and_repeated_trees_with_bounded_descriptors']},
			hwhost.Program{source: 'tools/packages/pkgcore/collection_retirement_test.v', path: 'usr/share/package-fixtures/retirement-5', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_collection_retirement_releases_owned_scratch']},
			hwhost.Program{source: 'tools/packages/pkgcore/collection_limit_test.v', path: 'usr/share/package-fixtures/limit', flags: ['-manualfree']},
			hwhost.Program{source: 'tools/packages/pkgcore/service_test.v', path: 'usr/share/package-fixtures/service', flags: ['-manualfree']}],
		directories: ['tmp:1777'], scenarios: [hwhost.Scenario{name: 'packages-collection-stress', arches: ['aarch64', 'x86_64'],
			about: 'Full native collection repetition with settled kernel reservations and every retirement control', ending: .poweroff, timeout: 900,
			required: ['HWTEST START packages-collection-stress', 'HWTEST PASS packages-collection-stress',
				'COLLECTION STRESS 48 cases with 64 measured calls after 8 warmups PASS',
				'COLLECTION STRESS all six retirement cases in separate processes PASS',
				'COLLECTION RETIREMENT 128 successful removals and 128 refusals retain zero removal-helper allocations PASS',
				'Package collection: 128 obsolete generations under RLIMIT_NOFILE=32; live lease preserved then retired'],
			forbidden: ['V panic:', 'HWTEST FAIL', 'Out of memory']}]}
	exit(hwhost.run_suite(definition, os.args[1..], @FILE))
}
