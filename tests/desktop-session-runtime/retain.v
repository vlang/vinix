// SPDX-License-Identifier: GPL-2.0-or-later
// Independently admit completed external broker/framebuffer guest evidence.
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso

struct Outcome {
	scenario string
	passed bool
	interrupted bool
	reason string
}

struct Receipt {
	architecture string
	scope string
	required_markers []string
	artifacts map[string]string
	artifact_paths map[string]string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		sum.write(buffer[..count])!
	}
	return sum.sum([]u8{}).hex()
}

fn retain() ! {
	$if prod {} $else { return error('compile the runtime validator with -prod to freeze its embedded source') }
	if os.args.len != 8 {
		return error('use RUN_DIRECTORY DESKTOP_ELF KERNEL_ELF CONTROLLER_ELF OUTPUT_DIRECTORY ARCH CROSS_DRIVER')
	}
	root := hwhost.find_root(@FILE)!
	if sha256.sum($embed_file('retain.v').to_string().bytes()).hex() !=
		digest(root + '/tests/desktop-session-runtime/retain.v')! {
		return error('retention source changed after validator compilation')
	}
	run := os.abs_path(os.args[1])
	desktop := os.abs_path(os.args[2])
	arch := os.args[6]
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	host := hwhost.find_host(root, arch, '')!
	cc_name := if arch == 'aarch64' { 'CC_AARCH64' } else { 'CC_AMD64' }
	cc_default := if arch == 'aarch64' { 'clang' } else { 'x86_64-linux-musl-gcc' }
	cc := os.find_abs_path_of_executable(if os.getenv(cc_name) != '' { os.getenv(cc_name) } else { cc_default })!
	mut paths := {
		'controller-source': root + '/tests/desktop-session-runtime/check.v'
		'guest-source': root + '/tests/desktop-session-runtime/guest/main.v'
		'controller': os.abs_path(os.args[4])
		'desktop': desktop
		'desktop-build-receipt': os.dir(desktop) + '/desktop-build.json'
		'compiler': host.v
		'c-compiler': cc
		'cross-driver': os.abs_path(os.args[7])
		'kernel': os.abs_path(os.args[3])
		'qemu': host.qemu
		'firmware': host.firmware
		'plain-iso-source': root + '/tests/hardware-platform/plainiso/iso.v'
	}
	if arch == 'x86_64' {
		for name, path in plainiso.inputs(root)! { paths[name] = path }
	}
	if host.firmware_vars != '' { paths['firmware-vars'] = host.firmware_vars }
	inputs := json2.decode[map[string]string](os.read_file(run + '/inputs.json')!)!
	if digest(run + '/source/check.v')! != inputs['controller-source'] ||
		digest(run + '/source/guest/main.v')! != inputs['guest-source'] ||
		digest(run + '/source/plainiso.v')! != inputs['plain-iso-source'] {
		return error('frozen fixture source does not match admitted input')
	}
	verified := json2.decode[map[string]string](os.read_file(run + '/inputs-verified.json')!)!
	if inputs != verified { return error('completed input verification differs from built input set') }
	before := json2.decode[map[string]string](os.read_file(run + '/inputs-before-build.json')!)!
	for name, expected in before {
		if inputs[name] != expected { return error('input changed between admission and build: ' + name) }
	}
	for path in os.walk_ext(root + '/tests/hardware-platform/hwhost', '.v') {
		if path.ends_with('_test.v') { continue }
		name := 'hwhost/' + os.base(path)
		paths[name] = path
		if digest(run + '/source/hwhost/' + os.base(path))! != inputs[name] {
			return error('frozen helper input mismatch: ' + name)
		}
	}
	for name in ['session', 'timesync', 'runner', 'guest'] {
		binary := if name == 'guest' { 'guest' } else if name == 'runner' { 'vinix-service-runner' } else { 'vinix-' + name }
		paths[binary] = run + '/build-' + name + '/' + binary
		paths[binary + '.c'] = paths[binary] + '.c'
	}
	if paths.len != inputs.len { return error('input digest set is not fully covered by admitted paths') }
	for name, path in paths {
		if digest(path)! != inputs[name] { return error('input mismatch: ' + name) }
	}
	outputs := json2.decode[map[string]string](os.read_file(run + '/outputs.json')!)!
	for required in ['source/check.v', 'source/guest/main.v', 'source/plainiso.v', 'inputs-before-build.json',
		'inputs.json', 'inputs-verified.json', 'result.json', 'boot/initramfs.tar',
		'boot/serial.log', 'boot/qemu.log', 'boot/qmp.log', 'boot/image.log'] {
		if required !in outputs { return error('output receipt lacks: ' + required) }
	}
	for name, expected in outputs {
		if name.starts_with('/') || '..' in name.split('/') { return error('invalid output receipt path') }
		if digest(run + '/' + name)! != expected { return error('output digest mismatch: ' + name) }
		paths['output/' + name] = run + '/' + name
	}
	for name in ['session', 'timesync', 'runner', 'guest'] {
		binary := if name == 'guest' { 'guest' } else if name == 'runner' { 'vinix-service-runner' } else { 'vinix-' + name }
		for file in [binary, binary + '.c', 'commands.json', 'build.log'] {
			if 'build-' + name + '/' + file !in outputs { return error('missing build command/log receipt') }
		}
	}
	media := if arch == 'aarch64' { ['boot/boot.img', 'boot/vars.fd', 'boot/limine.conf'] }
		else { ['boot/test.iso', 'boot/image-commands.json', 'boot/iso/iso-root/boot/limine.conf'] }
	for name in media {
		if name !in outputs { return error('missing qualified boot medium: ' + name) }
	}
	manifest := json2.decode[map[string]string](os.read_file(os.dir(desktop) + '/desktop-build.json')!)!
	if manifest['vinix-desktop'] != inputs['desktop'] || manifest['compiler'] != inputs['compiler'] {
		return error('desktop build receipt does not bind selected compiler and compositor')
	}
	for name in ['sessionruntime/runtime.c.v', 'sessionipc/client.c.v', 'windowfb/transport.c.v'] {
		if digest(root + '/desktop/' + name)! != manifest['desktop/' + name] ||
			digest(os.dir(desktop) + '/source/desktop/' + name)! != manifest['desktop/' + name] {
			return error('qualified runtime production source differs: ' + name)
		}
	}
	result := json2.decode[Outcome](os.read_file(run + '/result.json')!)!
	if result.scenario != 'session-runtime' || !result.passed || result.interrupted || result.reason != '' {
		return error('requires an uninterrupted, passing session-runtime result')
	}
	markers := ['HWTEST INFO ordinary-desktop ready uid=1000 account-runtime PASS',
		'HWTEST INFO external-broker uid=1000 ping=ok PASS',
		'HWTEST INFO external-framebuffer uid=1000 frames=3 acknowledged PASS',
		'HWTEST INFO account-isolation uid=1001 broker+framebuffer refused PASS',
		'HWTEST INFO numeric-runtime private owners=1000,1001 legacy-ordinary-paths=absent PASS',
		'HWTEST PASS session-runtime']
	serial := os.read_file(run + '/boot/serial.log')!
	for forbidden in hwhost.always_forbidden {
		if serial.contains(forbidden) { return error('forbidden serial marker: ' + forbidden) }
	}
	lines := serial.split_into_lines().map(it.trim_space())
	for marker in markers {
		if lines.filter(it == marker).len != 1 { return error('missing or duplicated exact marker: ' + marker) }
	}
	paths['output-receipt'] = run + '/outputs.json'
	paths['retention-source'] = root + '/tests/desktop-session-runtime/retain.v'
	paths['retention-controller'] = os.executable()
	mut artifacts := map[string]string{}
	for name, path in paths { artifacts[name] = digest(path)! }
	out := os.abs_path(os.args[5])
	os.mkdir_all(out)!
	prefix := out + '/software-session-runtime-' + arch
	os.write_file(prefix + '.json', json2.encode(Receipt{architecture: arch,
		scope: 'qemu ordinary-account external session broker and framebuffer transport',
		required_markers: markers, artifacts: artifacts, artifact_paths: paths}))!
	os.cp(run + '/boot/serial.log', prefix + '.serial.txt')!
	mut commands := map[string][][]string{}
	for name in ['session', 'timesync', 'runner', 'guest'] {
		commands[name] = json2.decode[[][]string](os.read_file(run + '/build-' + name + '/commands.json')!)!
	}
	os.write_file(prefix + '.commands.json', json2.encode(commands))!
	println('SESSION RUNTIME RETAIN PASS ' + arch + ': ' + artifacts.len.str() + ' artifact digests; six exact native markers')
}

fn main() { retain() or { eprintln(err); exit(1) } }
