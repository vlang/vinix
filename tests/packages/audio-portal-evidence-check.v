// SPDX-License-Identifier: GPL-2.0-or-later
// Mutate detached evidence copies. Every admission/refusal remains active with -prod.
module main

import crypto.sha256
import json2
import math
import os
import tests.packages.audioinputs
import tests.packages.audiotest

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
	format int = 1
	source_revision string
	source_patch_path string = 'source.patch'
	source_patch_sha256 string
	source_inventory_path string = 'source-inputs.sha256'
	source_inventory_sha256 string
	critical_sources map[string]string
	kernels map[string]KernelBuild
}

struct Control {
	name string
	code int
	output string
}

struct Report {
	format int = 1
	result string = 'PASS'
	qualification string
	retainer string
	checker string
	platform string
	controls []Control
}

fn retain_args(run string, out string, arch string, synthetic bool) []string {
	return if synthetic { ['--self-test', run, out, arch] } else { [run, out, arch] }
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

fn call(program string, args []string) Control {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(args)
	child.set_redirect_stdio()
	child.run()
	output := child.stdout_slurp() + child.stderr_slurp()
	child.wait()
	return Control{ code: child.code, output: output }
}

fn linked(source string, target string) ! {
	if os.exists(target) { return }
	if (os.lstat(source)!).mode & 0o170000 != 0o100000 { return error('clone requires regular source') }
	os.mkdir_all(os.dir(target))!
	os.link(source, target)!
}

// Never write through a hard link: detach before replacing any mutated bytes.
fn replace(path string, bytes []u8) ! {
	if os.exists(path) || os.is_link(path) { os.rm(path)! }
	os.mkdir_all(os.dir(path))!
	os.write_file_array(path, bytes)!
}

fn save(work string, receipt Receipt) ! {
	replace(work + '/qualification.json', (json2.encode(receipt) + '\n').bytes())!
}

fn seal_artifact(work string, receipt Receipt, name string, bytes []u8) !Receipt {
	path := receipt.artifact_paths[name] or { return error('no mutation artifact: ' + name) }
	if !path.starts_with(work + '/') { return error('mutation escaped evidence copy') }
	replace(path, bytes)!
	mut sums := receipt.artifacts.clone()
	for key, target in receipt.artifact_paths { if target == path { sums[key] = digest(path)! } }
	updated := Receipt{ ...receipt, artifacts: sums }
	save(work, updated)!
	return updated
}

fn clone(original string, work string, receipt Receipt) !Receipt {
	os.mkdir_all(work)!
	mut paths := map[string]string{}
	for name, path in receipt.artifact_paths {
		if !path.starts_with(original + '/') { return error('original artifact is outside retained run') }
		paths[name] = work + path[original.len..]
		linked(path, paths[name])!
	}
	for name, _ in receipt.sources { linked(receipt.source_root + '/' + name, work + '/inputs/source/' + name)! }
	generated := json2.decode[map[string]string](os.read_file(receipt.artifact_paths['generated-before'])!)!
	for name, _ in generated {
		if name.starts_with('/') || '..' in name.split('/') { return error('unsafe generated clone path') }
		linked(original + '/' + name, work + '/' + name)!
	}
	mut updated := Receipt{ ...receipt, source_root: work + '/inputs/source', artifact_paths: paths }
	save(work, updated)!
	for scenario in ['basic', 'lifecycle', 'seat'] {
		key := scenario + '-outcome'
		// Only the retained absolute state path changes; keep every raw outcome field.
		text := os.read_file(paths[key])!
		updated = seal_artifact(work, updated, key, text.replace(original + '/run/', work + '/run/').bytes())!
	}
	// Rebase the explicitly observed frozen-root argument only in this detached
	// positive-control copy; the original compiler diagnostic remains untouched.
	for name in audioinputs.trace_files() {
		key := 'trace/' + name
		trace := os.read_file(paths[key])!
		object := audioinputs.trace_object(original, name)!
		source := if name == 'sandbox-build/build.log' { original + '/sandbox-build/sandbox.c' } else { object[..object.len - 2] + '.c' }
		updated = seal_artifact(work, updated, key, trace.replace(original + '/inputs/cross-sysroot', work + '/inputs/cross-sysroot').replace(original + '/inputs/cross-gcc', work + '/inputs/cross-gcc').replace(original + '/inputs/source', work + '/inputs/source').replace(object, audioinputs.trace_object(work, name)!).replace(source + ':', work + source[original.len..] + ':').bytes())!
	}
	for key in ['input-before', 'input-after'] {
		mut inventory := json2.decode[map[string]string](os.read_file(paths[key])!)!
		for name, _ in paths {
			if name == 'cross-search.log' || name.starts_with('trace/') { inventory[name] = updated.artifacts[name] }
		}
		updated = seal_artifact(work, updated, key, json2.encode(inventory).bytes())!
	}
	return updated
}

fn le16(value int) []u8 { return [u8(value), u8(value >> 8)] }
fn le32(value int) []u8 { return [u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24)] }

