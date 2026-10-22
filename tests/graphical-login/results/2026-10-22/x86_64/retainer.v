// SPDX-License-Identifier: GPL-2.0-or-later
// Admit the actual graphical workflow independently before writing durable evidence.
module main

import crypto.sha256
import json2
import loginproof
import os
import screenshotcore

struct Receipt {
	architecture string
	scope string
	markers []string
	retainer string
	artifacts map[string]string
	artifact_paths map[string]string
}

fn frozen_sources() map[string]string {
	return {
		'controller-source': $embed_file('check.v').to_string()
		'guest-source': $embed_file('guest/main.v').to_string()
		'builder-source': $embed_file('build.v').to_string()
		'proof-source': $embed_file('loginproof/proof.v').to_string()
		'stager-source': $embed_file('../../tools/accounts/stage.v').to_string()
		'plainiso/iso.v': $embed_file('../hardware-platform/plainiso/iso.v').to_string()
		'hwhost/acpi_bench.v': $embed_file('../hardware-platform/hwhost/acpi_bench.v').to_string()
		'hwhost/aml.v': $embed_file('../hardware-platform/hwhost/aml.v').to_string()
		'hwhost/boot.v': $embed_file('../hardware-platform/hwhost/boot.v').to_string()
		'hwhost/cli.v': $embed_file('../hardware-platform/hwhost/cli.v').to_string()
		'hwhost/host.v': $embed_file('../hardware-platform/hwhost/host.v').to_string()
		'hwhost/markers.v': $embed_file('../hardware-platform/hwhost/markers.v').to_string()
		'hwhost/process.v': $embed_file('../hardware-platform/hwhost/process.v').to_string()
		'hwhost/qmp.v': $embed_file('../hardware-platform/hwhost/qmp.v').to_string()
		'hwhost/qmp_client.v': $embed_file('../hardware-platform/hwhost/qmp_client.v').to_string()
		'hwhost/scenario.v': $embed_file('../hardware-platform/hwhost/scenario.v').to_string()
		'hwhost/screen.v': $embed_file('../hardware-platform/hwhost/screen.v').to_string()
		'hwhost/sound.v': $embed_file('../hardware-platform/hwhost/sound.v').to_string()
		'hwhost/suite.v': $embed_file('../hardware-platform/hwhost/suite.v').to_string()
		'hwhost/thermal_bench.v': $embed_file('../hardware-platform/hwhost/thermal_bench.v').to_string()
		'hwhost/vm.v': $embed_file('../hardware-platform/hwhost/vm.v').to_string()
		'qmpclient/core.v': $embed_file('../../tools/qmpclient/core.v').to_string()
		'qmpclient/guest.v': $embed_file('../../tools/qmpclient/guest.v').to_string()
		'qmpclient/owned.v': $embed_file('../../tools/qmpclient/owned.v').to_string()
		'qmpclient/raw.v': $embed_file('../../tools/qmpclient/raw.v').to_string()
		'screenshotcore/core.v': $embed_file('../../build-support/screenshotcore/core.v').to_string()
	}
}

