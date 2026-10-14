// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct StoredArtifact { role string bytes u64 sha256 string }
struct StoredReceipt { format int = 1 architecture string completed_at i64 seconds f64 artifacts []StoredArtifact }

fn stored_artifact(role string, path string) !StoredArtifact {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return StoredArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn stored_suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-stored-state', guest: 'tests/accounts/guest',
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring'],
		programs: [hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' }],
		directories: ['run', 'home', 'var/log', 'tmp:1777'],
		scenarios: [hwhost.Scenario{ name: 'packages-state-schema', arches: ['aarch64', 'x86_64'],
			about: 'complete stored manifests, maintenance refusal without mutation and restored-state recovery', timeout: 240, ending: .poweroff,
			required: ['HWTEST START packages-state-schema',
				'PACKAGE STORED STATE active-previous missing-disclosures null-permissions coerced-sdk CLI-refusal no-mutation PASS',
				'PACKAGE STORED STATE restored reviewed-removal rollback collection offline-reinstall PASS',
				'HWTEST PASS packages-state-schema'], forbidden: ['V panic:'] }] }
}

fn check() !int {
	options := hwhost.parse_options(os.args[1..])!
	definition := stored_suite()
	if options.help || options.list { return hwhost.run_suite(definition, os.args[1..], @FILE) }
	if os.getenv('VINIX_HWTEST_TCG') != '1' || !os.is_file(options.kernel) || options.state_dir == ''
		|| os.exists(options.state_dir) || os.is_link(options.state_dir) {
		return error('provide VINIX_HWTEST_TCG=1, a target --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-state-schema') }
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [stored_artifact('kernel', work + '/kernel')!, stored_artifact('guest-init', guest)!,
		stored_artifact('package-service', root + '/usr/bin/vinix-package')!]
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-state-schema', timeout: if options.timeout > 240 { options.timeout } else { 240 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	for role, path in {'serial-log': 'serial.log', 'qmp-log': 'qmp.log'} {
		artifacts << stored_artifact(role, work + '/packages-state-schema/' + path)!
	}
	os.write_file(work + '/qualification.json', json2.encode(StoredReceipt{ architecture: options.arch, completed_at: time.now().unix(),
		seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check() or { eprintln(err); 2 }) }
