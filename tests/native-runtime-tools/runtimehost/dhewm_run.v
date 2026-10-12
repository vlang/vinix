// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import androidhost as ah
import androidrun
import cachecli
import gamehost
import hosttest
import os
import sourcecommand
import strconv
import time

pub struct DoomOptions {
pub:
	repo          string
	build         string
	kernel        string
	debian_kernel string
	debian_root   string
	work          string
	selected      string = 'both'
	rounds        int    = 3
	timeout       int    = 1800
	record        bool
	screenshot    bool
	check_clock   bool
	clock_only    bool
}

pub fn doom_options(root string, argv []string) !DoomOptions {
	return doom_options_inner(root, argv) or { return error_with_code(err.msg(), 2) }
}

fn doom_options_inner(root string, argv []string) !DoomOptions {
	args := cachecli.arguments(argv, ['--repo', '--build', '--kernel-dir', '--debian-kernel',
		'--debian-root', '--work', '--os', '--rounds', '--timeout'], [], ['--record', '--screenshot',
		'--check-clock', '--clock-only'], 0, 0, 'Replay identical dhewm3 frames on Vinix and Debian.\nUsage: run --work DIR [--os vinix|debian|both --debian-kernel FILE --debian-root DIR --record|--screenshot|--clock-only --check-clock --rounds 3 --timeout 1800]')!
	repo := hosttest.module_resolve(args.value('--repo', root))!
	options := DoomOptions{
		repo:          repo
		build:         hosttest.module_resolve(args.value('--build', gamehost.path(repo, 'build-aarch64-dhewm3')))!
		kernel:        hosttest.module_resolve(args.value('--kernel-dir', gamehost.path(repo, 'kernel')))!
		debian_kernel: args.value('--debian-kernel', '')
		debian_root:   args.value('--debian-root', '')
		work:          hosttest.module_resolve(args.required('--work')!)!
		selected:      args.value('--os', 'both')
		rounds:        strconv.atoi(args.value('--rounds', '3'))!
		timeout:       strconv.atoi(args.value('--timeout', '1800'))!
		record:        '--record' in args.options
		screenshot:    '--screenshot' in args.options
		check_clock:   '--check-clock' in args.options
		clock_only:    '--clock-only' in args.options
	}
	if options.rounds < 1 || options.timeout < 1 {
		return error('--rounds and --timeout must be positive')
	}
	if options.selected !in ['vinix', 'debian', 'both'] {
		return error('--os must be vinix, debian or both')
	}
	if int(options.record) + int(options.screenshot) + int(options.clock_only) > 1 {
		return error('--record, --screenshot and --clock-only are mutually exclusive')
	}
	if options.selected in ['debian', 'both'] && (options.debian_kernel == '' || options.debian_root == '') {
		return error('Debian runs require --debian-kernel and --debian-root')
	}
	if options.record && options.selected == 'both' {
		return error('Record once on one OS, then replay the shared file on both')
	}
	return options
}

pub fn doom_copy_layer(source string, destination string) ! {
	gamehost.mkdir(destination)!
	for name in os.ls(source)! {
		from := gamehost.path(source, name)
		target := gamehost.path(destination, name)
		if os.is_link(from) {
			if os.is_dir(target) && !os.is_link(target) { continue }
			if os.exists(target) || os.is_link(target) { os.rm(target)! }
			os.symlink(os.readlink(from)!, target)!
		} else if os.is_dir(from) {
			doom_copy_layer(from, target)!
		} else {
			if os.is_link(target) { os.rm(target)! }
			hosttest.module_copy_file_preserving_stat(from, target)!
		}
	}
}

