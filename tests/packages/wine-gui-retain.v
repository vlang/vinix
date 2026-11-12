// SPDX-License-Identifier: GPL-2.0-or-later
// Independently admit GUI outcome, captures, producer inputs and signed payload.
module main

import crypto.sha256
import encoding.hex
import hwhost
import json2
import os
import stbi
import tests.packages.winesource
import tests.packages.winegui
import tools.packages.pkgcore
import tools.packages.wineadapter
import tools.packages.signing as ed25519

struct Outcome { scenario string passed bool interrupted bool reason string }
struct Baseline { architecture string artifact_paths map[string]string artifacts map[string]string }
struct Receipt {
	format int = 1
	architecture string
	run string
	scope string = 'local-only ordinary signed USER32 calculator on authenticated headless Xvfb; real pointer arithmetic, captured pixels, natural close and fixture retirement; no desktop embedding, broad Wine compatibility, guest shutdown or redistribution acceptance'
	artifacts map[string]string
	auditor_sha256 string
	audit_source_sha256 string
}

fn digest(path string) !string { return winesource.file_digest(path) }
fn hashes(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }
fn argv(path string) ![]string { return json2.decode[[]string](os.read_file(path)!)! }

// This is historical signature/manifest binding. The recorded real package
// launch enforces repository expiry; this audit grants no current catalog
// trust and does not substitute a synthetic clock into a trust API.
fn publisher_binding(run string, namespace string, arch string, state pkgcore.State) ! {
	config := json2.decode[pkgcore.Config](os.read_file(run + '/extras/etc/vinix-packages/config.json')!)!
	if config.architecture != arch || config.repositories.len != 1 || config.repositories[0].id != 'wine-gui'
		|| config.repositories[0].url != 'file://' + namespace + '/publisher' { return error('GUI publisher configuration differs') }
	repository := config.repositories[0]
	key := hex.decode(repository.public_key)!
	signature := hex.decode(os.read_file(run + '/publisher/index.sig')!.trim_space())!
	message := os.read_bytes(run + '/publisher/index.json')!
	defer { unsafe { key.free(); signature.free(); message.free() } }
	if !ed25519.publisher_key_valid(ed25519.PublicKey(key))
		|| !ed25519.verify(ed25519.PublicKey(key), message, signature)! { return error('GUI publisher signature differs') }
	index := json2.decode[pkgcore.Index](message.bytestr())!
	if index.format != 1 || index.repository != repository.id || index.sequence != 1 || index.expires <= 0
		|| index.packages.len != state.packages.len { return error('GUI signed index differs') }
	for installed in state.packages {
		mut matches := 0
		for signed in index.packages {
			signed.validate()!
			if signed.id == installed.package.id && json2.encode(signed) == json2.encode(installed.package) { matches++ }
		}
		if matches != 1 || installed.repository != repository.id || installed.public_key != repository.public_key
			|| installed.sequence != index.sequence { return error('GUI installed manifest differs from signed publisher') }
	}
}

fn require_marker(lines []string, marker string, previous int) !int {
	if lines.filter(it == marker).len != 1 { return error('missing or duplicated GUI marker: ' + marker) }
	position := lines.index(marker)
	if position <= previous { return error('GUI marker order differs') }
	return position
}