fn encode(samples []i16) []u8 {
	mut bytes := 'RIFF'.bytes()
	bytes << le32(36 + samples.len * 2)
	bytes << 'WAVEfmt '.bytes()
	bytes << le32(16)
	for value in [1, 2] { bytes << le16(value) }
	bytes << le32(48000)
	bytes << le32(192000)
	bytes << le16(4)
	bytes << le16(16)
	bytes << 'data'.bytes()
	bytes << le32(samples.len * 2)
	for sample in samples { bytes << le16(int(u16(sample))) }
	return bytes
}

fn mutate(work string, receipt Receipt, name string) !string {
	serial := receipt.artifact_paths['basic-serial']
	if name == 'forged-header-origin' {
		mut origins := json2.decode[map[string]string](os.read_file(receipt.artifact_paths['input-origins'])!)!
		origins['v-thirdparty/forged.h'] = '/original/foreign.h'
		updated := seal_artifact(work, receipt, 'input-origins', json2.encode(origins).bytes())!
		key := 'trace/tone-build/build.log'
		text := os.read_file(receipt.artifact_paths[key])!
		seal_artifact(work, updated, key, (text + '. /original/foreign.h\n').bytes())!
		return 'uncaptured original V header input'
	}
	if name in ['relative-selected-object', 'foreign-cc-object'] {
		key := 'trace/tone-build/build.log'
		text := os.read_file(receipt.artifact_paths[key])!
		seal_artifact(work, receipt, key, (text + if name == 'relative-selected-object' { 'uncaptured.o\n' } else { '/original/ccforeign.o\n' }).bytes())!
		return if name == 'relative-selected-object' { 'relative selected target link input' } else { 'uncaptured selected target link input' }
	}
	if name == 'missing-target-object' {
		mut paths := receipt.artifact_paths.clone()
		mut sums := receipt.artifacts.clone()
		paths.delete('trace-object/tone-build/build.log')
		sums.delete('trace-object/tone-build/build.log')
		save(work, Receipt{ ...receipt, artifact_paths: paths, artifacts: sums })!
		return 'missing exact generated target object'
	}
	if name in ['original-selected-header', 'original-selected-startup', 'missing-selected-libc'] {
		key := 'trace/tone-build/build.log'
		text := os.read_file(receipt.artifact_paths[key])!
		changed := match name {
			'original-selected-header' { text.replace('. ' + work + '/inputs/cross-sysroot/include/stdint.h', '. /original/include/stdint.h') }
			'original-selected-startup' { text.replace(work + '/inputs/cross-sysroot/lib/crt1.o', '/original/lib/crt1.o') }
			else { text.replace(work + '/inputs/cross-sysroot/lib/libc.a\n', '') }
		}
		if changed == text { return error('selected target mutation did not change trace') }
		seal_artifact(work, receipt, key, changed.bytes())!
		return match name {
			'original-selected-header' { 'uncaptured selected header' }
			'original-selected-startup' { 'uncaptured selected target link input' }
			else { 'missing captured selected target input' }
		}
	}
	if name == 'missing-target-trace' {
		mut paths := receipt.artifact_paths.clone()
		mut sums := receipt.artifacts.clone()
		paths.delete('trace/guest-build/build.log')
		sums.delete('trace/guest-build/build.log')
		save(work, Receipt{ ...receipt, artifact_paths: paths, artifacts: sums })!
		return 'missing exact target compiler trace'
	}
	if name == 'wrong-cross-trace' {
		text := os.read_file(receipt.artifact_paths['cross-search.log'])!
		seal_artifact(work, receipt, 'cross-search.log', text.replace('--sysroot=' + work + '/inputs/cross-sysroot', '--sysroot=' + work + '/inputs/cross-sysroot-foreign').bytes())!
		return 'cross compiler trace lacks retained frozen sysroot'
	}
	if name == 'wrong-cross-probe' {
		mut bytes := os.read_bytes(receipt.artifact_paths['cross-probe'])!
		bytes[18] = if bytes[18] == 183 { 62 } else { 183 }
		seal_artifact(work, receipt, 'cross-probe', bytes)!
		return 'requires selected-architecture ELF64 input'
	}
	if name == 'incomplete-cross-sysroot' {
		mut files := json2.decode[map[string]string](os.read_file(receipt.artifact_paths['cross-sysroot-files'])!)!
		if files.len < 2 { return error('baseline sysroot lacks multiple files') }
		files.delete(files.keys()[0])
		seal_artifact(work, receipt, 'cross-sysroot-files', json2.encode(files).bytes())!
		return 'captured cross sysroot file coverage differs'
	}
	if name in ['changed-kernel-source', 'wrong-kernel-identity'] {
		path := if name == 'changed-kernel-source' { 'input/kernel-evidence/source/kernel/socket/unix/unix.v' } else { 'kernel' }
		mut bytes := os.read_bytes(receipt.artifact_paths[path])!
		bytes[bytes.len - 1] ^= 1
		seal_artifact(work, receipt, path, bytes)!
		return if name == 'changed-kernel-source' { 'sealed kernel input differs' } else { 'native audio kernel differs from reviewed sealed ELF' }
	}
	if name in ['missing-marker', 'duplicate-marker', 'reordered-marker'] {
		marker := 'AUDIO CONTROL absent-permission refused PASS'
		text := os.read_file(serial)!
		changed := match name {
			'missing-marker' { text.replace(marker, '') }
			'duplicate-marker' { text.replace(marker, marker + '\n' + marker) }
			else { text.replace(marker, '__REORDER__').replace('AUDIO CONTROL organization-policy refused PASS', marker).replace('__REORDER__', 'AUDIO CONTROL organization-policy refused PASS') }
		}
		seal_artifact(work, receipt, 'basic-serial', changed.bytes())!
		return 'ordered exact serial markers differ'
	}
	if name in ['wrong-waveform', 'silent-channel', 'extra-tone', 'unfinalized-wave', 'short-quiet-gap', 'short-leading-quiet'] {
		path := receipt.artifact_paths['basic-wav']
		recording := audiotest.read(path)!
		regions := recording.check_sequence([audiotest.Tone{ frequency: 440 }, audiotest.Tone{ frequency: 660 }, audiotest.Tone{ frequency: 880 }])!
		mut samples := recording.samples.clone()
		if name == 'short-quiet-gap' {
			start := (regions[0].end_frame + 9600) * 2
			end := regions[1].start_frame * 2
			if start >= end { return error('baseline has no removable quiet gap') }
			mut shortened := samples[..start].clone()
			shortened << samples[end..]
			samples = shortened.clone()
		} else if name == 'short-leading-quiet' {
			drop := (regions[0].start_frame - 9600) * 2
			if drop <= 0 { return error('baseline has no removable leading quiet') }
			samples = samples[drop..].clone()
		} else if name == 'wrong-waveform' {
			for frame in regions[0].start_frame .. regions[0].end_frame {
				value := i16(math.sin(2 * math.pi * 700 * f64(frame) / 48000) * 12000)
				samples[frame * 2] = value
				samples[frame * 2 + 1] = value
			}
		} else if name == 'silent-channel' {
			for frame in 0 .. samples.len / 2 { samples[frame * 2 + 1] = 0 }
		} else if name == 'extra-tone' {
			samples << []i16{len: 57600 * 2}
			for frame in 0 .. 48000 {
				value := i16(math.sin(2 * math.pi * 440 * f64(frame) / 48000) * 12000)
				samples << value
				samples << value
			}
			samples << []i16{len: 57600 * 2}
		}
		mut bytes := encode(samples)
		if name == 'unfinalized-wave' { for i in 40 .. 44 { bytes[i] = 0 } }
		seal_artifact(work, receipt, 'basic-wav', bytes)!
		return match name {
			'wrong-waveform', 'silent-channel' { 'frequency' }
			'extra-tone' { 'audible runs' }
			'short-quiet-gap' { 'recorded quiet gap is shorter' }
			'short-leading-quiet' { 'recording lacks one-second leading or trailing quiet' }
			else { 'nonempty complete stereo data' }
		}
	}
	if name in ['resealed-source', 'resealed-input-source'] {
		path := if name == 'resealed-input-source' { 'tests/packages/audioinputs/tree.v' } else { 'tools/packages/audiopcm/client.v' }
		file := receipt.source_root + '/' + path
		replace(file, (os.read_file(file)! + '\n// changed source refusal control\n').bytes())!
		mut sums := receipt.sources.clone()
		sums[path] = digest(file)!
		mut updated := Receipt{ ...receipt, sources: sums }
		save(work, updated)!
		for key in ['source-before', 'source-after'] { updated = seal_artifact(work, updated, key, json2.encode(sums).bytes())! }
		return 'embedded source differs'
	}
	if name == 'resealed-artifact' {
		path := receipt.artifact_paths['guest']
		mut bytes := os.read_bytes(path)!
		if bytes.len == 0 { return error('empty guest input') }
		bytes[bytes.len - 1] ^= 1
		seal_artifact(work, receipt, 'guest', bytes)!
		return 'input inventory receipt differs'
	}
	if name == 'incomplete-inputs' {
		mut updated := receipt
		for key in ['input-before', 'input-after'] {
			mut sums := json2.decode[map[string]string](os.read_file(receipt.artifact_paths[key])!)!
			sums.delete('session-cli')
			updated = seal_artifact(work, updated, key, json2.encode(sums).bytes())!
		}
		return 'incomplete input inventory'
	}
	if name == 'incomplete-retained-input' {
		key := 'input/sandbox-c'
		mut sums := receipt.artifacts.clone()
		mut paths := receipt.artifact_paths.clone()
		sums.delete(key)
		paths.delete(key)
		mut updated := Receipt{ ...receipt, artifacts: sums, artifact_paths: paths }
		save(work, updated)!
		for phase in ['input-before', 'input-after'] {
			mut values := json2.decode[map[string]string](os.read_file(paths[phase])!)!
			values.delete(key)
			updated = seal_artifact(work, updated, phase, json2.encode(values).bytes())!
		}
		return 'complete retained input inventory differs'
	}
	if name == 'generated-mismatch' {
		values := json2.decode[map[string]string](os.read_file(receipt.artifact_paths['generated-before'])!)!
		file := work + '/' + values.keys()[0]
		replace(file, (os.read_file(file)! + '\n/* changed generated refusal control */\n').bytes())!
		return 'generated source digest differs'
	}
	if name in ['failed-outcome', 'wrong-shutdown', 'duplicate-shutdown'] {
		key := if name == 'failed-outcome' { 'basic-outcome' } else { 'basic-qmp-log' }
		text := os.read_file(receipt.artifact_paths[key])!
		mut changed := ''
		if name == 'failed-outcome' {
			mut value := json2.decode[json2.Any](text)!.as_map()
			value['passed'] = json2.Any(false)
			changed = json2.encode(value)
		} else if name == 'wrong-shutdown' { changed = text.replace('guest-shutdown', 'host-qmp-quit') }
		else {
			line := text.split_into_lines().filter(it.contains('"SHUTDOWN"'))
			if line.len != 1 { return error('cannot locate exact shutdown control') }
			changed = text + '\n' + line[0] + '\n'
		}
		seal_artifact(work, receipt, key, changed.bytes())!
		return match name { 'failed-outcome' { 'raw hardware outcome did not pass' } 'wrong-shutdown' { 'requires guest-initiated QMP shutdown' } else { 'duplicated guest QMP shutdown' } }
	}
	if name == 'missing-artifact' {
		mut sums := receipt.artifacts.clone()
		mut paths := receipt.artifact_paths.clone()
		sums.delete('seat-wav')
		paths.delete('seat-wav')
		save(work, Receipt{ ...receipt, artifacts: sums, artifact_paths: paths })!
		return 'scenario artifact path differs'
	}
	return error('unknown evidence control: ' + name)
}

