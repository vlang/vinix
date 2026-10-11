// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import fixturehost
import guesthost
import hosttest
import json2
import math
import os
import policyhost
import strconv

fn regression_pass(text string, prefix string) !bool {
	rows := matched_rows(text, prefix + r'-CHECK DONE failures=(\d+)', 1)!
	return rows.len > 0 && rows[0][0] == '0' && !text.contains(prefix + '-CHECK FAIL')
}

fn regression_command(args []string, family string) !int {
	mut options := [hosttest.Option{ name: '--repo', value: true },
		hosttest.Option{ name: '--kernel', value: true }, hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--smp', value: true }, hosttest.Option{ name: '--log', value: true },
		hosttest.Option{ name: '--state-dir', value: true }, hosttest.Option{ name: '--build-only' }]
	if family == 'kernel-job-control' {
		for name in ['--fork-only', '--cycles-only', '--teardown-only', '--detached-churn'] { options << hosttest.Option{ name: name } }
	}
	parsed := hosttest.parse_arguments(args, options, 0,
		'Usage: run [--repo DIR] [--kernel DIR] [--timeout SECONDS] [--smp N] [--log FILE] [--state-dir FRESH-DIR] [--build-only]',
		'Cross-compile the unchanged ARM regression and supervise QEMU directly.') or { return error_with_code(err.msg(), 2) }
	repo := resolve(parsed.options['--repo'] or { root() })!
	kernel := resolve(parsed.options['--kernel'] or { root() + '/kernel' })!
	timeout := strconv.atof64(parsed.options['--timeout'] or { '180' }) or { return error_with_code('Invalid --timeout', 2) }
	if timeout <= 0 || math.is_nan(timeout) || math.is_inf(timeout, 0) { return error_with_code('--timeout must be finite and positive', 2) }
	smp := positive_option(parsed, '--smp', 4)!
	tag, prefix, filename := match family {
		'kernel-cpu' { 'cpu', 'CPU', 'cpu-regression.log' }
		'kernel-sysvmsg' { 'msg', 'MSG', 'sysvmsg-regression.log' }
		else { 'job', 'JOB', 'job-control-regression.log' }
	}
	log := resolve(parsed.options['--log'] or { filename })!
	work := hosttest.work_dir(parsed.options['--state-dir'] or { '' }, 'vinix-' + tag + '-')!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
	sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { repo + '/build-aarch64-userland/staging' }
	gcc_root := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl'
	mut versions := os.ls(gcc_root)!
	versions.sort()
	if versions.len == 0 { return error('Missing ARM Alpine GCC SDK') }
	gcc := gcc_root + '/' + versions.last()
	lib := sdk + '/usr/lib'
	source := root() + '/tests/' + family + '/check.c'
	binary := work + '/' + tag + '-check'
	mut command := [llvm + '/clang', '--target=aarch64-linux-musl', '-static', '-nostdinc', '-nostdlib',
		'-isystem', gcc + '/include', '-isystem', sdk + '/usr/include', '-O2', '-Wall', '-Wextra', '-Werror']
	if family == 'kernel-job-control' {
		for pair in [['--fork-only', 'JOB_FORK_ONLY'], ['--cycles-only', 'JOB_CYCLES_ONLY'],
			['--teardown-only', 'JOB_TEARDOWN_ONLY'], ['--detached-churn', 'JOB_DETACHED_CHURN']] {
			command << '-D' + pair[1] + '=' + if pair[0] in parsed.options { '1' } else { '0' }
		}
	}
	command << [lib + '/crt1.o', lib + '/crti.o', gcc + '/crtbeginT.o', source,
		'-L' + lib, '-L' + gcc, '-lc', '-lgcc', gcc + '/crtend.o', lib + '/crtn.o',
		'-fuse-ld=lld', '-B' + llvm, '-o', binary]
	run(command)!
	elf_arch(binary, 'aarch64')!
	private_kernel := snapshot_kernel(work, kernel, 'aarch64')!
	base := repo + '/build-support/init-aarch64/initramfs.tar'
	mut receipt := { 'family': json2.Any(family), 'compile_command': json2.Any(hosttest.strings(command)),
		'source_sha256': json2.Any(hosttest.sha(source)!), 'program_sha256': json2.Any(hosttest.sha(binary)!),
		'kernel_sha256': json2.Any(hosttest.sha(private_kernel + '/bin/vinix')!),
		'base_archive_sha256': json2.Any(hosttest.sha(base)!), 'timeout': json2.Any(timeout), 'smp': json2.Any(smp) }
	hosttest.write_json(work + '/inputs.json', receipt)!
	if '--build-only' in parsed.options { return 0 }
	// Keep the original shell image; only /sbin/init is replaced for this boot.
	os.mkdir(work + '/rootfs')!
	run(['tar', '-xf', base, '-C', work + '/rootfs'])!
	init := work + '/rootfs/sbin/init'
	if os.exists(init) || os.is_link(init) { os.rm(init)! }
	hosttest.module_copy_file_preserving_stat(binary, init)!
	archive := native_archive(work)!
	configured := guesthost.launch_from(binary, archive, work, private_kernel, 'aarch64', true, repo)!
	argv := configure_process_launch(configured.command, 'aarch64', 2048, smp, '')
	receipt['command'] = hosttest.strings(argv)
	hosttest.write_json(work + '/inputs.json', receipt)!
	os.mkdir_all(os.dir(log))!
	data := guesthost.boot_check_log(argv, configured.env, work, prefix + '-CHECK DONE', timeout, log)!
	for line in guesthost.replacement_text(data).split_into_lines() {
		if line.contains(prefix + '-CHECK') || (tag != 'cpu' && [prefix + '-SLAB', prefix + '-MEM'].any(line.contains(it))) { println(line.trim_right('\r')) }
	}
	println('Serial log: ' + log)
	passed := regression_pass(data.bytestr(), prefix)!
	hosttest.write_json(work + '/result.json', { 'passed': json2.Any(passed), 'serial_sha256': json2.Any(hosttest.sha(log)!) })!
	return if passed { 0 } else { 1 }
}

fn native_archive(work string) !string {
	archive := work + '/initramfs.tar'
	mut env := policyhost.environment()
	env['COPYFILE_DISABLE'] = '1'
	fixturehost.inherited_command_environment_preferred(['tar', '--format=ustar', '-cf', archive,
		'-C', work + '/rootfs', '.'], env, policyhost.caller_arch())!
	return archive
}
