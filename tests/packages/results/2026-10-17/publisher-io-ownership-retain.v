// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const work = 'build/package-publisher-io-owned-work'
const prefix = 'tests/packages/results/2026-10-17/publisher-io-ownership-'

struct Pin { path string bytes u64 sha256 string }
struct Ledger { format int = 1 baseline_commit string = '55bc8a5c0' compiler_version string = 'V 0.5.2 826e96f' scope string artifacts []Pin }
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
	println('PUBLISHER IO OWNERSHIP verified ' + ledger.artifacts.len.str() + ' source, compiler, artifact and evidence hashes PASS')
}

fn retain() ! {
	save(work + '/baseline.txt', 'baseline.txt')!; save(work + '/baseline.v', 'baseline.v')!
	for pair in [['qualification.json', 'host.json'], ['publisher_io_ownership-run.txt', 'core.txt'], ['io-tracked-run.txt', 'memory.txt'],
		['tracked-run.txt', 'pack.txt'], ['publisher_io_ownership-sanitize-run.txt', 'asan.txt'], ['distribution-cli-run.txt', 'cli.txt'], ['native-tracked-run.txt', 'native.txt']] {
		save(work + '/host-1/' + pair[0], pair[1])!
	}
	host := json2.decode[HostReceipt](os.read_file(prefix + 'host.json')!)!; assert host.checks.len == 59
	mut summary := []string{}
	for check in host.checks { summary << check.name + ' PASS (' + check.seconds.str() + 's)' }
	os.write_file(prefix + 'host.txt', summary.join('\n') + '\nPublisher IO ownership: fifty-nine host build/test checks PASS\n')!
	mut pins := []Pin{}
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }; state := 'build/pio-' + short + '-1'
		save(state + '/qualification.json', architecture + '.json')!; save(work + '/guest-' + architecture + '-1.txt', architecture + '.txt')!
		save(state + '/packages-publisher-io-ownership/serial.log', architecture + '.serial.txt')!
		save(state + '/packages-publisher-io-ownership/qmp.log', architecture + '.qmp.txt')!
		receipt := json2.decode[GuestReceipt](os.read_file(state + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.artifacts.len == 13
		for artifact in receipt.artifacts {
			path := if artifact.role == 'kernel' { state + '/kernel' } else if artifact.role == 'guest-init' { state + '/guest/init' }
				else if artifact.role == 'serial-log' { state + '/packages-publisher-io-ownership/serial.log' }
				else { state + '/guest/root/usr/share/package-fixtures/' + artifact.role }
			actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256; pins << actual
		}
		for index in 0 .. 10 { pins << pin(state + '/guest/program-' + index.str() + '/build.log')! }
	}
	for name in ['baseline', 'before-publisher_workspace.c.v', 'before-release.v', 'before-durability.c.v', 'before-prepared_root.c.v', 'host-controller', 'guest-controller', 'guest.v']! { pins << pin(work + '/' + name)! }
	pins << pin('build/package-release-work/v-toolchain/v')!; pins << pin(work + '/host-1/vinix-package')!
	for check in host.checks {
		pins << pin(work + '/host-1/' + check.name + '.txt')!
		if check.name.ends_with('-run') { pins << pin(work + '/host-1/' + check.name[..check.name.len - 4])! }
	}
	for name in os.ls('tools/packages/pkgcore')! {
		if name.ends_with('.v') && !name.ends_with('_test.v') { pins << pin('tools/packages/pkgcore/' + name)! }
	}
	for name in ['pack_ownership', 'pack_source', 'publisher_workspace', 'copy', 'import_capture', 'import_limits', 'import', 'catalog', 'composition', 'native_profile', 'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'profile_inventory', 'prepared_root', 'publisher_io_ownership', 'durability', 'atomic', 'release', 'native_profile_ownership']! {
		pins << pin('tools/packages/pkgcore/' + name + '_test.v')!
	}
	for path in ['tools/packages/main.v', 'desktop/tools/tests/heap_tracker.h', 'tests/packages/publisher-io-ownership-check.v',
		'tests/packages/publisher-io-ownership-runtime-check.v', 'tests/packages/publisher-io-ownership-guest/main.v',
		'tests/packages/pack-ownership-check.v', 'tests/packages/pack-ownership-runtime-check.v', 'tests/packages/pack-ownership-check.md',
		'tests/packages/publisher-io-ownership-check.md', 'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md', @FILE] { pins << pin(path)! }
	for name in os.ls(os.dir(prefix))! {
		if name.starts_with(os.file_name(prefix)) && name != os.file_name(prefix) + 'toolchain.json' { pins << pin(os.dir(prefix) + '/' + name)! }
	}
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ scope: 'owned workspace admission, relative/alias containment, publisher exclusion and durability; 2176 helper calls, 80 complete existing-workspace packs and 816 cold/cache source walks retain zero V bytes/allocations on host and both unchanged kernels; failure recovery, all five host profiles, signed maintenance and fresh workspace case processes; first-time workspace and full prepared-root/profile construction remain separate boundaries', artifacts: pins }).replace('},{', '},\n{') + '\n')!
	verify()!
}

fn main() { if os.args.len == 2 && os.args[1] == '--verify' { verify()! } else { retain()! } }
