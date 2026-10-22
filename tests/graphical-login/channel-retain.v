// SPDX-License-Identifier: GPL-2.0-or-later
// Independently admit the native inherited-capability evidence before copying it.
module main

import json2
import loginproof
import os

const channel_markers = ['HWTEST START login-channel',
	'LOGIN CHANNEL root-created peer survives ordinary UID drop PASS',
	'LOGIN CHANNEL ordinary exec loses manager capability PASS',
	'LOGIN CHANNEL hangup fails without closing borrowed descriptor PASS',
	'LOGIN CHANNEL ordinary forged peer refused before disclosure PASS',
	'LOGIN CHANNEL regular fd and arbitrary descriptor refused PASS',
	'LOGIN CHANNEL partial reply bounded refusal PASS', 'HWTEST PASS login-channel']

const channel_outputs = ['result.json', 'arguments.json', 'inputs.json', 'inputs-verified.json',
	'input-paths.json', 'source/channel-check.v', 'source/guest/main.v', 'build-guest/guest',
	'build-guest/guest.c', 'build-guest/build.log', 'boot/serial.log', 'boot/initramfs.tar',
	'boot/qemu.log', 'boot/qmp.log', 'boot/image.log']

struct Outcome {
	scenario string
	passed bool
	interrupted bool
	reason string
	state string
}

struct Receipt {
	architecture string
	passed bool
	scope string
	arguments []string
	inputs map[string]string
	input_paths map[string]string
	native_outputs map[string]string
	retained map[string]string
}

fn admit_serial(serial string) ! {
	for forbidden in ['HWTEST FAIL', 'KERNEL PANIC', 'V panic:', 'Assertion failed', 'FATAL EXCEPTION'] {
		if serial.contains(forbidden) { return error('forbidden channel serial marker: ' + forbidden) }
	}
	lines := serial.split_into_lines().map(it.trim_space())
	for marker in channel_markers {
		if lines.filter(it == marker).len != 1 { return error('missing or duplicated channel marker: ' + marker) }
	}
	if lines.index(channel_markers[0]) >= lines.index(channel_markers.last()) {
		return error('channel terminal marker precedes start')
	}
	for marker in channel_markers[1..channel_markers.len - 1] {
		if lines.index(marker) <= lines.index(channel_markers[0]) || lines.index(marker) >= lines.index(channel_markers.last()) {
			return error('channel case lies outside the scenario markers')
		}
	}
}

fn check() ! {
	$if prod {} $else { return error('compile this retainer with -prod') }
	if os.args.len != 4 { return error('use RUN OUTPUT ARCH') }
	run := os.real_path(os.args[1])
	output := os.abs_path(os.args[2])
	arch := os.args[3]
	root := os.real_path(@DIR + '/../..')
	if arch !in ['aarch64', 'x86_64'] || os.exists(output) || os.is_link(output) {
		return error('invalid architecture or output already exists')
	}
	self := $embed_file('channel-retain.v').to_string()
	if self != os.read_file(@FILE)! { return error('retainer source changed') }
	inputs := loginproof.strings(run + '/inputs.json')!
	paths := loginproof.strings(run + '/input-paths.json')!
	if inputs != loginproof.strings(run + '/inputs-verified.json')! { return error('channel inputs were not reverified') }
	loginproof.verify_files(inputs, paths)!
	mut required := ['controller-source', 'guest-source', 'controller', 'compiler', 'kernel', 'qemu', 'firmware',
		'c-compiler', 'plain-iso-source']
	if arch == 'aarch64' { required << ['firmware-vars', 'cross-driver'] }
	for module_name in ['loginchannel', 'authclient', 'authproto', 'hwhost'] {
		directory := if module_name == 'hwhost' { root + '/tests/hardware-platform/hwhost' } else { root + '/tools/accounts/' + module_name }
		for name in os.ls(directory)! {
			if name.ends_with('.v') && !name.ends_with('_test.v') {
				key := module_name + '/' + name
				required << key
				if paths[key] != directory + '/' + name { return error('channel source binding differs: ' + key) }
				if module_name != 'hwhost' && loginproof.digest(run + '/source/' + key)! != inputs[key] {
					return error('frozen channel module differs: ' + key)
				}
			}
		}
	}
	if arch == 'x86_64' {
		required << ['iso-xorriso', 'iso-BOOTX64.EFI', 'iso-limine-uefi-cd.bin']
	}
	if paths.len != required.len || required.any(it !in paths) { return error('channel input inventory differs') }
	for name, expected in {'controller-source': $embed_file('channel-check.v').to_string(),
		'guest-source': $embed_file('channel-guest/main.v').to_string(),
		'plain-iso-source': $embed_file('../hardware-platform/plainiso/iso.v').to_string()} {
		if os.read_file(paths[name])! != expected { return error('channel fixture differs from embedded source: ' + name) }
	}
	if os.read_file(run + '/source/channel-check.v')! != os.read_file(paths['controller-source'])!
		|| os.read_file(run + '/source/guest/main.v')! != os.read_file(paths['guest-source'])! {
		return error('frozen channel fixture differs')
	}
	args := json2.decode[[]string](os.read_file(run + '/arguments.json')!)!
	if args.len != 5 || args[0] != paths['controller'] || args[1] != arch
		|| args[2] != paths['kernel'] || args[3] != run { return error('channel argument bindings differ') }
	result := json2.decode[Outcome](os.read_file(run + '/result.json')!)!
	if !result.passed || result.interrupted || result.reason != '' || result.scenario != 'login-channel'
		|| result.state != run + '/boot' { return error('channel result did not pass') }
	outputs := loginproof.strings(run + '/outputs.json')!
	if outputs.len != channel_outputs.len || channel_outputs.any(it !in outputs) { return error('channel output inventory differs') }
	mut output_paths := map[string]string{}
	for name in channel_outputs { output_paths[name] = run + '/' + name }
	loginproof.verify_files(outputs, output_paths)!
	admit_serial(os.read_file(run + '/boot/serial.log')!)!
	// Admission is complete. Boot media remains hashed in native_outputs; retain
	// the smaller logs, generated code, ELF, manifests and exact frozen sources.
	os.mkdir(output, mode: 0o700)!
	mut retained := map[string]string{}
	mut retained_names := channel_outputs.filter(it != 'boot/initramfs.tar')
	retained_names << 'outputs.json'
	for name in retained_names {
		os.mkdir_all(os.dir(output + '/' + name))!
		os.cp(run + '/' + name, output + '/' + name)!
		retained[name] = loginproof.digest(output + '/' + name)!
	}
	for module_name in ['loginchannel', 'authclient', 'authproto'] {
		for key in required.filter(it.starts_with(module_name + '/')) {
			name := 'source/' + key
			os.mkdir_all(os.dir(output + '/' + name))!
			os.cp(run + '/' + name, output + '/' + name)!
			retained[name] = loginproof.digest(output + '/' + name)!
		}
	}
	os.write_file(output + '/retainer.v', self)!
	retained['retainer.v'] = loginproof.digest(output + '/retainer.v')!
	os.write_file(output + '/receipt.json', json2.encode(Receipt{architecture: arch, passed: true,
		scope: 'Native minimal root-created fd3 capability scenario; host stops the owned VM after PASS. Captured inputs only, not a full compiler sysroot inventory.',
		arguments: os.args, inputs: inputs, input_paths: paths, native_outputs: outputs, retained: retained}))!
	println('PASS independently retained native login channel: ' + output)
}

fn main() { check() or { eprintln(err); exit(1) } }
