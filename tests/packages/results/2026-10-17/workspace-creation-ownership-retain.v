// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const work = 'build/package-workspace-create-owned-work'
const prefix = 'tests/packages/results/2026-10-17/workspace-creation-ownership-'

struct Pin { path string bytes u64 sha256 string }
struct Ledger { format int = 1 baseline_commit string = '11504f125' compiler_version string = 'V 0.5.2 826e96f' scope string artifacts []Pin }
struct Check { name string seconds f64 }
struct HostReceipt { checks []Check }
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
	println('WORKSPACE CREATION OWNERSHIP verified ' + ledger.artifacts.len.str() + ' source, compiler, artifact and evidence hashes PASS')
}

fn retain() ! {
	save(work + '/baseline.txt', 'baseline.txt')!; save(work + '/baseline.v', 'baseline.v')!
	for pair in [['qualification.json', 'host.json'], ['workspace_creation_ownership-run.txt', 'core.txt'], ['creation-tracked-run.txt', 'memory.txt'],
		['tracked-run.txt', 'pack.txt'], ['workspace_creation_ownership-sanitize-run.txt', 'asan.txt'], ['distribution-cli-run.txt', 'cli.txt'], ['native-tracked-run.txt', 'native.txt'], ['io-tracked-run.txt', 'helpers.txt']] {
		save(work + '/host-1/' + pair[0], pair[1])!
	}
	host := json2.decode[HostReceipt](os.read_file(prefix + 'host.json')!)!; assert host.checks.len == 79
	mut summary := []string{}
	for check in host.checks { summary << check.name + ' PASS (' + check.seconds.str() + 's)' }
	os.write_file(prefix + 'host.txt', summary.join('\n') + '\nWorkspace creation ownership: seventy-nine host build/test checks PASS\n')!
	mut pins := []Pin{}
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }; state := 'build/wco-' + short + '-4'
		save(state + '/qualification.json', architecture + '.json')!; save(work + '/guest-' + architecture + '-4.txt', architecture + '.txt')!
		save(state + '/packages-workspace-creation-ownership/serial.log', architecture + '.serial.txt')!
		save(state + '/packages-workspace-creation-ownership/qmp.log', architecture + '.qmp.txt')!
		serial := os.read_file(prefix + architecture + '.serial.txt')!.replace('\r', '')
		assert serial.split('WORKSPACE CREATION resources before grace ').len == 26
		assert serial.split('WORKSPACE CREATION resources after grace ').len == 26
		assert serial.split('WORKSPACE CREATION CASE ').len == 25
		for line in serial.split_into_lines() {
			if line.starts_with('Denied: ') { assert line == 'Denied: 0' }
		}
		receipt := json2.decode[GuestReceipt](os.read_file(state + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.artifacts.len == 18
		for artifact in receipt.artifacts {
			path := if artifact.role == 'kernel' { state + '/kernel' } else if artifact.role == 'guest-init' { state + '/guest/init' }
				else if artifact.role == 'serial-log' { state + '/packages-workspace-creation-ownership/serial.log' }
				else { state + '/guest/root/usr/share/package-fixtures/' + artifact.role }
			actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256; pins << actual
		}
		for index in 0 .. 15 { pins << pin(state + '/guest/program-' + index.str() + '/build.log')! }
		for attempt in ['1', '2', '3']! {
			failed := 'build/wco-' + short + '-' + attempt
			save(work + '/guest-' + architecture + '-' + attempt + '.txt', architecture + '.failed-' + attempt + '.txt')!
			save(failed + '/packages-workspace-creation-ownership/serial.log', architecture + '.failed-' + attempt + '.serial.txt')!
			save(failed + '/packages-workspace-creation-ownership/qmp.log', architecture + '.failed-' + attempt + '.qmp.txt')!
			for name in ['kernel', 'guest/init', 'guest/init.c', 'guest/root/usr/share/package-fixtures/creation', 'guest/program-10/creation.c']! { pins << pin(failed + '/' + name)! }
		}
	}
	for name in ['baseline', 'before-publisher_workspace.c.v', 'before-export.v', 'before-io.c.v', 'host-controller', 'guest-controller', 'guest-controller-unsplit', 'guest.v', 'guest-2.v', 'guest-3.v', 'guest-4.v']! { pins << pin(work + '/' + name)! }
	pins << pin('build/package-release-work/v-toolchain/v')!; pins << pin(work + '/host-1/vinix-package')!
	for check in host.checks {
		pins << pin(work + '/host-1/' + check.name + '.txt')!
		if check.name.ends_with('-run') { pins << pin(work + '/host-1/' + check.name[..check.name.len - 4])! }
	}
	for name in os.ls('tools/packages/pkgcore')! {
		if name.ends_with('.v') && !name.ends_with('_test.v') { pins << pin('tools/packages/pkgcore/' + name)! }
	}
	for name in ['pack_ownership', 'pack_source', 'publisher_workspace', 'copy', 'import_capture', 'import_limits', 'import', 'catalog', 'composition', 'native_profile', 'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'profile_inventory', 'prepared_root', 'publisher_io_ownership', 'durability', 'atomic', 'release', 'native_profile_ownership', 'workspace_creation_ownership', 'export_stage', 'catalog_export', 'mirror', 'distribution', 'coordination', 'service']! {
		pins << pin('tools/packages/pkgcore/' + name + '_test.v')!
	}
	for path in ['tools/packages/main.v', 'desktop/tools/tests/heap_tracker.h', 'tests/packages/workspace-creation-ownership-check.v',
		'tests/packages/workspace-creation-ownership-runtime-check.v', 'tests/packages/workspace-creation-ownership-guest/main.v',
		'tests/packages/publisher-io-ownership-check.md',
		'build/package-release-work/v-toolchain/vlib/os/os.v', 'build/package-release-work/v-toolchain/vlib/os/os_nix.c.v', 'build/package-release-work/v-toolchain/vlib/json2/encode.v',
		'tests/packages/workspace-creation-ownership-check.md', 'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md', @FILE] { pins << pin(path)! }
	for name in os.ls(os.dir(prefix))! {
		if name.starts_with(os.file_name(prefix)) && name != os.file_name(prefix) + 'toolchain.json' { pins << pin(os.dir(prefix) + '/' + name)! }
	}
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ scope: 'owned fresh export/parent/workspace/private directory construction, preserved POSIX aliases/dotdot/umask/modes, refused native creation and corrected partial-parent retry; 1408 creation helpers and 192 complete cold first packs retain zero V bytes/allocations after immutable JSON metadata initialization; previous 2176 helper calls, 80 existing packs and 816 source walks remain zero; host consumer/profile/CLI/sanitizer coverage and both unchanged kernels with fresh case processes and 25 measured six-second cleanup intervals; unsuccessful earlier attempts retained; full prepared-root/profile construction and unsplit guest stress remain separate', artifacts: pins }).replace('},{', '},\n{') + '\n')!
	verify()!
}

fn main() { if os.args.len == 2 && os.args[1] == '--verify' { verify()! } else { retain()! } }
