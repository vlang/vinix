// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import hosttest
import json2
import os

#include <unistd.h>
#include <fcntl.h>

fn C.mkstemp(&u8) i32
fn C.fchmod(i32, u32) i32
fn C.rename(&char, &char) i32
fn C.unlink(&char) i32

fn install(source string, destination string, mode u32, prefix string) ! {
	os.mkdir_all(os.dir(destination))!
	mut pattern := (os.dir(destination) + '/' + prefix + 'XXXXXX\x00').bytes()
	fd := unsafe { C.mkstemp(pattern.data) }
	if fd < 0 { return error_with_code('Cannot create staged temporary file', int(C.errno)) }
	temporary := pattern[..pattern.len - 1].bytestr()
	mut opened := true
	defer {
		if opened { C.close(fd) }
		unsafe { C.unlink(temporary.str) }
	}
	data := os.read_bytes(source)!
	mut sent := 0
	for sent < data.len {
		count := unsafe { C.write(fd, &data[sent], usize(data.len - sent)) }
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return error_with_code('Cannot write staged temporary file', int(C.errno))
		}
		if count == 0 { return error('Short write to staged temporary file') }
		sent += int(count)
	}
	if C.fchmod(fd, mode) != 0 {
		return error_with_code('Cannot set staged permissions', int(C.errno))
	}
	opened = false
	if C.close(fd) != 0 {
		return error_with_code('Cannot close staged temporary file', int(C.errno))
	}
	if unsafe { C.rename(temporary.str, destination.str) } != 0 {
		return error_with_code('Cannot publish staged file', int(C.errno))
	}
}

fn elf_arch(path string, arch string) ! {
	data := os.read_bytes(path)!
	if data.len < 20 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| int(data[18]) + (int(data[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } {
		return error('Compiler produced a wrong-architecture ELF executable')
	}
}

fn stage_command(args []string, security bool) !int {
	parsed := hosttest.parse_arguments(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--staging', value: true },
		hosttest.Option{ name: '--cc', value: true },
	], 0,
		'Usage: stage --arch aarch64|x86_64 --staging DIR [--cc COMPILER]', 'Build and atomically install native V utilities into a target filesystem.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--arch', '--staging'])!
	arch := parsed.options['--arch']
	staging := resolve(parsed.options['--staging'])!
	if staging == '/' || !os.is_dir(staging) {
		return error_with_code('staging must be an existing target filesystem', 2)
	}
	mut compiler := parsed.options['--cc']
	if compiler == '' && security { compiler = os.getenv('VINIX_SECURITY_CC_' + arch.to_upper()) }
	if compiler == '' { compiler = os.getenv('VINIX_MUSL_CC_' + arch.to_upper()) }
	if compiler == '' { compiler = arch + '-linux-musl-gcc' }
	cc := hosttest.shell_split(compiler)!
	if cc.len == 0 { return error_with_code('Target musl compiler is missing', 2) }
	if security {
		os.find_abs_path_of_executable(cc[0]) or { return error_with_code('Target musl compiler is missing', 2) }
	}
	machine := output([...cc, '-dumpmachine'])!.trim_space()
	if !machine.starts_with(arch + '-') || !machine.contains('linux') {
		return error_with_code('Compiler architecture mismatch: ' + machine, 2)
	}
	work := hosttest.work_dir('', if security {
		'vinix-security-tools-'
	} else {
		'vinix-volume-tool-'
	})!
	defer { retire(work) }
	tools := if security { ['sandbox', 'mac', 'audit'] } else { ['volume'] }
	for tool in tools {
		module_path, headers, destination := match tool {
			'sandbox' { '', root() + '/tools/sandbox', '/usr/bin/vinix-sandbox' }
			'mac' { '', root() + '/tools/security-mac', '/usr/sbin/vinix-mac' }
			'audit' { '', root() + '/tools/security-audit', '/usr/sbin/vinix-security-audit' }
			else {
				root() + '/tools/volumes/volumecli', root() + '/tools/volumes/volumecli', '/usr/sbin/vinix-volume'
			}
		}
		source := work + '/' + tool + '.c'
		if security {
			security_core(tool, source, if arch == 'aarch64' { 'arm64' } else { 'amd64' }, []string{})!
		} else {
			generate(module_path, source, if arch == 'aarch64' { 'arm64' } else { 'amd64' }, []string{}, '')!
			write(source, read(source)! + '\n_Static_assert(sizeof(volumecli__Request)==32, "V request ABI");\n_Static_assert(sizeof(volumecli__Status)==128, "V status ABI");\n_Static_assert(sizeof(volumecli__Health)==1088, "V health ABI");\n_Static_assert(offsetof(volumecli__Health,data)==576, "V health data ABI");\n')!
		}
		binary := work + '/' + os.file_name(destination)
		mut flags := [...cc, '-static', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror']
		if !security {
			flags << ['-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label']
		}
		run([...flags, '-D_GNU_SOURCE', '-DVINIX_V_RUNTIME', '-I', headers, source, '-o', binary])!
		elf_arch(binary, arch)!
		install(binary, staging + destination, 0o755, if security {
			'.security-tool-'
		} else {
			'.vinix-volume-'
		})!
	}
	if security {
		// The default image must contain the privileged service and first-account
		// bootstrap before init can launch its ordinary graphical manager.
		run(['sh', root() + '/build-support/run-v-tool.sh', root() + '/tools/accounts/stage.v',
			'--arch', arch, '--staging', staging, '--cc-argv', json2.encode(cc)])!
		// Both desktop builders already stage these utilities. Keep package
		// distribution in the same native V build path on both architectures.
		run(['sh', root() + '/build-support/run-v-tool.sh', root() + '/tools/packages/stage.v',
			'--arch', arch, '--staging', staging, '--cc-argv', json2.encode(cc)])!
		install(root() + '/build-support/security-audit/run-collector', staging + '/usr/libexec/vinix-security-audit-supervise', 0o755, '.security-tool-')!
		log := staging + '/var/log/vinix-audit'
		if os.is_link(log) { return error('Audit log staging directory cannot be a symlink') }
		os.mkdir_all(log)!
		os.chmod(log, 0o700)!
		println('Staged Vinix sandbox, mandatory policy and audit utilities (' + arch + ').')
	} else {
		println('Staged vinix-volume (' + arch + ').')
	}
	return 0
}
