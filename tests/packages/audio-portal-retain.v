// SPDX-License-Identifier: GPL-2.0-or-later
// Admit complete native evidence; receipt inventories record the remaining source provenance.
module main

import crypto.sha256
import json2
import math
import os
import tests.packages.audiotest
import tests.packages.audioinputs

const trees = ['tools/packages', 'tools/accounts', 'tools/security-events', 'tools/keyring',
	'build-support/native-compat-tools/compathost', 'tools/sandbox', 'tests/qemu-core/fixturehost',
	'tests/native-guest-tools/guesthost', 'tests/linuxkpi/hosttest', 'tests/native-policy-tools/nativepolicy',
	'tests/host-policy/policyhost', 'tests/hardware-platform/hwhost',
	'tests/packages/audio-portal-guest', 'tests/packages/audio-portal-tone', 'tests/packages/audiotest',
	'tests/packages/audioinputs']
const files = ['tests/packages/audio-portal-runtime-check.v', 'tests/packages/audio-portal-retain.v',
	'tests/packages/audio-portal-evidence-check.v', 'tests/packages/audio-portal-wave-check.v',
	'build-support/native-compat-tools/main.v', 'build-support/security-tools/compile-v-core',
	'build-support/run-v-tool.sh', 'build-support/find-v.sh', 'tests/packages/audio-cross-cc.v',
	'tests/packages/audio-input-check.v', 'tests/packages/audio-cross-probe.v']
const inputs = ['guest', 'tone', 'package-cli', 'account-cli', 'session-cli', 'authd', 'kernel',
	'v', 'clang', 'qemu', 'firmware', 'sandbox', 'sandbox-c', 'adapter-host-cc',
	'cross-backend', 'cross-cc1', 'cross-collect2', 'cross-as', 'cross-ld', 'cross-lto-wrapper', 'cross-lto-plugin', 'cross-adapter',
	'cross-adapter-build', 'cross-probe.c', 'cross-probe', 'cross-probe-generate.log', 'cross-search.log',
	'cross-sysroot-files', 'cross-sysroot-links', 'cross-sysroot-root', 'input-origins']
const metadata = ['source-before', 'source-after', 'generated-before', 'generated-after', 'input-before', 'input-after']
const generated = ['guest-build/init.c', 'tone-build/tone.c', 'tools/program-0/vinix-package.c',
	'tools/program-1/vinix-account.c', 'tools/program-2/vinix-session.c', 'tools/program-3/vinix-authd.c']
// Reviewed observed inputs: section14/audio-peer-login-20261026/kernel-seal.json.
// This pin does not attest reproducibility or completion of the broader kernel checks.
const reviewed_kernel_seal = '839ad75dd1ec376a8cae4e75dc1cfbddc913406dc3e136e8d4f4a412657f9b73'
const kernel_sources = ['kernel/socket/public/public.v', 'kernel/socket/unix/unix.v', 'kernel/socket/socket.v']

struct KernelBuild {
	elf_path string
	elf_sha256 string
	generated_c_path string
	generated_c_sha256 string
	build_log_path string
	build_log_sha256 string
	build_flags []string
	compiler_path string
	compiler_sha256 string
	clang_path string
	clang_sha256 string
	linker_path string
	linker_sha256 string
}

struct KernelSeal {
	format int
	source_revision string
	source_patch_path string
	source_patch_sha256 string
	source_inventory_path string
	source_inventory_sha256 string
	critical_sources map[string]string
	kernels map[string]KernelBuild
}

struct Receipt {
	format int
	architecture string
	platform string
	result string
	completed_at i64
	source_root string
	source_revision string
	sources map[string]string
	artifacts map[string]string
	artifact_paths map[string]string
}

struct Outcome {
	scenario string
	passed bool
	interrupted bool
	seconds f64
	reason string
	state string
}