fn run(program string, original string, proof string, arch string, synthetic bool) ! {
	$if prod {} $else { return error('compile audio evidence checker with -prod') }
	if digest(@FILE)! != sha256.sum($embed_file('audio-portal-evidence-check.v').to_string().bytes()).hex() { return error('evidence checker changed after compilation') }
	if os.exists(proof) || os.is_link(proof) || proof.starts_with(original + '/') { return error('requires new proof directory outside original run') }
	os.mkdir_all(proof)!
	original_digest := digest(original + '/qualification.json')!
	receipt := json2.decode[Receipt](os.read_file(original + '/qualification.json')!)!
	baseline := call(program, retain_args(original, proof + '/baseline', arch, synthetic))
	if baseline.code != 0 { return error('baseline refused: ' + baseline.output) }
	mut controls := [Control{ ...baseline, name: 'baseline' }]
	clone(original, proof + '/clone', receipt)!
	cloned := call(program, retain_args(proof + '/clone', proof + '/clone-retained', arch, synthetic))
	if cloned.code != 0 { return error('unmodified rebased clone refused: ' + cloned.output) }
	controls << Control{ ...cloned, name: 'unmodified-rebased-clone' }
	for name in ['wrong-waveform', 'silent-channel', 'extra-tone', 'unfinalized-wave', 'short-quiet-gap', 'short-leading-quiet',
		'missing-marker', 'duplicate-marker', 'reordered-marker', 'resealed-source',
		'resealed-input-source', 'wrong-cross-trace', 'wrong-cross-probe', 'incomplete-cross-sysroot',
		'original-selected-header', 'original-selected-startup', 'missing-selected-libc', 'missing-target-trace',
		'relative-selected-object', 'foreign-cc-object', 'missing-target-object',
		'forged-header-origin',
		'resealed-artifact', 'changed-kernel-source', 'wrong-kernel-identity', 'incomplete-inputs', 'incomplete-retained-input', 'generated-mismatch', 'failed-outcome',
		'wrong-shutdown', 'duplicate-shutdown', 'missing-artifact'] {
		work := proof + '/' + name
		copied := clone(original, work, receipt)!
		reason := mutate(work, copied, name)!
		result := call(program, retain_args(work, work + '/retained', arch, synthetic))
		if result.code == 0 || !result.output.contains(reason) { return error('control ' + name + ' did not refuse for ' + reason + ': ' + result.output) }
		controls << Control{ ...result, name: name }
	}
	if digest(original + '/qualification.json')! != original_digest { return error('original receipt changed during controls') }
	for name, sum in receipt.artifacts {
		if digest(receipt.artifact_paths[name])! != sum { return error('original artifact changed during controls: ' + name) }
	}
	for name, sum in receipt.sources {
		if digest(receipt.source_root + '/' + name)! != sum { return error('original source changed during controls: ' + name) }
	}
	os.write_file(proof + '/evidence-controls.json', json2.encode(Report{ qualification: original_digest, platform: receipt.platform,
		retainer: digest(program)!, checker: digest(os.executable())!, controls: controls }) + '\n')!
	println('AUDIO PORTAL EVIDENCE PASS controls=' + controls.len.str() + ' platform=' + receipt.platform)
}

