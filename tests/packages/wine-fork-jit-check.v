// SPDX-License-Identifier: GPL-2.0-or-later
// Supplemental diagnostic; historical translated-fork requirements stay intact.
module main

import crypto.sha256
import hwhost
import json2
import os
import tools.packages.wineadapter

const clang = '/opt/homebrew/opt/llvm/bin/clang'
const linker = '/opt/homebrew/bin/ld.lld'

struct Pin {
	digest string
	link string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut sum := []u8{len: sha256.size}
	defer { unsafe { buffer.free(); sum.free(); hash.free(); free(hash) } }
	for {
		count := file.read(mut buffer) or {
			if file.eof() { unsafe { err.free() }; break }
			return error('cannot hash ' + path)
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn pin(path string) !Pin {
	return Pin{digest: digest(path)!, link: if os.is_link(path) { os.readlink(path)! } else { '' }}
}

fn add_tree(path string, mut pins map[string]Pin) ! {
	for name in os.ls(path)! {
		entry := os.join_path(path, name)
		if os.is_dir(entry) && !os.is_link(entry) { add_tree(entry, mut pins)! }
		else if os.is_file(entry) { pins[entry] = pin(entry)! }
		else { return error('unsupported inventory entry: ' + entry) }
	}
}

fn verify(pins map[string]Pin) ! {
	if pins.len == 0 { return error('empty inventory') }
	for path, expected in pins {
		if pin(path)! != expected { return error('input changed: ' + path) }
	}
}

fn invoke(arguments []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(arguments))!
	hwhost.run_tool(arguments, map[string]string{}, log, 300)!
}

fn check() ! {
	$if prod {} $else { return error('compile fork JIT diagnostic with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-fork-jit-check.v').to_string()) {
		return error('compiled fork JIT diagnostic source differs')
	}
	if os.args.len != 5 { return error('usage: wine-fork-jit-check ROOT VERIFIED_BASELINE NEW_OUTPUT KERNEL_BUILD_RECEIPT') }
	root := os.real_path(os.args[1])
	base := os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	kernel_receipt := os.real_path(os.args[4])
	if os.exists(work) { return error('fork JIT diagnostic output exists') }
	if digest(root + '/tests/packages/wine-fork-jit-check.v')! != digest(@FILE)! {
		return error('selected diagnostic source differs')
	}
	inputs := json2.decode[map[string]Pin](os.read_file(base + '/inputs.json')!)!
	if inputs != json2.decode[map[string]Pin](os.read_file(base + '/inputs-verified.json')!)! {
		return error('baseline input verification differs')
	}
	generated := json2.decode[map[string]Pin](os.read_file(base + '/generated.json')!)!
	verify(inputs)!
	verify(generated)!
	arguments := json2.decode[[]string](os.read_file(base + '/controller.argv.json')!)!
	if arguments.len != 10 || os.real_path(arguments[2]) != base {
		return error('baseline controller arguments differ')
	}
	v := os.real_path(arguments[3])
	kernel := os.real_path(arguments[4])
	translator := os.real_path(arguments[5])
	arm_sysroot := os.real_path(arguments[6])
	arm_gcc := os.real_path(arguments[7])
	probe := base + '/probe/program'
	patched := base + '/extras/qemu-x86_64'
	if probe !in generated || patched !in generated || kernel !in inputs || v !in inputs
		|| translator !in inputs || digest(probe)! != digest(base + '/extras/fork-probe')! {
		return error('baseline selected executable missing')
	}
	if os.read_file(patched)! != wineadapter.splitwx_patch(os.read_file(translator)!)! {
		return error('baseline translator patch differs')
	}
	for name in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(name, v, true) }
	for name in ['V_MACOS_V3_CALLER_VEXE_PRESENT', 'V_MACOS_V3_NO_FALLBACK', 'V_C_ERROR_BUG_REPORT_DISABLED'] {
		os.setenv(name, '1', true)
	}
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	host := hwhost.find_host(root, 'aarch64', '')!
	loader := os.getenv_opt('VINIX_LIMINE_BOOTAA64') or {
		hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI')
	}
	os.setenv('VINIX_LIMINE_BOOTAA64', loader, true)
	mut selected := map[string]Pin{}
	for path in [os.executable(), @FILE, root + '/tests/packages/wine-fork-jit-check.v',
		root + '/tools/packages/wineadapter/patch.v', kernel_receipt, v, kernel, probe,
		patched, translator, clang, linker, host.qemu, host.firmware, loader,
		root + '/build-support/limine.conf', base + '/inputs.json',
		base + '/inputs-verified.json', base + '/generated.json', base + '/result.json',
		base + '/controller.argv.json'] { selected[path] = pin(path)! }
	if host.firmware_vars != '' { selected[host.firmware_vars] = pin(host.firmware_vars)! }
	for name in ['mformat', 'mmd', 'mcopy', 'tar', 'cp'] {
		path := os.find_abs_path_of_executable(name)!
		selected[path] = pin(path)!
	}
	for directory in [root + '/tests/hardware-platform/hwhost',
		root + '/tests/packages/wine-fork-jit-guest'] { add_tree(directory, mut selected)! }
	os.mkdir_all(work + '/guest')!
	os.mkdir_all(work + '/extras')!
	os.write_file(work + '/inputs.json', json2.encode(selected))!
	os.write_file(work + '/controller.argv.json', json2.encode(os.args))!
	cfile := work + '/guest/program.c'
	invoke([v, '-prod', '-backend', 'c', '-os', 'linux', '-arch', 'arm64', '-gc', 'none',
		'-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', cfile,
		root + '/tests/packages/wine-fork-jit-guest'], work + '/guest/v.log')!
	invoke([clang, '--target=aarch64-linux-musl', '--sysroot=' + arm_sysroot,
		'--gcc-install-dir=' + arm_gcc, '-fuse-ld=' + linker, '-static', '-O2', '-w',
		'-D_GNU_SOURCE', '-fno-stack-protector', cfile, '-lm', '-lpthread', '-o',
		work + '/guest/program'], work + '/guest/cc.log')!
	os.cp(probe, work + '/extras/fork-probe')!
	os.cp(patched, work + '/extras/qemu-x86_64')!
	os.chmod(work + '/extras/fork-probe', 0o755)!
	os.chmod(work + '/extras/qemu-x86_64', 0o755)!
	mut outputs := map[string]Pin{}
	add_tree(work + '/guest', mut outputs)!
	add_tree(work + '/extras', mut outputs)!
	os.write_file(work + '/generated.json', json2.encode(outputs))!
	verify(inputs)!
	verify(generated)!
	verify(selected)!
	hwhost.watch_interrupts()
	outcome := hwhost.run_scenario(host, hwhost.Scenario{
		name: 'translator-fork-jit-capture', arches: ['aarch64'],
		required: ['TRANSLATOR JIT ordinary uid/gid=1000 groups=0 no-WX-exception PASS',
			'VINIX QEMU FORK NOEXEC START', 'HWTEST PASS translator-fork-jit-capture'],
		forbidden: ['HWTEST FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC'], ending: .running
	}, hwhost.Run{kernel: kernel, guest: work + '/guest/program',
		extras: work + '/extras', state: work + '/boot', timeout: 120, keep: true})
	os.write_file(work + '/capture-result.json', json2.encode(outcome))!
	verify(inputs)!
	verify(generated)!
	verify(selected)!
	verify(outputs)!
	os.write_file(work + '/inputs-verified.json', json2.encode(selected))!
	if !outcome.passed || outcome.interrupted || outcome.reason != '' {
		return error('fork JIT capture failed: ' + outcome.reason)
	}
	println('FORK JIT CAPTURE COMPLETE (not workload qualification): ' + work)
}

fn main() { check() or { eprintln(err); exit(1) } }
