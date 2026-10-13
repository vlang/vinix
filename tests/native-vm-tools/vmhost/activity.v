// SPDX-License-Identifier: GPL-2.0-or-later
module vmhost

import cachecli
import cachekey
import gamehost
import os
import sourcecommand
import strconv
import tarcore
import time

#include <poll.h>
struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

fn C.poll(&C.pollfd, usize, i32) i32

pub fn checked_command(argv []string, environment map[string]string) ! {
	result := sourcecommand.capture_full(argv, environment, -1, 64 * 1024 * 1024, cachecli.cancelled)!
	print(result.stdout)
	eprint(result.stderr)
	if result.status != 0 || result.stdout.contains('retrying with') || result.stderr.contains('retrying with') {
		return error('VM fixture command failed: ' + argv.str())
	}
}

pub fn activity_compile(root string, repo string, work string, arch string, environment map[string]string) !string {
	binary := work + '/activity-check'
	sources := [root + '/tests/activity-monitor/test.c', root + '/tests/activity-monitor/metrics.c']
	if arch == 'aarch64' {
		sdk := environment['VINIX_AARCH64_SYSROOT'] or { repo + '/build-aarch64-userland/sysroot' }
		checked_command([environment['CC'] or { 'clang' }, '--target=aarch64-linux-musl',
			'--sysroot=' + sdk, '-static', '-O2', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror',
			...sources, '-L' + sdk + '/lib', '-fuse-ld=lld', '-o', binary], environment)!
	} else {
		checked_command([environment['CC_AMD64'] or { 'x86_64-linux-musl-gcc' }, '-static', '-O2',
			'-Wall', '-Wextra', '-Werror', ...sources, '-lpthread', '-o', binary], environment)!
	}
	return binary
}

pub fn init_archive(binary string, work string, pointer bool) !string {
	root := work + '/rootfs'
	directories := if pointer { ['sbin'] } else { ['dev', 'root', 'sbin', 'tmp'] }
	for directory in directories { gamehost.mkdir(root + '/' + directory)! }
	os.cp(binary, root + '/sbin/init')!
	os.chmod(root + '/sbin/init', 0o755)!
	path := work + '/initramfs.tar'
	mut writer := tarcore.create(path)!
	defer { writer.close() }
	if !pointer {
		info := os.stat(root)!
		writer.add(tarcore.Member{ name: '.', kind: `5`, mode: i64(info.mode & 0o7777), uid: i64(info.uid), gid: i64(info.gid), mtime: info.mtime }, []u8{})!
	}
	for directory in directories {
		info := os.stat(root + '/' + directory)!
		name := (if pointer { '' } else { './' }) + directory
		writer.add(tarcore.Member{ name: name, kind: `5`, mode: i64(info.mode & 0o7777), uid: i64(info.uid), gid: i64(info.gid), mtime: info.mtime }, []u8{})!
		if directory == 'sbin' {
			file := os.stat(root + '/sbin/init')!
			writer.add(tarcore.Member{ name: name + '/init', mode: i64(file.mode & 0o7777), uid: i64(file.uid), gid: i64(file.gid), mtime: file.mtime, size: i64(os.file_size(binary)) }, os.read_bytes(binary)!)!
		}
	}
	writer.finish()!
	return path
}

pub fn activity_arm_launch(repo string, kernel string, work string, binary string, environment map[string]string) Launch {
	mut env := environment.clone()
	for key, value in {
		'VINIX_KERNEL_DIR':           kernel
		'VINIX_INITRAMFS':            repo + '/build-support/init-aarch64/initramfs.tar'
		'VINIX_QEMU_MODULE_ISO':      ''
		'VINIX_QEMU_BASE_ARCHIVE':    ''
		'VINIX_QEMU_MODULE_MANIFEST': ''
		'VINIX_QEMU_EXTRA_MODULES':   ''
		'VINIX_QEMU_PERSIST':         '0'
		'VINIX_QEMU_ROOT_DISK':       '0'
		'VINIX_BOOT_DISK':            work + '/boot.img'
		'VINIX_EFIVARS':              work + '/efivars.fd'
		'VINIX_QEMU_PACKAGE_STORE':   work + '/packages.tar'
		'VINIX_QEMU_PACKAGE_PERSIST': '0'
		'VINIX_QEMU_HOST_SOURCE':     '0'
		'VINIX_QEMU_AUDIO':           'off'
		'VINIX_QEMU_SMP':             '4'
		'VINIX_KEEP_TEMP_BOOT_DISK':  '1'
	} {
		env[key] = value
	}
	return Launch{[repo + '/scripts/run-aarch64.sh', '--no-build', '--no-persist', '--serial',
		'--mem=2048', '--guest-init=' + binary], env, repo}
}

pub fn activity_x86_launch(qemu string, firmware string, iso string, repo string, environment map[string]string) Launch {
	return Launch{[qemu, '-machine', 'q35,smm=off', '-accel',
		environment['VINIX_QEMU_ACCEL'] or { 'tcg' }, '-cpu', 'max', '-m', '2048', '-smp', '4',
		'-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware, '-cdrom', iso, '-display',
		'none', '-monitor', 'none', '-serial', 'stdio', '-no-reboot'], environment, repo}
}

