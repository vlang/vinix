// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct WorkspaceCreationArtifact { role string bytes u64 sha256 string }
struct WorkspaceCreationGuestReceipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-workspace-creation-ownership' seconds f64 artifacts []WorkspaceCreationArtifact }

fn workspace_creation_artifact(role string, path string) !WorkspaceCreationArtifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return WorkspaceCreationArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn workspace_creation_suite() hwhost.Suite {
	mut required := ["HWTEST START packages-workspace-creation-ownership", "HWTEST PASS packages-workspace-creation-ownership",
		"PACK OWNERSHIP cold/cache walks, growing inventories and late hash/copy/cache refusals retain zero owned scratch PASS",
		"PACK OWNERSHIP existing-workspace replies and locked/late-walk refusals retain zero owned scratch PASS",
		"PACK OWNERSHIP pack/root replies survive retired inputs and sibling close; ignored template inventory, literal declarations, legacy manifest bytes and saved objects remain intact PASS",
		"PACK OWNERSHIP late validation/publication/cache-directory refusals preserve saved metadata and recovery bytes; exact retry PASS"]
	for count in [16, 64]! { for cold in [false, true]! { for mode in ["complete", "hashed", "copied-or-cached"]! {
		required << "PACK OWNERSHIP walk files=" + count.str() + " cold=" + cold.str() + " mode=" + mode + " retained=0 allocations=0"
	} } }
	for name in ["pack-ownership", "pack-source", "copy", "import-capture", "import", "catalog", "release", "publisher-io", "durability", "publisher-workspace", "creation", "distribution", "coordination", "service", "export-stage"]! { required << "WORKSPACE CREATION PROCESS " + name + " PASS" }
	for mode in ["capture", "capture-alias", "workspace", "workspace-alias", "workspace-unsafe", "outside", "relative-outside", "contained", "relative-contained", "lock", "busy", "hard-linked", "file", "directory", "file-alias", "directory-alias", "flush-failure"]! {
		required << "PUBLISHER IO OWNERSHIP mode=" + mode + " retained=0 allocations=0"
	}
	for count in [1, 32]! { for mode in ["complete", "locked", "hashed"]! {
		if count == 1 && mode == "hashed" { continue }
		required << "PACK OWNERSHIP full files=" + count.str() + " mode=" + mode + " retained=0 allocations=0"
	} }
	for name in ["writers", "admission", "containment", "entries", "retirement"]! { required << "PUBLISHER IO WORKSPACE CASE " + name + " PASS" }
	for deep in [false, true]! {
		for mode in ["export", "workspace", "owned"]! {
			required << "WORKSPACE CREATION mode=" + mode + " deep=" + deep.str() + " retained=0 allocations=0"
			required << "WORKSPACE CREATION CASE component-" + mode + "-" + deep.str() + " PASS"
		}
		for count in [1, 32]! { for mode in ["complete", "locked", "hashed", "copied"]! {
			if count == 1 && mode in ["hashed", "copied"]! { continue }
			required << "WORKSPACE CREATION pack files=" + count.str() + " deep=" + deep.str() + " mode=" + mode + " retained=0 allocations=0"
			required << "WORKSPACE CREATION CASE pack-" + count.str() + "-" + deep.str() + "-" + mode + " PASS"
		} }
	}
	for mode in ["existing", "alias", "unsafe", "file-parent", "create-failure"]! {
		required << "WORKSPACE CREATION refusal=" + mode + " retained=0 allocations=0"
		required << "WORKSPACE CREATION CASE refusal-" + mode + " PASS"
	}
	required << "WORKSPACE CREATION CASE paths PASS"
	required << "WORKSPACE CREATION parent aliases and dotdot, trailing separators, umask, existing modes, invalid paths and retained partial-parent retry PASS"
	return hwhost.Suite{ name: "package-workspace-creation-ownership", guest: "tests/packages/workspace-creation-ownership-guest", module_paths: [".", "tools/accounts"], directories: ["tmp:1777"], programs: [
		hwhost.Program{ source: "tools/packages/pkgcore/pack_ownership_test.v", path: "usr/share/package-fixtures/pack-ownership", flags: ["-d", "track_heap", "-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/pack_source_test.v", path: "usr/share/package-fixtures/pack-source", flags: ["-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/copy_test.v", path: "usr/share/package-fixtures/copy", flags: ["-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/import_capture_test.v", path: "usr/share/package-fixtures/import-capture", flags: ["-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/import_test.v", path: "usr/share/package-fixtures/import", flags: ["-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/catalog_test.v", path: "usr/share/package-fixtures/catalog", flags: ["-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/release_test.v", path: "usr/share/package-fixtures/release", flags: ["-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/publisher_io_ownership_test.v", path: "usr/share/package-fixtures/publisher-io", flags: ["-d", "track_heap", "-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/durability_test.v", path: "usr/share/package-fixtures/durability", flags: ["-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/publisher_workspace_test.v", path: "usr/share/package-fixtures/publisher-workspace", flags: ["-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/workspace_creation_ownership_test.v", path: "usr/share/package-fixtures/creation", flags: ["-d", "track_heap", "-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/distribution_test.v", path: "usr/share/package-fixtures/distribution", flags: ["-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/coordination_test.v", path: "usr/share/package-fixtures/coordination", flags: ["-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/service_test.v", path: "usr/share/package-fixtures/service", flags: ["-manualfree"] },
		hwhost.Program{ source: "tools/packages/pkgcore/export_stage_test.v", path: "usr/share/package-fixtures/export-stage", flags: ["-manualfree"] },
	], scenarios: [hwhost.Scenario{ name: "packages-workspace-creation-ownership", arches: ["aarch64", "x86_64"], about: "owned first workspace/parent construction and cold packing, alias/mode/error recovery, signed maintenance and consumer coordination", required: required,
		forbidden: ["V panic:", "HWTEST FAIL"], ending: .poweroff, timeout: 600 }] }
}

fn workspace_creation_guest() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(workspace_creation_suite(), os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	definition := workspace_creation_suite()
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-workspace-creation-ownership') }
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [workspace_creation_artifact('kernel', work + '/kernel')!, workspace_creation_artifact('guest-init', guest)!]
	for name in ['pack-ownership', 'pack-source', 'copy', 'import-capture', 'import', 'catalog', 'release', 'publisher-io', 'durability', 'publisher-workspace', 'creation', 'distribution', 'coordination', 'service', 'export-stage']! { artifacts << workspace_creation_artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-workspace-creation-ownership', timeout: if options.timeout > 600 { options.timeout } else { 600 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << workspace_creation_artifact('serial-log', work + '/packages-workspace-creation-ownership/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(WorkspaceCreationGuestReceipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(workspace_creation_guest() or { eprintln(err); 2 }) }
