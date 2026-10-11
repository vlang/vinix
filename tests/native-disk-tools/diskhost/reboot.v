// SPDX-License-Identifier: GPL-2.0-or-later
module diskhost

import guesthost
import hosttest
import os

fn reboot(args []string) !int {
	options := parse(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--init', value: true },
		hosttest.Option{ name: '--initramfs', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--build-fixture' },
		hosttest.Option{ name: '--build-only' },
	],
		'Usage: run_vm --init ELF --initramfs TAR --state-dir DIR [--arch aarch64|x86_64] [--timeout 240] [--kernel-dir DIR]\n       run.sh [--arch aarch64|x86_64] [--state-dir DIR] [--build-only]')!
	arch := options.value('--arch', os.getenv_opt('VINIX_REBOOT_PERSISTENCE_ARCH') or { 'aarch64' })
	if arch !in ['aarch64', 'x86_64'] {
		return argument('unsupported reboot-persistence architecture: ' + arch)
	}
	seconds := caller_timeout(options, 240)!
	if seconds <= 0 { return argument('timeout must be positive') }
	if options.has('--build-fixture') && (options.has('--init') || options.has('--initramfs')) {
		return argument('choose --build-fixture or --init with --initramfs')
	}
	if !options.has('--build-fixture') && ['--init', '--initramfs', '--state-dir'].any(!options.has(it)) {
		return argument('missing required --init, --initramfs or --state-dir')
	}
	mut selected := options.values.clone()
	if !options.has('--state-dir') && os.getenv('VINIX_REBOOT_PERSISTENCE_STATE_DIR') != '' {
		selected['--state-dir'] = [os.getenv('VINIX_REBOOT_PERSISTENCE_STATE_DIR')]
	}
	owned := guesthost.Options{ values: selected }
	work := work_dir(owned, 'vinix-reboot-persistence-')!
	defer { remove_private(work, owned) }
	init := if options.has('--init') {
		resolve(options.value('--init', ''))!
	} else {
		work + '/init'
	}
	if options.has('--build-fixture') {
		module_path := root() + '/tests/reboot-persistence/persistfixture'
		mut compile := flags(if arch == 'aarch64' { arch } else { 'amd64' })
		compile << ['-std=gnu11', '-fno-builtin']
		guesthost.compile_module(module_path, work + '/fixture.o', arch, compile)!
		run([...compile, work + '/fixture.o', '-o', init])!
	}
	kernel_dir := kernel(work, options.value('--kernel-dir', ''), if arch == 'aarch64' {
		arch
	} else {
		'amd64'
	})!
	archive := work + '/initramfs.tar'
	if options.has('--initramfs') {
		source := resolve(options.value('--initramfs', ''))!
		if source != archive { os.cp(source, archive)! }
	} else {
		for name in ['root', 'sbin'] { mkdir(work + '/rootfs/' + name)! }
		guesthost.archive_tree(work + '/rootfs', archive)!
	}
	if arch == 'x86_64' {
		append_init(archive, init, work)!
		extract(archive, work + '/seed')!
		seed_identity(work + '/seed', archive)!
		format_ext2(tool()!, work + '/root.ext2', work + '/seed', 64 * 1024 * 1024)!
	}
	configured := launch(init, archive, work, kernel_dir, if arch == 'aarch64' {
		arch
	} else {
		'amd64'
	}, 2048, work + '/root.ext2', true, false)!
	if options.has('--build-only') {
		println('Prepared reboot guest: ' + work)
		return 0
	}
	println('==> Booting; the guest restarts itself with reboot(2)')
	if guesthost.boot_reboot(configured.command, configured.env, work, seconds, true)! != 0 {
		return 1
	}
	println('==> ' + arch + ' reboot persistence passed')
	return 0
}