fn frozen_tree(root string, target string, tree string, mut sources map[string]string) ! {
	for name in os.ls(root + '/' + tree)! {
		path := tree + '/' + name
		mode := (os.lstat(root + '/' + path)!).mode & 0o170000
		if mode == 0o040000 { frozen_tree(root, target, path, mut sources)! }
		else if mode == 0o100000 && !name.ends_with('_test.v') {
			os.mkdir_all(os.dir(target + '/' + path))!
			os.cp(root + '/' + path, target + '/' + path)!
			sources[path] = digest(target + '/' + path)!
		} else if mode != 0o100000 { return error('nonregular self-test source: ' + path) }
	}
}

fn sample_serial(scenario string) string {
	login := 'AUDIO LOGIN uid=1000 home=/home/alex supplementary-users PASS'
	mut lines := ['HWTEST START packages-audio-' + scenario, 'AUDIO SETUP signed tone and noaudio installed PASS']
	if scenario == 'basic' {
		lines << 'AUDIO CONTROL group0-forged-account-action refused PASS'
		for run, mode in {'missing': 'refuse', 'policy': 'tone', 'forged': 'forged', 'service': 'service', 'changed': 'changed', 'sequence': 'sequence'} {
			lines << login
			if run != 'policy' { lines << ['AUDIO PAYLOAD ${run} uid=1000 groups=0 signed-context direct-device-refused PASS', 'AUDIO PAYLOAD ${run} ${mode} PASS'] }
			lines << match run {
				'missing' { 'AUDIO CONTROL absent-permission refused PASS' }
				'policy' { 'AUDIO CONTROL organization-policy refused PASS' }
				'forged' { 'AUDIO CONTROL forged-endpoint refused PASS' }
				'sequence' { 'AUDIO PCM exact sequence 440 660 880 PASS' }
				else { 'AUDIO CONTROL ${run} refused and cleanup PASS' }
			}
		}
	} else if scenario == 'lifecycle' {
		for target in ['client', 'launcher'] {
			lines << [login, 'AUDIO PAYLOAD ${target} uid=1000 groups=0 signed-context direct-device-refused PASS', login,
				'AUDIO PAYLOAD after${target} uid=1000 groups=0 signed-context direct-device-refused PASS',
				'AUDIO PAYLOAD after${target} tone PASS', 'AUDIO LIFECYCLE ${target}-death cleanup and relaunch PASS']
		}
	} else {
		lines << [login, 'AUDIO PAYLOAD seat uid=1000 groups=0 signed-context direct-device-refused PASS', 'AUDIO PAYLOAD seat seat PASS',
			'AUDIO SEAT real-other-login inactive-write-refused active-relaunch PASS']
	}
	lines << 'HWTEST PASS packages-audio-' + scenario
	return lines.join('\n') + '\n'
}

