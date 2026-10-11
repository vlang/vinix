// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import guesthost
import hosttest
import json2
import os

const greeting = 'Hello world\nHello from Alpine GCC on Vinix!\nHello from Alpine GCC on Vinix/amd64!\nUSERLAND DEMO V PASS\n'

fn demo_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true }, hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--build-only' }], 0,
		'Usage: run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR [--build-only]',
		'Check exact greetings from production V bodies under host sanitizers and in a native guest.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--arch', '--kernel-dir', '--state-dir'])!
	work := hosttest.work_dir(parsed.options['--state-dir'], 'vinix-userland-demo-')!
	module_path := work + '/fixture'
	os.mkdir(module_path)!
	hosttest.module_copy_file_preserving_stat(root() + '/tests/userland-demo/fixture/core.v', module_path + '/core.v')!
	mut hashes := map[string]string{}
	for pair in [['world', 'base-files/root/hello.v'], ['arm', 'build-support/userland-demo/hello-aarch64.v'],
		['x86', 'build-support/userland-demo/hello-amd64.v']] {
		text := read(root() + '/' + pair[1])!
		if text.count('fn main()') != 1 || text.count('module main') != 1 { return error('Ambiguous maintained greeting: ' + pair[1]) }
		write(module_path + '/' + pair[0] + '.v', text.replace('module main', 'module fixture').replace('fn main()', 'fn greet_' + pair[0] + '()'))!
		hashes[pair[1]] = hosttest.text_sha(text)
	}
	generate(module_path, work + '/host.c', 'arm64', ['nofloat', 'hello_host'], '')!
	common := ['-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-fno-strict-aliasing']
	run(['clang', ...common, '-fsanitize=address,undefined', work + '/host.c', '-o', work + '/host'])!
	host := captured([work + '/host'])!
	if host.stdout != greeting { return error('Production greeting stdout differs: ' + host.stdout) }
	write(work + '/stdout', host.stdout)!
	write(work + '/stderr', host.stderr)!
	arch := parsed.options['--arch']
	generate(module_path, work + '/native.c', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, ['nofloat'], '')!
	mut cc := inspection_compiler(arch)!
	if arch == 'aarch64' {
		// This runner historically selected CC, rather than CC_AARCH64.
		cc[0] = os.getenv_opt('CC') or { '/opt/homebrew/opt/llvm/bin/clang' }
		cc << '-fuse-ld=lld'
	} else { cc = compiler_prefix('CC_AMD64', 'x86_64-linux-musl-gcc')! }
	guesthost.compile_module(root() + '/tests/kernel-gaps/serialcore', work + '/serial.o', arch, [...cc, ...common])!
	command := [...cc, ...common, '-static', work + '/native.c', work + '/serial.o', '-o', work + '/init']
	run(command)!
	elf_arch(work + '/init', arch)!
	private_kernel := snapshot_kernel(work, parsed.options['--kernel-dir'], arch)!
	hosttest.write_json(work + '/inputs.json', { 'arch': json2.Any(arch), 'expected_stdout': json2.Any(greeting),
		'sources': json2.Any(hosttest.string_map(hashes)), 'fixture_sha256': json2.Any(hosttest.sha(work + '/init')!),
		'kernel_sha256': json2.Any(hosttest.sha(private_kernel + '/bin/vinix')!), 'compile_command': json2.Any(hosttest.strings(command)),
		'host_sanitizers': json2.Any(hosttest.strings(['address', 'undefined'])) })!
	if '--build-only' in parsed.options { return 0 }
	archive := guesthost.image(work + '/init', work + '/guest')!
	configured := guesthost.launch(work + '/init', archive, work + '/guest', private_kernel, arch, true)!
	positive, negative := guesthost.verdict_policy(greeting.split_into_lines(), []string{}, false)
	code := guesthost.boot(configured.command, configured.env, work + '/guest', positive, negative, 300, true)!
	if code == 0 { println('USERLAND DEMO HOST AND NATIVE PASS: ' + arch) }
	return code
}

fn uname_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{ name: '--sysroot', value: true },
		hosttest.Option{ name: '--timeout', value: true }, hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true }, hosttest.Option{ name: '--build-only' }], 0,
		'Usage: run [--sysroot DIR] [--timeout SECONDS] [--kernel-dir DIR] [--state-dir FRESH-DIR] [--build-only]',
		'Check uname output and option behavior without overwriting BusyBox.') or { return error_with_code(err.msg(), 2) }
	work := hosttest.work_dir(parsed.options['--state-dir'] or { '' }, 'vinix-uname-')!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	sdk := resolve(parsed.options['--sysroot'] or { root() + '/build-aarch64-userland/staging' })!
	rootfs := work + '/rootfs'
	for name in ['bin', 'lib', 'sbin', 'proc', 'sys', 'dev', 'tmp', 'root'] { os.mkdir_all(rootfs + '/' + name)! }
	for name in ['bin/busybox', 'lib/ld-musl-aarch64.so.1'] { hosttest.module_copy_file_preserving_stat(sdk + '/' + name, rootfs + '/' + name)! }
	os.symlink('busybox', rootfs + '/bin/sh')!
	os.symlink('/bin/busybox', rootfs + '/bin/uname')!
	busybox := hosttest.sha(rootfs + '/bin/busybox')!
	run([root() + '/build-support/stage-uname.sh', rootfs])!
	if hosttest.sha(rootfs + '/bin/busybox')! != busybox || os.real_path(rootfs + '/usr/bin/uname') != rootfs + '/bin/uname' {
		return error('uname staging changed BusyBox or its relative command link')
	}
	hosttest.module_copy_file_preserving_stat(root() + '/tests/uname/guest-init.sh', rootfs + '/sbin/init')!
	archive := native_archive(work)!
	private_kernel := snapshot_kernel(work, parsed.options['--kernel-dir'] or { os.getenv_opt('VINIX_KERNEL_DIR') or { root() + '/kernel' } }, 'aarch64')!
	timeout := positive_option(parsed, '--timeout', 120)!
	hosttest.write_json(work + '/inputs.json', { 'busybox_sha256': json2.Any(busybox),
		'archive_sha256': json2.Any(hosttest.sha(archive)!), 'kernel_sha256': json2.Any(hosttest.sha(private_kernel + '/bin/vinix')!) })!
	if '--build-only' in parsed.options { return 0 }
	configured := guesthost.launch(rootfs + '/sbin/init', archive, work, private_kernel, 'aarch64', true)!
	argv := configure_process_launch(configured.command, 'aarch64', 512, 4, '')
	return guesthost.boot(argv, configured.env, work, ['UNAME PASS'], ['UNAME FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION'], timeout, true)!
}
