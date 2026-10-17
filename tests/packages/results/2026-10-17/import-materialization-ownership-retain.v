// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const work = 'build/package-import-materialization-owned-work'
const prefix = 'tests/packages/results/2026-10-17/import-materialization-ownership-'

struct Pin { path string bytes u64 sha256 string }
struct Ledger { format int = 1 baseline_commit string = 'c815c71af' compiler_version string = 'V 0.5.2 826e96f' scope string artifacts []Pin }
struct Check { name string seconds f64 completed_before_resume bool }
struct HostReceipt { compiler_sha256 string checks []Check }
struct GuestArtifact { role string bytes u64 sha256 string }
struct GuestReceipt { architecture string seconds f64 artifacts []GuestArtifact }

fn pin(path string) !Pin {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Pin{ path: path, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn save(source string, name string) ! { os.cp(source, prefix + name)! }

fn verify() ! {
	ledger := json2.decode[Ledger](os.read_file(prefix + 'toolchain.json')!)!
	for expected in ledger.artifacts { assert pin(expected.path)! == expected, expected.path }
	println('IMPORT MATERIALIZATION OWNERSHIP verified ' + ledger.artifacts.len.str() + ' source, compiler, artifact and evidence hashes PASS')
}

fn retain() ! {
	save(work + '/baseline.txt', 'baseline.txt')!; save(work + '/baseline.v', 'baseline.v')!
	save(work + '/controller-guards.txt', 'guards.txt')!
	save(work + '/resume-host.v', 'host-resume.v')!
	save(work + '/parallel-host.v', 'host-parallel.v')!
	save(work + '/host-2/resume-progress.json', 'host-progress.json')!
	for pair in [['qualification.json', 'host.json'], ['import_materialization_ownership-run.txt', 'core.txt'], ['tracked-run.txt', 'memory.txt'],
		['import_materialization_ownership-sanitize-run.txt', 'asan.txt'], ['import_capture-sanitize-run.txt', 'capture-asan.txt'],
		['import_limits-sanitize-run.txt', 'limits-asan.txt'], ['profile_export-sanitize-run.txt', 'profile-asan.txt'],
		['distribution-cli-run.txt', 'cli.txt'], ['native-tracked-run.txt', 'native.txt']] {
		save(work + '/host-2/' + pair[0], pair[1])!
	}
	host := json2.decode[HostReceipt](os.read_file(prefix + 'host.json')!)!; assert host.checks.len == 55
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == host.compiler_sha256 && compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	mut summary := []string{}
	mut resumed := 0
	for check in host.checks {
		if check.completed_before_resume {
			assert check.seconds == -1; resumed++
			summary << check.name + ' PASS (completed before interruption; timing unavailable)'
		} else {
			assert check.seconds >= 0
			summary << check.name + ' PASS (' + check.seconds.str() + 's)'
		}
	}
	assert resumed == 29
	os.write_file(prefix + 'host.txt', summary.join('\n') + '\nImport materialization ownership: fifty-five host build/test checks PASS\n')!
	save(work + '/host-1/profile_export-run.txt', 'host-input-failure.txt')!
	mut pins := [compiler]
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }; state := 'build/imo-' + short + '-1'
		save(state + '/qualification.json', architecture + '.json')!; save(work + '/guest-' + architecture + '-1.txt', architecture + '.txt')!
		save(state + '/packages-import-materialization-ownership/serial.log', architecture + '.serial.txt')!
		save(state + '/packages-import-materialization-ownership/qmp.log', architecture + '.qmp.txt')!
		serial := os.read_file(prefix + architecture + '.serial.txt')!.replace('\r', '')
		assert serial.split('IMPORT MATERIALIZATION resources before grace ').len == 24
		assert serial.split('IMPORT MATERIALIZATION resources after grace ').len == 24
		assert serial.split('IMPORT MATERIALIZATION CASE ').len == 24
		assert serial.contains('HWTEST PASS packages-import-materialization-ownership') && !serial.contains('HWTEST FAIL')
		for line in serial.split_into_lines() {
			if line.starts_with('Denied: ') { assert line == 'Denied: 0' }
		}
		for name in ['file', 'empty', 'nested', 'tree', 'alias', 'parent-alias', 'pinned', 'pin-size', 'pin-mode', 'pin-digest', 'cycle', 'special', 'opened', 'directory', 'sized', 'block', 'read', 'hashed', 'copy-block', 'copied', 'create-failure', 'parent-file']! {
			marker := 'IMPORT MATERIALIZATION case=' + name + ' retained=0 allocations=0'
			assert serial.contains(marker) && os.read_file(prefix + 'memory.txt')!.contains(marker)
		}
		receipt := json2.decode[GuestReceipt](os.read_file(state + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.artifacts.len == 11
		for artifact in receipt.artifacts {
			path := if artifact.role == 'kernel' { state + '/kernel' } else if artifact.role == 'guest-init' { state + '/guest/init' }
				else if artifact.role == 'serial-log' { state + '/packages-import-materialization-ownership/serial.log' }
				else { state + '/guest/root/usr/share/package-fixtures/' + artifact.role }
			actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256; pins << actual
		}
		kernel := pin(state + '/kernel')!
		expected_kernel := if architecture == 'aarch64' { 'cfa3788c594b308c6009bee49d9e08a92feb5c23fe3b710ab5142427fc1f2d7e' } else { 'a989a9b1aff3db4260fe435336d3fba6120450992a96ab0fccbab27c38dce5b1' }
		assert kernel.sha256 == expected_kernel
		for index in 0 .. 8 { pins << pin(state + '/guest/program-' + index.str() + '/build.log')! }
	}
	for name in ['baseline', 'before-import.c.v', 'baseline.v', 'capture-baseline.v', 'host-controller', 'guest-controller', 'guest.v', 'guards.v', 'bad-archive', 'resume-host', 'resume-host.v', 'parallel-host', 'parallel-host.v', 'host-2/resume-progress.json']! { pins << pin(work + '/' + name)! }
	for name in os.ls(work + '/host-2')! {
		if name.starts_with('parallel-') && name.ends_with('.json') { pins << pin(work + '/host-2/' + name)! }
	}
	pins << pin(work + '/host-2/vinix-package')!
	pins << pin(work + '/host-controller-before-archive-preflight')!
	pins << pin(work + '/host-1/profile_export')!
	pins << pin('build/package-ffmpeg-work/ffmpeg-8.0.1.tar.xz')!
	for check in host.checks {
		pins << pin(work + '/host-2/' + check.name + '.txt')!
		if check.name.ends_with('-run') { pins << pin(work + '/host-2/' + check.name[..check.name.len - 4])! }
	}
	for name in os.ls('tools/packages/pkgcore')! {
		if name.ends_with('.v') && !name.ends_with('_test.v') { pins << pin('tools/packages/pkgcore/' + name)! }
	}
	for directory in ['tests/packages/elffixture', 'tests/packages/applefixture']! {
		for name in os.ls(directory)! { if name.ends_with('.v') { pins << pin(directory + '/' + name)! } }
	}
	for name in ['import_materialization_ownership', 'import_lookup', 'import_capture', 'import_limits', 'import', 'prepared_root', 'pack_ownership', 'pack_source', 'native_profile', 'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'profile_inventory', 'profile_export', 'catalog', 'composition', 'catalog_export', 'release', 'export_stage', 'native_profile_ownership']! {
		pins << pin('tools/packages/pkgcore/' + name + '_test.v')!
	}
	for path in ['tools/packages/main.v', 'tests/packages/distribution-cli.v', 'desktop/tools/tests/heap_tracker.h',
		'tests/packages/import-materialization-ownership-check.v', 'tests/packages/import-materialization-ownership-runtime-check.v',
		'tests/packages/import-materialization-ownership-guest/main.v', 'tests/packages/import-lookup-check.md',
		'build/package-release-work/v-toolchain/vlib/os/os.v', 'build/package-release-work/v-toolchain/vlib/os/os_nix.c.v', 'build/package-release-work/v-toolchain/vlib/os/file.c.v',
		'tests/packages/import-materialization-ownership-check.md', 'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md', @FILE] { pins << pin(path)! }
	for name in os.ls(os.dir(prefix))! {
		if name.starts_with(os.file_name(prefix)) && name != os.file_name(prefix) + 'toolchain.json' { pins << pin(os.dir(prefix) + '/' + name)! }
	}
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ scope: 'owned prepared-root materialization scratch, numeric ancestry with growing-buffer retirement, POSIX parent construction and explicitly closed native writes; 352 calls across multiblock/empty/nested/tree/guest-alias/pinned success and late/native refusal under 32 descriptors, with partial-output retry; source mutation, traversal bounds, all five profiles, captured exports, canonical catalog/release and signed CLI/sanitizer regressions; both unchanged kernels, fresh case processes and 23 measured six-second cleanup intervals; complete private import workspace/profile construction and unbounded guest lifetime remain separate', artifacts: pins }).replace('},{', '},\n{') + '\n')!
	verify()!
}

fn main() { if os.args.len == 2 && os.args[1] == '--verify' { verify()! } else { retain()! } }