fn check() ! {
	$if prod {} $else { return error('compile GUI retainer with -prod') }
	if os.args.len != 4 { return error('usage: wine-gui-retain RUN BASELINE_RETAINER FRESH_OUTPUT') }
	run := os.real_path(os.args[1]); retainer := os.real_path(os.args[2]); out := os.abs_path(os.args[3])
	if os.exists(out) || os.is_link(out) || os.exists(out + '.baseline') { return error('GUI retained output must be fresh') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	for path, source in {
		@FILE: $embed_file('wine-gui-retain.v').to_string()
		root + '/tests/packages/wine-gui-check.v': $embed_file('wine-gui-check.v').to_string()
		root + '/tests/packages/wine-gui/main.v': $embed_file('wine-gui/main.v').to_string()
		root + '/tests/packages/winegui/frame.v': $embed_file('winegui/frame.v').to_string()
	} {
		if digest(path)! != sha256.hexhash(source) { return error('compiled GUI audit source differs: ' + path) }
	}
	outcome := json2.decode[Outcome](os.read_file(run + '/result.json')!)!
	if outcome.scenario != 'packaged-Wine-GUI' || !outcome.passed || outcome.interrupted || outcome.reason != '' {
		return error('requires uninterrupted passing GUI outcome')
	}
	declaration := hashes(run + '/declaration.json')!
	if declaration['diagnostic'] != '' { return error('diagnostic GUI run is not ordinary-host qualification') }
	arch := declaration['architecture']; namespace := declaration['run']; baseline := declaration['baseline']; prepared := declaration['prepared']
	if arch !in ['x86_64', 'aarch64'] || declaration['retainer'] != retainer || declaration['source_root'] != root
		|| !os.is_abs_path(namespace) || !os.is_abs_path(baseline) || !os.is_abs_path(prepared) {
		return error('GUI declaration binding differs')
	}
	inputs := hashes(run + '/inputs.json')!
	if inputs != hashes(run + '/inputs-verified.json')! { return error('GUI verified inventory differs') }
	for path, expected in hashes(run + '/inputs-before-build.json')! {
		if inputs[path] != expected { return error('GUI prebuild inventory differs') }
	}
	for path in [retainer, declaration['compiler'], declaration['controller'], declaration['kernel'], declaration['shell'],
		root + '/tests/packages/wine-gui-check.v', root + '/tests/packages/wine-gui/main.v', root + '/tests/packages/winegui/frame.v'] {
		if path !in inputs || inputs[path] != digest(path)! { return error('missing or changed GUI critical input: ' + path) }
	}
	build := namespace + '/build-guest'
	compiler := declaration['compiler']; sysroot := declaration['sysroot']; gcc := declaration['gcc']
	expected_v := [compiler, '-dump-files', build + '/sources-built.txt', '-backend', 'c', '-prod', '-os', 'linux', '-arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-path', '@vlib|' + root + '|@vmodules', '-o', build + '/guest.c', root + '/tests/packages/wine-gui']
	expected_c := ['/opt/homebrew/opt/llvm/bin/clang', '--target=' + arch + '-linux-musl', '--sysroot=' + sysroot,
		'--gcc-install-dir=' + gcc, '-fuse-ld=lld', '-static-libgcc', '-O1', '-w', '-D_GNU_SOURCE',
		'-fno-stack-protector', '-Wno-error=incompatible-pointer-types', '-L' + sysroot + '/lib',
		'-L' + sysroot + '/usr/lib', '-Wl,-rpath-link,' + sysroot + '/lib', '-Wl,-rpath-link,' + sysroot + '/usr/lib',
		build + '/guest.c', build + '/runtime.c', '-lm', '-lpthread', '-lX11', '-lXtst', '-o', build + '/guest']
	if argv(run + '/build-guest/v.log.argv.json')! != expected_v
		|| argv(run + '/build-guest/cc.log.argv.json')! != expected_c { return error('GUI producer argv differs') }
	mut discovery := expected_v.clone(); discovery[2] = build + '/sources-before.txt'; discovery.insert(1, '-print-watched-files')
	if argv(run + '/build-guest/discover.log.argv.json')! != discovery { return error('GUI discovery argv differs') }
	winesource.admit(run + '/build-guest/sources-before.txt', run + '/build-guest/sources-built.txt', inputs)!
	generated := hashes(run + '/generated-before-boot.json')!
	for name in ['build-guest/guest', 'build-guest/guest.c', 'build-guest/runtime.c', 'build-guest/v.log',
		'build-guest/cc.log', 'build-guest/v.log.argv.json', 'build-guest/cc.log.argv.json',
		'extras/bin/sh', 'extras/usr/bin/vinix-package', 'extras/usr/bin/vinix-sandbox',
		'extras/usr/bin/Xvfb', 'extras/usr/bin/xkbcomp'] {
		if name !in generated || digest(run + '/' + name)! != generated[name] { return error('missing or changed GUI generated artifact: ' + name) }
	}
	serial := os.read_file(run + '/boot/serial.log')!
	for forbidden in ['HWTEST FAIL', 'WINE GUI FAIL', 'Kernel panic', 'FATAL EXCEPTION'] {
		if serial.contains(forbidden) { return error('forbidden GUI serial marker') }
	}
	lines := serial.split_into_lines().map(it.trim_space())
	mut previous := -1
	previous = require_marker(lines, 'WINE GUI authenticated ordinary display PASS', previous)!
	previous = require_marker(lines, 'WINE GUI missing-authority mismatched-display refusals PASS', previous)!
	mut frames := []winegui.Frame{}
	for line in lines {
		if line.starts_with('WINE GUI FRAME ') { frames << winegui.decode_frame(line)! }
	}
	if frames.len != 2 || frames[0].name != 'before' || frames[1].name != 'after'
		|| frames[0].width != frames[1].width || frames[0].height != frames[1].height
		|| frames[0].rgb == frames[1].rgb { return error('GUI frame pair differs') }
	for frame in frames {
		mut dark := 0; mut light := 0
		for at := 0; at < frame.rgb.len; at += 3 {
			if frame.rgb[at] < 96 && frame.rgb[at + 1] < 96 && frame.rgb[at + 2] < 96 { dark++ }
			if frame.rgb[at] > 160 && frame.rgb[at + 1] > 160 && frame.rgb[at + 2] > 160 { light++ }
		}
		if dark < 100 || light < 1000 { return error('GUI frame lacks painted controls') }
		png_path := run + '/' + frame.name + '.png'
		png_info := os.lstat(png_path)!
		if png_info.get_filetype() != .regular || png_info.size < 8 || png_info.size > 4 * 1024 * 1024 {
			return error('GUI PNG must be a bounded ordinary file')
		}
		encoded := os.read_bytes(png_path)!
		defer { unsafe { encoded.free() } }
		if encoded.len < 8 || encoded.len > 4 * 1024 * 1024 || encoded[..8] != [u8(137), 80, 78, 71, 13, 10, 26, 10] {
			return error('GUI capture is not a bounded PNG')
		}
		info := stbi.info_from_memory(encoded.data, encoded.len)!
		if info.width != frame.width || info.height != frame.height { return error('GUI PNG dimensions differ') }
		image := stbi.load_from_memory(encoded.data, encoded.len, desired_channels: 3)!
		matches := image.width == frame.width && image.height == frame.height
			&& unsafe { image.data.vbytes(frame.rgb.len) } == frame.rgb
		image.free()
		if !matches { return error('GUI PNG pixels differ from captured frame') }
		mut record := ''
		for line in lines { if line.starts_with('WINE GUI FRAME ' + frame.name + ' ') { record = line } }
		previous = require_marker(lines, record, previous)!
	}
	for marker in ['VINIX WIN64 CALCULATOR READY', 'VINIX WIN64 CALCULATOR RESULT 42', 'VINIX WIN64 CALCULATOR CLOSED',
		'WINE GUI Windows pointer arithmetic close ordinary lease PASS', 'HWTEST PASS packaged-Wine-GUI'] {
		previous = require_marker(lines, marker, previous)!
	}
	mut pe := wineadapter.admit_local_pe_proof(declaration['pe'], root + '/tests/packages/wine-calculator/program.v', root + '/tests/packages/wine-pe-check.v')!
	defer { pe.close() }
	installed := run + '/extras/var/lib/vinix-packages/generations/1/apps'
	mut state := pkgcore.read_state(run + '/extras/var/lib/vinix-packages', arch)!
	defer { state.close() }
	if state.generation != 1 || state.packages.len != 2 { return error('GUI signed package state differs') }
	mut calculator := false; mut runtime := false
	for item in state.packages {
		p := item.package
		if p.id == 'org.vinix.wine-calculator' {
			calculator = p.kind == 'windows' && p.permissions == ['display', 'process'] && p.runtime == 'org.vinix.wine-runtime'
				&& p.arguments == ['@APP@/bin/program.exe'] && p.entrypoint == 'bin/wine-runner' && p.files.len == 2
		} else if p.id == 'org.vinix.wine-runtime' { runtime = p.kind == 'runtime' && p.version == '9.17.1' && p.permissions.len == 0 }
	}
	if !calculator || !runtime { return error('GUI application/runtime policy differs') }
	if digest(installed + '/org.vinix.wine-calculator/bin/program.exe')! != digest(pe.executable)! { return error('GUI signed PE differs from admitted producer') }
	publisher_binding(run, namespace, arch, state)!
	for name, original in {'bin/sh': declaration['shell'], 'usr/bin/Xvfb': declaration['x11'] + '/usr/bin/Xvfb',
		'usr/bin/xkbcomp': declaration['x11'] + '/usr/bin/xkbcomp', 'usr/bin/vinix-package': baseline + '/extras/usr/bin/vinix-package',
		'usr/bin/vinix-sandbox': baseline + '/extras/usr/bin/vinix-sandbox'} {
		if digest(run + '/extras/' + name)! != inputs[original] { return error('GUI selected executable binding differs') }
	}
	for path, expected in generated {
		if os.is_abs_path(path) || '..' in path.split('/') || digest(run + '/' + path)! != expected { return error('GUI generated inventory differs') }
	}
	for path, expected in inputs {
		if !os.is_abs_path(path) || expected.len != 64 || digest(path)! != expected { return error('GUI input digest differs: ' + path) }
	}
	mut args := [retainer, baseline, prepared, arch, out + '.baseline']
	if arch == 'aarch64' { args << '--forksafe-translator' }
	hwhost.run_tool(args, map[string]string{}, out + '.baseline.log', 600)!
	fresh := json2.decode[Baseline](os.read_file(out + '.baseline/wine-' + arch + '.json')!)!
	for stage in ['before', 'after'] {
		recorded := json2.decode[Baseline](os.read_file(run + '/baseline-' + stage + '/wine-' + arch + '.json')!)!
		if recorded.architecture != arch || recorded.artifact_paths != fresh.artifact_paths || recorded.artifacts != fresh.artifacts {
			return error('GUI baseline admission differs')
		}
	}
	for key, path in fresh.artifact_paths {
		if inputs[path] != fresh.artifacts[key] { return error('GUI omitted admitted baseline input: ' + path) }
	}
	original_runtime := prepared + '/prepared/' + arch + '/runtime'
	mut count := 0
	for path in os.walk_ext(original_runtime, '', hidden: true) {
		if !os.is_file(path) { continue }
		copy := installed + '/org.vinix.wine-runtime' + path[original_runtime.len..]
		if os.lstat(copy)!.get_filetype() != .regular || digest(copy)! != digest(path)! { return error('GUI runtime differs from admitted console runtime') }
		count++
	}
	if os.walk_ext(installed + '/org.vinix.wine-runtime', '', hidden: true).filter(os.is_file(it)).len != count { return error('GUI runtime file set differs') }
	mut artifacts := map[string]string{}
	for name in ['declaration.json', 'inputs.json', 'inputs-verified.json', 'generated-before-boot.json', 'result.json',
		'boot/serial.log', 'boot/qemu.log', 'boot/qmp.log', 'boot/initramfs.tar', 'before.png', 'after.png',
		'publisher/index.json', 'publisher/index.sig'] {
		artifacts[name] = digest(run + '/' + name)!
	}
	os.mkdir_all(out)!
	os.write_file(out + '/wine-gui-' + arch + '.json', json2.encode(Receipt{
		architecture: arch, run: run, artifacts: artifacts, auditor_sha256: digest(os.executable())!, audit_source_sha256: digest(@FILE)!
	}))!
	os.write_file(out + '/artifacts.json', json2.encode(artifacts))!
	println('WINE GUI RETAIN PASS ' + arch + ': actual paint/input/close with admitted baseline, PE, producer and captured pixels')
}

fn main() { check() or { eprintln(err); exit(1) } }
