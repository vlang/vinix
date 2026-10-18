// SPDX-License-Identifier: GPL-2.0-or-later
module main
import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact { role string bytes u64 sha256 string }
struct Receipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-image-owner' seconds f64 artifacts []Artifact }

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite(architecture string) hwhost.Suite {
	mut required := ['HWTEST START packages-image-owner', 'HWTEST PASS packages-image-owner',
		'IMAGE CAPTURE 80 capture/prepared/publication root and parent substitutions preserve replacements, recovery, trust and source; checked retirement and retry under 32 descriptors both targets PASS',
		'IMAGE OWNER PROCESS repositories  PASS', 'IMAGE OWNER PROCESS applications  PASS', 'IMAGE OWNER PROCESS configuration  PASS']
	for mode in ['complete', 'check-only', 'preserve', 'export', 'second-index', 'deny-license', 'staged', 'capture-replaced', 'unsafe-retire', 'flush']! {
		required << 'IMAGE OWNER arch=' + architecture + ' case=' + mode + ' retained=0 allocations=0'
		required << 'IMAGE OWNER PROCESS owner case ' + mode + ' ' + architecture + ' PASS'
		required << 'IMAGE OWNER ' + architecture + ' ' + mode + ' exact declaration retry, trust, sources, recovery and descriptors PASS'
	}
	mut programs := []hwhost.Program{}
	for pair in [['owner', 'image_owner'], ['repositories', 'image_repositories'], ['applications', 'image_applications'], ['configuration', 'image_configuration']] {
		programs << hwhost.Program{ source: 'tools/packages/pkgcore/' + pair[1] + '_test.v', path: 'usr/share/package-fixtures/' + pair[0],
			flags: if pair[0] in ['owner']! { ['-manualfree', '-d', 'track_heap'] } else { ['-manualfree'] } }
	}
	return hwhost.Suite{ name: 'package-image-owner', guest: 'tests/packages/image-owner-guest', module_paths: ['.', 'tools/accounts'],
		directories: ['tmp:1777'], programs: programs, scenarios: [hwhost.Scenario{ name: 'packages-image-owner',
			arches: ['aarch64', 'x86_64'], about: 'Owned offline image inputs and ten selected complete-call modes per target',
			required: required, forbidden: ['Out of memory', 'V panic:', 'HWTEST FAIL'], ending: .poweroff, timeout: 900 }] }
}

fn qualify() !int {
	options := hwhost.parse_options(os.args[1..])!; base := suite(options.arch)
	if options.help || options.list { return hwhost.run_suite(base, os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	definition := base
	repository := hwhost.find_root(@FILE)!; host := hwhost.find_host(repository, options.arch, options.qemu)!
	hwhost.validate_scenarios(definition.scenarios)!; selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-image-owner') }
	os.mkdir_all(options.state_dir)!; work := os.real_path(options.state_dir); os.cp(options.kernel, work + '/kernel')!; hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [artifact('kernel', work + '/kernel')!, artifact('guest-init', guest)!]
	for name in ['owner', 'repositories', 'applications', 'configuration']! { artifacts << artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-image-owner', timeout: if options.timeout > 900 { options.timeout } else { 900 }, keep: true })
	println(hwhost.report(options.arch, outcome)); if outcome.interrupted { return 130 }; if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-image-owner/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(qualify() or { eprintln(err); 2 }) }
