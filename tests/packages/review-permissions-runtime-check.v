// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import os

fn main() {
	definition := hwhost.Suite{name: 'package-review-permissions', guest: 'tests/packages/review-permissions-guest', module_paths: ['.', 'tools/accounts'],
		programs: [
			hwhost.Program{source: 'tools/packages/pkgcore/review_test.v', path: 'usr/share/package-fixtures/review', flags: ['-manualfree', '-d', 'track_heap']},
			hwhost.Program{source: 'tools/packages/pkgprotocol/review_permissions_test.v', path: 'usr/share/package-fixtures/protocol', flags: ['-manualfree', '-d', 'track_heap']}],
		directories: ['tmp:1777'], scenarios: [hwhost.Scenario{name: 'packages-review-permissions', arches: ['aarch64', 'x86_64'],
			about: 'Frozen installed/target permission declarations across signed maintenance and bounded legacy/current review decoding', ending: .poweroff, timeout: 300,
			required: ['HWTEST START packages-review-permissions', 'HWTEST PASS packages-review-permissions',
				'REVIEW PERMISSIONS both hosts retain installed declarations across new installs, updates, unchanged dependencies, empty sets, repair, rollback and revoked removal PASS',
				'REVIEW PERMISSIONS 1000 independently owned before/target row creation and retirement cycles retain zero tracked bytes PASS',
				'REVIEW PERMISSIONS both hosts admit complete/legacy/known-empty groups, reject fifteen malformed groups and retire 1000 valid/legacy/refused cycles PASS'],
			forbidden: ['V panic:', 'HWTEST FAIL', 'Out of memory']}]}
	exit(hwhost.run_suite(definition, os.args[1..], @FILE))
}
