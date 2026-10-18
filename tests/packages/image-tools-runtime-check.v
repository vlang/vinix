// SPDX-License-Identifier: GPL-2.0-or-later
module main
import crypto.sha256
import hwhost
import json2
import os

struct Artifact { role string path string sha256 string }
struct Receipt { format int = 1 architecture string seconds f64 artifacts []Artifact }
fn artifact(role string, path string) !Artifact { return Artifact{ role: role, path: path, sha256: sha256.sum(os.read_bytes(path)!).hex() } }

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-image-tools', guest: 'tests/packages/image-tools-guest', module_paths: ['.', 'tools/accounts'],
		programs: [hwhost.Program{ source: 'tools/packages/pkgcore/image_tools_test.v', path: 'usr/share/package-fixtures/image-tools', flags: ['-manualfree'] }],
		directories: ['tmp:1777'], scenarios: [hwhost.Scenario{ name: 'packages-image-tools', arches: ['aarch64', 'x86_64'],
			about: 'Production-staged static package tools and captured tool-build failure/publication checks', ending: .poweroff, timeout: 300,
			required: ['HWTEST START packages-image-tools', 'HWTEST PASS packages-image-tools',
				'IMAGE TOOLS 58 target/capture/publication/refusal cases preserve prior tools, replacements, unrelated temporaries and recovery; stable descriptors PASS',
				'IMAGE TOOLS native production-staged package/session/Linux-runner execution PASS'],
			forbidden: ['V panic:', 'HWTEST FAIL', 'Out of memory'] }] }
}

fn qualify() !int {
	options := hwhost.parse_options(os.args[1..])!; definition := suite()
	if options.help || options.list { return hwhost.run_suite(definition, os.args[1..], @FILE) }
	stage := os.getenv('VINIX_IMAGE_TOOLS_STAGE')
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir)
		|| os.getenv('VINIX_HWTEST_TCG') != '1' || !os.is_executable(stage) {
		return error('provide VINIX_HWTEST_TCG=1, VINIX_IMAGE_TOOLS_STAGE, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!; host := hwhost.find_host(repository, options.arch, options.qemu)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	assert selection.run.len == 1
	os.mkdir_all(options.state_dir)!; work := os.real_path(options.state_dir); os.cp(options.kernel, work + '/kernel')!; hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	compiler := os.find_abs_path_of_executable(options.arch + '-linux-musl-gcc')!
	hwhost.run_tool([stage, '--arch', options.arch, '--staging', root, '--cc-argv', json2.encode([compiler, '-w', '-fpermissive'])],
		{'V': host.v, 'VFLAGS': '-nocache'}, work + '/stage.log', 600)!
	mut artifacts := [artifact('kernel', work + '/kernel')!, artifact('guest-init', guest)!, artifact('host-stage', stage)!,
		artifact('fixture', root + '/usr/share/package-fixtures/image-tools')!, artifact('stage-log', work + '/stage.log')!]
	for path in ['usr/bin/vinix-package', 'usr/sbin/vinix-session', 'usr/libexec/vinix/vinix-linux-runner', 'etc/vinix-packages/config.json']! {
		artifacts << artifact(path, root + '/' + path)!
	}
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-image-tools', timeout: if options.timeout > 300 { options.timeout } else { 300 }, keep: true })
	println(hwhost.report(options.arch, outcome)); if outcome.interrupted { return 130 }; if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-image-tools/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(qualify() or { eprintln(err); 2 }) }
