// SPDX-License-Identifier: GPL-2.0-or-later
module ioshost

import cachecli
import gamehost
import net
import os
import sourcecommand
import time

pub fn launch(root string, init string, archive string, state string, original map[string]string) ([]string, map[string]string) {
	mut environment := original.clone()
	for key, value in {
		'VINIX_INITRAMFS':            archive
		'VINIX_BOOT_DISK':            state + '/boot.img'
		'VINIX_EFIVARS':              state + '/efivars.fd'
		'VINIX_QEMU_PACKAGE_STORE':   state + '/packages.tar'
		'VINIX_QEMU_PERSIST_DISK':    state + '/root.ext2'
		'VINIX_QEMU_PERSIST_SIZE_MB': '64'
		'VINIX_KEEP_TEMP_BOOT_DISK':  '1'
		'VINIX_QEMU_HOST_SOURCE':     '0'
		'VINIX_QEMU_CLIPBOARD':       '0'
		'VINIX_QEMU_AUDIO':           'off'
		'VINIX_QEMU_NETWORK':         '0'
	} {
		environment[key] = value
	}
	environment.delete('VINIX_QEMU_PERSIST')
	$if !macos {
		if 'USE_TCG' !in environment { environment['USE_TCG'] = '1' }
	}
	return [root + '/scripts/run-aarch64.sh', '--no-build', '--serial', '--mem=2048',
		'--guest-init=' + init], environment
}

fn available_port() !string {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	return listener.addr()!.str().all_after_last(':')
}

pub fn verdict(transcript []u8, expected []string, forced bool, status int) int {
	text := transcript.bytestr()
	if forced || status != 0 || has_failure(text) { return 1 }
	for marker in expected { if text.count(marker) != 1 { return 1 } }
	return 0
}

fn has_failure(text string) bool {
	for marker in ['iOS FAIL:', 'FATAL EXCEPTION', 'KERNEL PANIC'] {
		if text.contains(marker) { return true }
	}
	return false
}

pub fn finished_chunk(bytes []u8, previous_length int) bool {
	assert previous_length >= 0 && previous_length <= bytes.len
	if bytes.len == 0 { return false }
	// Every stop marker is shorter than 64 bytes. Only the new bytes and
	// that overlap can introduce a marker; the view dies before any append.
	start := if previous_length > 63 { previous_length - 63 } else { 0 }
	text := unsafe { tos(&u8(bytes.data) + start, bytes.len - start) }
	return text.contains('VINIX iOS GUEST: PASS') || has_failure(text)
}

fn write_console(bytes []u8) ! {
	mut at := 0
	for at < bytes.len {
		count := unsafe { C.write(1, &u8(bytes.data) + at, usize(bytes.len - at)) }
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return os.error_posix()
		}
		if count == 0 { return error('serial console output stopped') }
		at += int(count)
	}
}

fn stop(child &sourcecommand.PtyChild) ! {
	child.write([u8(1), `x`]) or {}
	for phase, seconds in [5, 2, 1] {
		if phase > 0 { child.signal(if phase == 1 { C.SIGTERM } else { C.SIGKILL })! }
		if child.settle(seconds)! { return }
	}
}

pub fn guest(root string, init string, archive string, state string, timeout int, expected []string, original map[string]string) !int {
	gamehost.mkdir(state)!
	command, mut environment := launch(root, init, archive, state, original)
	if 'VINIX_QEMU_PACKAGE_STORE_PORT' !in environment {
		environment['VINIX_QEMU_PACKAGE_STORE_PORT'] = available_port()!
	}
	println('==> Starting AArch64 QEMU boot for the real-time regression')
	mut child := sourcecommand.spawn_pty(command, environment, root)!
	defer { child.close() or {} }
	mut transcript := []u8{}
	transcript.flags |= .noslices
	mut status := sourcecommand.ChildExit{}
	mut failed := false
	mut cause := IError(none)
	deadline := time.sys_mono_now() + i64(timeout) * time.second
	mut shutdown := i64(-1)
	mut buffer := [65536]u8{}
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint() or {
			failed = true
			cause = err
			break
		}
		status = child.poll() or {
			failed = true
			cause = err
			break
		}
		if status.exited { break }
		count := child.read(mut buffer[..], 250) or {
			failed = true
			cause = err
			break
		}
		previous_length := transcript.len
		if count > 0 {
			if transcript.len + count > 64 * 1024 * 1024 {
				failed = true
				cause = error('iOS serial log exceeds 64 MiB')
				break
			}
			transcript << buffer[..count]
			write_console(buffer[..count]) or {
				failed = true
				cause = err
				break
			}
		}
		if shutdown < 0 && finished_chunk(transcript, previous_length) {
			child.write([u8(1), `x`]) or {
				if err.code() != C.EIO {
					failed = true
					cause = err
					break
				}
			}
			shutdown = time.sys_mono_now() + 10 * time.second
		}
		if shutdown >= 0 && time.sys_mono_now() >= shutdown { break }
	}
	forced := !status.exited
	if forced {
		stop(&child) or {
			failed = true
			cause = err
		}
	}
	child.close() or {
		failed = true
		cause = err
	}
	os.write_file_array(state + '/serial.log', transcript)!
	if failed { return cause }
	result := verdict(transcript, expected, forced, status.return_code)
	if result == 0 {
		println('==> AArch64 QEMU real-time regression passed')
	} else {
		eprintln('ERROR: iOS guest verdicts missing/duplicated, failed or VM did not exit; see ' + state + '/serial.log')
	}
	return result
}

pub fn (tools Tools) run(options Options) !int {
	options.validate()!
	build := tools.environment['VINIX_IOS_BUILD_DIR'] or { tools.root + '/build/ios' }
	tools.build(build, options)!
	work := sourcecommand.temporary('vinix-ios-vm-')!
	defer { gamehost.remove(work) or {} }
	rootfs := stage(build, work, options)!
	tools.compile(work)!
	archive := work + if options.with_gles { '/initramfs.tar.gz' } else { '/initramfs.tar' }
	if options.with_gles {
		gamehost.archive_gzip(rootfs, archive)!
	} else {
		gamehost.archive(rootfs, archive)!
	}
	runner_root := tools.environment['VINIX_VM_RUNNER_ROOT'] or { tools.root }
	return guest(runner_root, work + '/init', archive, work + '/vm', options.timeout, options.expected(), tools.environment)!
}
