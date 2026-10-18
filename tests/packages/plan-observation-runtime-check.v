// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import os

fn main() {
	definition := hwhost.Suite{name: 'package-plan-observation', guest: 'tests/packages/plan-observation-guest', module_paths: ['.', 'tools/accounts'],
		programs: [
			hwhost.Program{source: 'tools/packages/pkgcore/plan_observation_test.v', path: 'usr/share/package-fixtures/plan', flags: ['-manualfree', '-d', 'track_heap']},
			hwhost.Program{source: 'tools/packages/pkgcore/resolve_preference_test.v', path: 'usr/share/package-fixtures/preference', flags: ['-manualfree', '-d', 'track_heap']},
			hwhost.Program{source: 'tools/packages/pkgcore/service_test.v', path: 'usr/share/package-fixtures/service', flags: ['-manualfree']},
			hwhost.Program{source: 'tools/packages/pkgcore/deployment_empty_test.v', path: 'usr/share/package-fixtures/empty', flags: ['-manualfree']}],
		directories: ['tmp:1777'], scenarios: [hwhost.Scenario{name: 'packages-plan-observation', arches: ['aarch64', 'x86_64'],
			about: 'Owned complete public plan previews, nested manifest copies and unchanged borrowed resolver/maintenance semantics', ending: .poweroff, timeout: 900,
			required: ['HWTEST START packages-plan-observation', 'HWTEST PASS packages-plan-observation',
				'PLAN OBSERVATION complete service and explicit previews preserve independent manifests, exact JSON and signed state across 64 calls per case on both declarations PASS',
				'PLAN OBSERVATION 33-package nested copies preserve every field, full-width numbers and independent retirement across 1000 cycles per architecture PASS',
				'Resolver preference: 32768 catalog variants and 4096 installed identities retain one choice each and stable fallback order PASS',
				'Resolver preference: 1000 public successful multi-version installs and missing-requirement refusals retain zero tracked bytes PASS'],
			forbidden: ['V panic:', 'HWTEST FAIL', 'Out of memory']}]}
	exit(hwhost.run_suite(definition, os.args[1..], @FILE))
}