fn synthetic_kernel_file(raw string, name string, bytes []u8, mut paths map[string]string,
	mut sums map[string]string, mut input_sums map[string]string) !string {
	path := raw + '/inputs/kernel-evidence/' + name
	replace(path, bytes)!
	sum := digest(path)!
	key := 'input/kernel-evidence/' + name
	paths[key] = path
	sums[key] = sum
	input_sums[key] = sum
	return sum
}

fn synthetic_kernel(raw string, mut paths map[string]string, mut sums map[string]string,
	mut input_sums map[string]string) ! {
	patch := synthetic_kernel_file(raw, 'source.patch', 'SYNTHETIC KERNEL CONTROL\n'.bytes(), mut paths, mut sums, mut input_sums)!
	mut critical := map[string]string{}
	mut inventory := []string{}
	for source in ['kernel/socket/public/public.v', 'kernel/socket/unix/unix.v', 'kernel/socket/socket.v'] {
		critical[source] = synthetic_kernel_file(raw, 'source/' + source, 'SYNTHETIC KERNEL SOURCE\n'.bytes(), mut paths, mut sums, mut input_sums)!
		inventory << critical[source] + '  ' + source
	}
	index := synthetic_kernel_file(raw, 'source-inputs.sha256', (inventory.join('\n') + '\n').bytes(), mut paths, mut sums, mut input_sums)!
	v := synthetic_kernel_file(raw, 'toolchain/v', 'SYNTHETIC V\n'.bytes(), mut paths, mut sums, mut input_sums)!
	cc := synthetic_kernel_file(raw, 'toolchain/clang', 'SYNTHETIC CLANG\n'.bytes(), mut paths, mut sums, mut input_sums)!
	ld := synthetic_kernel_file(raw, 'toolchain/ld.lld', 'SYNTHETIC LINKER\n'.bytes(), mut paths, mut sums, mut input_sums)!
	mut kernels := map[string]KernelBuild{}
	for arch in ['aarch64', 'x86_64'] {
		mut elf := []u8{len: 64}
		for i, byte in [u8(127), `E`, `L`, `F`, 2, 1, 1] { elf[i] = byte }
		elf[18] = if arch == 'aarch64' { 183 } else { 62 }
		e := synthetic_kernel_file(raw, 'kernel-' + arch + '/bin/vinix', elf, mut paths, mut sums, mut input_sums)!
		c := synthetic_kernel_file(raw, 'kernel-' + arch + '/obj/blob.c', '/* SYNTHETIC KERNEL C */\n'.bytes(), mut paths, mut sums, mut input_sums)!
		log := synthetic_kernel_file(raw, 'build-' + arch + '-current-v.log', 'SYNTHETIC BUILD LOG\n'.bytes(), mut paths, mut sums, mut input_sums)!
		kernels[arch] = KernelBuild{ elf_path: 'kernel-' + arch + '/bin/vinix', elf_sha256: e,
			generated_c_path: 'kernel-' + arch + '/obj/blob.c', generated_c_sha256: c,
			build_log_path: 'build-' + arch + '-current-v.log', build_log_sha256: log,
			build_flags: ['ARCH=' + arch, 'ALLOC_TRACK=1', 'PROD=true', if arch == 'aarch64' { 'LIMINE_MP=1' } else { 'LIMINE_MP=0' }],
			compiler_path: 'toolchain/v', compiler_sha256: v, clang_path: 'toolchain/clang', clang_sha256: cc,
			linker_path: 'toolchain/ld.lld', linker_sha256: ld }
	}
	seal := KernelSeal{ source_revision: '0000000000000000000000000000000000000000',
		source_patch_sha256: patch, source_inventory_sha256: index, critical_sources: critical, kernels: kernels }
	sum := synthetic_kernel_file(raw, 'kernel-seal.json', json2.encode(seal).bytes(), mut paths, mut sums, mut input_sums)!
	paths['kernel-seal'] = raw + '/inputs/kernel-evidence/kernel-seal.json'
	sums['kernel-seal'] = sum
	input_sums['kernel-seal'] = sum
}

