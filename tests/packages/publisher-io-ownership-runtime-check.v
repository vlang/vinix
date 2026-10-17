// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct PublisherIOArtifact { role string bytes u64 sha256 string }
struct PublisherIOGuestReceipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-publisher-io-ownership' seconds f64 artifacts []PublisherIOArtifact }

fn publisher_io_artifact(role string, path string) !PublisherIOArtifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return PublisherIOArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn publisher_io_suite() hwhost.Suite {
	mut required := ["HWTEST START packages-publisher-io-ownership", "HWTEST PASS packages-publisher-io-ownership",
		"PACK OWNERSHIP cold/cache walks, growing inventories and late hash/copy/cache refusals retain zero owned scratch PASS",
		"PACK OWNERSHIP existing-workspace replies and locked/late-walk refusals retain zero owned scratch PASS",
		"PACK OWNERSHIP pack/root replies survive retired inputs and sibling close; ignored template inventory, literal declarations, legacy manifest bytes and saved objects remain intact PASS",
		"PACK OWNERSHIP late validation/publication/cache-directory refusals preserve saved metadata and recovery bytes; exact retry PASS"]
	for count in [16, 64]! { for cold in [false, true]! { for mode in ["complete", "hashed", "copied-or-cached"]! {
		required << "PACK OWNERSHIP walk files=" + count.str() + " cold=" + cold.str() + " mode=" + mode + " retained=0 allocations=0"
	} } }
	for name in ["pack-ownership", "pack-source", "copy", "import-capture", "import", "catalog", "release", "publisher-io", "durability", "publisher-workspace"]! { required << "PUBLISHER IO OWNERSHIP PROCESS " + name + " PASS" }
	for mode in ["capture", "capture-alias", "workspace", "workspace-alias", "workspace-unsafe", "outside", "relative-outside", "contained", "relative-contained", "lock", "busy", "hard-linked", "file", "directory", "file-alias", "directory-alias", "flush-failure"]! {
		required << "PUBLISHER IO OWNERSHIP mode=" + mode + " retained=0 allocations=0"
	}
	for count in [1, 32]! { for mode in ["complete", "locked", "hashed"]! {
		if count == 1 && mode == "hashed" { continue }
		required << "PACK OWNERSHIP full files=" + count.str() + " mode=" + mode + " retained=0 allocations=0"
	} }
	for name in ["writers", "admission", "containment", "entries", "retirement"]! { required << "PUBLISHER IO WORKSPACE CASE " + name + " PASS" }
	return hwhost.Suite{ name: "package-publisher-io-ownership", guest: "tests/packages/publisher-io-ownership-guest", module_paths: [".", "tools/accounts"], directories: ["tmp:1777"], programs: [
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
	], scenarios: [hwhost.Scenario{ name: "packages-publisher-io-ownership", arches: ["aarch64", "x86_64"], about: "owned filesystem admission, locks and durability; zero-retention existing-workspace packing, aliases, recovery and signed releases", required: required,
		forbidden: ["V panic:", "HWTEST FAIL"], ending: .poweroff, timeout: 300 }] }
}

fn publisher_io_guest() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(publisher_io_suite(), os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	definition := publisher_io_suite()
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-publisher-io-ownership') }
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [publisher_io_artifact('kernel', work + '/kernel')!, publisher_io_artifact('guest-init', guest)!]
	for name in ['pack-ownership', 'pack-source', 'copy', 'import-capture', 'import', 'catalog', 'release', 'publisher-io', 'durability', 'publisher-workspace']! { artifacts << publisher_io_artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-publisher-io-ownership', timeout: if options.timeout > 300 { options.timeout } else { 300 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << publisher_io_artifact('serial-log', work + '/packages-publisher-io-ownership/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(PublisherIOGuestReceipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(publisher_io_guest() or { eprintln(err); 2 }) }
