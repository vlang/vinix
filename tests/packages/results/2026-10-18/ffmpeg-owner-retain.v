// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const work = 'build/package-ffmpeg-owner-work'
const prefix = 'tests/packages/results/2026-10-18/ffmpeg-owner-'

struct Pin { path string bytes u64 sha256 string }
struct SourcePin { path string sha256 string }
struct Inputs { compiler string sources []SourcePin }
struct Check { name string seconds f64 argv []string artifacts []SourcePin }
struct HostReceipt { format int inputs Inputs checks []Check }
struct GuestArtifact { role string bytes u64 sha256 string }
struct GuestReceipt { format int architecture string scenario string seconds f64 artifacts []GuestArtifact }
struct Ledger { format int = 1 baseline_commit string = '138c08d1e' compiler_version string = 'V 0.5.2 826e96f' scope string artifacts []Pin }

fn pin(path string) !Pin {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Pin{ path: path, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn save(source string, name string) ! { os.cp(source, prefix + name)! }

fn verify() ! {
	ledger := json2.decode[Ledger](os.read_file(prefix + 'toolchain.json')!)!
	for expected in ledger.artifacts { assert pin(expected.path)! == expected, expected.path }
	println('FFMPEG OWNER verified ' + ledger.artifacts.len.str() + ' source, compiler, artifact and evidence hashes PASS')
}

fn retain() ! {
	os.mkdir_all(os.dir(prefix))!
	for pair in [['baseline.txt', 'baseline.txt'], ['baseline.v', 'baseline.v'], ['host-1/qualification.json', 'host.json']] {
		save(work + '/' + pair[0], pair[1])!
	}
	for name in ['ffmpeg_profile.v']! {
		save(work + '/before-' + name, 'baseline-' + name)!
		before := os.exec(['git', 'show', '138c08d1e:tools/packages/pkgcore/' + name])
		assert before.exit_code == 0 && before.output == os.read_file(work + '/before-' + name)!
	}
	assert os.read_file(prefix + 'baseline.v')! == os.read_file('tools/packages/pkgcore/ffmpeg_builder_ownership_test.v')!
	save(work + '/cli.txt', 'cli.txt')!
	assert os.read_file(prefix + 'cli.txt')!.contains('production CLI format-1 replies, paths with spaces, unchanged application on runtime update and exact refusal preservation PASS')
	host := json2.decode[HostReceipt](os.read_file(prefix + 'host.json')!)!
	assert host.format == 1 && host.checks.len == 55
	compiler := pin(host.inputs.compiler)!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	mut paths := [compiler.path]
	paths << work + '/cli-check'
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
	os.write_file(prefix + 'host.txt', summary.join('\n') + '\nFFMPEG OWNER fifty-five host build/test checks PASS\n')!
	memory := os.read_file(prefix + 'ffmpeg-builder-run.txt')!
	assert memory.split(' retained=0 allocations=0').len == 39
	assert os.read_file(prefix + 'ffmpeg-owned-run.txt')!.contains('1152 cycles retire templates, partial inventories, canonicalization, replies and late refusals PASS')
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		attempt := '1'; state := 'build/ffo-' + short + '-' + attempt
		save(state + '/qualification.json', architecture + '.json')!
		save(work + '/guest-' + architecture + '-' + attempt + '.txt', architecture + '.txt')!
		save(state + '/packages-ffmpeg-owner/serial.log', architecture + '.serial.txt')!
		save(state + '/packages-ffmpeg-owner/qmp.log', architecture + '.qmp.txt')!
		serial := os.read_file(prefix + architecture + '.serial.txt')!.replace('\r', '')
		assert serial.split('FFMPEG OWNER resources before grace ').len == 9
		assert serial.split('FFMPEG OWNER resources after grace ').len == 9
		assert serial.split(' retained=0 allocations=0').len == 18
		assert serial.contains('HWTEST PASS packages-ffmpeg-owner') && !serial.contains('HWTEST FAIL')
		mut denied := 0
		for line in serial.split_into_lines() {
			if line.starts_with('Denied') { assert line.all_after(': ') == '0'; denied++ }
		}
		assert denied == 112
		receipt := json2.decode[GuestReceipt](os.read_file(state + '/qualification.json')!)!
		assert receipt.format == 1 && receipt.architecture == architecture && receipt.scenario == 'packages-ffmpeg-owner' && receipt.artifacts.len == 7
		for artifact in receipt.artifacts {
			path := if artifact.role == 'kernel' { state + '/kernel' } else if artifact.role == 'guest-init' { state + '/guest/init' }
				else if artifact.role == 'source-archive' { state + '/guest/root/usr/share/package-fixtures/ffmpeg.tar.xz' }
				else if artifact.role == 'serial-log' { state + '/packages-ffmpeg-owner/serial.log' }
				else { state + '/guest/root/usr/share/package-fixtures/' + artifact.role }
			actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256; paths << path
		}
		expected_kernel := if architecture == 'aarch64' { 'cfa3788c594b308c6009bee49d9e08a92feb5c23fe3b710ab5142427fc1f2d7e' } else { 'a989a9b1aff3db4260fe435336d3fba6120450992a96ab0fccbab27c38dce5b1' }
		assert pin(state + '/kernel')!.sha256 == expected_kernel
		paths << state + '/guest/build.log'
		for index in 0 .. 3 { paths << state + '/guest/program-' + index.str() + '/build.log' }
	}
	save(work + '/legacy-media.v', 'legacy-media.v')!; save(work + '/guest.v', 'guest-launch.v')!
	save(work + '/journal-check.v', 'journal-check.v')!; save(work + '/journal-check.txt', 'journal-check.txt')!
	for name in ['sources', 'artifact', 'existing', 'resume']! { save(work + '/journal-guards/' + name + '.txt', 'journal-' + name + '.txt')! }
	for name in ['baseline', 'baseline.v', 'baseline.txt', 'host-controller', 'guest-controller', 'guest', 'guest.v', 'legacy-media', 'legacy-media.v', 'journal-check', 'journal-check.v', 'host-1/inputs.json']! { paths << work + '/' + name }
	for name in ['ffmpeg_profile.v']! { paths << work + '/before-' + name }
	for path in os.walk_ext(work + '/baseline-tree/tools/packages/pkgcore', '.v') {
		name := os.file_name(path)
		if name == 'ffmpeg_profile.v' { assert os.read_file(path)! == os.read_file(work + '/before-ffmpeg_profile.v')! }
		else { assert os.read_file(path)! == os.read_file('tools/packages/pkgcore/' + name)! }
		paths << path
	}
	paths << work + '/baseline-tree.v'
	for name in ['limine', 'limine-uefi-cd.bin', 'limine-bios-cd.bin', 'limine-bios.sys', 'BOOTX64.EFI']! { paths << 'build/alloc-bench-kernel-before-schema2-1/iso-build/limine/' + name }

	for directory in ['tools/accounts', 'tests/hardware-platform/hwhost']! {
		for path in os.walk_ext(directory, '.v') { if !path.ends_with('_test.v') { paths << path } }
	}
	for path in ['tests/packages/ffmpeg-owner-runtime-check.v', 'tests/packages/ffmpeg-owner-guest/main.v',
		'tools/packages/pkgcore/pack_source_test.v', 'tests/packages/ffmpeg-owner-check.md',
		'build-support/build-amd64-iso.sh', 'build-support/limine-binary.sh', 'build-support/limine.conf',
		'build/package-release-work/v-toolchain/vlib/os/os.v', 'build/package-release-work/v-toolchain/vlib/os/os_nix.c.v',
		'build/package-release-work/v-toolchain/vlib/os/file.c.v', 'build/package-launch-transport-work/cross-cc',
		'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md', @FILE] { paths << path }
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
		scope: 'FFmpeg profile storage after JSON initialization; 76 complete-call host frames across 38 cases under 32 descriptors and 1152 metadata cycles; both guests qualify 1152 metadata cycles and a selected eight-case complete-call subset (16 frames each) using the full reviewed archive; 55 host checks, eight ASan/UBSan suites, all five profiles and 320 captured staging substitutions; independent replies, source pins, exact canonical retry and saved/recovery output; first-call JSON metadata, other complete profile/catalog/release owners and broader runtime/graphical acceptance remain separate', artifacts: pins }).replace('},{', '},\n{') + '\n')!
	verify()!
}

fn main() { if os.args.len == 2 && os.args[1] == '--verify' { verify()! } else { retain()! } }
