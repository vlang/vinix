// SPDX-License-Identifier: GPL-2.0-or-later
module main
import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact { role string bytes u64 sha256 string }
struct Receipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-apple-owner' seconds f64 artifacts []Artifact }

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	mut required := ['HWTEST START packages-apple-owner', 'HWTEST PASS packages-apple-owner',
		'APPLE METADATA 640 cycles retire decoded templates, partial manifests, canonicalization, replies and late refusals PASS',
		'APPLE METADATA independent replies survive plan and caller retirement and close idempotently PASS',
		'APPLE OWNER PROCESS metadata  PASS', 'APPLE OWNER PROCESS admission  PASS',
		'APPLE ADMISSION 1920 Mach-O and XML/binary plist cycles retire successful and refused admission storage PASS', 'APPLE OWNER PROCESS profile  PASS']
	for mode in ['complete', 'invalid-schema', 'wrong-macho', 'wrong-plist', 'packed-1', 'packed-2', 'import-macho', 'import-plist', 'changed-template', 'flush', 'cleanup', 'root-replaced']! {
		required << 'APPLE OWNER case=' + mode + ' retained=0 allocations=0'
		required << 'APPLE OWNER PROCESS builder case ' + mode + ' PASS'
		required << 'APPLE OWNER ' + mode + ' canonical retry, saved output, source and descriptor preservation PASS'
	}
	mut programs := []hwhost.Program{}
	for pair in [['builder', 'apple_builder_ownership'], ['metadata', 'apple_profile_ownership'], ['admission', 'apple_admission_ownership'], ['profile', 'apple_profile']] {
		programs << hwhost.Program{ source: 'tools/packages/pkgcore/' + pair[1] + '_test.v', path: 'usr/share/package-fixtures/' + pair[0],
			flags: if pair[0] != 'profile' { ['-manualfree', '-d', 'track_heap'] } else { ['-manualfree'] } }
	}
	return hwhost.Suite{ name: 'package-apple-owner', guest: 'tests/packages/apple-owner-guest', module_paths: ['.', 'tools/accounts'],
		directories: ['tmp:1777'], programs: programs, scenarios: [hwhost.Scenario{ name: 'packages-apple-owner',
			arches: ['aarch64', 'x86_64'], about: '640 Apple metadata cycles and selected twelve complete-call cases with captured declarations',
			required: required, forbidden: ['Out of memory', 'V panic:', 'HWTEST FAIL'], ending: .poweroff, timeout: 900 }] }
}

fn qualify() !int {
	options := hwhost.parse_options(os.args[1..])!; base := suite()
	if options.help || options.list { return hwhost.run_suite(base, os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	definition := base
	repository := hwhost.find_root(@FILE)!; host := hwhost.find_host(repository, options.arch, options.qemu)!
	hwhost.validate_scenarios(definition.scenarios)!; selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-apple-owner') }
	os.mkdir_all(options.state_dir)!; work := os.real_path(options.state_dir); os.cp(options.kernel, work + '/kernel')!; hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [artifact('kernel', work + '/kernel')!, artifact('guest-init', guest)!]
	for name in ['builder', 'metadata', 'admission', 'profile']! { artifacts << artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-apple-owner', timeout: if options.timeout > 900 { options.timeout } else { 900 }, keep: true })
	println(hwhost.report(options.arch, outcome)); if outcome.interrupted { return 130 }; if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-apple-owner/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(qualify() or { eprintln(err); 2 }) }
