// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidhost as ah
import cachecli
import crypto.sha256
import encoding.base64
import gamehost
import hosttest
import os
import runtimehost
import sourcecommand
import time

fn xwd() []u8 {
	mut header := []u32{len: 25}
	header[0] = 100
	header[1] = 7
	header[4] = 10
	header[5] = 1
	header[11] = 32
	header[12] = 40
	mut bytes := []u8{}
	for value in header { bytes << [u8(value >> 24), u8(value >> 16), u8(value >> 8), u8(value)] }
	for color in 0 .. 10 { bytes << [u8(color), u8(color * 10), u8(color * 20), u8(0)] }
	return bytes
}

fn vulkan_capture() string {
	data := xwd()
	encoded := base64.encode(data)
	mut rows := ['VINIX-DOTA2-VULKAN-SHOT-BEGIN',
		'VINIX-DOTA2-VULKAN-SHOT-SHA256: ' + sha256.sum(data).hex()]
	for start := 0; start < encoded.len; start += 76 {
		row := 'S' + (start / 76 + 1).str() + ' ' + encoded[start..int_min(start + 76, encoded.len)]
		rows << row
		rows << row
	}
	rows << ['VINIX-DOTA2-VULKAN-SHOT-END', 'VINIX-DOTA2-VULKAN-ENUMERATE-PASS',
		'VINIX-DOTA2-VULKAN-PASS']
	return rows.join('\n') + '\n'
}

fn mock(directory string, family string, mode string) ! {
	os.write_file(directory + '/child.pid', os.getpid().str())!
	if mode !in ['interrupt', 'timeout'] {
		prefix := 'native serial output\n'.repeat(60000)
		mut output := os.stdout()
		unsafe { output.write_full_buffer(prefix.str, usize(prefix.len))! }
		output.flush()
		if mode == 'failure' {
			println(if family == 'doom' { 'DHEWM3-FAILED' } else { 'VINIX-DOTA2-VULKAN-FAIL' })
		} else if mode == 'panic' {
			println('KERNEL PANIC')
		} else if family == 'vulkan' {
			print(if mode == 'capture-failure' {
				vulkan_capture().replace('S1 ', 'broken1 ')
			} else {
				vulkan_capture()
			})
		} else if mode in ['record', 'screenshot', 'capture-failure'] {
			if mode == 'record' {
				println('DHEWM3-DEMO-BEGIN\n' + base64.encode('shared demo'.bytes()) + '\nDHEWM3-DEMO-END')
			}
			println('DHEWM3-SHOT-BEGIN\n' + if mode == 'capture-failure' {
				'A'
			} else {
				base64.encode(xwd())
			} + '\nDHEWM3-SHOT-END\nDHEWM3-DONE')
		} else {
			for pair in [['2.0', '50.0'], ['1.0', '100.0'], ['1.25', '80.0'], ['1.1', '90.0']] {
				println('100 frames rendered in ' + pair[0] + ' seconds = ' + pair[1] + ' fps\nDHEWM3-ELAPSED ns=2100000000 status=0')
			}
			println('DHEWM3-DONE')
		}
		flush_stdout()
	}
	for { time.sleep(10 * time.millisecond) }
}

fn session_command(argv []string, _ bool, _ voidptr) !sourcecommand.Output {
	if argv[0] == '/bin/cp' {
		assert argv[1] == '-cRp'
		gamehost.copy_tree(argv[2], argv[3], false)!
	} else if argv[0] == 'aarch64-linux-musl-readelf' {
		return sourcecommand.Output{}
	} else if argv[0] == 'aarch64-linux-musl-gcc' {
		assert argv[1..5] == ['-O2', '-Wall', '-Wextra', '-static']
		os.write_file(argv.last(), 'native helper')!
	} else if argv[0].ends_with('/ffmpeg') || argv[0] == 'ffmpeg' {
		os.write_file(argv.last(), 'converted image')!
	} else {
		return error('unexpected native guest fixture command: ' + argv.str())
	}
	return sourcecommand.Output{}
}

fn write(file string, data string) ! {
	gamehost.mkdir(gamehost.parent(file))!
	os.write_file(file, data)!
}

