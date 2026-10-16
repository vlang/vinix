// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct ImageInputArtifact { role string bytes u64 sha256 string }
struct ImageInputGuestReceipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-image-input' seconds f64 artifacts []ImageInputArtifact }

fn image_input_artifact(role string, path string) !ImageInputArtifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return ImageInputArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn image_input_suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-image-input', guest: 'tests/packages/image-input-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/stage.v', path: 'usr/share/package-fixtures/stage-check' },
			hwhost.Program{ source: 'tools/packages/pkgcore/image_check_test.v', path: 'usr/share/package-fixtures/image-check' },
			hwhost.Program{ source: 'tools/packages/pkgcore/image_repositories_test.v', path: 'usr/share/package-fixtures/image-repositories' },
			hwhost.Program{ source: 'tools/packages/pkgcore/image_configuration_test.v', path: 'usr/share/package-fixtures/image-configuration' },
			hwhost.Program{ source: 'tools/packages/pkgcore/release_test.v', path: 'usr/share/package-fixtures/release' },
			hwhost.Program{ source: 'tools/packages/pkgcore/catalog_test.v', path: 'usr/share/package-fixtures/catalog' },
		], scenarios: [hwhost.Scenario{ name: 'packages-image-input', arches: ['aarch64', 'x86_64'],
			about: 'compiler-free release-image preflight with authenticated bundles, preserved state and signed maintenance',
			required: ['HWTEST START packages-image-input',
				'IMAGE INPUT CHECK reproducible both-host trust/policy, exact signed digests, architecture/license/firmware counts and deduplicated bytes without image publication PASS',
				'IMAGE INPUT CHECK preserved literal existing configuration and consumer history; no-bundle scope and zero bundle estimate PASS',
				'IMAGE INPUT CHECK capture corruption, unrelated plans, appeared consumer state and replaced roots refuse with unchanged targets; stable capture survives source removal PASS',
				'IMAGE INPUT CHECK CLI flag placement, literal paths, environment/explicit selection and reproducible compiler-free reports; normal staging and invalid-input refusals PASS',
				'IMAGE INPUT CHECK publish/preserve/none decisions, occupied configuration, aliased/special/shared-write/damaged bundles refuse without overwriting destinations PASS',
				'IMAGE INPUT PROCESS image-check PASS', 'IMAGE INPUT PROCESS image-repositories PASS',
				'IMAGE INPUT PROCESS image-configuration PASS', 'IMAGE INPUT PROCESS release PASS', 'IMAGE INPUT PROCESS catalog PASS',
				'HWTEST PASS packages-image-input'], forbidden: ['V panic:', 'HWTEST FAIL'], ending: .poweroff, timeout: 180 }]
	}
}

fn image_input_guest() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(image_input_suite(), os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	definition := image_input_suite()
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-image-input') }
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [image_input_artifact('kernel', work + '/kernel')!, image_input_artifact('guest-init', guest)!]
	for name in ['stage-check', 'image-check', 'image-repositories', 'image-configuration', 'release', 'catalog']! { artifacts << image_input_artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-image-input', timeout: if options.timeout > 180 { options.timeout } else { 180 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << image_input_artifact('serial-log', work + '/packages-image-input/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(ImageInputGuestReceipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(image_input_guest() or { eprintln(err); 2 }) }
