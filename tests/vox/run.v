// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import json2
import os
import qmpclient
import time

fn key_name(character u8) !string {
	if (character >= `a` && character <= `z`) || (character >= `0` && character <= `9`) {
		return character.ascii_str()
	}
	if character >= `A` && character <= `Z` { return 'shift-' + (character + 32).ascii_str() }
	return match character {
		` ` { 'spc' }
		`\n` { 'ret' }
		`/` { 'slash' }
		`.` { 'dot' }
		`:` { 'shift-semicolon' }
		`-` { 'minus' }
		else { return error('unsupported typing character: ${character}') }
	}
}

fn run(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error('${args}\n${result.output}') }
	return result.output
}

fn copy_file(source string, destination string) ! {
	os.mkdir_all(os.dir(destination))!
	os.cp(os.real_path(source), destination)!
	os.chmod(destination, int(os.stat(source)!.mode & 0o777))!
}

fn library(name string, roots []string) !string {
	for root in roots {
		for directory in ['usr/lib', 'lib'] {
			path := '${root}/${directory}/${name}'
			if os.is_file(path) { return path }
		}
	}
	return error('missing runtime library: ' + name)
}

fn closure(source string, destination string, guest string, roots []string, mut copied map[string]bool) ! {
	if destination in copied { return }
	copy_file(source, destination)!
	copied[destination] = true
	info := run(['/opt/homebrew/opt/llvm/bin/llvm-readelf', '-d', source])!
	for line in info.split_into_lines() {
		if !line.contains('(NEEDED)') { continue }
		name := line.all_after('[').all_before(']')
		if name.starts_with('libX') || name.contains('xcb') || name.contains('wayland') || name.starts_with('libgtk') || name.contains('sokol') {
			return error('unexpected display-server dependency: ' + name)
		}
		closure(library(name, roots)!, guest + '/usr/lib/' + name, guest, roots, mut copied)!
	}
}

fn main() {
	start() or {
		eprintln(err)
		exit(1)
	}
}