fn worker(directory string, family string, mode string) ! {
	repo := directory + '/repo'
	build := directory + '/build'
	kernel := directory + '/kernel'
	for relative in ['build-aarch64-x11/staging/usr/bin', 'build-aarch64-x11/staging/lib',
		'build-aarch64-x11/staging/usr/lib', 'scripts', 'tests/dota2', 'tests/dhewm3'] {
		gamehost.mkdir(repo + '/' + relative)!
	}
	for pair in [['bin/busybox', 'busybox'], ['lib/ld-musl-aarch64.so.1', 'musl']] {
		write(repo + '/build-aarch64-userland/staging/' + pair[0], pair[1])!
	}
	write(repo + '/tests/dota2/vulkan-init.sh', 'native Vulkan init')!
	write(repo + '/tests/dhewm3/guest-init.sh', 'native Doom init')!
	write(kernel + '/bin/vinix', 'frozen kernel')!
	script := '#!/bin/sh\nexec ' + hosttest.shell_quote(os.executable()) + ' --mock ' + hosttest.shell_quote(directory) + ' ' + family + ' ' + mode + '\n'
	write(repo + '/scripts/run-aarch64.sh', script)!
	os.chmod(repo + '/scripts/run-aarch64.sh', 0o755)!
	tools := gamehost.Tools{ root: repo, command_hook: session_command }
	if family == 'doom' {
		write(build + '/staging/usr/bin/dhewm3', 'engine')!
		gamehost.mkdir(build + '/staging/lib')!
		write(directory + '/vinix-demo.demo', 'recorded demo')!
		options := runtimehost.DoomOptions{ repo: repo, build: build, kernel: kernel, work: directory, selected: 'vinix', record: mode == 'record', screenshot: mode in [
			'screenshot',
			'capture-failure',
		], timeout: if mode == 'timeout' { 2 } else { 30 } }
		private := runtimehost.prepare_doom(tools, options)!
		result := runtimehost.run_doom(tools, options, private, 'vinix')!.object()
		if mode == 'complete' {
			assert ah.encode(ah.field(result, 'median_fps')) == '90.0'
		} else if mode == 'record' {
			assert os.read_file(directory + '/vinix-demo.demo')! == 'shared demo'
		}
	} else {
		source := build + '/staging/usr/libexec/vinix-dota2/root'
		write(source + '/.vinix-dota2-vulkan-generation', 'native generation\n')!
		for name in ['libvulkan_lvp.so', 'libvulkan_virtio.so'] {
			write(source + '/usr/lib/x86_64-linux-gnu/' + name, name)!
		}
		for name in ['swrast_dri.so', 'kms_swrast_dri.so', 'hardware_dri.so'] {
			write(source + '/usr/lib/x86_64-linux-gnu/dri/' + name, name)!
		}
		write(source + '/usr/share/doc/remove', 'pruned')!
		mut elf := []u8{len: 64}
		for index, byte in [u8(127), `E`, `L`, `F`, 2, 1, 1] { elf[index] = byte }
		elf[16] = 2
		elf[18] = 183
		gamehost.mkdir(build + '/staging/usr/bin')!
		os.write_file_array(build + '/staging/usr/bin/qemu-x86_64', elf)!
		os.chmod(build + '/staging/usr/bin/qemu-x86_64', 0o755)!
		options := runtimehost.VulkanGuestOptions{ staging: build + '/staging', kernel: kernel, work: directory, timeout: if mode == 'timeout' {
			2
		} else {
			30
		}, venus: mode == 'venus' }
		if !runtimehost.run_vulkan_guest(tools, options)! {
			return error('controlled guest failed')
		}
		assert os.read_file(directory + '/results.json')!.contains('"captured_colors": 10')
		assert !os.exists(directory + '/root/usr/libexec/vinix-dota2/root/usr/share/doc')
		assert !os.exists(directory + '/root/usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/dri/hardware_dri.so')
	}
}

struct Interrupt {
	directory string
	signal    int
}

fn send_interrupt(pid int, pointer voidptr) ! {
	request := unsafe { &Interrupt(pointer) }
	until := time.sys_mono_now() + 15 * time.second
	for !os.exists(request.directory + '/child.pid') {
		if time.sys_mono_now() > until { return error('mock guest absent') }
		time.sleep(10 * time.millisecond)
	}
	assert C.kill(pid, request.signal) == 0
}

fn main() {
	if os.args.len == 5 && os.args[1] == '--mock' {
		mock(os.args[2], os.args[3], os.args[4]) or { panic(err) }
		return
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len == 5 && os.args[1] == '--worker' {
		worker(os.args[2], os.args[3], os.args[4]) or {
			eprintln(err)
			exit(if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 })
		}
		return
	}
	if os.args.len != 2 { exit(2) }
	work := os.args[1]
	gamehost.mkdir(work) or { panic(err) }
	for family in ['doom', 'vulkan'] {
		modes := if family == 'doom' {
			['complete', 'record', 'screenshot', 'failure', 'panic', 'timeout', 'capture-failure',
				'interrupt-int', 'interrupt-term']
		} else {
			['complete', 'venus', 'failure', 'panic', 'timeout', 'capture-failure', 'interrupt-int',
				'interrupt-term']
		}
		for mode in modes {
			directory := work + '/' + family + '-' + mode
			argv := [os.executable(), '--worker', directory, family,
				if mode.starts_with('interrupt') { 'interrupt' } else { mode }]
			result := if mode.starts_with('interrupt') {
				request := Interrupt{ directory: directory, signal: if mode.ends_with('int') {
					C.SIGINT
				} else {
					C.SIGTERM
				} }
				sourcecommand.capture_owned(argv, os.environ(), 60, 1024 * 1024, cachecli.cancelled, unsafe { nil }, send_interrupt, &request, 0) or { panic(err) }
			} else {
				sourcecommand.capture(argv, os.environ(), 60, 1024 * 1024, cachecli.cancelled) or { panic(err) }
			}
			os.write_file(directory + '/controller.log', result.stdout + result.stderr) or { panic(err) }
			assert !result.stdout.contains(': fn ') && !result.stderr.contains(': fn ')
			expected := if mode in ['complete', 'record', 'screenshot', 'venus'] {
				0
			} else if mode.ends_with('-int') {
				130
			} else if mode.ends_with('-term') {
				143
			} else {
				1
			}
			assert result.status == expected, result.stderr
			pid := (os.read_file(directory + '/child.pid') or { panic(err) }).int()
			assert C.kill(pid, 0) != 0 && C.errno == C.ESRCH
			if mode in ['complete', 'record', 'screenshot', 'venus'] {
				assert os.file_size(directory + '/vinix.log') > 1200000
			}
			eprintln(family + '/' + mode + ': PASS')
		}
	}
	os.write_file(work + '/passed', 'PASS 17 whole PTY sessions\n') or { panic(err) }
}
