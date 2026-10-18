// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import os

fn main() {
	definition := hwhost.Suite{name: 'package-refresh-request', guest: 'tests/packages/refresh-request-guest', module_paths: ['.', 'tools/accounts', 'tests/packages'],
		programs: [
			hwhost.Program{source: 'tools/packages/pkgcore/refresh_request_test.v', path: 'usr/share/package-fixtures/request', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_complete_refresh_requests_retire_replies_and_success_refusal_scratch']},
			hwhost.Program{source: 'tools/packages/pkgcore/refresh_request_test.v', path: 'usr/share/package-fixtures/lifetime', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_refresh_replies_outlive_configuration_and_other_replies']},
			hwhost.Program{source: 'tools/packages/pkgcore/refresh_request_test.v', path: 'usr/share/package-fixtures/workspace', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_refresh_workspace_retirement_and_publication_failures']},
			hwhost.Program{source: 'tools/packages/pkgcore/service_test.v', path: 'usr/share/package-fixtures/service', flags: ['-manualfree']},
			hwhost.Program{source: 'tools/packages/pkgcore/copy_output_test.v', path: 'usr/share/package-fixtures/copy', flags: ['-manualfree']}],
		directories: ['tmp:1777'], scenarios: [hwhost.Scenario{name: 'packages-refresh-request', arches: ['aarch64', 'x86_64'],
			about: 'Owned complete refresh requests and independent replies with captured workspace retirement and publication refusals', ending: .poweroff, timeout: 1200,
			required: ['HWTEST START packages-refresh-request', 'HWTEST PASS packages-refresh-request',
				'REFRESH REQUEST 72 cases with 64 measured calls after 8 warmups PASS',
				'REFRESH REQUEST independently owned publisher identities and nested manifests survive configuration and sibling reply retirement PASS',
				'REFRESH WORKSPACE captured stale nested work retires; aliases and writable work preserve metadata and foreign files PASS',
				'REFRESH PUBLICATION trust-history 64 refused calls retained 0 tracked bytes PASS',
				'REFRESH PUBLICATION catalog 64 refused calls retained 0 tracked bytes PASS'],
			forbidden: ['V panic:', 'HWTEST FAIL', 'Out of memory']}]}
	exit(hwhost.run_suite(definition, os.args[1..], @FILE))
}
