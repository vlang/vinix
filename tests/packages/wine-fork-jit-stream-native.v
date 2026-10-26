// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone supplemental capture; canonical fork requirements stay unchanged.
module main

import crypto.sha256
import hwhost
import json2
import os
import tools.packages.winejitstream

const native_clang = '/opt/homebrew/opt/llvm/bin/clang'
const native_linker = '/opt/homebrew/bin/ld.lld'
const native_resource = '/opt/homebrew/opt/llvm/lib/clang/23'
const native_translator_sha = '93f1e83fbb7cedcfe2813f6b65775685a8dbc46943c1280ad3da650567985475'

struct KernelBinding {
	architecture     string
	profile          string
	build_executed   bool
	build_exit_code  int
	candidate_commit string
	outputs          map[string]string
}

fn native_sources(root string) ! {
	expected := {
		'tests/packages/wine-fork-jit-stream-native.v': $embed_file('wine-fork-jit-stream-native.v').to_string()
		'tools/packages/winejitstream/native_guard.v':  $embed_file('../../tools/packages/winejitstream/native_guard.v').to_string()
		'tools/packages/winejitstream/native_inputs.v': $embed_file('../../tools/packages/winejitstream/native_inputs.v').to_string()
		'tools/packages/winejitstream/native_policy.v': $embed_file('../../tools/packages/winejitstream/native_policy.v').to_string()
		'tools/packages/winejitstream/supervisor.v':    $embed_file('../../tools/packages/winejitstream/supervisor.v').to_string()
		'tools/packages/winejitstream/parse.v':         $embed_file('../../tools/packages/winejitstream/parse.v').to_string()
		'tests/hardware-platform/hwhost/boot.v':        $embed_file('../hardware-platform/hwhost/boot.v').to_string()
		'tests/hardware-platform/hwhost/process.v':     $embed_file('../hardware-platform/hwhost/process.v').to_string()
		'tests/hardware-platform/hwhost/vm.v':          $embed_file('../hardware-platform/hwhost/vm.v').to_string()
		'tests/hardware-platform/hwhost/host.v':        $embed_file('../hardware-platform/hwhost/host.v').to_string()
		'tests/hardware-platform/hwhost/qmp_client.v':  $embed_file('../hardware-platform/hwhost/qmp_client.v').to_string()
		'tests/hardware-platform/hwhost/qmp.v':         $embed_file('../hardware-platform/hwhost/qmp.v').to_string()
		'tests/hardware-platform/hwhost/markers.v':     $embed_file('../hardware-platform/hwhost/markers.v').to_string()
		'tests/hardware-platform/hwhost/scenario.v':    $embed_file('../hardware-platform/hwhost/scenario.v').to_string()
	}
	for relative, text in expected {
		if winejitstream.native_input_digest(root + '/' + relative)! != sha256.hexhash(text) {
			return error('compiled native source differs: ' + relative)
		}
	}
}

fn native_invoke(arguments []string, work string, name string, timeout_ms int) ! {
	os.write_file(work + '/' + name + '.argv.json', json2.encode(arguments))!
	result := winejitstream.native_guard(arguments, work, name + '.log', winejitstream.native_capture_limits(timeout_ms))!
	os.write_file(work + '/' + name + '.guard.json', json2.encode(result))!
	if !result.stopped || result.wait_status != 0 || result.timed_out || result.size_limited || result.reason != '' {
		return error('native operation failed or exceeded bounds: ' + name)
	}
}

fn little16(bytes []u8, offset int) u16 {
	return u16(bytes[offset]) | (u16(bytes[offset + 1]) << 8)
}

fn little32(bytes []u8, offset int) u32 {
	return u32(little16(bytes, offset)) | (u32(little16(bytes, offset + 2)) << 16)
}

fn little64(bytes []u8, offset int) u64 {
	mut result := u64(0)
	for index in 0 .. 8 { result |= u64(bytes[offset + index]) << (index * 8) }
	return result
}

fn native_static_elf(path string, machine u16) ! {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	if bytes.len < 64 || bytes[..4] != [u8(0x7f), `E`, `L`, `F`] || bytes[4] != 2
		|| bytes[5] != 1 || little16(bytes, 16) !in [u16(2), 3]
		|| little16(bytes, 18) != machine || little16(bytes, 54) != 56 {
		return error('requires matching ELF64 executable: ' + path)
	}
	start := little64(bytes, 32)
	count := int(little16(bytes, 56))
	if count < 1 || count > 64 || start > u64(bytes.len) || u64(count * 56) > u64(bytes.len) - start {
		return error('invalid ELF program table')
	}
	for index in 0 .. count {
		if little32(bytes, int(start) + index * 56) == 3 {
			return error('dynamic ELF interpreter outside standalone scope')
		}
	}
}

