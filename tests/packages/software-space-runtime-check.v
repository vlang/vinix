// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import os

fn main() {
	definition := hwhost.Suite{name: 'package-software-space', guest: 'tests/packages/software-space-guest', module_paths: ['.', 'tools/accounts'],
		programs: [
			hwhost.Program{source: 'tools/packages/pkgcore/rollback_test.v', path: 'usr/share/package-fixtures/rollback', flags: ['-manualfree']},
			hwhost.Program{source: 'tools/packages/pkgprotocol/space_test.v', path: 'usr/share/package-fixtures/protocol', flags: ['-manualfree']}],
		directories: ['tmp:1777'], scenarios: [hwhost.Scenario{name: 'packages-software-space', arches: ['aarch64', 'x86_64'],
			about: 'Overflow-safe review budgets, exact reserve boundaries and transactional rollback disk refusal/recovery', ending: .poweroff, timeout: 300,
			required: ['HWTEST START packages-software-space', 'HWTEST PASS packages-software-space',
				'SOFTWARE SPACE 125 counter combinations and exact/one-byte-short boundaries preserve reserve without overflow PASS',
				'SOFTWARE SPACE ordinary no-op reserve exemptions, mirror destination enforcement, shared-disk accounting and separate warm/cold caches PASS',
				'ROLLBACK TRANSACTION exact retained-source disk estimate and reserve refusal preserve activation, rollback and interrupted work PASS',
				'ROLLBACK TRANSACTION interrupted staging and damaged published copy preserve current; reviewed retry uses retained source without acquisition PASS'],
			forbidden: ['V panic:', 'HWTEST FAIL', 'Out of memory']}]}
	exit(hwhost.run_suite(definition, os.args[1..], @FILE))
}
