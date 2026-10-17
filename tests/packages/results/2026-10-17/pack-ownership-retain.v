// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const work = 'build/package-pack-owned-work'
const prefix = 'tests/packages/results/2026-10-17/pack-ownership-'

struct Pin { path string bytes u64 sha256 string }
struct Ledger { format int = 1 baseline_commit string = '2f81b0590' compiler_version string = 'V 0.5.2 826e96f' scope string artifacts []Pin }
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
	for expected in ledger.artifacts {
		actual := pin(expected.path)!
		assert actual == expected, expected.path
	}
	println('PACK OWNERSHIP verified ' + ledger.artifacts.len.str() + ' source, compiler, artifact and evidence hashes PASS')
}

fn retain() ! {
	mut child := os.new_process(work + '/baseline'); child.set_args(['--pack-owned-baseline']); child.set_redirect_stdio_merged()
	child.run(); baseline := child.stdout_slurp(); child.wait(); code := child.code; child.close(); assert code == 0
	os.write_file(prefix + 'baseline.txt', baseline)!
	save(work + '/before-pack_ownership_test.v', 'baseline.v')!
	for pair in [['qualification.json', 'host.json'], ['pack_ownership-run.txt', 'core.txt'], ['tracked-run.txt', 'memory.txt'],
		['pack_ownership-sanitize-run.txt', 'asan.txt'], ['distribution-cli-run.txt', 'cli.txt'], ['native-tracked-run.txt', 'native.txt']] {
		save(work + '/host-1/' + pair[0], pair[1])!
	}
	host := json2.decode[HostReceipt](os.read_file(prefix + 'host.json')!)!
	assert host.checks.len == 45
	mut summary := []string{}
	for check in host.checks { summary << check.name + ' PASS (' + check.seconds.str() + 's)' }
	os.write_file(prefix + 'host.txt', summary.join('\n') + '\nPacking ownership: forty-five host build/test checks PASS\n')!
	mut pins := []Pin{}
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		state := 'build/po-' + short + '-1'
		save(state + '/qualification.json', architecture + '.json')!
		save(work + '/guest-' + architecture + '-1.txt', architecture + '.txt')!
		save(state + '/packages-pack-ownership/serial.log', architecture + '.serial.txt')!
		save(state + '/packages-pack-ownership/qmp.log', architecture + '.qmp.txt')!
		receipt := json2.decode[GuestReceipt](os.read_file(state + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.artifacts.len == 10
		for artifact in receipt.artifacts {
			path := if artifact.role == 'kernel' { state + '/kernel' } else if artifact.role == 'guest-init' { state + '/guest/init' }
				else if artifact.role == 'serial-log' { state + '/packages-pack-ownership/serial.log' }
				else { state + '/guest/root/usr/share/package-fixtures/' + artifact.role }
			actual := pin(path)!
			assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256
			pins << actual
		}
		for index in 0 .. 7 { pins << pin(state + '/guest/program-' + index.str() + '/build.log')! }
	}
	for name in ['baseline', 'before-publish.v', 'before-pack_source.c.v', 'before-import.c.v', 'before-copy.c.v', 'before-pack_ownership_test.v', 'host-controller', 'guest-controller', 'guest.v']! {
		pins << pin(work + '/' + name)!
	}
	pins << pin('build/package-release-work/v-toolchain/v')!
	pins << pin(work + '/host-1/vinix-package')!
	for check in host.checks {
		pins << pin(work + '/host-1/' + check.name + '.txt')!
		if check.name.ends_with('-run') { pins << pin(work + '/host-1/' + check.name[..check.name.len - 4])! }
	}
	for path in ['tools/packages/main.v', 'tools/packages/pkgcore/publish.v', 'tools/packages/pkgcore/pack_source.c.v',
		'tools/packages/pkgcore/import.c.v', 'tools/packages/pkgcore/copy.c.v', 'tools/packages/pkgcore/pack_ownership_test.v',
		'tools/packages/pkgcore/publisher_encoding.v', 'tools/packages/pkgcore/index_schema.v', 'desktop/tools/tests/heap_tracker.h',
		'tests/packages/pack-ownership-check.v', 'tests/packages/pack-ownership-runtime-check.v', 'tests/packages/pack-ownership-guest/main.v',
		'tests/packages/pack-ownership-check.md', 'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md', @FILE] {
		pins << pin(path)!
	}
	names := os.ls(os.dir(prefix))!
	for name in names {
		if name.starts_with(os.file_name(prefix)) && name != os.file_name(prefix) + 'toolchain.json' { pins << pin(os.dir(prefix) + '/' + name)! }
	}
	ledger := Ledger{ scope: 'owned packing templates and cold/cache inventories, captured-copy stat lifetime, closeable pack/root replies and exact CLI/manifest JSON, literal object-slot replacement and recovery; 816 zero-retention walks and separately bounded whole calls, all five host profiles, copy/import mutation, signed catalogs/releases on both unchanged kernels; complete workspace/lock/durability and prepared-root/profile allocation freedom remains open', artifacts: pins }
	os.write_file(prefix + 'toolchain.json', json2.encode(ledger).replace('},{', '},\n{') + '\n')!
	verify()!
}

fn main() { if os.args.len == 2 && os.args[1] == '--verify' { verify()! } else { retain()! } }