struct Retained {
	format int = 1
	result string = 'PASS'
	architecture string
	platform string
	qualification string
	retainer string
	regions map[string][]audiotest.Region
	limitation string = 'Critical producer and authority sources are embedded; remaining frozen source inventory is provenance, not a source signature. Healthy-device execution does not qualify stalled drain.'
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn hex(value string, length int) bool {
	return value.len == length && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn regular(path string) ! {
	if (os.lstat(path)!).mode & 0o170000 != 0o100000 { return error('requires regular evidence file: ' + path) }
}

fn bounded(path string) !string {
	regular(path)!
	if (os.stat(path)!).size > 16 * 1024 * 1024 { return error('text evidence exceeds limit: ' + path) }
	return os.read_file(path)!
}

fn target_elf(path string, arch string) ! {
	mut file := os.open(path)!
	defer { file.close() }
	mut header := []u8{len: 64}
	if file.read(mut header)! != 64 || header[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| header[6] != 1 || int(header[18]) + (int(header[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } {
		return error('requires selected-architecture ELF64 input: ' + path)
	}
}

fn relative(path string) bool {
	return path != '' && !os.is_abs_path(path) && !path.contains('\\')
		&& path.split('/').all(it != '' && it != '.' && it != '..')
}

fn sealed_file(root string, path string, sum string) ! {
	if !relative(path) || !hex(sum, 64) || os.real_path(root + '/' + path) != root + '/' + path {
		return error('invalid sealed kernel input: ' + path)
	}
	regular(root + '/' + path)!
	if digest(root + '/' + path)! != sum { return error('sealed kernel input differs: ' + path) }
}

fn admit_kernel(run string, receipt Receipt, arch string, synthetic bool) ! {
	root := run + '/inputs/kernel-evidence'
	path := root + '/kernel-seal.json'
	if receipt.artifact_paths['kernel-seal'] != path { return error('missing retained kernel seal') }
	if !synthetic && (!hex(reviewed_kernel_seal, 64) || receipt.artifacts['kernel-seal'] != reviewed_kernel_seal) {
		return error('requires independently reviewed native kernel seal')
	}
	seal := json2.decode[KernelSeal](bounded(path)!)!
	if seal.format != 1 || !hex(seal.source_revision, 40) || seal.source_patch_path != 'source.patch'
		|| seal.source_inventory_path != 'source-inputs.sha256' || seal.critical_sources.len != kernel_sources.len
		|| seal.kernels.len != 2 { return error('incomplete retained kernel seal') }
	sealed_file(root, seal.source_patch_path, seal.source_patch_sha256)!
	sealed_file(root, seal.source_inventory_path, seal.source_inventory_sha256)!
	for source in kernel_sources {
		sealed_file(root, 'source/' + source, seal.critical_sources[source])!
	}
	for architecture in ['aarch64', 'x86_64'] {
		build := seal.kernels[architecture] or { return error('missing sealed kernel architecture') }
		expected_flags := ['ARCH=' + architecture, 'ALLOC_TRACK=1', 'PROD=true',
			if architecture == 'aarch64' { 'LIMINE_MP=1' } else { 'LIMINE_MP=0' }]
		if build.build_flags != expected_flags { return error('sealed kernel build flags differ') }
		sealed_file(root, build.elf_path, build.elf_sha256)!
		sealed_file(root, build.generated_c_path, build.generated_c_sha256)!
		sealed_file(root, build.build_log_path, build.build_log_sha256)!
		sealed_file(root, build.compiler_path, build.compiler_sha256)!
		sealed_file(root, build.clang_path, build.clang_sha256)!
		sealed_file(root, build.linker_path, build.linker_sha256)!
		target_elf(root + '/' + build.elf_path, architecture)!
		if architecture == arch && build.elf_sha256 != receipt.artifacts['kernel'] {
			return error('native audio kernel differs from reviewed sealed ELF')
		}
	}
}

fn observed_argument(text string, argument string) bool {
	mut offset := 0
	for {
		position := text.index_after(argument, offset) or { return false }
		end := position + argument.len
		if (position == 0 || text[position - 1] in [u8(32), 9, 10, 13, 34, 39])
			&& (end == text.len || text[end] in [u8(32), 9, 10, 13, 34, 39]) { return true }
		offset = position + 1
	}
	return false
}

fn admit_cross(run string, receipt Receipt, arch string) ! {
	for name in ['files', 'links', 'root'] {
		if receipt.artifact_paths['cross-sysroot-' + name] != run + '/cross-sysroot-' + name + '.json' {
			return error('misplaced captured cross sysroot metadata')
		}
	}
	roots := json2.decode[map[string]string](bounded(receipt.artifact_paths['cross-sysroot-root'])!)!
	root := roots['root']
	if roots.len != 1 || !root.starts_with('/') || !relative(root[1..]) {
		return error('invalid original cross sysroot root')
	}
	sysroot_files := json2.decode[map[string]string](bounded(receipt.artifact_paths['cross-sysroot-files'])!)!
	links := json2.decode[map[string]string](bounded(receipt.artifact_paths['cross-sysroot-links'])!)!
	if sysroot_files.len == 0 { return error('empty captured cross sysroot') }
	mut captured := map[string]string{}
	input_inventory(run + '/inputs/cross-sysroot', '', mut captured)!
	if captured.len != sysroot_files.len { return error('captured cross sysroot file coverage differs') }
	for name, original in sysroot_files {
		if !relative(name) || !original.starts_with(root + '/') || !relative(original[root.len + 1..])
			|| sysroot_files[original[root.len + 1..]] != original {
			return error('invalid captured cross sysroot source: ' + name)
		}
		key := 'cross-sysroot/' + name
		if receipt.artifact_paths[key] != run + '/inputs/' + key || receipt.artifacts[key] != captured['input/' + name] {
			return error('captured cross sysroot file differs: ' + name)
		}
	}
	for name, target in links {
		if !relative(name) || target == '' || target.contains('\x00') { return error('invalid literal cross sysroot link') }
	}
	target_elf(receipt.artifact_paths['cross-probe'], arch)!
	if !observed_argument(bounded(receipt.artifact_paths['cross-search.log'])!, '--sysroot=' + run + '/inputs/cross-sysroot') {
		return error('cross compiler trace lacks retained frozen sysroot')
	}
	if receipt.artifact_paths['input-origins'] != run + '/original-input-paths.json' {
		return error('misplaced original compiler input inventory')
	}
	origins := json2.decode[map[string]string](bounded(receipt.artifact_paths['input-origins'])!)!
	for name, path in origins {
		if (!name.starts_with('vlib/') && !name.starts_with('v-thirdparty/')) || !name.ends_with('.h') { continue }
		if !relative(name) || !os.is_abs_path(path) || receipt.artifact_paths[name] != run + '/inputs/' + name
			|| !hex(receipt.artifacts[name], 64) { return error('uncaptured original V header input: ' + name) }
	}
	allowed := audioinputs.header_allowlist(receipt.source_root, receipt.sources, origins)
	for name in audioinputs.trace_files() {
		key := 'trace/' + name
		if receipt.artifact_paths[key] != run + '/' + name { return error('missing exact target compiler trace: ' + name) }
		if receipt.artifact_paths['trace-object/' + name] != audioinputs.trace_object(run, name)! { return error('missing exact generated target object: ' + name) }
		audioinputs.verify_trace(bounded(receipt.artifact_paths[key])!, run, name, allowed)!
	}
}

fn raw_artifact(name string) bool {
	return name in ['basic', 'lifecycle', 'seat'].map(it + '-outcome')
		|| name in ['basic', 'lifecycle', 'seat'].map(it + '-serial')
		|| name in ['basic', 'lifecycle', 'seat'].map(it + '-wav')
		|| name in ['basic', 'lifecycle', 'seat'].map(it + '-qemu-log')
		|| name in ['basic', 'lifecycle', 'seat'].map(it + '-qmp-log')
}

fn inventory(root string, prefix string, mut result map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		path := prefix + '/' + name
		mode := (os.lstat(root + '/' + path)!).mode & 0o170000
		if mode == 0o040000 { inventory(root, path, mut result)! }
		else if mode == 0o100000 {
			if !name.ends_with('_test.v') { result[path] = digest(root + '/' + path)! }
		} else { return error('nonregular frozen source: ' + path) }
	}
}

fn input_inventory(root string, prefix string, mut result map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		if prefix == '' && name == 'source' { continue }
		path := if prefix == '' { name } else { prefix + '/' + name }
		mode := (os.lstat(root + '/' + path)!).mode & 0o170000
		if mode == 0o040000 { input_inventory(root, path, mut result)! }
		else if mode == 0o100000 { result['input/' + path] = digest(root + '/' + path)! }
		else { return error('nonregular retained input: ' + path) }
	}
}

// Embedding these bytes refuses resealed changes in the producer and audio authority path.
fn embedded() map[string]string {
	return {
		'tests/packages/audio-portal-runtime-check.v': $embed_file('audio-portal-runtime-check.v').to_string()
		'tests/packages/audio-portal-retain.v': $embed_file('audio-portal-retain.v').to_string()
		'tests/packages/audio-portal-evidence-check.v': $embed_file('audio-portal-evidence-check.v').to_string()
		'tests/packages/audio-portal-wave-check.v': $embed_file('audio-portal-wave-check.v').to_string()
		'tests/packages/audio-input-check.v': $embed_file('audio-input-check.v').to_string()
		'tests/packages/audioinputs/tree.v': $embed_file('audioinputs/tree.v').to_string()
		'tests/packages/audio-cross-cc.v': $embed_file('audio-cross-cc.v').to_string()
		'tests/packages/audio-cross-probe.v': $embed_file('audio-cross-probe.v').to_string()
		'tests/packages/audiotest/wave.v': $embed_file('audiotest/wave.v').to_string()
		'tests/packages/audio-portal-guest/main.v': $embed_file('audio-portal-guest/main.v').to_string()
		'tests/packages/audio-portal-guest/scenarios.v': $embed_file('audio-portal-guest/scenarios.v').to_string()
		'tests/packages/audio-portal-guest/seat.v': $embed_file('audio-portal-guest/seat.v').to_string()
		'tests/packages/audio-portal-guest/forgery.v': $embed_file('audio-portal-guest/forgery.v').to_string()
		'tests/packages/audio-portal-tone/main.v': $embed_file('audio-portal-tone/main.v').to_string()
		'tools/packages/main.v': $embed_file('../../tools/packages/main.v').to_string()
		'tools/packages/pkgcore/launch.v': $embed_file('../../tools/packages/pkgcore/launch.v').to_string()
		'tools/packages/pkgcore/audio_launch.v': $embed_file('../../tools/packages/pkgcore/audio_launch.v').to_string()
		'tools/packages/pkglaunch/audio.v': $embed_file('../../tools/packages/pkglaunch/audio.v').to_string()
		'tools/packages/pkglaunch/client.v': $embed_file('../../tools/packages/pkglaunch/client.v').to_string()
		'tools/packages/pkglaunch/protocol.v': $embed_file('../../tools/packages/pkglaunch/protocol.v').to_string()
		'tools/packages/pkglaunch/request_reader.v': $embed_file('../../tools/packages/pkglaunch/request_reader.v').to_string()
		'tools/packages/pkglaunch/display.v': $embed_file('../../tools/packages/pkglaunch/display.v').to_string()
		'tools/packages/audiopcm/bootstrap.v': $embed_file('../../tools/packages/audiopcm/bootstrap.v').to_string()
		'tools/packages/audiopcm/capability.v': $embed_file('../../tools/packages/audiopcm/capability.v').to_string()
		'tools/packages/audiopcm/client.v': $embed_file('../../tools/packages/audiopcm/client.v').to_string()
		'tools/packages/audiopcm/native.c.v': $embed_file('../../tools/packages/audiopcm/native.c.v').to_string()
		'tools/packages/audiopcm/worker.v': $embed_file('../../tools/packages/audiopcm/worker.v').to_string()
		'tools/accounts/session.v': $embed_file('../../tools/accounts/session.v').to_string()
		'tools/accounts/sessioncore/launch.v': $embed_file('../../tools/accounts/sessioncore/launch.v').to_string()
	}
}

fn identity(run string) string { return 'AUDIO PAYLOAD ${run} uid=1000 groups=0 signed-context direct-device-refused PASS' }

fn markers(scenario string) []string {
	login := 'AUDIO LOGIN uid=1000 home=/home/alex supplementary-users PASS'
	mut result := ['HWTEST START packages-audio-' + scenario, 'AUDIO SETUP signed tone and noaudio installed PASS']
	if scenario == 'basic' {
		result << 'AUDIO CONTROL group0-forged-account-action refused PASS'
		result << [login, identity('missing'), 'AUDIO PAYLOAD missing refuse PASS', 'AUDIO CONTROL absent-permission refused PASS',
			login, 'AUDIO CONTROL organization-policy refused PASS', login, identity('forged'), 'AUDIO PAYLOAD forged forged PASS',
			'AUDIO CONTROL forged-endpoint refused PASS']
		for mode in ['service', 'changed'] {
			result << [login, identity(mode), 'AUDIO PAYLOAD ${mode} ${mode} PASS', 'AUDIO CONTROL ${mode} refused and cleanup PASS']
		}
		result << [login, identity('sequence'), 'AUDIO PAYLOAD sequence sequence PASS', 'AUDIO PCM exact sequence 440 660 880 PASS']
	} else if scenario == 'lifecycle' {
		for target in ['client', 'launcher'] {
			next := 'after' + target
			result << [login, identity(target), login, identity(next), 'AUDIO PAYLOAD ${next} tone PASS',
				'AUDIO LIFECYCLE ${target}-death cleanup and relaunch PASS']
		}
	} else {
		result << [login, identity('seat'), 'AUDIO PAYLOAD seat seat PASS', 'AUDIO SEAT real-other-login inactive-write-refused active-relaunch PASS']
	}
	result << 'HWTEST PASS packages-audio-' + scenario
	return result
}

fn serial(path string, scenario string) ! {
	text := bounded(path)!
	for forbidden in ['AUDIO PAYLOAD FAIL', 'AUDIO LOGIN FAIL', 'HWTEST FAIL', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION'] {
		if text.contains(forbidden) { return error('forbidden serial marker: ' + forbidden) }
	}
	actual := text.split_into_lines().map(it.trim_right('\r')).filter(it.starts_with('AUDIO ') || it.starts_with('HWTEST '))
	if actual != markers(scenario) { return error('ordered exact serial markers differ: ' + scenario) }
}

fn admit_shutdown(path string) ! {
	mut count := 0
	for line in bounded(path)!.split_into_lines() {
		if !line.contains('] <- ') { continue }
		object := json2.decode[json2.Any](line.all_after('] <- '))!.as_map()
		event := (object['event'] or { json2.Any('') }).str()
		if event in ['RESET', 'GUEST_PANICKED'] { return error('forbidden QMP event: ' + event) }
		if event == 'SHUTDOWN' {
			data := object['data']!.as_map()
			if data['guest']! != json2.Any(true) || data['reason']! != json2.Any('guest-shutdown') {
				return error('requires guest-initiated QMP shutdown')
			}
			count++
		}
	}
	if count != 1 { return error('missing or duplicated guest QMP shutdown') }
}

fn retain(run string, out string, arch string, synthetic bool) ! {
	$if prod {} $else { return error('compile audio retainer with -prod') }
	if digest(@FILE)! != sha256.sum($embed_file('audio-portal-retain.v').to_string().bytes()).hex() { return error('retainer changed after compilation') }
	if os.exists(out) || os.is_link(out) { return error('requires new retention output') }
	receipt := json2.decode[Receipt](bounded(run + '/qualification.json')!)!
	platform := if synthetic { 'synthetic-audio-retainer-control' } else { 'qemu-native-audio-ordinary-account-seat' }
	if receipt.format != 1 || receipt.platform != platform || receipt.result != 'PASS'
		|| arch !in ['aarch64', 'x86_64'] || receipt.architecture != arch || receipt.completed_at <= 0
		|| !hex(receipt.source_revision, 40) { return error('requires complete selected-architecture native audio receipt') }
	if receipt.source_root != run + '/inputs/source' || os.real_path(receipt.source_root) != receipt.source_root {
		return error('frozen source root differs from retained native run')
	}
	if receipt.artifacts.len != receipt.artifact_paths.len { return error('artifact map coverage differs') }
	for name, sum in receipt.artifacts {
		path := receipt.artifact_paths[name] or { return error('missing artifact path: ' + name) }
		if !hex(sum, 64) || !path.starts_with(run + '/') || os.real_path(path) != path { return error('unsafe artifact path or hash: ' + name) }
		regular(path)!
		if digest(path)! != sum { return error('artifact digest differs: ' + name) }
	}
	for name in inputs { if name !in receipt.artifacts { return error('missing input artifact: ' + name) } }
	for name in ['guest', 'tone', 'package-cli', 'account-cli', 'session-cli', 'authd', 'kernel', 'sandbox'] {
		target_elf(receipt.artifact_paths[name], arch)!
	}
	admit_kernel(run, receipt, arch, synthetic)!
	admit_cross(run, receipt, arch)!
	for name in metadata {
		if name !in receipt.artifacts || receipt.artifact_paths[name] != run + '/' + name + '.json' {
			return error('missing or misplaced inventory artifact: ' + name)
		}
	}
	mut source := map[string]string{}
	for tree in trees { inventory(receipt.source_root, tree, mut source)! }
	for file in files { regular(receipt.source_root + '/' + file)!; source[file] = digest(receipt.source_root + '/' + file)! }
	if source != receipt.sources { return error('complete source inventory differs') }
	for name, expected in embedded() {
		if source[name] != sha256.sum(expected.bytes()).hex() { return error('embedded source differs: ' + name) }
	}
	for kind in ['source', 'generated', 'input'] {
		before := json2.decode[map[string]string](bounded(receipt.artifact_paths[kind + '-before'])!)!
		after := json2.decode[map[string]string](bounded(receipt.artifact_paths[kind + '-after'])!)!
		if before.len == 0 || before != after { return error(kind + ' pre/post inventory differs') }
		if kind == 'source' {
			if before != source { return error('source inventory receipt differs') }
		} else if kind == 'generated' {
			if before.len != generated.len { return error('incomplete generated inventory') }
			for name in generated { if name !in before { return error('missing generated source: ' + name) } }
			for name, sum in before {
				if !relative(name) || !hex(sum, 64) || os.real_path(run + '/' + name) != run + '/' + name { return error('invalid generated inventory entry') }
				regular(run + '/' + name)!
				if digest(run + '/' + name)! != sum { return error('generated source digest differs: ' + name) }
			}
		} else {
			for name in inputs { if name !in before { return error('incomplete input inventory: ' + name) } }
			for name, _ in receipt.artifacts {
				if name !in metadata && !raw_artifact(name) && name !in before { return error('incomplete input inventory: ' + name) }
			}
			for name, sum in before {
				if name in metadata || raw_artifact(name) || receipt.artifacts[name] != sum { return error('input inventory receipt differs: ' + name) }
			}
			mut retained_inputs := map[string]string{}
			input_inventory(run + '/inputs', '', mut retained_inputs)!
			for name, sum in retained_inputs {
				if before[name] != sum || receipt.artifact_paths[name] != run + '/inputs/' + name.all_after('input/') {
					return error('complete retained input inventory differs: ' + name)
				}
			}
			for name, _ in before {
				if name.starts_with('input/') && name !in retained_inputs { return error('inventoried retained input is absent: ' + name) }
			}
		}
	}
	mut regions := map[string][]audiotest.Region{}
	for scenario in ['basic', 'lifecycle', 'seat'] {
		state := run + '/run/packages-audio-' + scenario
		for suffix, name in {'outcome': 'outcome.json', 'serial': 'serial.log', 'wav': 'sound.wav', 'qemu-log': 'qemu.log', 'qmp-log': 'qmp.log'} {
			if receipt.artifact_paths[scenario + '-' + suffix] != state + '/' + name { return error('scenario artifact path differs: ' + scenario + '-' + suffix) }
		}
		outcome := json2.decode[Outcome](bounded(state + '/outcome.json')!)!
		if !outcome.passed || outcome.interrupted || outcome.reason != '' || outcome.scenario != 'packages-audio-' + scenario
			|| outcome.state != state || !math.is_finite(outcome.seconds) || outcome.seconds <= 0 || outcome.seconds > 300 {
			return error('raw hardware outcome did not pass: ' + scenario)
		}
		serial(state + '/serial.log', scenario)!
		admit_shutdown(state + '/qmp.log')!
		recording := audiotest.read(state + '/sound.wav')!
		frequencies := match scenario { 'basic' { [440, 660, 880] } 'lifecycle' { [440, 660, 880, 440] } else { [440, 880] } }
		tone_regions := recording.check_sequence(frequencies.map(audiotest.Tone{ frequency: f64(it) }))!
		for index in 1 .. tone_regions.len { recording.require_gap(tone_regions[index - 1], tone_regions[index], 1, 0.04)! }
		if tone_regions[0].start_frame < 48000 || recording.seconds() - f64(tone_regions.last().end_frame) / 48000 < 1 {
			return error('recording lacks one-second leading or trailing quiet: ' + scenario)
		}
		recording.require_quiet(0, f64(tone_regions[0].start_frame) / 48000 - 0.04, 64)!
		recording.require_quiet(f64(tone_regions.last().end_frame) / 48000 + 0.04, recording.seconds(), 64)!
		regions[scenario] = tone_regions
	}
	os.mkdir_all(out)!
	os.write_file(out + '/retained.json', json2.encode(Retained{ architecture: arch, platform: platform,
		qualification: digest(run + '/qualification.json')!, retainer: digest(os.executable())!, regions: regions }) + '\n')!
	println('AUDIO PORTAL RETAIN PASS architecture=' + arch + ' platform=' + platform)
}

fn main() {
	synthetic := os.args.len == 5 && os.args[1] == '--self-test'
	args := if synthetic { os.args[2..] } else { os.args[1..] }
	if args.len != 3 { eprintln('use [--self-test] RUN_DIRECTORY NEW_OUTPUT_DIRECTORY aarch64|x86_64'); exit(1) }
	retain(os.real_path(args[0]), os.abs_path(args[1]), args[2], synthetic) or { eprintln(err); exit(1) }
}
