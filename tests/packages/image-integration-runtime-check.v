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
	return hwhost.Suite{ name: 'package-image-integration', guest: 'tests/packages/image-integration-guest', module_paths: ['.', 'tools/accounts'],
		programs: [hwhost.Program{ source: 'tools/packages/pkgcore/image_integration_test.v', path: 'usr/share/package-fixtures/image-integration', flags: ['-manualfree'] }],
		directories: ['tmp:1777'], scenarios: [hwhost.Scenario{ name: 'packages-image-integration', arches: ['aarch64', 'x86_64'],
			about: 'Captured license/action bytes, controlled image integration and production-staged tools', ending: .poweroff, timeout: 300,
			required: ['HWTEST START packages-image-integration', 'HWTEST PASS packages-image-integration',
				'IMAGE INTEGRATION 82 source/capture/publication/refusal cases preserve overrides and outside data; stable descriptors PASS',
				'IMAGE INTEGRATION native staged licenses/actions/launcher/registration and empty consumer state PASS',
				'IMAGE INTEGRATION native production-staged package/session/Linux-runner execution PASS'],
			forbidden: ['V panic:', 'HWTEST FAIL', 'Out of memory'] }] }
}

fn qualify() !int {
	options := hwhost.parse_options(os.args[1..])!; definition := suite()
	if options.help || options.list { return hwhost.run_suite(definition, os.args[1..], @FILE) }
	stage := os.getenv('VINIX_IMAGE_INTEGRATION_STAGE')
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir)
		|| os.getenv('VINIX_HWTEST_TCG') != '1' || !os.is_executable(stage) {
		return error('provide VINIX_HWTEST_TCG=1, VINIX_IMAGE_INTEGRATION_STAGE, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!; host := hwhost.find_host(repository, options.arch, options.qemu)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	assert selection.run.len == 1
	os.mkdir_all(options.state_dir)!; work := os.real_path(options.state_dir); os.cp(options.kernel, work + '/kernel')!; hwhost.watch_interrupts()
	// Production mode embeds the expected notices/actions in PID 1. Development
	// embed_file values otherwise try to reopen host source paths in the guest.
	guest := hwhost.build_program_with_flags(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths, ['-prod'])!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	compiler := os.find_abs_path_of_executable(options.arch + '-linux-musl-gcc')!
	hwhost.run_tool([stage, '--arch', options.arch, '--staging', root, '--cc-argv', json2.encode([compiler, '-w', '-fpermissive'])],
		{'V': host.v, 'VFLAGS': '-nocache'}, work + '/stage.log', 600)!
	mut artifacts := [artifact('kernel', work + '/kernel')!, artifact('guest-init', guest)!, artifact('host-stage', stage)!,
		artifact('fixture', root + '/usr/share/package-fixtures/image-integration')!, artifact('stage-log', work + '/stage.log')!, artifact('guest-source', repository + '/tests/packages/image-integration-guest/main.v')!, artifact('controller-source', @FILE)!]
	for path in ['usr/bin/vinix-package', 'usr/sbin/vinix-session', 'usr/libexec/vinix/vinix-linux-runner', 'etc/vinix-packages/config.json', 'usr/share/licenses/vinix-packages/ed25519-MIT.txt', 'usr/share/licenses/vinix-packages/application-sdk-MIT.txt', 'usr/share/vinix/actions/packages-change', 'usr/share/vinix/actions/packages-launch']! {
		artifacts << artifact(path, root + '/' + path)!
	}
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-image-integration', timeout: if options.timeout > 300 { options.timeout } else { 300 }, keep: true })
	println(hwhost.report(options.arch, outcome)); if outcome.interrupted { return 130 }; if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-image-integration/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(qualify() or { eprintln(err); 2 }) }