pub fn prepare_doom(tools gamehost.Tools, options DoomOptions) !string {
	root := gamehost.path(options.work, 'root')
	if !os.exists(gamehost.path(root, '.prepared')) {
		gamehost.remove(root)!
		doom_copy_layer(gamehost.path(options.build, 'staging'), root)!
		doom_copy_layer(gamehost.path(options.repo, 'build-aarch64-x11/staging/usr'), gamehost.path(root, 'usr'))!
		gamehost.mkdir(gamehost.path(root, 'bin'))!
		hosttest.module_copy_file_preserving_stat(gamehost.path(options.repo, 'build-aarch64-userland/staging/bin/busybox'), gamehost.path(root, 'bin/busybox'))!
		for name in ['sh', 'cat', 'mkdir', 'chmod', 'chown', 'sleep', 'kill', 'base64', 'uname',
			'mount', 'grep'] {
			os.symlink('busybox', gamehost.path(root, 'bin/' + name))!
		}
		loader := gamehost.path(root, 'lib/ld-musl-aarch64.so.1')
		if os.is_link(loader) { os.rm(loader)! }
		hosttest.module_copy_file_preserving_stat(gamehost.path(options.repo, 'build-aarch64-userland/staging/lib/ld-musl-aarch64.so.1'), loader)!
		for name in ['sbin', 'proc', 'dev', 'tmp', 'root', 'run', 'opt/dhewm3', 'etc'] {
			gamehost.mkdir(gamehost.path(root, name))!
		}
		os.write_file(gamehost.path(root, 'etc/passwd'), 'root:x:0:0:root:/root:/bin/sh\ndoom:x:1000:1000:Doom:/home/doom:/bin/sh\n')!
		os.write_file(gamehost.path(root, 'etc/group'), 'root:x:0:root\ndoom:x:1000:doom\n')!
		os.write_file(gamehost.path(root, '.prepared'), '')!
	}
	hosttest.module_copy_file_preserving_stat(gamehost.path(tools.root, 'tests/dhewm3/guest-init.sh'), gamehost.path(root, 'sbin/init'))!
	for helper in ['as-user', 'clock-probe'] {
		tools.run(['aarch64-linux-musl-gcc', '-O2', '-Wall', '-Wextra', '-static',
			gamehost.path(tools.root, 'tests/dhewm3/' + helper + '.c'), '-o',
			gamehost.path(root, 'opt/dhewm3/' + helper)])!
	}
	mode := if options.record {
		'record'
	} else if options.screenshot {
		'screenshot'
	} else if options.clock_only {
		'clock'
	} else {
		'benchmark'
	}
	os.write_file(gamehost.path(root, 'opt/dhewm3/config'), 'MODE=${mode}\nROUNDS=${options.rounds}\nCHECK_CLOCK=${int(options.check_clock)}\n')!
	if !options.record && !options.clock_only {
		demo := gamehost.path(options.work, 'vinix-demo.demo')
		if !os.exists(demo) { return error('Record a shared demo first with --record') }
		target := gamehost.path(root, 'usr/share/games/dhewm3/demo/demos/vinix-demo.demo')
		gamehost.mkdir(gamehost.parent(target))!
		hosttest.module_copy_file_preserving_stat(demo, target)!
	}
	return root
}

pub struct DoomPlan {
pub:
	command     []string
	environment map[string]string
}

