// SPDX-License-Identifier: GPL-2.0-or-later
module vmhost

import cachecli
import cachekey
import gamehost
import hosttest
import json2
import os
import perfreport
import qmpclient
import sourcecommand
import time

pub fn pointer_compile(root string, work string, environment map[string]string) !string {
	source := work + '/fixture.c'
	result := hosttest.generate_module_capture(root + '/tests/pointer-scroll/fixture', source, 'arm64', [])!
	print(result.stdout)
	eprint(result.stderr)
	if result.stdout.contains('retrying with') || result.stderr.contains('retrying with') {
		return error('compiler fallback is not qualification')
	}
	binary := work + '/sbin/init'
	gamehost.mkdir(work + '/sbin')!
	sdk := environment['VINIX_AARCH64_SYSROOT'] or { root + '/build-aarch64-userland/staging' }
	gccroot := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl'
	versions := os.ls(gccroot)!.sorted()
	if versions.len == 0 { return error('guest GCC runtime missing') }
	clang := if os.exists('/opt/homebrew/opt/llvm/bin/clang') {
		'/opt/homebrew/opt/llvm/bin/clang'
	} else {
		'clang'
	}
	checked_command([clang, '--target=aarch64-linux-musl', '--sysroot=' + sdk,
		'--gcc-install-dir=' + gccroot + '/' + versions.last(), '-static', '-fuse-ld=lld', '-O2',
		source, '-o', binary], environment)!
	return binary
}

pub fn pointer_launch(root string, kernel string, image string, work string, environment map[string]string) Launch {
	mut env := environment.clone()
	for key, value in {
		'VINIX_KERNEL_DIR':           kernel
		'VINIX_INITRAMFS':            image
		'VINIX_BOOT_DISK':            work + '/boot.img'
		'VINIX_BOOT_DISK_SIZE_MB':    '128'
		'VINIX_EFIVARS':              work + '/efivars.fd'
		'VINIX_QEMU_EXTRA':           '-qmp unix:' + work + '/qmp.sock,server,nowait'
		'VINIX_QEMU_ROOT_DISK':       '0'
		'VINIX_QEMU_HOST_SOURCE':     '0'
		'VINIX_QEMU_NETWORK':         '0'
		'VINIX_QEMU_AUDIO':           'off'
		'VINIX_QEMU_PACKAGE_PERSIST': '0'
		'VINIX_QEMU_PACKAGE_STORE':   work + '/packages.tar'
	} {
		env[key] = value
	}
	return Launch{[root + '/scripts/run-aarch64.sh', '--no-build', '--serial', '--no-persist',
		'--no-clipboard', '--mem=1024'], env, ''}
}

fn pointer_wait(child &sourcecommand.ReaderChild, marker string, seconds f64, log string, mut transcript []u8) ! {
	deadline := now() + seconds
	mut buffer := []u8{len: 65536}
	for !transcript.bytestr().contains(marker) {
		cachecli.checkpoint()!
		if now() >= deadline || child.poll()!.exited {
			return error('missing b' + perfreport.quoted(marker) + '; see ' + log)
		}
		count := pipe_read(child.descriptor, mut buffer, 200)!
		if count == 0 {
			return error('VM exited before b' + perfreport.quoted(marker) + '; see ' + log)
		}
		if count > 0 { transcript << buffer[..count] }
	}
}

pub fn pointer_exchange(child &sourcecommand.ReaderChild, qmp_path string, log string, ready_seconds f64, mut transcript []u8) ! {
	pointer_wait(child, 'POINTER_SCROLL READY', ready_seconds, log, mut transcript)!
	mut monitor := qmpclient.connect_json(qmp_path, u64(time.sys_mono_now() + 10 * time.second), cachecli.cancelled)!
	defer { monitor.close() }
	for event in [['wheel-left', '-1', '0'], ['wheel-right', '1', '0'], ['wheel-up', '0', '1'],
		['wheel-down', '0', '-1']] {
		mut events := []json2.Any{}
		for down in [true, false] {
			events << json2.Any({
				'type': json2.Any('btn')
				'data': json2.Any({
					'button': json2.Any(event[0])
					'down':   json2.Any(down)
				})
			})
		}
		monitor.set_deadline(u64(time.sys_mono_now() + 10 * time.second))
		monitor.command('input-send-event', {
			'events': json2.Any(events)
		})!
		pointer_wait(child, 'POINTER_SCROLL dx=' + event[1] + ' dy=' + event[2], 10, log, mut transcript)!
	}
	pointer_wait(child, 'POINTER_SCROLL PASS', 10, log, mut transcript)!
}

pub fn pointer_capture(launch Launch, qmp string, log string, ready_seconds f64) ! {
	mut child := sourcecommand.spawn_reader_at(launch.command, launch.environment, launch.directory, true)!
	defer { child.close() or {} }
	mut transcript := []u8{}
	mut failed := false
	mut cause := IError(none)
	pointer_exchange(&child, qmp, log, ready_seconds, mut transcript) or {
		failed = true
		cause = err
	}
	terminate_reader(&child) or {
		if !failed {
			failed = true
			cause = err
		}
	}
	child.close() or {
		if !failed {
			failed = true
			cause = err
		}
	}
	gamehost.mkdir(gamehost.parent(log))!
	os.write_file_array(log, transcript)!
	if failed { return cause }
	println('Pointer scroll PASS: left/right/up/down, legacy reads, consumed deltas')
}

pub fn pointer_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--kernel-dir', '--log'], [], [], 0, 0, 'Verify both wheel axes and the compatible pointer ABI.\nUsage: run [--kernel-dir DIR --log /tmp/vinix-pointer-scroll.log]') or { return error_with_code(err.msg(), 2) }
	kernel := cachekey.resolve_path(args.value('--kernel-dir', root + '/kernel'))!
	log := args.value('--log', '/tmp/vinix-pointer-scroll.log')
	work := sourcecommand.temporary('vinix-pointer-scroll-')!
	defer { gamehost.remove(work) or {} }
	env := os.environ()
	binary := pointer_compile(root, work, env)!
	image := init_archive(binary, work, true)!
	pointer_capture(pointer_launch(root, kernel, image, work, env), work + '/qmp.sock', log, 120)!
	return 0
}
