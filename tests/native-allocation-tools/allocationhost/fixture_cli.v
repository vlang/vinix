// SPDX-License-Identifier: GPL-2.0-or-later
module allocationhost

import cachecli
import guesthost
import hosttest
import os
import sourcecommand

pub fn test_cli(argv []string, sampler bool) int {
	args := cachecli.arguments(argv, ['--host-arch', '--arch', '--state-dir', '--original-reference',
		'--kernel-dir', '--guest-state-dir'], []string{}, if sampler {
		['--build-only']
	} else {
		['--model', '--build-only']
	}, 0, 0,
		'usage: test-v-' + if sampler { 'sampler' } else { 'bench' } + ' [--host-arch arm64|amd64] [--original-reference FILE] [--state-dir NEW_DIR] [--arch aarch64|x86_64 --kernel-dir DIR --guest-state-dir NEW_DIR] [--build-only]') or {
		eprintln(err)
		return 2
	}
	host_arch := args.value('--host-arch', $if amd64 { 'amd64' } $else { 'arm64' })
	guest := '--arch' in args.options
	guest_arch := args.value('--arch', if host_arch == 'arm64' { 'aarch64' } else { 'x86_64' })
	if host_arch !in ['arm64', 'amd64'] || guest_arch !in ['aarch64', 'x86_64'] {
		eprintln('invalid architecture')
		return 2
	}
	build_only := '--build-only' in args.options
	if build_only && !guest {
		eprintln('--build-only requires --arch')
		return 2
	}
	if guest && !build_only && ('--kernel-dir' !in args.options || '--guest-state-dir' !in args.options) {
		eprintln('--arch requires --kernel-dir and --guest-state-dir')
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	test_options(args, sampler, host_arch, guest, guest_arch, build_only) or {
		report_failure(err)
		return if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.msg() == 'Guest run interrupted' {
			130
		} else {
			1
		}
	}
	return 0
}

fn test_options(args cachecli.Arguments, sampler bool, host_arch string, guest bool, guest_arch string, build_only bool) ! {
	work := if '--state-dir' in args.options {
		hosttest.work_dir(if args.value('--state-dir', '') == '' {
			'.'
		} else {
			args.value('--state-dir', '')
		}, if sampler { 'vinix-sampler-test-' } else { 'vinix-bench-test-' })!
	} else {
		sourcecommand.temporary(if sampler { 'vinix-sampler-test' } else { 'vinix-bench-test' })!
	}
	defer { if '--state-dir' !in args.options { hosttest.remove_work_dir(work) or {} } }
	arch := if guest {
		if guest_arch == 'aarch64' { 'arm64' } else { 'amd64' }
	} else {
		host_arch
	}
	flags := compiler_flags(arch, guest, sampler)
	original := if '--original-reference' in args.options {
		resolve(args.value('--original-reference', ''))!
	} else {
		''
	}
	if sampler {
		executable := build_sampler(work, if arch == 'arm64' { 'aarch64' } else { 'x86_64' }, flags, original, guest)!
		if guest {
			if build_only {
				println(executable)
				return
			}
			guesthost.guest_with_cancel('', executable, args.value('--guest-state-dir', ''), args.value('--kernel-dir', ''), guest_arch, [sampler_verdict], []string{}, false, true, 360, cachecli.cancelled)!
		} else {
			result := capture([executable], environment(), 180)!
			if result.status != 0 || result.stdout != sampler_verdict + '\n' || !clean_diagnostics(result.stderr) {
				return error(result.str())
			}
			os.write_file(work + '/stdout', result.stdout)!
			print(result.stdout)
		}
		println('Shared kernel allocator sampler: original ownership and no implicit allocator imports passed')
		return
	}
	if guest {
		executable := build_benchmark(work, flags, arch, original, '--model' in args.options, true)!
		if build_only {
			println(executable)
			return
		}
		guesthost.guest_with_cancel('', executable, args.value('--guest-state-dir', ''), args.value('--kernel-dir', ''), guest_arch,
			['ALLOC-DONE label=native workloads=6 checksum=453'], ['ALLOC-ERROR'], false, true, 360, cachecli.cancelled)!
	} else if original != '' {
		os.mkdir(work + '/v')!
		os.mkdir(work + '/c')!
		translated := build_benchmark(work + '/v', flags, arch, '', true, false)!
		control := build_benchmark(work + '/c', flags, arch, original, true, false)!
		compare_benchmark(translated, control, work)!
	} else {
		executable := build_benchmark(work, flags, arch, '', '--model' in args.options, false)!
		result := invoke_benchmark(executable, ['--iterations', '2000', '--samples', '6', '--label',
			'host'], 'none', 1)!
		if result.status != 0 || !result.stdout.contains('ALLOC-DONE') || !clean_diagnostics(result.stderr) {
			return error(result.str())
		}
		os.write_file(work + '/stdout', result.stdout)!
		os.write_file(work + '/stderr', result.stderr)!
		println('Portable allocation benchmark: all six real host workloads passed')
	}
}
