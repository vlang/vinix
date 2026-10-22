// SPDX-License-Identifier: GPL-2.0-or-later
// Retain actual signed Neovim execution only after checking native evidence.
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
	contents := os.read_file(path)!
	defer { unsafe { contents.free() } }
	return sha256.hexhash(contents)
}

fn retain() ! {
	$if prod {} $else { return error('compile Neovim retention with -prod') }
	if os.args.len != 7 { return error('use RUN ARCH KERNEL CONTROLLER SANDBOX NEW_OUTPUT_DIRECTORY') }
	root := hwhost.find_root(@FILE)!
	if digest(root + '/tests/packages/neovim-retain.v')! != sha256.hexhash($embed_file('neovim-retain.v').to_string()) {
		return error('retention source changed after compilation')
	}
	run := os.abs_path(os.args[1])
	arch := os.args[2]
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	out := os.abs_path(os.args[6])
	if os.exists(out) { return error('retention output must be new') }
	host := hwhost.find_host(root, arch, '')!
	mut required_inputs := [os.abs_path(os.args[3]), os.abs_path(os.args[4]), os.abs_path(os.args[5]),
		host.v, host.qemu, host.firmware,
		os.find_abs_path_of_executable(os.getenv_opt('CLANG') or { '/opt/homebrew/opt/llvm/bin/clang' })!,
		os.dir(host.v) + '/vlib/os/execute_capture_nix.h', os.dir(host.v) + '/vlib/sync/thread_helper.h']
	if host.firmware_vars != '' { required_inputs << host.firmware_vars }
	if arch == 'x86_64' { for _, path in plainiso.inputs(root)! { required_inputs << path } }
	else {
		required_inputs << [os.getenv_opt('VINIX_LIMINE_BOOTAA64') or { hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI') },
			root + '/build-support/limine.conf', os.find_abs_path_of_executable('mformat')!,
			os.find_abs_path_of_executable('mmd')!, os.find_abs_path_of_executable('mcopy')!]
	}
	for directory in ['tools/accounts', 'tools/packages', 'desktop/ptycore', 'tests/packages/neovim-native',
		'tests/hardware-platform/hwhost', 'tests/hardware-platform/plainiso'] {
		for path in os.walk_ext(root + '/' + directory, '.v') {
			if !path.ends_with('_test.v') { required_inputs << path }
		}
	}
	required_inputs << root + '/tests/packages/neovim-native-check.v'
	inputs := json2.decode[map[string]string](os.read_file(run + '/inputs.json')!)!
	verified := json2.decode[map[string]string](os.read_file(run + '/inputs-verified.json')!)!
	if inputs != verified { return error('completed input verification differs from admitted inputs') }
	before := json2.decode[map[string]string](os.read_file(run + '/inputs-before-build.json')!)!
	for path, expected in before {
		if inputs[path] != expected { return error('input changed during build admission: ' + path) }
	}
	for path in required_inputs { if path !in before { return error('missing required admitted input: ' + path) } }
	mut paths := map[string]string{}
	for path, expected in inputs {
		if !path.starts_with('/') || digest(path)! != expected { return error('input digest mismatch: ' + path) }
		paths['input/' + path] = path
	}
	for name in ['neovim-native-check.v', 'neovim-native/main.v'] {
		if digest(run + '/source/tests/packages/' + name)! != inputs[root + '/tests/packages/' + name] {
			return error('frozen fixture source differs from admitted source')
		}
	}
	for directory in ['tools/accounts', 'tools/packages', 'desktop/ptycore'] {
		for path in os.walk_ext(root + '/' + directory, '.v') {
			if !path.ends_with('_test.v') && digest(run + '/source/' + path[root.len + 1..])! != inputs[path] {
				return error('frozen account/package/PTY source differs from admitted source')
			}
		}
	}
	outputs := json2.decode[map[string]string](os.read_file(run + '/outputs.json')!)!
	mut required_outputs := ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json', 'result.json',
		'source/tests/packages/neovim-native-check.v', 'source/tests/packages/neovim-native/main.v',
		'boot/initramfs.tar', 'boot/serial.log', 'boot/qemu.log', 'boot/qmp.log', 'boot/image.log']
	for name in ['guest', 'vinix-account', 'vinix-session', 'vinix-package'] {
		for file in [name, name + '.c', 'runtime.c', 'v.log', 'v.log.argv.json', 'cc.log', 'cc.log.argv.json'] {
			required_outputs << 'build-' + name + '/' + file
		}
	}
	required_outputs << if arch == 'aarch64' { ['boot/boot.img', 'boot/vars.fd', 'boot/limine.conf'] }
		else { ['boot/test.iso', 'boot/image-commands.json', 'boot/iso/iso-root/boot/limine.conf'] }
	for name in required_outputs { if name !in outputs { return error('missing required output: ' + name) } }
	for name, expected in outputs {
		if name.starts_with('/') || '..' in name.split('/') || digest(run + '/' + name)! != expected {
			return error('output digest mismatch: ' + name)
		}
		paths['output/' + name] = run + '/' + name
	}
	mut build_roots := []string{}
	for path, _ in inputs {
		if path.ends_with('/build-guest/guest') { build_roots << path[..path.len - '/build-guest/guest'.len] }
	}
	if build_roots.len != 1 { return error('missing or ambiguous admitted build root') }
	for product in ['guest', 'vinix-account', 'vinix-session', 'vinix-package'] {
		for file in [product, product + '.c', 'runtime.c', 'v.log', 'v.log.argv.json', 'cc.log', 'cc.log.argv.json'] {
			name := 'build-' + product + '/' + file
			path := build_roots[0] + '/' + name
			if path !in inputs || outputs[name] != inputs[path] { return error('retained build product differs from boot input: ' + name) }
		}
	}
	result := json2.decode[Outcome](os.read_file(run + '/result.json')!)!
	if result.scenario != 'packaged-Neovim' || !result.passed || result.interrupted || result.reason != '' {
		return error('requires an uninterrupted passing packaged-Neovim result')
	}
	markers := ['HWTEST INFO Neovim signed-musl fixed-runtime Lua-LPEG Vimscript-syntax ordinary-uid outside-write-refused PASS',
		'HWTEST INFO Neovim real-PTY input resize exact-save ordinary-owner live-uninstall lease-held natural-exit gc PASS',
		'HWTEST INFO Neovim signed-runtime update-1.1 rollback-1.0 exact-Lua-reopen offline PASS',
		'HWTEST INFO Neovim offline-cache reinstall exact-reopen data-preserving-uninstall pipe-refusal PASS',
		'HWTEST PASS packaged-Neovim']
	serial := os.read_file(run + '/boot/serial.log')!
	for forbidden in [...hwhost.always_forbidden, 'Kernel panic'] {
		if serial.contains(forbidden) { return error('forbidden serial marker: ' + forbidden) }
	}
	lines := serial.split_into_lines().map(it.trim_space())
	for marker in markers { if lines.filter(it == marker).len != 1 { return error('missing or duplicated exact marker: ' + marker) } }
	paths['output-receipt'] = run + '/outputs.json'
	paths['retention-source'] = root + '/tests/packages/neovim-retain.v'
	paths['retention-controller'] = os.executable()
	mut artifacts := map[string]string{}
	for name, path in paths { artifacts[name] = digest(path)! }
	os.mkdir_all(out)!
	prefix := out + '/neovim-' + arch
	os.write_file(prefix + '.json', json2.encode(Receipt{architecture: arch,
		scope: 'QEMU signed musl Neovim ordinary-account Lua/LPEG/Vimscript runtime, real PTY edit/save/resize, lease and offline update/rollback; host stops after PASS',
		required_markers: markers, artifacts: artifacts, artifact_paths: paths}) + '\n')!
	os.cp(run + '/boot/serial.log', prefix + '.serial.txt')!
	println('NEOVIM RETAIN PASS ' + arch + ': five exact native markers and all admitted artifact digests')
}

fn main() { retain() or { eprintln(err); exit(1) } }
