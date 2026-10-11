// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import fixturehost
import guesthost
import hosttest
import json2
import os
import policyhost

fn smt_guest_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--build-only' }], 0, 'Usage: run [--state-dir FRESH-DIR] [--build-only]',
		'Boot the unchanged SMT affinity probe with both policies and the original topology.') or { return error_with_code(err.msg(), 2) }
	timeout := environment_timeout(180)!
	work := hosttest.work_dir(parsed.options['--state-dir'] or { '' }, 'vinix-smt-')!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	repo := resolve(os.getenv_opt('VINIX_VM_RUNNER_ROOT') or { root() })!
	private_kernel := snapshot_kernel_input(work, os.getenv_opt('VINIX_AMD64_KERNEL') or { root() + '/build-amd64-kernel/bin/vinix' }, 'x86_64')!
	compiler := os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }
	flags := [compiler, '-O2', '-Wall', '-Wextra', '-Werror', '-D_GNU_SOURCE', '-fno-strict-aliasing']
	fixture := work + '/fixture.o'
	guesthost.compile_module(root() + '/tests/smt-policy/guestfixture', fixture, 'x86_64', flags)!
	for name in ['sbin', 'dev', 'sys', 'proc', 'root'] { os.mkdir_all(work + '/rootfs/' + name)! }
	init := work + '/rootfs/sbin/init'
	compile := [compiler, '-static', '-O2', '-Wall', '-Wextra', '-Werror', fixture, '-o', init]
	run(compile)!
	elf_arch(init, 'x86_64')!
	mut receipt := { 'compile_command': json2.Any(hosttest.strings(compile)), 'fixture_flags': json2.Any(hosttest.strings(flags)),
		'init_sha256': json2.Any(hosttest.sha(init)!), 'kernel_sha256': json2.Any(hosttest.sha(private_kernel + '/bin/vinix')!),
		'sources': json2.Any(hosttest.string_map(directory_hashes(root() + '/tests/smt-policy/guestfixture', '')!)),
		'topology': json2.Any('4,sockets=1,cores=2,threads=2'), 'timeout': json2.Any(timeout) }
	mut variants := map[string]json2.Any{}
	for enabled in ['0', '1'] {
		write(work + '/rootfs/smt-request', enabled)!
		archive := native_archive(work)!
		state := work + '/policy-' + enabled
		os.mkdir(state)!
		os.cp(archive, state + '/initramfs.tar')!
		mut item := { 'request': json2.Any(enabled), 'cmdline': json2.Any('vinix.smt=' + enabled),
			'archive_sha256': json2.Any(hosttest.sha(state + '/initramfs.tar')!) }
		variants[enabled] = item
		receipt['variants'] = variants
		hosttest.write_json(work + '/inputs.json', receipt)!
		if '--build-only' in parsed.options { continue }
		configured := smt_launch(init, state, private_kernel, repo, enabled)!
		item['command'] = hosttest.strings(configured.command)
		variants[enabled] = item
		receipt['variants'] = variants
		hosttest.write_json(work + '/inputs.json', receipt)!
		// FEATURE_MARKERS and PASS_MARKER deliberately contain the same entry.
		code := guesthost.boot_abi(configured.command, configured.env, state, 'x86_64',
			['SMT POLICY: PASS', 'SMT POLICY: PASS'], 'SMT POLICY: PASS',
			['SMT POLICY: FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION'], timeout, true)!
		item['passed'] = code == 0
		variants[enabled] = item
		receipt['variants'] = variants
		hosttest.write_json(work + '/inputs.json', receipt)!
		if code != 0 { return code }
	}
	return 0
}

fn smt_launch(init string, state string, kernel string, repo string, enabled string) !guesthost.Launch {
	previous := os.getenv_opt('VINIX_CMDLINE')
	os.setenv('VINIX_CMDLINE', 'vinix.smt=' + enabled, true)
	defer { if text := previous { os.setenv('VINIX_CMDLINE', text, true) } else { os.unsetenv('VINIX_CMDLINE') } }
	configured := guesthost.launch_from(init, state + '/initramfs.tar', state, kernel, 'x86_64', false, repo)!
	return guesthost.Launch{
		command: optin_launch(configured.command, 'x86_64', state, 'max', '4,sockets=1,cores=2,threads=2', 'VINIX_OVMF_CODE')
		env: configured.env
	}
}

fn acpi_worktree(kernel string) ! {
	parent := os.dir(kernel)
	common_text := output(['git', '-C', parent, 'rev-parse', '--git-common-dir'])!.trim_space()
	common := resolve(if os.is_abs_path(common_text) { common_text } else { parent + '/' + common_text })!
	if parent == os.dir(common) { return error_with_code('use an isolated git worktree for the kernel build', 2) }
}

fn acpi_build_command(kernel string, compiler string, arch string, linker string, ar string) []string {
	mut argv := ['make', '-C', kernel, '-j4', 'CC=clang', 'V=' + compiler, 'ARCH=' + arch, 'ACPI_SYNC_TEST=1', 'STACK_GUARD_TEST=0']
	if ar != '' { argv << 'AR=' + ar }
	if arch == 'aarch64' { argv << ['LIMINE_MP=1', 'LD_AARCH64=' + linker] } else { argv << 'LD_X86_64=' + linker }
	return argv
}

fn acpi_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--v', value: true }, hosttest.Option{ name: '--state-dir', value: true }], 0,
		'Usage: run --kernel-dir ISOLATED-WORKTREE/kernel --arch aarch64|x86_64 --v V --state-dir DIR',
		'Build and exercise production ACPI gates in an isolated kernel worktree.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--kernel-dir', '--arch', '--v', '--state-dir'])!
	kernel := resolve(parsed.options['--kernel-dir'])!
	compiler := resolve(parsed.options['--v'])!
	state := resolve(parsed.options['--state-dir'])!
	acpi_worktree(kernel)!
	if !os.is_file(compiler) { return error_with_code('V compiler missing: ' + compiler, 2) }
	linker := os.find_abs_path_of_executable('ld.lld') or { return error_with_code('ld.lld is required', 2) }
	os.mkdir_all(state)!
	mut env := policyhost.environment()
	env['VEXE'] = compiler
	argv := acpi_build_command(kernel, compiler, parsed.options['--arch'], linker, os.getenv('AR'))
	hosttest.write_json(state + '/build-inputs.json', { 'command': json2.Any(hosttest.strings(argv)), 'v_sha256': json2.Any(hosttest.sha(compiler)!) })!
	fixturehost.capture_in_preferred(argv, state + '/build.log', env, true, '', false, policyhost.caller_arch()) or {
		return error('ACPI kernel build failed: ' + err.msg() + '; log: ' + state + '/build.log')
	}
	previous := os.getenv_opt('VEXE')
	os.setenv('VEXE', compiler, true)
	defer { if text := previous { os.setenv('VEXE', text, true) } else { os.unsetenv('VEXE') } }
	return guesthost.controller(['--kernel-dir', kernel, '--arch', parsed.options['--arch'],
		'--source', root() + '/tests/kernel-gaps/smokefixture/core.v', '--state-dir', state + '/guest',
		'--expect', 'ACPI-SYNC: bootstrap polling PASS', '--expect', 'ACPI-SYNC: ALL PASS',
		'--expect', 'KERNEL GUEST RUNNER: PASS'], 'generic')
}