pub fn doom_plan(options DoomOptions, root string, operating_system string) !DoomPlan {
	if operating_system == 'debian' {
		linux_root := gamehost.path(options.work, 'debian-root')
		gamehost.remove(linux_root)!
		doom_copy_layer(root, linux_root)!
		gamehost.mkdir(gamehost.path(linux_root, 'sys'))!
		doom_copy_layer(options.debian_root, linux_root)!
		mut busybox := ''
		for relative in ['usr/bin/busybox', 'bin/busybox'] {
			candidate := gamehost.path(options.debian_root, relative)
			if os.exists(candidate) {
				busybox = candidate
				break
			}
		}
		if busybox == '' { return error('Debian busybox missing') }
		hosttest.module_copy_file_preserving_stat(busybox, gamehost.path(linux_root, 'bin/busybox'))!
		os.symlink('sbin/init', gamehost.path(linux_root, 'init'))!
		initrd := gamehost.path(options.work, 'initrd.cpio')
		cpio(linux_root, initrd)!
		return DoomPlan{ command: ['qemu-system-aarch64', '-machine', 'virt,gic-version=3', '-accel',
			'hvf', '-cpu', 'host', '-smp', '4', '-m', '8192', '-kernel', options.debian_kernel,
			'-initrd', initrd, '-append', 'console=ttyAMA0 rdinit=/init quiet', '-display', 'none',
			'-serial', 'mon:stdio', '-no-reboot'], environment: os.environ() }
	}
	archive := gamehost.path(options.work, 'initramfs.tar')
	gamehost.archive(root, archive)!
	mut environment := os.environ()
	for key, value in {
		'VINIX_KERNEL_DIR':           options.kernel
		'VINIX_INITRAMFS':            archive
		'VINIX_INITRAMFS_COMPRESSED': '0'
		'VINIX_QEMU_ROOT_DISK':       '0'
		'VINIX_BOOT_DISK':            gamehost.path(options.work, 'boot.img')
		'VINIX_EFIVARS':              gamehost.path(options.work, 'efivars.fd')
		'VINIX_BOOT_DISK_SIZE_MB':    '2048'
		'VINIX_QEMU_PACKAGE_STORE':   gamehost.path(options.work, 'packages.tar')
		'VINIX_QEMU_PACKAGE_PERSIST': '0'
		'VINIX_QEMU_HOST_SOURCE':     '0'
		'VINIX_QEMU_AUDIO':           'off'
		'VINIX_QEMU_SMP':             '4'
		'VINIX_KEEP_TEMP_BOOT_DISK':  '1'
	} {
		environment[key] = value
	}
	return DoomPlan{ command: [gamehost.path(options.repo, 'scripts/run-aarch64.sh'), '--no-build',
		'--serial', '--no-persist', '--mem=8192'], environment: environment }
}

pub fn run_doom(tools gamehost.Tools, options DoomOptions, root string, operating_system string) !ah.Value {
	plan := doom_plan(options, root, operating_system)!
	action := if options.record {
		'recording'
	} else if options.screenshot {
		'capturing'
	} else if options.clock_only {
		'checking clocks'
	} else {
		'benchmarking'
	}
	println('Booting ${operating_system}, ${action}')
	flush_stdout()
	executable := if plan.command[0].contains('/') {
		plan.command[0]
	} else {
		os.find_abs_path_of_executable(plan.command[0])!
	}
	mut child := sourcecommand.spawn_pty([executable, ...plan.command[1..]], plan.environment, options.repo)!
	defer { gamehost.stop(mut child) or {} }
	mut log := os.create(gamehost.path(options.work, operating_system + '.log'))!
	defer { log.close() }
	mut transcript := []u8{}
	mut buffer := []u8{len: 65536}
	deadline := time.sys_mono_now() + u64(options.timeout) * time.second
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint()!
		count := child.read(mut buffer, 100)!
		if count == 0 { break }
		if count < 0 { continue }
		transcript << buffer[..count]
		unsafe { log.write_full_buffer(buffer.data, usize(count))! }
		log.flush()
		recent := transcript[int_max(0, transcript.len - 65536)..].bytestr()
		mut finished := false
		for marker in ['DHEWM3-DONE', 'DHEWM3-FAILED', 'KERNEL PANIC', 'crashed with signal'] {
			if recent.contains(marker) {
				finished = true
				break
			}
		}
		if finished { break }
	}
	gamehost.stop(mut child)!
	return doom_result(tools, options, transcript.bytestr(), operating_system)
}

pub fn doom_run_cli(root string, argv []string) !int {
	options := doom_options(root, argv)!
	gamehost.mkdir(options.work)!
	tools := gamehost.Tools{ root: root }
	private := prepare_doom(tools, options)!
	mut results := []ah.Value{}
	for selected in if options.selected == 'both' {
		['vinix', 'debian']
	} else {
		[options.selected]
	} {
		results << run_doom(tools, options, private, selected)!
	}
	text := androidrun.dump_json(ah.Value(results), 2) + '\n'
	os.write_file(gamehost.path(options.work, 'results.json'), text)!
	print(text)
	return 0
}
