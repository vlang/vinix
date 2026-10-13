// SPDX-License-Identifier: MIT
module vmhost

import cachecli
import gamehost
import math
import os
import sourcecommand
import time

fn C.mkfifo(&char, u32) i32

struct RobloxInput {
mut:
	descriptor i32 = -1
	path       string
}

pub fn roblox_launch(options RobloxOptions, archive string, environment map[string]string) Launch {
	mut env := environment.clone()
	for name, value in {
		'VINIX_KERNEL_DIR':           options.kernel
		'VINIX_INITRAMFS':            archive
		'VINIX_INITRAMFS_COMPRESSED': '0'
		'VINIX_QEMU_ROOT_DISK':       '0'
		'VINIX_BOOT_DISK':            options.work + '/boot.img'
		'VINIX_EFIVARS':              options.work + '/efivars.fd'
		'VINIX_BOOT_DISK_SIZE_MB':    '4096'
		'VINIX_QEMU_PACKAGE_STORE':   options.work + '/packages.tar'
		'VINIX_QEMU_PACKAGE_PERSIST': '0'
		'VINIX_QEMU_HOST_SOURCE':     '0'
		'VINIX_QEMU_AUDIO':           'off'
		'VINIX_QEMU_SMP':             options.cpus
		'VINIX_KEEP_TEMP_BOOT_DISK':  '1'
	} {
		env[name] = value
	}
	return Launch{[options.repo + '/scripts/run-aarch64.sh', '--no-build', '--no-persist',
		'--mem=' + options.memory, '--serial'], env, options.repo}
}

pub fn roblox_capture(launch Launch, work string, shell bool, seconds f64) ![]u8 {
	mut child := sourcecommand.spawn_pty(launch.command, launch.environment, launch.directory)!
	defer { child.close() or {} }
	mut bytes := []u8{}
	mut input := RobloxInput{}
	defer {
		if input.descriptor >= 0 {
			C.close(input.descriptor)
			os.rm(input.path) or {}
		}
	}
	mut cause := IError(none)
	mut failed := false
	roblox_drive(&child, work, shell, seconds, mut bytes, mut input) or {
		cause = err
		failed = true
	}
	previous_int := unsafe { C.signal(C.SIGINT, C.SIG_IGN) }
	previous_term := unsafe { C.signal(C.SIGTERM, C.SIG_IGN) }
	defer {
		unsafe {
			C.signal(C.SIGINT, previous_int)
			C.signal(C.SIGTERM, previous_term)
		}
	}
	child.write([u8(1), `x`]) or {}
	time.sleep(time.second)
	child.signal(C.SIGTERM) or {
		if !failed {
			cause = err
			failed = true
		}
	}
	child.settle(5) or {
		if !failed {
			cause = err
			failed = true
		}
		false
	}
	child.close() or {
		if !failed {
			cause = err
			failed = true
		}
	}
	for path in [work + '/initramfs.tar', work + '/boot.img'] {
		if os.exists(path) {
			os.rm(path) or {
				if !failed {
					cause = err
					failed = true
				}
			}
		}
	}
	if failed { return cause }
	return bytes
}

fn roblox_drive(child &sourcecommand.PtyChild, work string, shell bool, seconds f64, mut bytes []u8, mut input RobloxInput) ! {
	if math.is_inf(seconds, 0) { return error('int too large to convert to float') }
	pipe := work + '/shell.in'
	if shell {
		if os.exists(pipe) { os.rm(pipe)! }
		if C.mkfifo(pipe.str, 0o666) != 0 { return os.error_posix() }
		input.path = pipe
		input.descriptor = C.open(pipe.str, C.O_RDWR | C.O_NONBLOCK | C.O_CLOEXEC)
		if input.descriptor < 0 {
			os.rm(pipe) or {}
			return os.error_posix()
		}
		println('Guest shell: write commands to ' + pipe + ', read ' + work + "/vinix.log; 'poweroff-test' ends it")
		flush_stdout()
	}
	mut log := os.create(work + '/vinix.log')!
	defer { log.close() }
	deadline := now() + seconds
	mut buffer := []u8{len: 65536}
	for now() < deadline {
		cachecli.checkpoint()!
		if input.descriptor >= 0 {
			count := unsafe { C.read(input.descriptor, buffer.data, usize(buffer.len)) }
			if count < 0 && C.errno !in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR] {
				return os.error_posix()
			}
			if count > 0 {
				command := buffer[..int(count)].clone()
				if command.bytestr().contains('poweroff-test') { break }
				child.write(command)!
			}
		}
		count := child.read(mut buffer, if shell { 200 } else { 1000 })!
		if count == 0 { break }
		if count > 0 {
			bytes << buffer[..count]
			unsafe { log.write_full_buffer(buffer.data, usize(count))! }
			log.flush()
		}
		if !shell && bytes.len > 0 {
			// Borrow the captured bytes only for this immediate search. Repeated
			// full-stream copies make a long observation unnecessarily costly.
			text := unsafe { tos(bytes.data, bytes.len) }
			if ['ROBLOX-WINDOWS-DONE', 'KERNEL PANIC', 'ROBLOX-WINDOWS-FAIL'].any(text.contains(it)) {
				break
			}
		}
	}
}

pub fn roblox_guest(options RobloxOptions, root string, seconds f64) ![]u8 {
	archive := options.work + '/initramfs.tar'
	gamehost.archive(root, archive)!
	println('Booting Vinix with the Windows Player')
	flush_stdout()
	return roblox_capture(roblox_launch(options, archive, os.environ()), options.work, options.shell, seconds)!
}
