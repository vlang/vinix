// SPDX-License-Identifier: GPL-2.0-or-later
module iosui

import cachecli
import gamehost
import json2
import math
import os
import qmpclient
import sourcecommand
import strconv
import time

pub fn desktop_compile_command(root string, app string, output string) []string {
	sdk := root + '/build-aarch64-userland/sysroot'
	return ['clang', '--target=aarch64-linux-musl', '--sysroot=' + sdk, '-static', '-O2',
		'-fno-stack-protector', '-Wall', '-Wextra', '-Werror',
		'-DIOS_TEST_APP="' + if app == '2048' { 'iOS 2048' } else { 'iOS Calculator' } + '"',
		root + '/tests/ios/desktop-init.c', '-L' + sdk + '/lib', '-fuse-ld=lld', '-o', output]
}

pub fn desktop_environment(root string, work string, socket_path string, original map[string]string) map[string]string {
	mut environment := original.clone()
	for key, value in {
		'VINIX_INITRAMFS':            work + '/rootfs.tar'
		'VINIX_BOOT_DISK':            work + '/boot.img'
		'VINIX_EFIVARS':              work + '/efivars.fd'
		'VINIX_QEMU_PACKAGE_STORE':   work + '/packages.tar'
		'VINIX_QEMU_PERSIST_DISK':    work + '/root.ext2'
		'VINIX_QEMU_PERSIST_SIZE_MB': '64'
		'VINIX_QEMU_HOST_SOURCE':     '0'
		'VINIX_QEMU_NETWORK':         '0'
		'VINIX_QEMU_AUDIO':           'off'
		'VINIX_QEMU_CLIPBOARD':       '0'
		'VINIX_KEEP_TEMP_BOOT_DISK':  '1'
		'VINIX_OVMF_CODE':            root + '/boot-image/edk2-aarch64-code-2048x1536.fd'
		'VINIX_QEMU_RESOLUTION':      '2048x1536x32'
		'VINIX_QEMU_EXTRA':           '-qmp unix:' + socket_path + ',server,nowait'
	} {
		environment[key] = value
	}
	for key in ['VINIX_QEMU_PERSIST', 'VINIX_QEMU_OVERLAY', 'VINIX_QEMU_ROOT_DISK'] {
		environment.delete(key)
	}
	return environment
}

pub fn absolute_events(x f64, y f64) []json2.Any {
	return [
		json2.Any({
			'type': json2.Any('abs')
			'data': json2.Any({
				'axis':  json2.Any('x')
				'value': json2.Any(int(math.round_to_even(x * 32767 / 2048)))
			})
		}),
		json2.Any({
			'type': json2.Any('abs')
			'data': json2.Any({
				'axis':  json2.Any('y')
				'value': json2.Any(int(math.round_to_even(y * 32767 / 1536)))
			})
		}),
	]
}

fn button_event(down bool) json2.Any {
	return json2.Any({
		'type': json2.Any('btn')
		'data': json2.Any({
			'button': json2.Any('left')
			'down':   json2.Any(down)
		})
	})
}

fn call(mut monitor qmpclient.Monitor, name string, arguments map[string]json2.Any) ! {
	monitor.set_deadline(u64(time.sys_mono_now() + 10 * time.second))
	monitor.command(name, arguments)!
}

fn events(mut monitor qmpclient.Monitor, input []json2.Any) ! {
	call(mut monitor, 'input-send-event', {
		'events': json2.Any(input)
	})!
}

fn click(mut monitor qmpclient.Monitor, x f64, y f64) ! {
	mut input := absolute_events(x, y)
	input << button_event(true)
	events(mut monitor, input)!
	gamehost.pause(0.15)!
	events(mut monitor, [button_event(false)])!
	gamehost.pause(0.4)!
}

fn swipe(mut monitor qmpclient.Monitor, points []int) ! {
	x0, y0, x1, y1 := points[0], points[1], points[2], points[3]
	events(mut monitor, absolute_events(x0, y0))!
	events(mut monitor, [button_event(true)])!
	gamehost.pause(0.1)!
	for index in 1 .. 7 {
		events(mut monitor, absolute_events(x0 + f64(x1 - x0) * index / 6, y0 + f64(y1 - y0) * index / 6))!
		gamehost.pause(0.04)!
	}
	events(mut monitor, [button_event(false)])!
	gamehost.pause(0.4)!
}

pub fn desktop_score(transcript string) !int {
	marker := 'iOS UILabel: SCORE: '
	mut maximum := -1
	for part in transcript.split(marker)[1..] {
		mut length := 0
		for ch in part.bytes() {
			if !ch.is_digit() { break }
			length++
		}
		if length > 0 {
			value := int(strconv.common_parse_int(part[..length], 10, 32, true, true)!)
			if value > maximum { maximum = value }
		}
	}
	return maximum
}

struct DesktopSession {
pub:
	log     string
	build   string
	qmp     string
	app     string
	timeout int
}

fn transcript(path string) !string {
	if os.stat(path)!.size > 32 * 1024 * 1024 { return error('desktop log exceeds 32 MiB') }
	return os.read_file(path)!
}

