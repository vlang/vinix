// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct ImageExportArtifact { role string bytes u64 sha256 string }
struct ImageExportGuestReceipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-image-export' seconds f64 artifacts []ImageExportArtifact }

fn image_export_artifact(role string, path string) !ImageExportArtifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return ImageExportArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn image_export_suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-image-export', guest: 'tests/packages/image-export-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/stage.v', path: 'usr/share/package-fixtures/stage-check' },
			hwhost.Program{ source: 'tools/packages/pkgcore/image_applications_test.v', path: 'usr/share/package-fixtures/image-export' },
			hwhost.Program{ source: 'tools/packages/pkgcore/image_check_test.v', path: 'usr/share/package-fixtures/image-check' },
			hwhost.Program{ source: 'tools/packages/pkgcore/image_repositories_test.v', path: 'usr/share/package-fixtures/image-repositories' },
			hwhost.Program{ source: 'tools/packages/pkgcore/image_configuration_test.v', path: 'usr/share/package-fixtures/image-configuration' },
			hwhost.Program{ source: 'tools/packages/pkgcore/release_test.v', path: 'usr/share/package-fixtures/release' },
			hwhost.Program{ source: 'tools/packages/pkgcore/catalog_test.v', path: 'usr/share/package-fixtures/catalog' },
			hwhost.Program{ source: 'tools/packages/pkgcore/deployment_test.v', path: 'usr/share/package-fixtures/deployment' },
			hwhost.Program{ source: 'tools/packages/pkgcore/resolve_search_test.v', path: 'usr/share/package-fixtures/resolve' },
			hwhost.Program{ source: 'tools/packages/pkgcore/atomic_new_test.v', path: 'usr/share/package-fixtures/atomic-new' },
		], scenarios: [hwhost.Scenario{ name: 'packages-image-export', arches: ['aarch64', 'x86_64'],
			about: 'explicit canonical image deployment export: namespace/new-file protection, failure cleanup and ordinary reviewed offline installation',
			required: ['HWTEST START packages-image-export',
				'IMAGE DEPLOYMENT EXPORT both-host exact canonical format-2 locks, inline/file parity, independent source/result digests, exclusive atomic publication and independent receipts PASS',
				'IMAGE DEPLOYMENT EXPORT existing file/link/FIFO/directory/hardlink outputs, direct/aliased image namespaces, unsafe parents, invalid paths and invalid app sets refuse unchanged PASS',
				'IMAGE DEPLOYMENT EXPORT write/space/checkpoint/flush failures and destination races retire temporary files, report saved outputs accurately and permit safe retry without image writes PASS',
				'IMAGE DEPLOYMENT EXPORT real CLI both-host inline/file exports, option placement, compiler bypass, existing-file protection and required context preserve target images PASS',
				'NEW METADATA existing file/alias/dangling/FIFO/directory/hardlink destinations refuse without replacement or blocking PASS',
				'NEW METADATA checkpoint/write/space/flush failures, destination races, mode/parent/final substitutions, cleanup and saved-file retry refusal PASS',
				'NEW METADATA concurrent publishers admit exactly one complete file with canonical final mode and no temporary leftovers PASS',
				'IMAGE REQUIREMENTS FILE exact-byte digests, canonical both-host joint locks, inline parity, whitespace/order provenance and independent reports without publication PASS',
				'IMAGE REQUIREMENTS FILE format-2 pin downgrades, schema/host/empty/invalid/oversized/conflicting sets and missing/aliased/special/oversized files refuse unchanged; restore/retry PASS',
				'IMAGE REQUIREMENTS FILE CLI both-host inherited/explicit selection, inline override, mutual exclusion and normal/check compiler gates preserve unchanged images PASS',
				'IMAGE APPLICATIONS reproducible both-host joint locks, signed provenance, runtime/shared closure, app-kind selection and independent reports PASS',
				'IMAGE APPLICATIONS individually valid conflicting runtimes, missing/wrong-host/nonapp roots, duplicate/invalid/oversized sets and absent bundles refuse without publication; retry PASS',
				'IMAGE APPLICATIONS organization permissions/allowlist/pins and captured payload integrity remain mandatory before app resolution; restoration/retry PASS',
				'IMAGE APPLICATIONS exported format-2 locks drive ordinary reviewed offline install and integrity verification for both hosts; staged trust and consumer state remain separate PASS',
				'IMAGE APPLICATIONS real CLI repeated/position-independent app requirements, canonical compiler-free reports and normal/check refusal before compiler lookup PASS',
				'IMAGE INPUT CHECK reproducible both-host trust/policy, exact signed digests, architecture/license/firmware counts and deduplicated bytes without image publication PASS',
				'IMAGE INPUT CHECK preserved literal existing configuration and consumer history; no-bundle scope and zero bundle estimate PASS',
				'IMAGE INPUT CHECK capture corruption, unrelated plans, appeared consumer state and replaced roots refuse with unchanged targets; stable capture survives source removal PASS',
				'IMAGE INPUT CHECK CLI flag placement, literal paths, environment/explicit selection and reproducible compiler-free reports; normal staging and invalid-input refusals PASS',
				'IMAGE INPUT CHECK publish/preserve/none decisions, occupied configuration, aliased/special/shared-write/damaged bundles refuse without overwriting destinations PASS',
				'IMAGE EXPORT PROCESS atomic-new PASS', 'IMAGE EXPORT PROCESS image-export PASS', 'IMAGE EXPORT PROCESS deployment PASS', 'IMAGE EXPORT PROCESS resolve PASS', 'IMAGE EXPORT PROCESS image-check PASS', 'IMAGE EXPORT PROCESS image-repositories PASS',
				'IMAGE EXPORT PROCESS image-configuration PASS', 'IMAGE EXPORT PROCESS release PASS', 'IMAGE EXPORT PROCESS catalog PASS',
				'HWTEST PASS packages-image-export'], forbidden: ['V panic:', 'HWTEST FAIL'], ending: .poweroff, timeout: 180 }]
	}
}

fn image_export_guest() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(image_export_suite(), os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	definition := image_export_suite()
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-image-export') }
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [image_export_artifact('kernel', work + '/kernel')!, image_export_artifact('guest-init', guest)!]
	for name in ['stage-check', 'image-export', 'image-check', 'image-repositories', 'image-configuration', 'release', 'catalog', 'deployment', 'resolve', 'atomic-new']! { artifacts << image_export_artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-image-export', timeout: if options.timeout > 180 { options.timeout } else { 180 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << image_export_artifact('serial-log', work + '/packages-image-export/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(ImageExportGuestReceipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(image_export_guest() or { eprintln(err); 2 }) }
