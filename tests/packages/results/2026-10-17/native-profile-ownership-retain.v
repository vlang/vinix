// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the local qualification, or verify its source/artifact/evidence hashes.
module main

import crypto.sha256
import json2
import os

const prefix = 'tests/packages/results/2026-10-17/native-profile-ownership-'
const work = 'build/package-native-profile-owned-work'

struct Artifact { role string path string bytes u64 sha256 string }
struct Ledger { format int = 1 baseline_commit string = 'aabb8411e' compiler_version string = 'V 0.5.2 826e96f' scope string artifacts []Artifact }
struct Check { name string seconds f64 }
struct HostReceipt { checks []Check }
struct GuestReceipt { architecture string seconds f64 artifacts []Artifact }

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, path: path, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn save(source string, name string) ! { os.cp(source, prefix + name)! }

fn verify() ! {
	ledger := json2.decode[Ledger](os.read_file(prefix + 'toolchain.json')!)!
	for pin in ledger.artifacts {
		actual := artifact(pin.role, pin.path)!
		assert actual.bytes == pin.bytes && actual.sha256 == pin.sha256, pin.path
	}
	println('NATIVE OWNERSHIP verified ' + ledger.artifacts.len.str() + ' source, compiler, artifact and evidence hashes PASS')
}

fn retain() ! {
	for pair in [
		['baseline.txt', 'baseline.txt'], ['baseline.json', 'baseline.json'], ['before-test.v', 'baseline.v'], ['golden.json', 'golden.json'],
		['host-1/qualification.json', 'host.json'], ['host-1/native_profile_ownership-run.txt', 'core.txt'], ['host-1/tracked-run.txt', 'memory.txt'],
		['host-1/native_profile_ownership-sanitize-run.txt', 'asan.txt'], ['host-1/native_profile-sanitize-run.txt', 'native-asan.txt'],
		['host-1/distribution-cli-run.txt', 'cli.txt'], ['host-1/profile-export-run.txt', 'exports.txt'],
	] { save(work + '/' + pair[0], pair[1])! }
	host := json2.decode[HostReceipt](os.read_file(prefix + 'host.json')!)!
	assert host.checks.len == 31
	mut summary := []string{}
	for item in host.checks { summary << item.name + ' PASS (' + item.seconds.str() + 's)' }
	os.write_file(prefix + 'host.txt', summary.join('\n') + '\nNative profile ownership: thirty-one host build/test checks PASS\n')!
	mut pins := []Artifact{}
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		state := 'build/no-' + short + '-3'
		save(state + '/qualification.json', architecture + '.json')!
		save(work + '/guest-' + architecture + '-3.txt', architecture + '.txt')!
		save(state + '/packages-native-ownership/serial.log', architecture + '.serial.txt')!
		save(state + '/packages-native-ownership/qmp.log', architecture + '.qmp.txt')!
		receipt := json2.decode[GuestReceipt](os.read_file(state + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.artifacts.len == 12
		for item in receipt.artifacts {
			path := if item.role == 'kernel' { state + '/kernel' }
				else if item.role == 'guest-init' { state + '/guest/init' }
				else if item.role == 'serial-log' { state + '/packages-native-ownership/serial.log' }
				else if item.role.starts_with('reviewed-example:') { state + '/guest/root/' + item.role.all_after('reviewed-example:').trim_left('/') }
				else { state + '/guest/root/usr/share/package-fixtures/' + item.role }
			actual := artifact('guest-' + architecture + ':' + item.role, path)!
			assert actual.bytes == item.bytes && actual.sha256 == item.sha256
			pins << actual
		}
		for index in 0 .. 3 {
			pins << artifact('guest-build', state + '/guest/program-' + index.str() + '/build.log')!
		}
		for attempt in 1 .. 3 {
			prior := 'build/no-' + short + '-' + attempt.str()
			label := if attempt == 1 { 'fixture-' } else { 'unsplit-' }
			source := work + '/guest-' + architecture + if attempt == 1 { '.txt' } else { '-2.txt' }
			save(source, label + architecture + '.txt')!
			save(prior + '/packages-native-ownership/serial.log', label + architecture + '.serial.txt')!
			save(prior + '/packages-native-ownership/qmp.log', label + architecture + '.qmp.txt')!
			for name in ['init', 'init.c']! { pins << artifact('earlier-guest', prior + '/guest/' + name)! }
		}
	}
	save('build/no-arm-2/qualification.json', 'unsplit-aarch64.json')!
	for name in ['v', 'v.c']! {
		if os.is_file('build/package-release-work/v-toolchain/' + name) { pins << artifact('compiler', 'build/package-release-work/v-toolchain/' + name)! }
	}
	for name in ['baseline', 'before-native.v', 'before-test.v', 'host-controller', 'guest-controller', 'guest-controller-2', 'guest-controller-3', 'guest.v']! {
		pins << artifact('local-artifact', work + '/' + name)!
	}
	for entry in host.checks {
		pins << artifact('host-log', work + '/host-1/' + entry.name + '.txt')!
		if entry.name.ends_with('-run') {
			name := entry.name[..entry.name.len - 4]
			pins << artifact('host-binary', work + '/host-1/' + name)!
		}
	}
	for path in ['tools/packages/main.v', 'tools/packages/pkgcore/native_profile.v', 'tools/packages/pkgcore/native_profile_ownership_test.v',
		'tools/packages/pkgcore/native_profile_test.v', 'tools/packages/pkgcore/profile_export_test.v', 'tools/packages/pkgcore/publish.v',
		'tools/packages/pkgcore/import.c.v', 'tools/packages/pkgcore/pack_source.c.v', 'tools/packages/pkgcore/publisher_schema.v',
		'tools/packages/pkgcore/publisher_encoding.v', 'tools/packages/pkgcore/catalog.v', 'tools/packages/pkgcore/export_stage.c.v',
		'tools/packages/pkgcore/profile_stage.c.v', 'desktop/tools/tests/heap_tracker.h',
		'tests/packages/native-profile-ownership-check.v', 'tests/packages/native-profile-ownership-runtime-check.v',
		'tests/packages/native-profile-ownership-guest/main.v', 'tests/packages/native-profile-ownership-check.md',
		'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md', @FILE] {
		pins << artifact('source', path)!
	}
	for name in os.ls(os.dir(prefix))! {
		if name.starts_with(os.file_name(prefix)) && name != os.file_name(prefix) + 'toolchain.json' {
			pins << artifact('evidence', os.dir(prefix) + '/' + name)!
		}
	}
	ledger := Ledger{ scope: 'owned native SDK profile templates, partial manifests, canonicalization and replies; 1152 zero-retention metadata cycles, identical catalog bytes, signed native lifecycle and four guest staging cohorts on both targets; whole-build retention and unsplit x86 owner-budget denial remain explicit', artifacts: pins }
	os.write_file(prefix + 'toolchain.json', json2.encode(ledger).replace('},{', '},\n{') + '\n')!
	verify()!
}

fn main() { if os.args.len == 2 && os.args[1] == '--verify' { verify()! } else { retain()! } }