fn synthetic_cross(raw string, mut paths map[string]string, mut sums map[string]string,
	mut input_sums map[string]string) ! {
	root := '/synthetic/original-sysroot'
	mut files := {'lib/libc.so': root + '/lib/libc.so', 'lib/loader': root + '/lib/libc.so'}
	for name in ['lib/crt1.o', 'lib/crti.o', 'lib/crtn.o', 'lib/libc.a', 'include/stdint.h'] { files[name] = root + '/' + name }
	for name, bytes in {
		'cross-adapter-build': 'SYNTHETIC ADAPTER BUILD\n'
		'cross-probe-generate.log': 'SYNTHETIC PROBE V GENERATION\n'
		'cross-probe.c': '/* SYNTHETIC PROBE */\n'
		'input-origins': '{}'
		'cross-sysroot-files': json2.encode(files)
		'cross-sysroot-links': json2.encode({'lib/loader': 'libc.so'})
		'cross-sysroot-root': json2.encode({'root': root})
	} {
		filename := match name {
			'cross-probe.c', 'cross-probe-generate.log', 'cross-search.log' { name }
			'cross-adapter-build' { 'cross-adapter-build.log' }
			'input-origins' { 'original-input-paths.json' }
			else { name + '.json' }
		}
		path := raw + '/' + filename
		replace(path, bytes.bytes())!
		paths[name] = path
		sums[name] = digest(path)!
		input_sums[name] = sums[name]
	}
	for name, _ in files {
		key := 'cross-sysroot/' + name
		path := raw + '/inputs/' + key
		replace(path, 'SYNTHETIC LIBC\n'.bytes())!
		for alias in [key, 'input/' + key] {
			paths[alias] = path
			sums[alias] = digest(path)!
			input_sums[alias] = sums[alias]
		}
	}
	for name in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] {
		key := 'cross-gcc/' + name
		path := raw + '/inputs/' + key
		replace(path, 'SYNTHETIC GCC INPUT\n'.bytes())!
		paths['input/' + key] = path
		sums['input/' + key] = digest(path)!
		input_sums['input/' + key] = sums['input/' + key]
	}
	mut trace := 'SYNTHETIC TRACE --sysroot=' + raw + '/inputs/cross-sysroot\n#include <...> search starts here:\n'
	for directory in ['/cross-gcc/include', '/cross-gcc/include-fixed', '/cross-sysroot/include'] { trace += ' ' + raw + '/inputs' + directory + '\n' }
	trace += 'End of search list.\n. ' + raw + '/inputs/cross-sysroot/include/stdint.h\n'
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a'] { trace += raw + '/inputs/cross-sysroot/lib/' + name + '\n' }
	for name in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] { trace += raw + '/inputs/cross-gcc/' + name + '\n' }
	for name in audioinputs.trace_files() {
		path := raw + '/' + name
		object := audioinputs.trace_object(raw, name)!
		replace(object, 'SYNTHETIC GENERATED OBJECT\n'.bytes())!
		paths['trace-object/' + name] = object
		sums['trace-object/' + name] = digest(object)!
		input_sums['trace-object/' + name] = sums['trace-object/' + name]
		advice := if name == 'cross-search.log' { raw + '/cross-probe.c:12:3: warning: synthetic exact-source diagnostic\n' } else { '' }
		replace(path, (trace + object + '\n' + advice).bytes())!
		key := 'trace/' + name
		paths[key] = path
		sums[key] = digest(path)!
		input_sums[key] = sums[key]
		if name == 'cross-search.log' { paths[name] = path; sums[name] = sums[key]; input_sums[name] = sums[key] }
	}
}

