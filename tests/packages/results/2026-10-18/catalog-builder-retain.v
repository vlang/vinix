// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const work = 'build/package-catalog-owner-work'
const prefix = 'tests/packages/results/2026-10-18/catalog-builder-'

struct Pin { path string bytes u64 sha256 string }
struct SourcePin { path string sha256 string }
struct Inputs { compiler string sources []SourcePin }
struct Check { name string seconds f64 argv []string artifacts []SourcePin }
struct HostReceipt { format int inputs Inputs checks []Check }
struct GuestArtifact { role string bytes u64 sha256 string }
struct GuestReceipt { format int architecture string scenario string seconds f64 artifacts []GuestArtifact }
struct Ledger { format int = 1 baseline_commit string = '2459df53a' compiler_version string = 'V 0.5.2 826e96f' scope string artifacts []Pin }

fn pin(path string) !Pin {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Pin{ path: path, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn invoke(arguments []string) os.Result {
	mut child := os.new_process(arguments[0]); child.set_args(arguments[1..]); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	return os.Result{ output: output, exit_code: code }
}

fn save(source string, name string) ! { os.cp(source, prefix + name)! }

fn verify() ! {
	ledger := json2.decode[Ledger](os.read_file(prefix + 'toolchain.json')!)!
	for expected in ledger.artifacts { assert pin(expected.path)! == expected, expected.path }
	println('CATALOG BUILDER verified ' + ledger.artifacts.len.str() + ' source, compiler, artifact and evidence hashes PASS')
}

fn retain() ! {
	os.mkdir_all(os.dir(prefix))!
	baseline := invoke([work + '/baseline', 'case', 'complete'])
	assert baseline.exit_code == 0 && baseline.output.contains('allocations=48') && baseline.output.contains('canonical retry, deduplication, saved output, sources and descriptors PASS')
	os.write_file(work + '/baseline.txt', baseline.output)!
	os.write_file(prefix + 'baseline-command.json', json2.encode([
		'build/package-release-work/v-toolchain/v', '-nocache', '-gc', 'none', '-manualfree', '-d', 'track_heap', '-d', 'catalog_builder_baseline',
		'-cflags', '-O1', '-path', '@vlib|@vmodules|build/package-catalog-owner-work/baseline-modules|.|tools/accounts',
		'-o', work + '/baseline', work + '/baseline-modules/tools/packages/pkgcore/catalog_builder_ownership_test.v']) + '\n')!
	for pair in [['baseline.txt', 'baseline.txt'], ['baseline.v', 'baseline.v'], ['host-1/qualification.json', 'host.json']] {
		save(work + '/' + pair[0], pair[1])!
	}
	for name in ['catalog.v', 'transaction.v']! {
		save(work + '/before-' + name, 'baseline-' + name)!
		before := invoke(['git', 'show', '2459df53a:tools/packages/pkgcore/' + name])
		assert before.exit_code == 0 && before.output == os.read_file(work + '/before-' + name)!
	}
	assert os.read_file(prefix + 'baseline.v')! == os.read_file('tools/packages/pkgcore/catalog_builder_ownership_test.v')!
	save(work + '/host-1/distribution-cli-run.txt', 'cli.txt')!
	assert os.read_file(prefix + 'cli.txt')!.contains('Package CLI: lock-scoped configuration, JSON verification, authenticated enrollment, offline mirror, reviewed deployment locks, rollback and revoked-publisher uninstall passed')
	host := json2.decode[HostReceipt](os.read_file(prefix + 'host.json')!)!
	assert host.format == 1 && host.checks.len == 29
	compiler := pin(host.inputs.compiler)!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	mut paths := [compiler.path]
	mut summary := []string{}
	for input in host.inputs.sources {
		assert pin(input.path)!.sha256 == input.sha256, input.path
		paths << input.path
	}
	for check in host.checks {
		assert check.seconds >= 0 && check.argv.len > 0 && check.artifacts.len == 2
		for artifact in check.artifacts { assert pin(artifact.path)!.sha256 == artifact.sha256; paths << artifact.path }
		save(work + '/host-1/' + check.name + '.txt', check.name + '.txt')!
		summary << check.name + ' PASS (' + check.seconds.str() + 's)'
	}
	os.write_file(prefix + 'host.txt', summary.join('\n') + '\nCATALOG BUILDER twenty-nine host build/test checks PASS\n')!
	memory := os.read_file(prefix + 'builder-run.txt')!
	assert memory.split(' retained=0 allocations=0').len == 36
	assert os.read_file(prefix + 'plan-run.txt')!.split(' retained=0 allocations=0').len == 15
	assert os.read_file(prefix + 'flush-run.txt')!.split(' retained=0 allocations=0').len == 4
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		attempt := '1'; state := 'build/cbo-' + short + '-' + attempt
		save(state + '/qualification.json', architecture + '.json')!
		save(work + '/guest-' + architecture + '-' + attempt + '.txt', architecture + '.txt')!
		save(state + '/packages-catalog-builder/serial.log', architecture + '.serial.txt')!
		save(state + '/packages-catalog-builder/qmp.log', architecture + '.qmp.txt')!
		serial := os.read_file(prefix + architecture + '.serial.txt')!.replace('\r', '')
		assert serial.split('CATALOG BUILDER resources before grace ').len == 11
		assert serial.split('CATALOG BUILDER resources after grace ').len == 11
		assert serial.split(' retained=0 allocations=0').len == 14
		assert serial.contains('HWTEST PASS packages-catalog-builder') && !serial.contains('HWTEST FAIL')
		mut denied := 0
		for line in serial.split_into_lines() {
			if line.starts_with('Denied') { assert line.all_after(': ') == '0'; denied++ }
		}
		assert denied == 140
		receipt := json2.decode[GuestReceipt](os.read_file(state + '/qualification.json')!)!
		assert receipt.format == 1 && receipt.architecture == architecture && receipt.scenario == 'packages-catalog-builder' && receipt.artifacts.len == 7
		for artifact in receipt.artifacts {
			path := if artifact.role == 'kernel' { state + '/kernel' } else if artifact.role == 'guest-init' { state + '/guest/init' }
				else if artifact.role == 'serial-log' { state + '/packages-catalog-builder/serial.log' }
				else { state + '/guest/root/usr/share/package-fixtures/' + artifact.role }
			actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256; paths << path
		}
		expected_kernel := if architecture == 'aarch64' { 'cfa3788c594b308c6009bee49d9e08a92feb5c23fe3b710ab5142427fc1f2d7e' } else { 'a989a9b1aff3db4260fe435336d3fba6120450992a96ab0fccbab27c38dce5b1' }
		assert pin(state + '/kernel')!.sha256 == expected_kernel
		paths << state + '/guest/build.log'
		for index in 0 .. 4 { paths << state + '/guest/program-' + index.str() + '/build.log' }
	}
	save(work + '/legacy-media.v', 'legacy-media.v')!; save(work + '/guest.v', 'guest-launch.v')!
	save(work + '/journal-check.v', 'journal-check.v')!; save(work + '/journal-check.txt', 'journal-check.txt')!
	for name in ['sources', 'artifact', 'existing', 'resume']! { save(work + '/journal-guards/' + name + '.txt', 'journal-' + name + '.txt')! }
	for name in ['baseline', 'baseline.v', 'baseline.txt', 'host-controller', 'guest-controller', 'guest', 'guest.v', 'legacy-media', 'legacy-media.v', 'journal-check', 'journal-check.v', 'host-1/inputs.json']! { paths << work + '/' + name }
	for name in ['catalog.v', 'transaction.v']! { paths << work + '/before-' + name }
	for path in os.walk_ext(work + '/baseline-modules/tools/packages/pkgcore', '.v') {
		name := os.file_name(path)
		if name in ['catalog.v', 'transaction.v']! { assert os.read_file(path)! == os.read_file(work + '/before-' + name)! }
		else { assert os.read_file(path)! == os.read_file('tools/packages/pkgcore/' + name)! }
		paths << path
	}
	paths << work + '/baseline-tree.v'
	for name in ['limine', 'limine-uefi-cd.bin', 'limine-bios-cd.bin', 'limine-bios.sys', 'BOOTX64.EFI']! { paths << 'build/alloc-bench-kernel-before-schema2-1/iso-build/limine/' + name }

	for directory in ['tools/accounts', 'tests/hardware-platform/hwhost']! {
		for path in os.walk_ext(directory, '.v') { if !path.ends_with('_test.v') { paths << path } }
	}
	for path in ['tests/packages/catalog-builder-runtime-check.v', 'tests/packages/catalog-builder-guest/main.v',
		'tools/packages/pkgcore/pack_source_test.v', 'tests/packages/catalog-builder-check.md',
		'build-support/build-amd64-iso.sh', 'build-support/limine-binary.sh', 'build-support/limine.conf',
		'build/package-release-work/v-toolchain/vlib/os/os.v', 'build/package-release-work/v-toolchain/vlib/os/os_nix.c.v',
		'build/package-release-work/v-toolchain/vlib/os/file.c.v', 'build/package-launch-transport-work/cross-cc',
		'build/package-release-work/v-toolchain/vlib/os/execute_capture_nix.h',
		'tools/packages/SDK.md', 'tools/packages/README.md', 'docs/application-distribution.md', 'roadmap.md', @FILE] { paths << path }
	for name in os.ls(os.dir(prefix))! {
		if name.starts_with(os.file_name(prefix)) && name != os.file_name(prefix) + 'toolchain.json' { paths << os.dir(prefix) + '/' + name }
	}
	mut unique := map[string]bool{}
	mut normalized := []string{}
	for path in paths {
		absolute := os.abs_path(path)
		root := os.getwd() + '/'
		assert absolute.starts_with(root)
		name := absolute[root.len..]
		if name !in unique { unique[name] = true; normalized << name }
	}
	normalized.sort()
	mut pins := []Pin{}
	for path in normalized { pins << pin(path)! }
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{
		scope: 'Catalog builder ownership after JSON initialization; 280 complete-call frames across 35 cases under 32 descriptors, 192 recursive flush cycles and 1792 tracked host planning attempts; both guests qualify flushing, ordinary catalog/planning regressions and ten selected complete-call cases (80 frames each); 29 host checks, four ASan/UBSan suites and 144 catalog/composition staging substitutions; exact canonical retry, deduplicated objects, captured declarations and saved/recovery output; cold JSON, complete release ownership and broader catalog/graphical/runtime acceptance remain separate', artifacts: pins }).replace('},{', '},\n{') + '\n')!
	verify()!
}

fn main() { if os.args.len == 2 && os.args[1] == '--verify' { verify()! } else { retain()! } }
