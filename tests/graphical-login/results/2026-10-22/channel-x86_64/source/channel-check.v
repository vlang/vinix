// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso

fn digest(path string) !string {
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	return sha256.hexhash(unsafe { tos(data.data, data.len) })
}

fn check() ! {
	$if prod {} $else { return error('compile this controller with -prod') }
	if os.args.len != 5 { return error('usage: channel-check ARCH KERNEL OUTPUT_DIR SHARED_CHECKOUT') }
	arch := os.args[1]
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	root := hwhost.find_root(@FILE)!
	kernel := os.abs_path(os.args[2]); work := os.abs_path(os.args[3]); shared := os.abs_path(os.args[4])
	if os.exists(work) { return error('output already exists') }
	host := hwhost.find_host(root, arch, '')!
	before := $embed_file('channel-check.v').to_string()
	if sha256.hexhash(before) != digest(@FILE)! { return error('controller source changed') }
	os.mkdir_all(work + '/source/guest')!
	os.write_file(work + '/source/channel-check.v', before)!
	os.cp(root + '/tests/graphical-login/channel-guest/main.v', work + '/source/guest/main.v')!
	mut inputs := {'controller-source': @FILE, 'guest-source': root + '/tests/graphical-login/channel-guest/main.v',
		'controller': os.executable(), 'compiler': host.v, 'kernel': kernel, 'qemu': host.qemu,
		'firmware': host.firmware, 'plain-iso-source': root + '/tests/hardware-platform/plainiso/iso.v'}
	if host.firmware_vars != '' { inputs['firmware-vars'] = host.firmware_vars }
	for module_name in ['loginchannel', 'authclient', 'authproto'] {
		os.mkdir_all(work + '/source/' + module_name)!
		for name in os.ls(root + '/tools/accounts/' + module_name)! {
			if !name.ends_with('.v') || name.ends_with('_test.v') { continue }
			source := root + '/tools/accounts/' + module_name + '/' + name
			os.cp(source, work + '/source/' + module_name + '/' + name)!
			inputs[module_name + '/' + name] = source
		}
	}
	for name in os.ls(root + '/tests/hardware-platform/hwhost')! {
		if name.ends_with('.v') && !name.ends_with('_test.v') { inputs['hwhost/' + name] = root + '/tests/hardware-platform/hwhost/' + name }
	}
	if arch == 'x86_64' { for name, path in plainiso.inputs(shared)! { inputs[name] = path } }
	cc_name := if arch == 'aarch64' { 'CC_AARCH64' } else { 'CC_AMD64' }
	cc := os.find_abs_path_of_executable(os.getenv(cc_name))!
	inputs['c-compiler'] = cc
	if os.getenv('VINIX_CHANNEL_CROSS_DRIVER') != '' { inputs['cross-driver'] = os.getenv('VINIX_CHANNEL_CROSS_DRIVER') }
	mut hashes := map[string]string{}
	for name, path in inputs { hashes[name] = digest(path)! }
	os.write_file(work + '/inputs.json', json2.encode(hashes))!
	os.write_file(work + '/input-paths.json', json2.encode(inputs))!
	os.write_file(work + '/arguments.json', json2.encode(os.args))!
	flags := ['-new-compiler', '-manualfree', '-enable-globals', '-path', '@vlib|' + work + '/source|@vmodules']
	guest := hwhost.build_program_with_flags(host, work + '/source/guest/main.v', work + '/build-guest', 'guest', [], flags)!
	scenario := hwhost.Scenario{
		name: 'login-channel'
		about: 'Root-created manager capability inherited by the actual ordinary UID client'
		arches: [arch]
		qemu_x86_64: ['-cpu', 'max']
		required: ['HWTEST START login-channel',
			'LOGIN CHANNEL root-created peer survives ordinary UID drop PASS',
			'LOGIN CHANNEL ordinary exec loses manager capability PASS',
			'LOGIN CHANNEL hangup fails without closing borrowed descriptor PASS',
			'LOGIN CHANNEL ordinary forged peer refused before disclosure PASS',
			'LOGIN CHANNEL regular fd and arbitrary descriptor refused PASS',
			'LOGIN CHANNEL partial reply bounded refusal PASS', 'HWTEST PASS login-channel']
		forbidden: ['V panic:', 'Assertion failed']
		ending: .running
	}
	runtime_host := if arch == 'x86_64' { hwhost.Host{...host, root: plainiso.prepare(shared, work)!} } else { host }
	outcome := hwhost.run_scenario(runtime_host, scenario, hwhost.Run{kernel: kernel, guest: guest,
		state: work + '/boot', timeout: 90, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	for name, path in inputs { if digest(path)! != hashes[name] { return error('input changed: ' + name) } }
	os.write_file(work + '/inputs-verified.json', json2.encode(hashes))!
	mut outputs := map[string]string{}
	for entry in ['result.json', 'arguments.json', 'inputs.json', 'inputs-verified.json', 'input-paths.json',
		'source/channel-check.v', 'source/guest/main.v', 'build-guest/guest', 'build-guest/guest.c',
		'build-guest/build.log', 'boot/serial.log', 'boot/initramfs.tar', 'boot/qemu.log', 'boot/qmp.log', 'boot/image.log'] {
		outputs[entry] = digest(work + '/' + entry)!
	}
	if !outcome.passed { return error(outcome.reason + '\n' + outcome.tail.join('\n')) }
	serial := os.read_file(work + '/boot/serial.log')!
	for marker in scenario.required {
		if serial.split_into_lines().filter(it.trim_space() == marker).len != 1 { return error('missing or duplicated exact marker: ' + marker) }
	}
	os.write_file(work + '/outputs.json', json2.encode(outputs))!
	println('PASS ' + arch + ' inherited root manager channel: ' + work)
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	check() or { eprintln(err); exit(1) }
}
