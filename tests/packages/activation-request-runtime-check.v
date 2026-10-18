// SPDX-License-Identifier: GPL-2.0-or-later
module main
import hwhost
import os
fn main() {
	definition := hwhost.Suite{name: 'package-activation-request', guest: 'tests/packages/activation-request-guest', module_paths: ['.', 'tools/accounts', 'tests/packages'],
		programs: [
			hwhost.Program{source: 'tools/packages/pkgcore/activation_request_test.v', path: 'usr/share/package-fixtures/request', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_complete_activation_requests_retire_success_refusal_and_owned_replies']},
			hwhost.Program{source: 'tools/packages/pkgcore/activation_request_test.v', path: 'usr/share/package-fixtures/lifetime', flags: ['-manualfree', '-d', 'track_heap', '-run-only', 'test_activation_replies_outlive_configuration_and_sibling_replies']},
			hwhost.Program{source: 'tools/packages/pkgcore/service_test.v', path: 'usr/share/package-fixtures/service', flags: ['-manualfree']},
			hwhost.Program{source: 'tools/packages/pkgcore/rollback_test.v', path: 'usr/share/package-fixtures/rollback', flags: ['-manualfree']},
			hwhost.Program{source: 'tools/packages/pkgcore/deployment_empty_test.v', path: 'usr/share/package-fixtures/empty', flags: ['-manualfree']},
			hwhost.Program{source: 'tools/packages/pkgcore/generation_admission_test.v', path: 'usr/share/package-fixtures/admission', flags: ['-manualfree']}],
		directories: ['tmp:1777'], scenarios: [hwhost.Scenario{name: 'packages-activation-request', arches: ['aarch64', 'x86_64'],
			about: 'Owned complete activation, rollback and deployment requests with independent replies and preserved refusal/recovery behavior', ending: .poweroff, timeout: 1800,
			required: ['HWTEST START packages-activation-request', 'HWTEST PASS packages-activation-request',
				'ACTIVATION REQUEST 92 cases with 64 measured calls after 2 warmups PASS',
				'ACTIVATION REQUEST independent nested replies survive configuration, sibling and fixture retirement PASS'],
			forbidden: ['V panic:', 'HWTEST FAIL', 'Out of memory']}]}
	exit(hwhost.run_suite(definition, os.args[1..], @FILE))
}
