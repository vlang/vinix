// SPDX-License-Identifier: GPL-2.0-or-later
module main
import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact { role string bytes u64 sha256 string }
struct Receipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-catalog-builder' seconds f64 artifacts []Artifact }

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	mut required := ['HWTEST START packages-catalog-builder', 'HWTEST PASS packages-catalog-builder',
		'CATALOG PLAN owned metadata/budget planning and schema/architecture/depth/closure/object-length refusals PASS',
		'PUBLISHER FLUSH 192 recursive success and ordinary/nested durability refusal cycles retire names, paths and errors PASS',
		'CATALOG BUILDER PROCESS plan  PASS', 'CATALOG BUILDER PROCESS flush  PASS', 'CATALOG BUILDER PROCESS catalog  PASS']
	for mode in ['complete', 'unresolved', 'alias-source', 'packed-3', 'packed-5', 'import-missing', 'manifest-mutated', 'object-mutated', 'flush', 'root-replaced-refused']! {
		required << 'CATALOG BUILDER case=' + mode + ' retained=0 allocations=0'
		required << 'CATALOG BUILDER PROCESS builder case ' + mode + ' PASS'
		required << 'CATALOG BUILDER ' + mode + ' canonical retry, deduplication, saved output, sources and descriptors PASS'
	}
	mut programs := []hwhost.Program{}
	for pair in [['builder', 'catalog_builder_ownership'], ['flush', 'publisher_flush_ownership'], ['catalog', 'catalog'], ['plan', 'catalog_plan']] {
		programs << hwhost.Program{ source: 'tools/packages/pkgcore/' + pair[1] + '_test.v', path: 'usr/share/package-fixtures/' + pair[0],
			flags: if pair[0] in ['builder', 'flush']! { ['-manualfree', '-d', 'track_heap'] } else { ['-manualfree'] } }
	}
	return hwhost.Suite{ name: 'package-catalog-builder', guest: 'tests/packages/catalog-builder-guest', module_paths: ['.', 'tools/accounts'],
		directories: ['tmp:1777'], programs: programs, scenarios: [hwhost.Scenario{ name: 'packages-catalog-builder',
			arches: ['aarch64', 'x86_64'], about: 'Owned recursive flushing, catalog plan/lifecycle regressions and ten selected complete-call cases',
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
	if selection.run.len != 1 { return error('select packages-catalog-builder') }
	os.mkdir_all(options.state_dir)!; work := os.real_path(options.state_dir); os.cp(options.kernel, work + '/kernel')!; hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [artifact('kernel', work + '/kernel')!, artifact('guest-init', guest)!]
	for name in ['builder', 'flush', 'catalog', 'plan']! { artifacts << artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-catalog-builder', timeout: if options.timeout > 900 { options.timeout } else { 900 }, keep: true })
	println(hwhost.report(options.arch, outcome)); if outcome.interrupted { return 130 }; if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-catalog-builder/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(qualify() or { eprintln(err); 2 }) }