// Synthetic files use a separate platform accepted only through the explicit self-test switch.
fn self_test(program string, out string, arch string) ! {
	$if prod {} $else { return error('compile audio evidence checker with -prod') }
	if digest(@FILE)! != sha256.sum($embed_file('audio-portal-evidence-check.v').to_string().bytes()).hex() { return error('evidence checker changed after compilation') }
	if os.exists(out) || os.is_link(out) { return error('requires new synthetic control output') }
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported self-test architecture') }
	root := os.dir(os.dir(os.dir(@FILE)))
	raw := out + '/synthetic-raw'
	mut sources := map[string]string{}
	for tree in ['tools/packages', 'tools/accounts', 'tools/security-events', 'tools/keyring', 'build-support/native-compat-tools/compathost',
		'tools/sandbox', 'tests/qemu-core/fixturehost', 'tests/native-guest-tools/guesthost', 'tests/linuxkpi/hosttest',
		'tests/native-policy-tools/nativepolicy', 'tests/native-policy-tools/cpufixture', 'tests/host-policy/policyhost',
		'tests/hardware-platform/hwhost', 'tests/packages/audio-portal-guest', 'tests/packages/audio-portal-tone', 'tests/packages/audiotest',
		'tests/packages/audioinputs', 'tests/packages/audioprepare'] {
		frozen_tree(root, raw + '/inputs/source', tree, mut sources)!
	}
	for path in ['tests/packages/audio-portal-runtime-check.v', 'tests/packages/audio-portal-retain.v', 'tests/packages/audio-portal-evidence-check.v',
		'tests/packages/audio-portal-wave-check.v', 'build-support/native-compat-tools/main.v', 'build-support/security-tools/compile-v-core',
		'build-support/run-v-tool.sh', 'build-support/find-v.sh', 'tests/packages/audio-cross-cc.v', 'tests/packages/audio-input-check.v',
		'tests/packages/audio-cross-probe.v', 'tests/packages/audio-portal-prepare-check.v', 'build-support/limine.conf'] {
		os.mkdir_all(os.dir(raw + '/inputs/source/' + path))!
		os.cp(root + '/' + path, raw + '/inputs/source/' + path)!
		sources[path] = digest(raw + '/inputs/source/' + path)!
	}
	mut paths := map[string]string{}
	mut sums := map[string]string{}
	mut input_sums := map[string]string{}
	for name in ['guest', 'tone', 'package-cli', 'account-cli', 'session-cli', 'authd', 'kernel', 'v', 'clang', 'qemu', 'firmware', 'sandbox', 'sandbox-c',
		'adapter-host-cc', 'cross-backend', 'cross-cc1', 'cross-collect2', 'cross-as', 'cross-ld', 'cross-lto-wrapper', 'cross-lto-plugin', 'cross-adapter', 'cross-probe'] {
		mut bytes := []u8{len: 64}
		for i, byte in [u8(127), `E`, `L`, `F`, 2, 1, 1] { bytes[i] = byte }
		bytes[18] = if arch == 'aarch64' { 183 } else { 62 }
		path := raw + '/inputs/' + name
		replace(path, bytes)!
		paths[name] = path
		sums[name] = digest(path)!
		input_sums[name] = sums[name]
		paths['input/' + name] = path
		sums['input/' + name] = sums[name]
		input_sums['input/' + name] = sums[name]
	}
	synthetic_kernel(raw, mut paths, mut sums, mut input_sums)!
	synthetic_cross(raw, mut paths, mut sums, mut input_sums)!
	mut generated := map[string]string{}
	for path in ['guest-build/init.c', 'tone-build/tone.c', 'tools/program-0/vinix-package.c', 'tools/program-1/vinix-account.c',
		'tools/program-2/vinix-session.c', 'tools/program-3/vinix-authd.c'] {
		replace(raw + '/' + path, '/* SYNTHETIC CONTROL: no native execution claimed. */\n'.bytes())!
		generated[path] = digest(raw + '/' + path)!
	}
	for kind, values in {'source': sources, 'generated': generated, 'input': input_sums} {
		for phase in ['before', 'after'] {
			key := kind + '-' + phase
			path := raw + '/' + key + '.json'
			replace(path, json2.encode(values).bytes())!
			paths[key] = path
			sums[key] = digest(path)!
		}
	}
	finish_synthetic(program, out, raw, arch, sources, paths, sums)!
}

