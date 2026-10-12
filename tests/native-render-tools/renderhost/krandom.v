// SPDX-License-Identifier: GPL-2.0-or-later
module renderhost

import cachecli
import cachekey
import gamehost
import os
import sourcecommand

fn source_command_combined(argv []string, env map[string]string) !sourcecommand.Output {
	return sourcecommand.capture_combined(argv, env, -1, 64 * 1024 * 1024, cachecli.cancelled)!
}

pub fn krandom_cli(tools Tools, argv []string) !int {
	args := cachecli.arguments(argv, ['--kernel-dir', '--arch', '--v', '--state-dir'], [], [], 0, 0, 'Measure production random reseeding and partial reads on an isolated kernel.\nUsage: run_native --kernel-dir WORKTREE/kernel --arch aarch64|x86_64 --v COMPILER --state-dir NEW') or { return error_with_code(err.msg(), 2) }
	kernel := cachekey.resolve_path(args.required('--kernel-dir') or { return error_with_code(err.msg(), 2) })!
	compiler := cachekey.resolve_path(args.required('--v') or { return error_with_code(err.msg(), 2) })!
	state := cachekey.resolve_path(args.required('--state-dir') or { return error_with_code(err.msg(), 2) })!
	arch := args.required('--arch') or { return error_with_code(err.msg(), 2) }
	if arch !in ['aarch64', 'x86_64'] { return error_with_code('unsupported architecture', 2) }
	return krandom(tools, kernel, compiler, state, arch)!
}

pub fn krandom(tools Tools, kernel string, compiler string, state string, arch string) !int {
	parent := gamehost.parent(kernel)
	common_raw := tools.checked(['git', '-C', parent, 'rev-parse', '--git-common-dir'], os.environ())!.trim_space()
	common := cachekey.resolve_path(if common_raw.starts_with('/') {
		common_raw
	} else {
		parent + '/' + common_raw
	})!
	if parent == gamehost.parent(common) {
		return error_with_code('use an isolated git worktree for the kernel build', 2)
	}
	info := os.stat(compiler) or { return error_with_code('V compiler missing: ' + compiler, 2) }
	if info.get_filetype() != .regular {
		return error_with_code('V compiler missing: ' + compiler, 2)
	}
	gamehost.mkdir(gamehost.parent(state))!
	os.mkdir(state)!
	for name in ['obj/blob.c', 'obj/blob.c.o', 'obj/blob.c.d'] {
		os.rm(kernel + '/' + name) or {
			if os.exists(kernel + '/' + name) || os.is_link(kernel + '/' + name) {
				return err
			}
		}
	}
	mut env := os.environ()
	env['VEXE'] = compiler
	mut command := ['make', '-C', kernel, '-j4', 'CC=clang', 'V=' + compiler, 'ARCH=' + arch,
		'PROD=false', 'VFLAGS=-d krandom_selftest']
	if arch == 'x86_64' {
		linker := os.find_abs_path_of_executable('ld.lld') or { return error_with_code('ld.lld is required', 2) }
		command << 'LD_X86_64=' + linker
	}
	// Preserve the original merged build log, including the failed compiler.
	result := if tools.command_hook != unsafe { nil } {
		tools.command(command, env)!
	} else {
		source_command_combined(command, env)!
	}
	os.write_file(state + '/build.log', result.stdout + result.stderr)!
	if result.status != 0 {
		return error_with_code('random self-test kernel build failed; see ' + state + '/build.log', if result.status > 0 {
			result.status
		} else {
			1
		})
	}
	boot := tools.command([tools.root + '/tests/kernel-gaps/run-native', '--kernel-dir', kernel,
		'--arch', arch, '--source', tools.root + '/tests/kernel-gaps/smokefixture/core.v', '--state-dir',
		state + '/guest', '--timeout', '240', '--expect',
		'RANDOM-RESEED: 10000 reseeds and partial reads PASS', '--expect', 'KERNEL GUEST RUNNER: PASS'], env)!
	print(boot.stdout)
	eprint(boot.stderr)
	return boot.status
}