fn desktop_observe(pid int, context voidptr) ! {
	session := unsafe { &DesktopSession(context) }
	deadline := time.sys_mono_now() + u64(if session.timeout > 0 { session.timeout } else { 0 }) * time.second
	mut ready := false
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint()!
		text := transcript(session.log)!
		if text.contains('FAIL:') || text.contains('KERNEL PANIC') || sourcecommand.child_exit(pid)!.exited {
			return error('desktop boot failed; see ' + session.log)
		}
		if text.contains('vinix-desktop: ready') {
			ready = true
			break
		}
		gamehost.pause(0.2)!
	}
	if !ready { return error('desktop startup timed out; see ' + session.log) }
	mut monitor := qmpclient.connect_json(session.qmp, u64(time.sys_mono_now() + 10 * time.second), cachecli.cancelled)!
	defer { monitor.close() }
	gamehost.pause(1)!
	call(mut monitor, 'screendump', {
		'filename': json2.Any(session.build + '/' + session.app + '-before.ppm')
	})!
	if session.app == '2048' {
		click(mut monitor, 280, 378)!
		directions := [[420, 434, 220, 434], [315, 534, 315, 334], [220, 434, 420, 434],
			[315, 334, 315, 534]]
		for index in 0 .. 16 { swipe(mut monitor, directions[index % 4])! }
	} else {
		for point in [[177.75, 441.75], [452.25, 624.75], [269.25, 533.25], [452.25, 716.25]] {
			click(mut monitor, point[0], point[1])!
		}
	}
	gamehost.pause(1)!
	call(mut monitor, 'screendump', {
		'filename': json2.Any(session.build + '/' + session.app + '.ppm')
	})!
	text := transcript(session.log)!
	if session.app == '2048' {
		score := desktop_score(text)!
		if score < 4 { return error('real desktop swipes did not merge tiles; see ' + session.log) }
		println('Vinix desktop: upstream iOS-2048 launched; pointer swipes reached score ${score}')
	} else if !text.contains('iOS UILabel: 12') {
		return error('real desktop clicks did not calculate 12; see ' + session.log)
	}
	call(mut monitor, 'quit', {})!
	exit_deadline := time.sys_mono_now() + 10 * time.second
	for !sourcecommand.child_exit(pid)!.exited {
		if time.sys_mono_now() >= exit_deadline { return error('desktop process did not exit') }
		gamehost.pause(0.01)!
	}
}

pub fn desktop(root string, desktop_path string, timeout int, app string) ! {
	if app !in ['calculator', '2048'] {
		return error_with_code('app must be calculator or 2048', 2)
	}
	if !os.is_file(desktop_path) {
		return error_with_code('build the desktop with ./scripts/build-desktop-aarch64.sh first', 2)
	}
	work := sourcecommand.temporary('vinix-ios-desktop-')!
	defer { gamehost.remove(work) or {} }
	// Exclusive short directory avoids collisions and the Darwin socket limit.
	old_tmp := os.getenv_opt('TMPDIR')
	os.setenv('TMPDIR', '/tmp', true)
	socket_work := sourcecommand.temporary('vios') or {
		if value := old_tmp { os.setenv('TMPDIR', value, true) } else { os.unsetenv('TMPDIR') }
		return err
	}
	if value := old_tmp { os.setenv('TMPDIR', value, true) } else { os.unsetenv('TMPDIR') }
	defer { gamehost.remove(socket_work) or {} }
	rootfs := work + '/rootfs'
	for name in ['run', 'root', 'sbin', 'usr/bin', 'usr/share/vinix/icons', 'dev', 'tmp', 'proc',
		'sys'] {
		gamehost.mkdir(rootfs + '/' + name)!
	}
	gamehost.copy_file(desktop_path, rootfs + '/usr/bin/vinix-desktop')!
	gamehost.copy_tree(root + '/build/ios/staging/usr', rootfs + '/usr', false)!
	gamehost.copy_file(root + '/desktop/assets/calculator.qoi', rootfs + '/usr/share/vinix/icons/calculator.qoi')!
	result := sourcecommand.run_preferred(desktop_compile_command(root, app, work + '/init'), os.environ(), cachecli.cancelled, '')!
	if result.status != 0 { return error('desktop init compiler failed') }
	gamehost.archive(rootfs, work + '/rootfs.tar')!
	build := root + '/build/ios'
	session := DesktopSession{ log: build + '/' + if app == '2048' {
		'2048-desktop.log'
	} else {
		'desktop.log'
	}, build: build, qmp: socket_work + '/qmp.sock', app: app, timeout: timeout }
	sourcecommand.run_logged_pipe_owned([root + '/scripts/run-aarch64.sh', '--no-build', '--serial',
		'--mem=2048', '--guest-init=' + work + '/init'], desktop_environment(root, work, session.qmp, os.environ()), cachecli.cancelled, session.log, desktop_observe, unsafe { &session }, 10)!
	if app == 'calculator' {
		println('Vinix desktop: unmodified iOS Mach-O launched; real clicks calculated 7+5=12')
	}
	println('Screenshot: ' + build + '/' + app + '.ppm')
}
