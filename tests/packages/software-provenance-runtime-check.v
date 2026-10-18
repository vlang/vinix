// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import os

fn main() {
	definition := hwhost.Suite{ name: 'package-software-provenance', guest: 'tests/packages/software-provenance-guest', module_paths: ['.', 'tools/accounts'],
		programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/view_test.v', path: 'usr/share/package-fixtures/view', flags: ['-manualfree'] },
			hwhost.Program{ source: 'tools/packages/pkgprotocol/view_reader_test.v', path: 'usr/share/package-fixtures/protocol', flags: ['-manualfree'] }],
		directories: ['tmp:1777'], scenarios: [hwhost.Scenario{ name: 'packages-software-provenance', arches: ['aarch64', 'x86_64'],
			about: 'Installed versus displayed publisher, requirements, license, payload flags and runtime facts with native protocol/service regressions', ending: .poweroff, timeout: 300,
			required: ['HWTEST START packages-software-provenance', 'HWTEST PASS packages-software-provenance',
				'SOFTWARE PROVENANCE both hosts retain installed publisher across previews, removal, revocation, activation, restored generations and unavailable catalogs PASS',
				'SOFTWARE PROVENANCE protocol keeps installed and displayed publishers distinct; legacy groups, duplicate/partial/invalid identity and uninstalled rows PASS',
				'SOFTWARE PAYLOAD both hosts keep installed license, proprietary/firmware flags and runtime distinct across previews, policy/trust failures and generation changes PASS',
				'SOFTWARE PAYLOAD protocol preserves installed disclosure; complete/legacy groups, flags, runtime, bounds, duplicates and malformed fields PASS'],
			forbidden: ['V panic:', 'HWTEST FAIL', 'Out of memory'] }] }
	exit(hwhost.run_suite(definition, os.args[1..], @FILE))
}
