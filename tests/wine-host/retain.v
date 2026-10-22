// SPDX-License-Identifier: GPL-2.0-or-later
// Admit real authenticated Xvfb/signed-launch evidence before retaining it.
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
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		sum.write(buffer[..count])!
	}
	return sum.sum([]u8{}).hex()
}

fn retain() ! {
	$if prod {} $else { return error('compile the X11 evidence validator with -prod') }
	if os.args.len != 7 { return error('use RUN ARCH KERNEL CONTROLLER HOST_TOOL NEW_OUTPUT_DIRECTORY') }
	root := hwhost.find_root(@FILE)!
	if digest(root + '/tests/wine-host/retain.v')! != sha256.sum($embed_file('retain.v').to_string().bytes()).hex() {
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
		os.find_abs_path_of_executable(os.getenv_opt('READELF') or { '/opt/homebrew/opt/llvm/bin/llvm-readelf' })!]
	if host.firmware_vars != '' { required_inputs << host.firmware_vars }
	if arch == 'x86_64' { for _, path in plainiso.inputs(root)! { required_inputs << path } }
	for directory in ['tools/accounts', 'tools/packages', 'build-support/xorg-server/winehost',
		'build-support/native-compat-tools/compathost', 'tests/wine-host',
		'tests/hardware-platform/hwhost', 'tests/hardware-platform/plainiso'] {
		for path in os.walk_ext(root + '/' + directory, '.v') {
			if !path.ends_with('_test.v') { required_inputs << path }
		}
	}
	for name in ['build-support/xorg-server/wine-host-v-abi.h', 'build-support/xorg-server/build-wine-host.sh',
		'build-support/xorg-server/compile-v-host', 'build-support/native-compat-tools/main.v'] {
		required_inputs << root + '/' + name
	}
	inputs := json2.decode[map[string]string](os.read_file(run + '/inputs.json')!)!
	verified := json2.decode[map[string]string](os.read_file(run + '/inputs-verified.json')!)!
	if inputs != verified { return error('completed input verification differs from admitted inputs') }
	before := json2.decode[map[string]string](os.read_file(run + '/inputs-before-build.json')!)!
	for path, expected in before {
		if inputs[path] != expected { return error('input changed during build admission: ' + path) }
	}
	for path in required_inputs { if path !in inputs { return error('missing required admitted input: ' + path) } }
	mut paths := map[string]string{}
	for path, expected in inputs {
		if !path.starts_with('/') || digest(path)! != expected { return error('input digest mismatch: ' + path) }
		paths['input/' + path] = path
	}
	for name in ['native-check.v', 'native/main.v'] {
		if digest(run + '/source/tests/wine-host/' + name)! != inputs[root + '/tests/wine-host/' + name] {
			return error('frozen fixture source differs from admitted source')
		}
	}
	for directory in ['tools/accounts', 'tools/packages'] {
		for path in os.walk_ext(root + '/' + directory, '.v') {
			if !path.ends_with('_test.v') && digest(run + '/source/' + path[root.len + 1..])! != inputs[path] {
				return error('frozen account/package source differs from admitted source')
			}
		}
	}
	outputs := json2.decode[map[string]string](os.read_file(run + '/outputs.json')!)!
	mut required_outputs := ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json', 'result.json',
		'source/tests/wine-host/native-check.v', 'source/tests/wine-host/native/main.v',
		'boot/initramfs.tar', 'boot/serial.log', 'boot/qemu.log', 'boot/qmp.log', 'boot/image.log',
		'vinix-wine-host', 'vinix-wine-host.c', 'host-build.log', 'host-build.log.argv.json',
		'copy-xkb.log', 'copy-xkb.log.argv.json']
	for name in ['guest', 'vinix-account', 'vinix-session', 'vinix-authd', 'vinix-package'] {
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
	// Bind retained build products to the products admitted before boot, even
	// when a validator is checking a private copy of the output receipt.
	// The bridge also appears in extras/usr/bin. Find the unique build root
	// through the guest build product, then require each exact original path.
	mut build_roots := []string{}
	for path, _ in inputs {
		if path.ends_with('/build-guest/guest') { build_roots << path[..path.len - '/build-guest/guest'.len] }
	}
	if build_roots.len != 1 { return error('missing or ambiguous admitted build root') }
	for name in ['vinix-wine-host', 'vinix-wine-host.c', 'build-guest/guest', 'build-guest/guest.c',
		'build-vinix-account/vinix-account', 'build-vinix-account/vinix-account.c',
		'build-vinix-session/vinix-session', 'build-vinix-session/vinix-session.c',
		'build-vinix-authd/vinix-authd', 'build-vinix-authd/vinix-authd.c',
		'build-vinix-package/vinix-package', 'build-vinix-package/vinix-package.c'] {
		path := build_roots[0] + '/' + name
		if path !in inputs { return error('missing admitted build product: ' + name) }
		if outputs[name] != inputs[path] { return error('retained build product differs from boot input: ' + name) }
	}
	result := json2.decode[Outcome](os.read_file(run + '/result.json')!)!
	if result.scenario != 'hosted-X11' || !result.passed || result.interrupted || result.reason != '' {
		return error('requires an uninterrupted passing hosted-X11 result')
	}
	markers := ['HWTEST INFO signed-X11 ordinary-groups transport sandbox-context literal-document PASS',
		'HWTEST INFO real-Xvfb correct-cookie accepted wrong+missing-cookie refused PASS',
		'HWTEST INFO signed-X11 framebuffer colored-window damage-observed PASS',
		'HWTEST INFO real-Xvfb second-account authority+socket refused PASS',
		'HWTEST INFO signed-X11 bridge-closed server-reaped live-child-lease-held PASS',
		'HWTEST INFO signed-X11 natural-child-exit lease-released PASS', 'HWTEST PASS hosted-X11']
	serial := os.read_file(run + '/boot/serial.log')!
	for forbidden in [...hwhost.always_forbidden, 'Kernel panic', 'Fatal server error:'] {
		if serial.contains(forbidden) { return error('forbidden serial marker: ' + forbidden) }
	}
	lines := serial.split_into_lines().map(it.trim_space())
	for marker in markers { if lines.filter(it == marker).len != 1 { return error('missing or duplicated exact marker: ' + marker) } }
	paths['output-receipt'] = run + '/outputs.json'
	paths['retention-source'] = root + '/tests/wine-host/retain.v'
	paths['retention-controller'] = os.executable()
	mut artifacts := map[string]string{}
	for name, path in paths { artifacts[name] = digest(path)! }
	os.mkdir_all(out)!
	prefix := out + '/hosted-x11-' + arch
	os.write_file(prefix + '.json', json2.encode(Receipt{ architecture: arch,
		scope: 'qemu ordinary-account authenticated Xvfb signed-package literal launch, framebuffer and lease lifecycle',
		required_markers: markers, artifacts: artifacts, artifact_paths: paths }) + '\n')!
	os.cp(run + '/boot/serial.log', prefix + '.serial.txt')!
	println('HOSTED X11 RETAIN PASS ' + arch + ': seven exact native markers and all admitted artifact digests')
}

fn main() { retain() or { eprintln(err); exit(1) } }
