// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import os

fn main() {
	definition := hwhost.Suite{name: 'package-review-request', guest: 'tests/packages/review-request-guest', module_paths: ['.', 'tools/accounts'],
		programs: [
			hwhost.Program{source: 'tools/packages/pkgcore/review_request_test.v', path: 'usr/share/package-fixtures/request', flags: ['-manualfree', '-d', 'track_heap']},
			hwhost.Program{source: 'tools/packages/pkgcore/review_construction_test.v', path: 'usr/share/package-fixtures/construction', flags: ['-manualfree', '-d', 'track_heap']},
			hwhost.Program{source: 'tools/packages/pkgcore/review_test.v', path: 'usr/share/package-fixtures/review', flags: ['-manualfree', '-d', 'track_heap']},
			hwhost.Program{source: 'tools/packages/pkgcore/deployment_test.v', path: 'usr/share/package-fixtures/deployment', flags: ['-manualfree']}],
		directories: ['tmp:1777'], scenarios: [hwhost.Scenario{name: 'packages-review-request', arches: ['aarch64', 'x86_64'],
			about: 'Owned review construction, exact fingerprints and signed ordinary/deployment maintenance', ending: .poweroff, timeout: 900,
			required: ['HWTEST START packages-review-request', 'HWTEST PASS packages-review-request',
				'REVIEW REQUEST complete public ordinary/deployment calls retire preparation and preserve signed state across 64 calls per case on both declarations PASS',
				'REVIEW CONSTRUCTION both hosts preserve changed/no-op proposals, reject space/validation/generation failures and retire 128 repeated calls per case PASS',
				'REVIEW CONSTRUCTION ordinary/deployment identities retain exact prior JSON digests, repair domains and 1000 repeated hash retirements PASS',
				'REVIEW CONSTRUCTION independently owned fingerprints, rows and prior declarations survive input retirement on both hosts PASS',
				'REVIEW PERMISSIONS both hosts retain installed declarations across new installs, updates, unchanged dependencies, empty sets, repair, rollback and revoked removal PASS'],
			forbidden: ['V panic:', 'HWTEST FAIL', 'Out of memory']}]}
	exit(hwhost.run_suite(definition, os.args[1..], @FILE))
}
