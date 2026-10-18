// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import os

fn main() {
	definition := hwhost.Suite{name: 'package-https-diagnostics', guest: 'tests/packages/https-diagnostics-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{source: 'tools/packages/pkgcore/https_output_test.v', path: 'usr/share/package-fixtures/core', flags: ['-manualfree', '-d', 'track_heap']},
			hwhost.Program{source: 'tests/packages/output-fixture.v', path: 'usr/share/package-fixtures/producer', flags: ['-manualfree']}],
		scenarios: [hwhost.Scenario{name: 'packages-https-diagnostics', arches: ['aarch64', 'x86_64'],
			about: 'Actionable HTTPS failure diagnostics with preserved prefixes, bounded retries and captured-output regressions',
			ending: .poweroff, timeout: 300, required: ['HWTEST START packages-https-diagnostics', 'HWTEST PASS packages-https-diagnostics',
				'HTTPS DIAGNOSTICS 41 exit statuses and terminated transport give actionable errors, preserve fresh/resumed prefixes, retry only range refusal and reap children PASS',
				'HTTPS DIAGNOSTICS 1000 cycles across 43 statuses retire owned messages and errors with zero tracked bytes PASS',
				'HTTPS GUARD 72 fresh/resumed checkpoint and progress mutations stop before further writes; replacements survive and restored output retries PASS',
				'HTTPS GUARD 96 fresh/resumed flush interruption, storage failure and link-change cycles preserve partials and retire children/descriptors under a 32-descriptor limit PASS'],
			forbidden: ['HWTEST FAIL', 'V panic:', 'Out of memory']}]}
	exit(hwhost.run_suite(definition, os.args[1..], @FILE))
}