fn finish_synthetic(program string, out string, raw string, arch string, sources map[string]string,
	input_paths map[string]string, input_sums map[string]string) ! {
	mut paths := input_paths.clone()
	mut sums := input_sums.clone()
	for scenario in ['basic', 'lifecycle', 'seat'] {
		state := raw + '/run/packages-audio-' + scenario
		frequencies := match scenario { 'basic' { [440, 660, 880] } 'lifecycle' { [440, 660, 880, 440] } else { [440, 880] } }
		mut samples := []i16{len: 57600 * 2}
		for frequency in frequencies {
			for frame in 0 .. 48000 {
				value := i16(math.sin(2 * math.pi * frequency * f64(frame) / 48000) * 12000)
				samples << value
				samples << value
			}
			samples << []i16{len: 57600 * 2}
		}
		outcome := '{"scenario":"packages-audio-${scenario}","passed":true,"interrupted":false,"seconds":20,"reason":"","state":"${state}"}'
		for suffix, filename in {'outcome': 'outcome.json', 'serial': 'serial.log', 'wav': 'sound.wav', 'qemu-log': 'qemu.log', 'qmp-log': 'qmp.log'} {
			path := state + '/' + filename
			bytes := match suffix {
				'outcome' { outcome.bytes() }
				'serial' { sample_serial(scenario).bytes() }
				'wav' { encode(samples) }
				'qmp-log' { '[  20.000] <- {"event":"SHUTDOWN","data":{"guest":true,"reason":"guest-shutdown"}}\n'.bytes() }
				else { 'SYNTHETIC CONTROL ONLY\n'.bytes() }
			}
			replace(path, bytes)!
			paths[scenario + '-' + suffix] = path
			sums[scenario + '-' + suffix] = digest(path)!
		}
	}
	save(raw, Receipt{ format: 1, architecture: arch, platform: 'synthetic-audio-retainer-control', result: 'PASS', completed_at: 1,
		source_root: raw + '/inputs/source', source_revision: '0000000000000000000000000000000000000000', sources: sources, artifacts: sums, artifact_paths: paths })!
	refused := call(program, [raw, out + '/native-must-refuse', arch])
	if refused.code == 0 || !refused.output.contains('requires complete selected-architecture native audio receipt') { return error('native mode accepted synthetic evidence: ' + refused.output) }
	os.write_file(out + '/synthetic-native-refusal.log', refused.output)!
	run(program, raw, out + '/proof', arch, true)!
}

fn main() {
	if os.args.len == 5 && os.args[1] == '--self-test' {
		self_test(os.real_path(os.args[2]), os.abs_path(os.args[3]), os.args[4]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 5 { eprintln('use RETAINER RUN_DIRECTORY NEW_PROOF_DIRECTORY aarch64|x86_64'); exit(1) }
	run(os.real_path(os.args[1]), os.real_path(os.args[2]), os.abs_path(os.args[3]), os.args[4], false) or { eprintln(err); exit(1) }
}