fn retain() ! {
	$if prod {} $else { return error('compile this validator with -prod') }
	if loginproof.digest(@FILE)! != sha256.hexhash($embed_file('retain.v').to_string()) {
		return error('retainer source differs from this executable')
	}
	if os.args.len != 9 {
		return error('use RUN DESKTOP_BUILD ACCOUNTS_STAGE ACCOUNT_PROOF KERNEL CONTROLLER OUTPUT ARCH')
	}
	run := os.abs_path(os.args[1])
	desktop := os.abs_path(os.args[2])
	accounts := os.abs_path(os.args[3])
	account_proof := os.abs_path(os.args[4])
	kernel := os.abs_path(os.args[5])
	controller := os.abs_path(os.args[6])
	output := os.abs_path(os.args[7])
	arch := os.args[8]
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	if os.exists(output) || os.is_link(output) { return error('evidence output already exists') }
	inputs := loginproof.strings(run + '/inputs.json')!
	paths := loginproof.strings(run + '/input-paths.json')!
	if inputs != loginproof.strings(run + '/inputs-verified.json')! {
		return error('completed input verification differs from admitted input set')
	}
	loginproof.verify_files(inputs, paths)!
	for name, source in frozen_sources() {
		if inputs[name] != sha256.hexhash(source) {
			return error('qualified graphical fixture differs from embedded source: ' + name)
		}
	}
	for name, expected in {
		'kernel': kernel
		'controller': controller
		'desktop': desktop + '/vinix-desktop'
		'desktop-build': desktop + '/desktop-build.json'
		'desktop-inputs': desktop + '/build-inputs.json'
		'desktop-input-paths': desktop + '/build-input-paths.json'
		'desktop-argv': desktop + '/build-argv.json'
	} {
		if paths[name] != expected || inputs[name] != loginproof.digest(expected)! {
			return error('selected input differs from qualification: ' + name)
		}
	}
	for required in ['compiler', 'qemu', 'firmware', 'guest-c-compiler', 'base-passwd', 'base-group',
		'vinix-account', 'vinix-auth', 'vinix-authd', 'vinix-session', 'vinix-system', 'tool/cp', 'tool/tar'] {
		if required !in inputs { return error('missing required input digest: ' + required) }
	}
	for required in if arch == 'aarch64' {
		['firmware-vars', 'limine-loader', 'limine-config', 'tool/mformat', 'tool/mmd', 'tool/mcopy']
	} else { ['iso-xorriso', 'iso-BOOTX64.EFI', 'iso-limine-uefi-cd.bin'] } {
		if required !in inputs { return error('missing required input digest: ' + required) }
	}
	for name in ['inputs', 'input-paths', 'outputs', 'arguments', 'result'] {
		key := 'account-proof-' + name
		if paths[key] != account_proof + '/receipt/' + name + '.json' {
			return error('account build receipt differs from qualification')
		}
	}
	for name in ['account', 'auth', 'authd', 'system', 'session'] {
		key := 'vinix-' + name
		expected := accounts + '/usr/' + (if name == 'auth' { 'bin' } else { 'sbin' }) + '/' + key
		if paths[key] != expected { return error('account executable path differs: ' + name) }
	}
	loginproof.desktop(desktop, sha256.hexhash($embed_file('build.v').to_string()))!
	loginproof.accounts(account_proof, accounts, arch, sha256.hexhash($embed_file('../../tools/accounts/stage.v').to_string()))!
	if loginproof.strings(account_proof + '/receipt/inputs.json')!['compiler-v'] != inputs['compiler'] {
		return error('guest compiler differs from account compiler')
	}
	outputs := loginproof.strings(run + '/outputs.json')!
	names := loginproof.output_names(arch)
	if outputs.len != names.len { return error('graphical output inventory differs') }
	for name in names {
		if name !in outputs { return error('missing required output digest: ' + name) }
		if loginproof.digest(run + '/' + name)! != outputs[name] { return error('output digest differs: ' + name) }
	}
	if outputs['source/check.v'] != inputs['controller-source'] || outputs['source/guest/main.v'] != inputs['guest-source'] {
		return error('frozen fixture differs from admitted source')
	}
	result := loginproof.strings(run + '/result.json')!
	if result != {'passed': 'true', 'platform': 'direct-graphical-manager-registration-login-switch-logout', 'arch': arch} {
		return error('requires a passing direct-manager graphical result')
	}
	controller_args := json2.decode[[]string](os.read_file(run + '/arguments.json')!)!
	if controller_args.len != 8 || os.abs_path(controller_args[0]) != controller || controller_args[1] != arch
		|| os.abs_path(controller_args[2]) != kernel || os.abs_path(controller_args[3]) != desktop
		|| os.abs_path(controller_args[4]) != accounts || os.abs_path(controller_args[5]) != account_proof
		|| os.abs_path(controller_args[6]) != run {
		return error('controller arguments differ from selected qualification')
	}
	qemu_arguments := json2.decode[[]string](os.read_file(run + '/qemu-argv.json')!)!
	if qemu_arguments.len < 2 || qemu_arguments[0] != paths['qemu'] { return error('QEMU arguments do not bind admitted executable') }
	guest_arguments := json2.decode[map[string][]string](os.read_file(run + '/guest-argv.json')!)!
	if guest_arguments['v'].len < 2 || guest_arguments['c'].len < 2 || guest_arguments['v'][0] != paths['compiler']
		|| guest_arguments['c'][0] != paths['guest-c-compiler'] { return error('guest build arguments do not bind admitted compilers') }
	serial := os.read_file(run + '/boot/serial.log')!
	loginproof.serial(serial)!
	mut actual_shots := os.ls(run)!.filter(it.ends_with('.png'))
	mut required_shots := loginproof.screenshots.clone()
	actual_shots.sort()
	required_shots.sort()
	if actual_shots != required_shots { return error('required screenshot inventory differs') }
	for name in loginproof.screenshots {
		image := screenshotcore.read(run + '/' + name)!
		if image.width != 1024 || image.height != 768 { return error('screenshot dimensions differ: ' + name) }
	}
	// All refusal paths above precede output creation/copying.
	os.mkdir(output, mode: 0o700)!
	mut artifacts := map[string]string{}
	mut artifact_paths := map[string]string{}
	for name in ['result.json', 'arguments.json', 'guest-argv.json', 'qemu-argv.json', 'inputs.json', 'inputs-verified.json',
		'input-paths.json', 'outputs.json', 'source/check.v', 'source/guest/main.v', 'build-guest/guest.c',
		'build-guest/guest', 'build-guest/build.log', 'boot/serial.log', 'boot/image.log', 'qemu.log', 'stage.log',
		...loginproof.screenshots] {
		os.mkdir_all(os.dir(output + '/' + name))!
		os.cp(run + '/' + name, output + '/' + name)!
		artifacts[name] = loginproof.digest(output + '/' + name)!
		artifact_paths[name] = output + '/' + name
	}
	for name in ['desktop-build.json', 'build-inputs.json', 'build-input-paths.json', 'build-argv.json'] {
		os.mkdir_all(output + '/desktop')!
		os.cp(desktop + '/' + name, output + '/desktop/' + name)!
		artifacts['desktop/' + name] = loginproof.digest(output + '/desktop/' + name)!
		artifact_paths['desktop/' + name] = output + '/desktop/' + name
	}
	for name in ['desktop.c', 'execinfo.c', 'presenter.c'] {
		os.cp(desktop + '/app/' + name, output + '/desktop/' + name)!
		artifacts['desktop/' + name] = loginproof.digest(output + '/desktop/' + name)!
		artifact_paths['desktop/' + name] = output + '/desktop/' + name
	}
	os.cp(desktop + '/vinix-desktop', output + '/desktop/vinix-desktop')!
	artifacts['desktop/vinix-desktop'] = loginproof.digest(output + '/desktop/vinix-desktop')!
	artifact_paths['desktop/vinix-desktop'] = output + '/desktop/vinix-desktop'
	os.cp_all(account_proof, output + '/accounts', true)!
	for path in os.walk_ext(output + '/accounts', '') {
		if !os.is_file(path) { continue }
		name := path[output.len + 1..]
		artifacts[name] = loginproof.digest(path)!
		artifact_paths[name] = path
	}
	os.write_file(output + '/retainer.v', $embed_file('retain.v').to_string())!
	artifacts['retainer.v'] = loginproof.digest(output + '/retainer.v')!
	artifact_paths['retainer.v'] = output + '/retainer.v'
	os.write_file(output + '/receipt.json', json2.encode(Receipt{
		architecture: arch
		scope: 'Actual graphical registration, refused login, ordinary login, switch, resume, logout and fresh login through the production manager on a minimal fixture image; normal init boot is separate.'
		markers: loginproof.markers
		retainer: loginproof.digest(os.executable())!
		artifacts: artifacts
		artifact_paths: artifact_paths
	}))!
	println('PASS ' + arch + ' independently retained graphical login: ' + output)
}

fn main() { retain() or { eprintln(err); exit(1) } }
