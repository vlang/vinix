// SPDX-License-Identifier: GPL-2.0-or-later
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
			return error('cannot hash ' + path + ': ' + err.msg())
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn pin(path string) !Pin {
	return Pin{ digest: digest(path)!, link: if os.is_link(path) { os.readlink(path)! } else { '' } }
}

fn inventory(files []string, directories []string) !map[string]Pin {
	mut result := map[string]Pin{}
	for path in files { result[path] = pin(path)! }
	for directory in directories {
		if !os.is_dir(directory) { return error('missing inventory directory: ' + directory) }
		for path in os.walk_ext(directory, '') {
			if os.is_file(path) { result[path] = pin(path)! }
		}
	}
	return result
}

fn invoke(arguments []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(arguments))!
	hwhost.run_tool(arguments, map[string]string{}, log, 300)!
}

fn build(v string, source string, arch string, sysroot string, gcc string, work string) !string {
	os.mkdir_all(work)!
	cfile := work + '/program.c'
	invoke([v, '-prod', '-backend', 'c', '-os', 'linux', '-arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-gc', 'none', '-manualfree',
		'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', cfile, source], work + '/v.log')!
	invoke([clang, '--target=' + arch + '-linux-musl', '--sysroot=' + sysroot,
		'--gcc-install-dir=' + gcc, '-fuse-ld=' + linker, '-static', '-O2', '-w',
		'-D_GNU_SOURCE', '-fno-stack-protector', cfile, '-lm', '-lpthread', '-o',
		work + '/program'], work + '/cc.log')!
	return work + '/program'
}

fn check() ! {
	$if prod {} $else { return error('compile translator fork controller with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-translation-fork-check.v').to_string()) {
		return error('compiled translator fork controller source differs')
	}
	if os.args.len != 10 {
		return error('usage: wine-translation-fork-check ROOT OUTPUT V KERNEL ORIGINAL_TRANSLATOR ARM_SYSROOT ARM_GCC X86_SYSROOT X86_GCC')
	}
	root := os.real_path(os.args[1])
	work := os.abs_path(os.args[2])
	v := os.real_path(os.args[3])
	kernel := os.real_path(os.args[4])
	translator := os.real_path(os.args[5])
	arm_sysroot := os.real_path(os.args[6])
	arm_gcc := os.real_path(os.args[7])
	x86_sysroot := os.real_path(os.args[8])
	x86_gcc := os.real_path(os.args[9])
	if os.exists(work) { return error('translator fork output already exists') }
	if digest(root + '/tests/packages/wine-translation-fork-check.v')! != digest(@FILE)! {
		return error('selected source root differs from controller')
	}
	if digest(root + '/tools/packages/wineadapter/patch.v')! != sha256.hexhash($embed_file('../../tools/packages/wineadapter/patch.v').to_string()) {
		return error('compiled translator patch source differs')
	}
	os.setenv('V', v, true)
	os.setenv('VEXE', v, true)
	os.setenv('V_MACOS_V3_CALLER_VEXE', v, true)
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	host := hwhost.find_host(root, 'aarch64', '')!
	loader := os.getenv_opt('VINIX_LIMINE_BOOTAA64') or {
		hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI')
	}
	os.setenv('VINIX_LIMINE_BOOTAA64', loader, true)
	mut files := [os.executable(), @FILE, v, kernel, translator, clang, linker,
		host.qemu, host.firmware, root + '/build-support/limine.conf',
		root + '/tests/packages/wine-fork-probe/main.v',
		root + '/tests/packages/wine-translation-fork-guest/main.v',
		root + '/tools/packages/wineadapter/patch.v',
		loader]
	if host.firmware_vars != '' { files << host.firmware_vars }
	for name in ['mformat', 'mmd', 'mcopy', 'tar', 'cp'] {
		files << os.find_abs_path_of_executable(name)!
	}
	directories := [root + '/tests/hardware-platform/hwhost',
		root + '/tests/packages/wine-fork-probe',
		root + '/tests/packages/wine-translation-fork-guest', os.dir(v) + '/vlib',
		os.dir(v) + '/thirdparty', arm_sysroot + '/usr/include', arm_sysroot + '/usr/lib',
		arm_sysroot + '/lib', arm_gcc, x86_sysroot + '/usr/include',
		x86_sysroot + '/usr/lib', x86_sysroot + '/lib', x86_gcc]
	inputs := inventory(files, directories)!
	if inputs[@FILE].digest != sha256.hexhash($embed_file('wine-translation-fork-check.v').to_string())
		|| inputs[root + '/tests/packages/wine-translation-fork-check.v'].digest != inputs[@FILE].digest
		|| inputs[root + '/tools/packages/wineadapter/patch.v'].digest != sha256.hexhash($embed_file('../../tools/packages/wineadapter/patch.v').to_string()) {
		return error('captured translator fork sources differ from compiled controller')
	}
	os.mkdir_all(work + '/extras')!
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	os.write_file(work + '/controller.argv.json', json2.encode(os.args))!
	// The adapter accepts the original pinned bytes and forces split RW/RX.
	// No executable or kernel privilege exception is introduced by this test.
	original := os.read_file(translator)!
	patched := wineadapter.splitwx_patch(original)!
	os.write_file(work + '/extras/qemu-x86_64', patched)!
	os.chmod(work + '/extras/qemu-x86_64', 0o755)!
	probe := build(v, root + '/tests/packages/wine-fork-probe', 'x86_64',
		x86_sysroot, x86_gcc, work + '/probe')!
	guest := build(v, root + '/tests/packages/wine-translation-fork-guest', 'aarch64',
		arm_sysroot, arm_gcc, work + '/guest')!
	os.cp(probe, work + '/extras/fork-probe')!
	os.chmod(work + '/extras/fork-probe', 0o755)!
	generated := inventory([], [work + '/probe', work + '/guest', work + '/extras'])!
	os.write_file(work + '/generated.json', json2.encode(generated))!
	if inventory(files, directories)! != inputs { return error('translator fork inputs changed during build') }
	hwhost.watch_interrupts()
	outcome := hwhost.run_scenario(host, hwhost.Scenario{
		name: 'translator-fork', arches: ['aarch64'],
		required: ['TRANSLATOR FORK ordinary uid/gid=1000 groups=0 no-WX-exception PASS',
			'VINIX QEMU FORK NOEXEC 32 CHILDREN REAPED PASS', 'HWTEST PASS translator-fork'],
		forbidden: ['HWTEST FAIL', 'QEMU internal SIGSEGV', 'FATAL EXCEPTION', 'KERNEL PANIC'],
		ending: .running
	}, hwhost.Run{kernel: kernel, guest: guest, extras: work + '/extras',
		state: work + '/boot', timeout: 120, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	if inventory(files, directories)! != inputs { return error('translator fork inputs changed during boot') }
	if inventory([], [work + '/probe', work + '/guest', work + '/extras'])! != generated {
		return error('translator fork generated files changed during boot')
	}
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if !outcome.passed || outcome.interrupted || outcome.reason != '' {
		return error('translator fork failed: ' + outcome.reason)
	}
	println('TRANSLATOR FORK PASS: ' + work)
}

fn main() {
	check() or { eprintln(err); exit(1) }
}
