// SPDX-License-Identifier: GPL-2.0-or-later
module kpihost

import cachecli
import gamehost
import hostfixturebuild
import hosttest
import os
import sourcecommand

pub struct Tools {
pub:
	root         string
	command_hook fn ([]string, map[string]string, voidptr) !sourcecommand.Output = unsafe { nil }
	module_hook  fn (string, string, string, []string, voidptr) !                = unsafe { nil }
	header_hook  fn (string, string, bool, bool, voidptr) !                      = unsafe { nil }
	suite_hook   fn (string, string, bool, map[string]string, voidptr) !         = unsafe { nil }
	context      voidptr
}

pub fn (tools Tools) command(argv []string, environment map[string]string) !sourcecommand.Output {
	return tools.command_timeout(argv, environment, -1)!
}

pub fn (tools Tools) command_timeout(argv []string, environment map[string]string, timeout f64) !sourcecommand.Output {
	if tools.command_hook != unsafe { nil } {
		return tools.command_hook(argv, environment, tools.context)!
	}
	return sourcecommand.capture_full(argv, environment, timeout, 64 * 1024 * 1024, cachecli.cancelled)!
}

pub fn (tools Tools) checked(argv []string, environment map[string]string) !string {
	result := tools.command(argv, environment)!
	if result.status != 0 || result.stdout.contains('retrying with') || result.stderr.contains('retrying with') {
		return error('LinuxKPI command failed: ' + argv.str() + '\n' + result.stdout + result.stderr)
	}
	if result.stdout != '' {
		print(gamehost.decode_utf8(result.stdout.bytes()))
		flush_stdout()
	}
	if result.stderr != '' {
		eprint(gamehost.decode_utf8(result.stderr.bytes()))
		flush_stderr()
	}
	return result.stdout
}

pub fn (tools Tools) generate_module(source string, output string, arch string, defines []string) ! {
	if tools.module_hook != unsafe { nil } {
		tools.module_hook(source, output, arch, defines, tools.context)!
		return
	}
	result := hosttest.generate_module_capture(source, output, arch, defines)!
	if result.stdout.contains('retrying with') || result.stderr.contains('retrying with') {
		return error('V compiler fallback rejected: ' + result.stdout + result.stderr)
	}
	print(result.stdout)
	eprint(result.stderr)
}

pub fn (tools Tools) header_primitives(output string, arch string, host bool, implementations_only bool) ! {
	if tools.header_hook != unsafe { nil } {
		tools.header_hook(output, arch, host, implementations_only, tools.context)!
		return
	}
	hosttest.generate_header_primitives(output, arch, host, implementations_only)!
}

pub fn (tools Tools) host_suite(work string, arch string, sanitize bool, environment map[string]string) ! {
	if tools.suite_hook != unsafe { nil } {
		tools.suite_hook(work, arch, sanitize, environment, tools.context)!
		return
	}
	hostfixturebuild.build_suite(work, arch, sanitize, environment, host_arch()!)!
}

pub fn no_allocations(symbols string) ! {
	for word in hosttest.undefined_symbols(symbols) {
		name := word.trim_left('_')
		if name in ['malloc', 'calloc', 'realloc', 'free', 'memdup', 'v_malloc', 'v_calloc'] || name.starts_with('new_array') {
			return error('Implicit allocator import: ' + word)
		}
	}
}

pub fn dispatch(root string, command string, argv []string) !int {
	tools := Tools{ root: root }
	return match command {
		'fixture' { fixture_cli(tools, argv)! }
		'exchange' { exchange_cli(tools, argv)! }
		'goldens' { golden_cli(tools, argv)! }
		'native-host' { native_host_cli(tools, argv)! }
		'audit' { audit_cli(tools, argv)! }
		'audit-generation' { audit_generation_cli(tools, argv)! }
		'run' { host_run_cli(tools, argv)! }
		'pci-config' { pci_cli(tools, argv)! }
		else { return error_with_code('unknown LinuxKPI command: ' + command, 2) }
	}
}

fn private_work(argv []string, help string) !(cachecli.Arguments, string, bool) {
	args := cachecli.arguments(argv, ['--work'], [], [], 0, 0, help) or { return error_with_code(err.msg(), 2) }
	temporary := '--work' !in args.options
	work := if temporary {
		sourcecommand.temporary('vinix-linuxkpi-')!
	} else {
		args.required('--work')!
	}
	gamehost.mkdir(work)!
	return args, work, temporary
}

pub fn host_arch() !string {
	machine := os.uname().machine.to_lower()
	return match machine {
		'arm64', 'aarch64' { 'arm64' }
		'x86_64', 'amd64' { 'amd64' }
		else { return error('Unsupported LinuxKPI host: ' + machine) }
	}
}

pub fn clang_host_flags(arch string) []string {
	return if os.user_os() == 'macos' {
		['-arch', if arch == 'arm64' { 'arm64' } else { 'x86_64' }]
	} else {
		[]string{}
	}
}