fn native_boot(root string, work string, kernel string) ! {
	native_sources(root)!
	host := hwhost.find_host(root, 'aarch64', '')!
	hwhost.watch_interrupts()
	outcome := hwhost.run_scenario(host, hwhost.Scenario{
		name:      'jit-stream-capture'
		arches:    ['aarch64']
		required:  ['JITSTREAM CAPTURE ',
			'HWTEST COMPLETE jit-stream-capture (not workload qualification)']
		forbidden: ['HWTEST FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC']
		ending:    .running
	}, hwhost.Run{
		kernel:  kernel
		guest:   work + '/guest/program'
		extras:  work + '/extras'
		state:   work + '/boot'
		timeout: 60
		keep:    true
	})
	os.write_file(work + '/capture-result.json', json2.encode(outcome))!
	if !outcome.passed || outcome.interrupted || outcome.reason != '' {
		return error('native capture markers unavailable')
	}
}

fn native_run() ! {
	$if prod {
	} $else {
		return error('compile native stream controller with -prod')
	}
	if os.args.len != 11 {
		return error('usage: native-stream ROOT PATCHED_TRANSLATOR KERNEL KERNEL_RECEIPT V ARM_SYSROOT ARM_GCC AMD_SYSROOT AMD_GCC NEW_OUTPUT')
	}
	root := os.real_path(os.args[1])
	translator := os.real_path(os.args[2])
	kernel := os.real_path(os.args[3])
	receipt := os.real_path(os.args[4])
	v := os.real_path(os.args[5])
	arm_sysroot := os.real_path(os.args[6])
	arm_gcc := os.real_path(os.args[7])
	amd_sysroot := os.real_path(os.args[8])
	amd_gcc := os.real_path(os.args[9])
	work := os.abs_path(os.args[10])
	if os.exists(work) || os.is_link(work) { return error('native output already exists') }
	if os.real_path(os.dir(work)) != os.dir(work) {
		return error('output parent must be canonical')
	}
	native_sources(root)!
	if winejitstream.native_input_digest(translator)! != native_translator_sha {
		return error('patched translator differs')
	}
	native_static_elf(translator, 183)!
	binding := json2.decode[KernelBinding](os.read_file(receipt)!)!
	if binding.architecture != 'arm' || binding.profile != 'prod' || !binding.build_executed
		|| binding.build_exit_code != 0 || binding.candidate_commit.len != 40
		|| binding.outputs[kernel] != winejitstream.native_input_digest(kernel)! {
		return error('kernel bytes not bound by ARM build receipt')
	}
	for name in ['V', 'VEXE', 'VINIX_V_COMPILER', 'V_MACOS_V3_CALLER_VEXE'] {
		os.setenv(name, v, true)
	}
	for name in ['V_MACOS_V3_CALLER_VEXE_PRESENT', 'V_MACOS_V3_NO_FALLBACK',
		'V_C_ERROR_BUG_REPORT_DISABLED'] {
		os.setenv(name, '1', true)
	}
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT', '0', true)
	for name in ['VCHILD', 'V_MACOS_V3_CALLER_VCHILD', 'V_MACOS_V3_CALLER_NO_FALLBACK',
		'V_MACOS_V3_CHILD_VEXE_PRESENT'] {
		os.unsetenv(name)
	}
	os.setenv('LANG', 'C', true)
	os.setenv('LC_ALL', 'C', true)
	os.setenv('PATH', '/opt/homebrew/bin:/usr/bin:/bin', true)
	for name in ['VINIX_ALLOW_WX', 'QEMU_LOG_FILENAME', 'QEMU_LOG', 'QEMU_STRACE'] {
		os.unsetenv(name)
	}
	compiler_environment := winejitstream.native_clear_compiler_environment()
	host := hwhost.find_host(root, 'aarch64', '')!
	loader := os.getenv_opt('VINIX_LIMINE_BOOTAA64') or { hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI') }
	os.setenv('VINIX_LIMINE_BOOTAA64', loader, true)
	mut inputs := map[string]winejitstream.NativePin{}
	for path in [os.executable(), v, translator, kernel, receipt, native_clang, native_linker,
		host.qemu, host.firmware, host.firmware_vars, loader, root + '/build-support/limine.conf'] {
		winejitstream.native_input_add(path, mut inputs)!
	}
	for name in ['mformat', 'mmd', 'mcopy', 'tar', 'cp'] {
		winejitstream.native_input_add(os.find_abs_path_of_executable(name)!, mut inputs)!
	}
	for directory in [os.dir(v) + '/vlib', os.dir(v) + '/thirdparty', arm_sysroot, arm_gcc,
		amd_sysroot, amd_gcc, native_resource, root + '/tests/hardware-platform/hwhost',
		root + '/tools/packages/winejitstream', root + '/tests/packages/wine-fork-jit-stream-probe',
		root + '/tests/packages/wine-fork-jit-stream-guest'] {
		winejitstream.native_input_tree(directory, mut inputs)!
	}
	for relative in ['tests/packages/wine-fork-jit-stream-native.v',
		'tests/packages/wine-fork-jit-stream-check.v'] {
		winejitstream.native_input_add(root + '/' + relative, mut inputs)!
	}
	// Reserve for private boot media, retained state and monitored-threshold overshoot.
	winejitstream.native_require_free(os.dir(work), winejitstream.native_free_floor(true))!
	os.mkdir(work)!
	for directory in ['guest', 'probe', 'extras', 'tmp'] { os.mkdir(work + '/' + directory)! }
	os.setenv('TMPDIR', work + '/tmp', true)
	os.setenv('VTMP', work + '/tmp', true)
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	os.write_file(work + '/controller.argv.json', json2.encode(os.args))!
	mut environment := map[string]string{}
	for name in ['V', 'VEXE', 'VINIX_V_COMPILER', 'V_MACOS_V3_CALLER_VEXE',
		'V_MACOS_V3_CALLER_VEXE_PRESENT', 'V_MACOS_V3_CALLER_VCHILD', 'V_MACOS_V3_CALLER_VCHILD_PRESENT',
		'V_MACOS_V3_CALLER_NO_FALLBACK', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT',
		'V_MACOS_V3_NO_FALLBACK', 'VCHILD', 'V_C_ERROR_BUG_REPORT_DISABLED', 'LANG', 'LC_ALL',
		'PATH', 'TMPDIR', 'VTMP', 'VINIX_LIMINE_BOOTAA64', 'VINIX_HWTEST_TCG'] {
		environment[name] = os.getenv(name)
	}
	os.write_file(work + '/environment.json', json2.encode(environment))!
	os.write_file(work + '/compiler-environment.json', json2.encode(compiler_environment))!
	for role in ['probe', 'guest'] {
		arch := if role == 'guest' { 'arm64' } else { 'amd64' }
		cfile := work + '/' + role + '/program.c'
		native_invoke([v, '-nocache', '-prod', '-backend', 'c', '-os', 'linux', '-arch', arch, '-gc', 'none',
			'-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path',
			'@vlib|' + root + '|@vmodules', '-o', cfile,
			root + '/tests/packages/wine-fork-jit-stream-' + role], work, role + '-v', 60000)!
		sysroot := if role == 'guest' { arm_sysroot } else { amd_sysroot }
		gcc := if role == 'guest' { arm_gcc } else { amd_gcc }
		target := if role == 'guest' { 'aarch64' } else { 'x86_64' }
		native_invoke(winejitstream.native_target_c_arguments(native_clang, native_linker,
			native_resource, target, sysroot, gcc, cfile, work + '/' + role + '/program')!,
			work, role + '-cc', 60000)!
		native_static_elf(work + '/' + role + '/program', if role == 'guest' {
			u16(183)
		} else {
			u16(62)
		})!
	}
	os.cp(translator, work + '/extras/qemu-x86_64')!
	os.cp(work + '/probe/program', work + '/extras/fork-jit-stream-probe')!
	for name in ['qemu-x86_64', 'fork-jit-stream-probe'] {
		os.chmod(work + '/extras/' + name, 0o755)!
	}
	mut generated := map[string]winejitstream.NativePin{}
	for directory in ['guest', 'probe', 'extras'] {
		winejitstream.native_input_tree(work + '/' + directory, mut generated)!
	}
	os.write_file(work + '/generated.json', json2.encode(generated))!
	winejitstream.native_input_verify(inputs)!
	winejitstream.native_require_free(work, winejitstream.native_free_floor(true))!
	native_invoke([os.executable(), '--boot', root, work, kernel], work, 'boot-worker', 90000)!
	winejitstream.native_input_verify(inputs)!
	winejitstream.native_input_verify(generated)!
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	os.write_file(work + '/scope.json', json2.encode({
		'scope':                   'Supplemental PID stream capture only. No canonical workload, ARM, Wine, shared backing, failure cause or complete corresponding-source qualification.'
		'kernel_candidate_commit': binding.candidate_commit
		'observed_state_bytes':    winejitstream.native_state_bytes(work)!.str()
		'limits':                  'VM worker90s plus cleanup2s; innerVM60s; build steps60s each; file hard128MiB; monitored state256MiB/log256KiB/serial6MiB every10ms, thresholds may overshoot; checked statvfs >=2GiB initially/pre-VM and >=1GiB before each child and once per second during it.'
		'toolchain_limit':         'Captured paths for selected sources, compiler, resources, target dependencies and host tools are pinned and rechecked. Newly added directory entries, host SDK, transitive dynamic libraries and external tool behavior are not hermetically frozen.'
	}))!
	println('STANDALONE JIT STREAM CAPTURE COMPLETE (not workload qualification): ' + work)
}

fn main() {
	if os.args.len == 5 && os.args[1] == '--boot' {
		native_boot(os.args[2], os.args[3], os.args[4]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	native_run() or {
		eprintln(err)
		exit(1)
	}
}
