// SPDX-License-Identifier: GPL-2.0-or-later
module main
import hwhost
import os
fn main() {
	definition := hwhost.Suite{name: 'package-https-owner', guest: 'tests/packages/https-owner-guest',
		module_paths: ['.', 'tools/accounts', 'tests/packages'], directories: ['tmp:1777'], programs: [
			hwhost.Program{source: 'tools/packages/pkgcore/https_owner_test.v', path: 'usr/share/package-fixtures/owner', flags: ['-manualfree', '-d', 'track_heap']},
			hwhost.Program{source: 'tools/packages/pkgcore/https_output_test.v', path: 'usr/share/package-fixtures/core', flags: ['-manualfree', '-d', 'track_heap']},
			hwhost.Program{source: 'tests/packages/output-fixture.v', path: 'usr/share/package-fixtures/producer', flags: ['-manualfree']}],
		scenarios: [hwhost.Scenario{name: 'packages-https-owner', arches: ['aarch64', 'x86_64'],
			about: 'Owned complete HTTPS process/pipe/argument paths with bounded fallback and output/recovery controls; TLS is host-qualified',
			ending: .poweroff, timeout: 1200, required: ['HWTEST START packages-https-owner', 'HWTEST PASS packages-https-owner',
				'HTTPS OWNER 57 cases with 64 measured calls preserve bytes, bounded retries, output guards and child/descriptor retirement PASS',
				'HTTPS DIAGNOSTICS 41 exit statuses', 'HTTPS DIAGNOSTICS 1000 cycles', 'HTTPS GUARD 72', 'HTTPS GUARD 96'],
			forbidden: ['HWTEST FAIL', 'V panic:', 'Out of memory']}]}
	exit(hwhost.run_suite(definition, os.args[1..], @FILE))
}