fn start() ! {
	root := os.real_path('.')
	work := os.getenv('VINIX_VOX_STATE')
	if work == '' { panic('VINIX_VOX_STATE must name an external state directory') }
	qmp := work + '/qmp.sock'
	if os.args.len > 1 && os.args[1] in ['shot', 'quit', 'key', 'type', 'mouse'] {
		mut monitor := qmpclient.connect(qmp)!
		defer { monitor.close() }
		if os.args[1] == 'shot' {
			monitor.command('screendump', {
				'filename': json2.Any(work + '/vox-vinix-desktop.png')
				'format':   json2.Any('png')
			})!
		} else if os.args[1] == 'mouse' {
			if os.args.len < 4 { return error('mouse requires x y [click|down|up]') }
			mut events := []json2.Any{}
			for index, axis in ['x', 'y'] {
				extent := if index == 0 { 1024 } else { 768 }
				events << json2.Any({
					'type': json2.Any('abs')
					'data': json2.Any({
						'axis':  json2.Any(axis)
						'value': json2.Any(os.args[index + 2].int() * 32767 / (extent - 1))
					})
				})
			}
			monitor.command('input-send-event', {
				'events': json2.Any(events)
			})!
			if os.args.len > 4 {
				action := os.args[4]
				if action !in ['click', 'down', 'up'] { return error('invalid mouse action') }
				time.sleep(150 * time.millisecond)
				for down in if action == 'click' { [true, false] } else { [action == 'down'] } {
					monitor.command('input-send-event', {
						'events': json2.Any([json2.Any({
							'type': json2.Any('btn')
							'data': json2.Any({
								'down':   json2.Any(down)
								'button': json2.Any('left')
							})
						})])
					})!
					time.sleep(150 * time.millisecond)
				}
			}
		} else if os.args[1] == 'type' {
			for character in os.args[2].bytes() {
				monitor.command('human-monitor-command', {
					'command-line': json2.Any('sendkey ' + key_name(character)!)
				})!
				time.sleep(180 * time.millisecond)
			}
		} else if os.args[1] == 'key' {
			monitor.command('human-monitor-command', {
				'command-line': json2.Any('sendkey ' + os.args[2])
			})!
		} else {
			monitor.command('quit', {})!
		}
		return
	}
	if os.args.len > 1 && os.args[1] == 'package' {
		package(root, work, work + '/staging')!
		println('Native Vox package: ' + work + '/staging')
		return
	}
	guest := work + '/guest'
	if os.exists(qmp) { return error('a Vox guest is already running') }
	if os.exists(guest) { os.mv(guest, guest + '-previous-' + time.now().unix_micro().str())! }
	os.mkdir_all(guest)!
	stable := root + '/build-aarch64-userland/staging'
	roots := [work + '/glvnd', work + '/sysroot', stable]
	mut copied := map[string]bool{}
	for entry in ['bin/busybox', 'bin/zsh'] {
		closure(stable + '/' + entry, guest + '/' + entry, guest, roots, mut copied)!
	}
	package(root, work, guest)!
	copy_file(stable + '/lib/ld-musl-aarch64.so.1', guest + '/lib/ld-musl-aarch64.so.1')!
	copy_file(work + '/vinix-desktop', guest + '/usr/bin/vinix-desktop')!
	copy_file(work + '/init', guest + '/sbin/init')!
	copy_file(work + '/native-tests', guest + '/usr/bin/vox-native-tests')!
	if os.is_file(work + '/libvox-trace.so') {
		closure(work + '/libvox-trace.so', guest + '/usr/lib/libvox-trace.so', guest, roots, mut copied)!
		os.mv(guest + '/usr/bin/vox', guest + '/usr/bin/vox-real')!
		copy_file(work + '/trace-launcher', guest + '/usr/bin/vox')!
	}
	for name in ['vinix-session', 'vinix-timesync', 'vinix-service-runner'] {
		if os.is_file(work + '/services/' + name) {
			copy_file(work + '/services/' + name, guest + '/usr/bin/' + name)!
		}
	}
	for directory in ['etc/fonts', 'usr/share/fonts'] {
		source := root + '/build-aarch64-firefox/staging/' + directory
		if os.is_dir(source) {
			os.mkdir_all(guest + '/' + directory)!
			run(['cp', '-Rp', source + '/.', guest + '/' + directory])!
		}
	}
	for name in ['sh', 'mkdir', 'sleep', 'cat', 'rm', 'env', 'ps'] {
		os.symlink('busybox', guest + '/bin/' + name)!
	}
	for name in ['vinix-files', 'vinix-terminal', 'vinix-settings', 'vinix-activity'] {
		os.symlink('vinix-desktop', guest + '/usr/bin/' + name)!
	}
	os.mkdir_all(guest + '/etc/ssl/certs')!
	certificates := root + '/build-aarch64-firefox/staging/etc/ssl/certs/ca-certificates.crt'
	if os.is_file(certificates) {
		copy_file(certificates, guest + '/etc/ssl/certs/ca-certificates.crt')!
	}
	os.write_file(guest + '/etc/passwd', 'root:x:0:0:root:/root:/bin/zsh\n')!
	os.write_file(guest + '/etc/group', 'root:x:0:\n')!
	os.write_file(guest + '/etc/resolv.conf', 'nameserver 10.0.2.3\n')!
	copy_file(root + '/build-support/vox/welcome.html', guest + '/usr/share/vinix/vox-welcome.html')!
	os.setenv('COPYFILE_DISABLE', '1', true)
	archive := work + '/initramfs.tar'
	run(['tar', '--format=ustar', '-cf', archive, '-C', guest, '.'])!
	host := hwhost.Host{
		root:          root
		arch:          'aarch64'
		qemu:          '/opt/homebrew/bin/qemu-system-aarch64'
		firmware:      root + '/boot-image/edk2-aarch64-code-2048x1536.fd'
		firmware_vars: '/opt/homebrew/share/qemu/edk2-arm-vars.fd'
	}
	kernel := root + '/build/pty-kernels/aarch64/vinix'
	media := hwhost.boot_media(host, kernel, archive, 'quiet', work)!
	println('Booting Vox on native Vinix; no X11 runtime in guest')
	mut process := os.new_process(host.qemu)
	process.set_args(['-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m',
		'8192', '-smp', '4', ...media, '-object', 'rng-random,filename=/dev/urandom,id=rng0', '-device',
		'virtio-rng-device,rng=rng0', '-device', 'virtio-keyboard-device', '-device',
		'virtio-tablet-device', '-device', 'ramfb', '-display', 'none', '-serial',
		'file:' + work + '/serial.log', '-qmp', 'unix:' + qmp + ',server=on,wait=off', '-netdev',
		'user,id=net0', '-device', 'virtio-net-device,netdev=net0', '-no-reboot'])
	process.run()
	process.wait()
	if process.code != 0 { return error('QEMU failed: ${process.code}') }
}

fn package(root string, work string, staging string) ! {
	private := staging + '/usr/libexec/vinix-vox/root'
	if os.exists(private) { os.rmdir_all(private)! }
	os.mkdir_all(private)!
	stable := root + '/build-aarch64-userland/staging'
	roots := [work + '/glvnd', work + '/sysroot', stable]
	mut copied := map[string]bool{}
	closure(work + '/vox', private + '/usr/bin/vox', private, roots, mut copied)!
	copy_file(stable + '/lib/ld-musl-aarch64.so.1', private + '/lib/ld-musl-aarch64.so.1')!
	copy_file(work + '/launcher', staging + '/usr/bin/vox')!
	for directory in ['etc/fonts', 'usr/share/fonts', 'etc/ssl/certs'] {
		source := root + '/build-aarch64-firefox/staging/' + directory
		if !os.is_dir(source) { return error('missing browser data: ' + source) }
		os.mkdir_all(private + '/' + directory)!
		run(['cp', '-Rp', source + '/.', private + '/' + directory])!
	}
}
