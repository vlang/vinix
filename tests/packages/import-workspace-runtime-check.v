// SPDX-License-Identifier: GPL-2.0-or-later
module main
import crypto.sha256
import hwhost
import json2
import os
import time

struct WorkspaceArtifact { role string bytes u64 sha256 string }
struct WorkspaceGuestReceipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-import-workspace' seconds f64 artifacts []WorkspaceArtifact }

fn workspace_artifact(role string, path string) !WorkspaceArtifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return WorkspaceArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn workspace_suite() hwhost.Suite {
	mut required := ['HWTEST START packages-import-workspace', 'HWTEST PASS packages-import-workspace',
		'IMPORT WORKSPACE complete cold/pinned imports and early/late/publisher refusals retire storage and descriptors; exact canonical retry PASS',
		'IMPORT WORKSPACE CAPTURE 16 public root/payload/manifest/content/unexpected-entry refusals preserve source, publication timing and canonical retry PASS',
		'IMPORT WORKSPACE CAPTURE creation refusal closes both captured descriptors, retires scratch and identifies retained unadmitted data PASS',
		'IMPORT CAPTURE 49 file identity/size/execute mutations refuse before publication; 32-descriptor cleanup and exact retry PASS',
		'IMPORT LIMITS exact 128-level directory/file boundary and nested selector parents match final pack rules PASS']
	for name in ['complete', 'pinned', 'opened', 'directory', 'copied', 'publisher-file', 'object-directory', 'manifest-directory']! {
		required << 'IMPORT WORKSPACE case=' + name + ' retained=0 allocations=0'
		required << 'IMPORT WORKSPACE PROCESS workspace case ' + name + ' PASS'
	}
	for name in ['ordinary', 'root-directory', 'root-alias', 'root-mode', 'payload-directory', 'payload-alias', 'manifest-directory', 'manifest-file', 'manifest-alias', 'manifest-fifo', 'manifest-content', 'unexpected-directory', 'renamed-parent', 'creation-refusal']! {
		required << 'IMPORT WORKSPACE CAPTURE case=' + name + ' retained=0 allocations=0'
		required << 'IMPORT WORKSPACE PROCESS capture case ' + name + ' PASS'
	}
	required << 'IMPORT WORKSPACE PROCESS capture case public PASS'
	for name in ['import-capture', 'import-limits', 'pack-source', 'native-profile']! { required << 'IMPORT WORKSPACE PROCESS ' + name + '  PASS' }
	mut programs := []hwhost.Program{}
	for pair in [['import-capture', 'import_capture'], ['import-limits', 'import_limits'], ['pack-source', 'pack_source'], ['native-profile', 'native_profile'], ['workspace', 'import_workspace_ownership'], ['capture', 'import_workspace_capture']] {
		programs << hwhost.Program{ source: 'tools/packages/pkgcore/' + pair[1] + '_test.v', path: 'usr/share/package-fixtures/' + pair[0],
			flags: if pair[0] in ['workspace', 'capture']! { ['-manualfree', '-d', 'track_heap'] } else { ['-manualfree'] } }
	}
	return hwhost.Suite{ name: 'package-import-workspace', guest: 'tests/packages/import-workspace-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: programs,
		scenarios: [hwhost.Scenario{ name: 'packages-import-workspace', arches: ['aarch64', 'x86_64'], about: 'captured private import workspace ownership, retained recovery data, source consistency, traversal limits and native profiles',
			required: required, forbidden: ['Out of memory', 'V panic:', 'HWTEST FAIL', 'IMPORT LIMITS baseline:'], ending: .poweroff, timeout: 600 }] }
}

fn qualify() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(workspace_suite(), os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	definition := workspace_suite(); hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-import-workspace') }
	os.mkdir_all(options.state_dir)!; work := os.real_path(options.state_dir); os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [workspace_artifact('kernel', work + '/kernel')!, workspace_artifact('guest-init', guest)!]
	for name in ['import-capture', 'import-limits', 'pack-source', 'native-profile', 'workspace', 'capture']! { artifacts << workspace_artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	// The existing native-profile regression compares its generated declarations
	// with repository examples through its compile-time @FILE repository path.
	fixture_repository := os.dir(os.dir(os.dir(os.dir(os.real_path(repository + '/tools/packages/pkgcore/native_profile_test.v')))))
	for name in ['hello', 'counter', 'memo']! {
		for architecture in ['aarch64', 'x86_64']! {
			path := fixture_repository + '/examples/package-' + name + '/manifest-' + architecture + '.json'
			target := root + path
			os.mkdir_all(os.dir(target))!; os.cp(path, target)!
			artifacts << workspace_artifact('example-' + name + '-' + architecture, target)!
		}
	}
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-import-workspace', timeout: if options.timeout > 600 { options.timeout } else { 600 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }; if !outcome.passed { return 1 }
	artifacts << workspace_artifact('serial-log', work + '/packages-import-workspace/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(WorkspaceGuestReceipt{ architecture: options.arch, completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(qualify() or { eprintln(err); 2 }) }
