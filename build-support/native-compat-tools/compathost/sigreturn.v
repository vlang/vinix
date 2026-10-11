// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import guesthost
import hosttest
import json2
import os
import policyhost
import fixturehost

fn sigreturn_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--runner-root', value: true },
		hosttest.Option{ name: '--musl', value: true },
		hosttest.Option{ name: '--cc', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--build-only' },
	], 0, 'Usage: run --state-dir FRESH-DIR [--kernel-dir DIR] [--runner-root DIR] [--musl FILE] [--cc COMPILER] [--timeout SECONDS] [--build-only]',
		'Exercise genuine dynamic-musl ARM64 signal return in an isolated native guest.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--state-dir'])!
	work_path := resolve(parsed.options['--state-dir'])!
	if os.exists(work_path) { return error_with_code('Use a fresh state directory to preserve prior evidence', 2) }
	kernel := resolve(parsed.options['--kernel-dir'] or { root() + '/kernel' })!
	loader := resolve(parsed.options['--musl'] or {
		root() + '/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/lib/ld-musl-aarch64.so.1'
	})!
	repo := resolve(parsed.options['--runner-root'] or { root() })!
	timeout := positive_option(parsed, '--timeout', 90)!
	for source in [kernel + '/bin/vinix', loader, repo + '/build-support/build-aarch64-iso.sh'] {
		if !os.is_file(source) { return error_with_code('Built kernel, genuine musl image and native runner required: ' + source, 2) }
	}
	cc := os.find_abs_path_of_executable(parsed.options['--cc'] or {
		os.getenv_opt('VINIX_AARCH64_CC') or { 'aarch64-linux-musl-gcc' }
	}) or { return error_with_code('ARM64 musl compiler unavailable: ' + err.msg(), 2) }
	work := hosttest.work_dir(work_path, 'vinix-sigreturn-')!
	flags := ['-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector', '-Wl,-z,max-page-size=65536']
	commands := [
		[cc, ...flags, root() + '/tests/aarch64-sigreturn/probe.c', '-ldl', '-o', work + '/signal-return-probe'],
		[cc, ...flags, '-static', root() + '/tests/aarch64-sigreturn/init.c', '-o', work + '/init'],
	]
	for command in commands { run(command)! }
	elf_arch(work + '/init', 'aarch64')!
	elf_arch(work + '/signal-return-probe', 'aarch64')!
	elf_arch(loader, 'aarch64')!
	os.mkdir(work + '/sources')!
	for source in ['tests/aarch64-sigreturn/probe.c', 'tests/aarch64-sigreturn/init.c',
		'tests/aarch64-sigreturn/run', 'build-support/native-compat-tools/compathost/sigreturn.v'] {
		hosttest.module_copy_file_preserving_stat(root() + '/' + source, work + '/sources/' + os.file_name(source))!
	}
	rootfs := work + '/rootfs'
	for name in ['sbin', 'bin', 'lib', 'dev', 'proc', 'sys', 'tmp', 'root'] { os.mkdir_all(rootfs + '/' + name)! }
	for source, target in {
		work + '/init': rootfs + '/sbin/init'
		work + '/signal-return-probe': rootfs + '/bin/signal-return-probe'
		loader: rootfs + '/lib/ld-musl-aarch64.so.1'
	} { hosttest.module_copy_file_preserving_stat(source, target)! }
	os.symlink('ld-musl-aarch64.so.1', rootfs + '/lib/libc.musl-aarch64.so.1')!
	private_kernel := snapshot_kernel(work, kernel, 'aarch64')!
	archive := work + '/initramfs.tar'
	mut archive_env := policyhost.environment()
	archive_env['COPYFILE_DISABLE'] = '1'
	fixturehost.inherited_command_environment_preferred(['tar', '--format=ustar', '-cf', archive, '-C', rootfs, '.'], archive_env, policyhost.caller_arch())!
	mut inputs := map[string]string{}
	for path in [root() + '/tests/aarch64-sigreturn/probe.c', root() + '/tests/aarch64-sigreturn/init.c',
		root() + '/tests/aarch64-sigreturn/run', root() + '/build-support/native-compat-tools/compathost/sigreturn.v',
		loader, kernel + '/bin/vinix', repo + '/build-support/build-aarch64-iso.sh',
		root() + '/tests/native-guest-tools/guesthost/pty.v'] { inputs[path] = hosttest.sha(path)! }
	mut outputs := map[string]string{}
	for name in ['signal-return-probe', 'init', 'kernel/bin/vinix', 'initramfs.tar'] { outputs[name] = hosttest.sha(work + '/' + name)! }
	hosttest.write_json(work + '/build.json', {
		'kind': json2.Any('genuine-dynamic-musl-signal-return')
		'commands': string_rows(commands)
		'inputs': json2.Any(hosttest.string_map(inputs))
		'outputs': json2.Any(hosttest.string_map(outputs))
	})!
	if '--build-only' in parsed.options { return 0 }
	configured := guesthost.launch_from(work + '/init', archive, work, private_kernel, 'aarch64', true, repo)!
	expected := ['SIGNAL-RETURN-PASS signals=', 'SIGNAL-RETURN-CHILD-EXIT status=0']
	failures := ['KERNEL PANIC', 'FATAL EXCEPTION', 'FAIL:']
	verdict := guesthost.boot(configured.command, configured.env, work, expected, failures, timeout, true)!
	serial := os.read_file(work + '/serial.log')!
	hosttest.write_json(work + '/result.json', {
		'verdict': json2.Any(verdict)
		'command': json2.Any(hosttest.strings(configured.command))
		'expected': json2.Any(hosttest.strings(expected))
		'failures': json2.Any(hosttest.strings(failures.filter(serial.contains(it))))
		'build_sha256': json2.Any(hosttest.sha(work + '/build.json')!)
		'serial_sha256': json2.Any(hosttest.sha(work + '/serial.log')!)
		'kernel_sha256': json2.Any(hosttest.sha(private_kernel + '/bin/vinix')!)
		'probe_sha256': json2.Any(hosttest.sha(work + '/signal-return-probe')!)
	})!
	return verdict
}