fn pipe_read(fd i32, mut bytes []u8, milliseconds int) !int {
	mut readiness := C.pollfd{ fd: fd, events: i16(C.POLLIN) }
	ready := C.poll(&readiness, 1, i32(milliseconds))
	if ready < 0 {
		if C.errno == C.EINTR { return -1 }
		return os.error_posix()
	}
	if ready == 0 { return -1 }
	n := C.read(fd, bytes.data, usize(bytes.len))
	if n < 0 {
		if C.errno in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR] { return -1 }
		return os.error_posix()
	}
	return int(n)
}

fn terminate_reader(child &sourcecommand.ReaderChild) ! {
	if child.poll()!.exited { return }
	if C.killpg(child.pid, C.SIGTERM) != 0 && C.errno != C.ESRCH { return os.error_posix() }
	deadline := now() + 10
	for now() < deadline {
		if child.poll()!.exited { return }
		time.sleep(10 * time.millisecond)
	}
	if C.killpg(child.pid, C.SIGKILL) != 0 && C.errno != C.ESRCH { return os.error_posix() }
}

pub fn activity_verdict(bytes []u8) int {
	text := bytes.bytestr()
	if text.contains('ACTIVITY-CHECK FAIL') { return 1 }
	prefix := 'ACTIVITY-CHECK DONE failures='
	mut cursor := 0
	for cursor < text.len {
		at := cursor + (text[cursor..].index(prefix) or { return 1 })
		cursor = at + prefix.len
		tail := text[cursor..]
		mut length := 0
		for length < tail.len && tail[length].is_digit() { length++ }
		if length > 0 { return if length == 1 && tail[0] == `0` { 0 } else { 1 } }
	}
	return 1
}

pub fn activity_capture(launch Launch, log_path string, seconds f64) ![]u8 {
	gamehost.mkdir(gamehost.parent(log_path))!
	mut log := os.create(log_path)!
	defer { log.close() }
	mut child := sourcecommand.spawn_reader_at(launch.command, launch.environment, launch.directory, true)!
	defer { child.close() or {} }
	mut bytes := []u8{}
	mut buffer := []u8{len: 65536}
	mut failed := false
	mut cause := IError(none)
	deadline := now() + seconds
	for now() < deadline {
		cachecli.checkpoint() or {
			failed = true
			cause = err
			break
		}
		observed := child.poll() or {
			failed = true
			cause = err
			break
		}
		n := pipe_read(child.descriptor, mut buffer, if observed.exited { 0 } else { 200 }) or {
			failed = true
			cause = err
			break
		}
		if n > 0 {
			bytes << buffer[..n]
			unsafe { log.write_full_buffer(buffer.data, usize(n))! }
			log.flush()
		}
		if observed.exited && (n <= 0) { break }
		if ['ACTIVITY-CHECK DONE', 'KERNEL PANIC', 'FATAL EXCEPTION'].any(bytes.bytestr().contains(it)) {
			break
		}
	}
	// The original log file continues receiving bytes during the final wait.
	if !child.poll()!.exited { C.killpg(child.pid, C.SIGTERM) }
	until := now() + 10
	for now() < until {
		n := pipe_read(child.descriptor, mut buffer, 50) or { -1 }
		if n > 0 {
			bytes << buffer[..n]
			unsafe { log.write_full_buffer(buffer.data, usize(n))! }
			log.flush()
		}
		if child.poll()!.exited && n <= 0 { break }
	}
	child.close()!
	if failed { return cause }
	return bytes
}

pub fn activity_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--repo', '--kernel', '--arch', '--timeout', '--log'], [], [], 0, 0, 'Boot the process-control syscall regression.\nUsage: run [--repo DIR --kernel DIR --arch aarch64|x86_64 --timeout 180 --log activity-controls.log]') or { return error_with_code(err.msg(), 2) }
	arch := args.value('--arch', 'aarch64')
	if arch !in ['aarch64', 'x86_64'] { return error_with_code('unsupported architecture', 2) }
	repo := cachekey.resolve_path(args.value('--repo', root))!
	kernel := cachekey.resolve_path(args.value('--kernel', repo + '/kernel'))!
	seconds := strconv.atof64(args.value('--timeout', '180')) or { return error_with_code(err.msg(), 2) }
	log := cachekey.resolve_path(args.value('--log', 'activity-controls.log'))!
	work := sourcecommand.temporary('vinix-activity-controls-')!
	defer { gamehost.remove(work) or {} }
	mut env := os.environ()
	binary := activity_compile(root, repo, work, arch, env)!
	launch := if arch == 'aarch64' {
		activity_arm_launch(repo, kernel, work, binary, env)
	} else {
		image := init_archive(binary, work, false)!
		iso := work + '/test.iso'
		env['VINIX_AMD64_KERNEL'] = kernel + '/bin/vinix'
		env['VINIX_AMD64_INITRAMFS'] = image
		env['VINIX_AMD64_ISO'] = iso
		env['VINIX_AMD64_ISO_BUILD_DIR'] = work + '/iso'
		checked_command([repo + '/build-support/build-amd64-iso.sh'], env)!
		qemu := os.find_abs_path_of_executable(env['VINIX_QEMU_X86_64'] or { 'qemu-system-x86_64' })!
		firmware := env['VINIX_OVMF_CODE'] or { gamehost.parent(gamehost.parent(qemu)) + '/share/qemu/edk2-x86_64-code.fd' }
		activity_x86_launch(qemu, firmware, iso, repo, env)
	}
	bytes := activity_capture(launch, log, seconds)!
	for line in gamehost.decode_utf8(bytes).split_into_lines() {
		if line.contains('ACTIVITY-CHECK') { println(line) }
	}
	println('Serial log: ' + log)
	return activity_verdict(bytes)
}
