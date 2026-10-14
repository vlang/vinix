// SPDX-License-Identifier: GPL-2.0-or-later
// Assemble and boot only this demonstration's files, with a private QMP socket.
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
		`\t` { 'tab' }
		`/` { 'slash' }
		`.` { 'dot' }
		`(` { 'shift-9' }
		`)` { 'shift-0' }
		`{` { 'shift-bracket_left' }
		`}` { 'shift-bracket_right' }
		`'` { 'apostrophe' }
		`!` { 'shift-1' }
		else { return error('unsupported demonstration typing character') }
	}
}

fn run(program string, args []string) ! {
	mut p := os.new_process(program)
	defer { p.close() }
	p.set_args(args)
	p.run()
	p.wait()
	if p.code != 0 { return error('${program} failed (${p.code})') }
}

fn copy_file(source string, destination string) ! {
	os.mkdir_all(os.dir(destination))!
	os.cp(source, destination) or { return error('copy ${source} to ${destination}: ${err}') }
	os.chmod(destination, int(os.stat(source)!.mode & 0o777))!
}

fn copy_tree(source string, destination string) ! {
	os.mkdir_all(destination)!
	run('cp', ['-Rp', source + '/.', destination])!
}

fn library_path(name string, roots []string) !string {
	for directory in roots {
		for suffix in ['usr/lib', 'lib'] {
			path := '${directory}/${suffix}/${name}'
			if os.is_file(path) { return path }
		}
	}
	return error('missing native guest library ${name}')
}

fn elf_closure(source string, destination string, roots []string, mut copied map[string]bool) ! {
	if destination in copied { return }
	copy_file(source, destination)!
	copied[destination] = true
	result := os.exec(['/opt/homebrew/opt/llvm/bin/llvm-readelf', '-d', source])
	if result.exit_code != 0 { return error('cannot inspect ${source}') }
	guest := destination.all_before('/usr/')
	base := if destination.contains('/usr/') { guest } else { destination.all_before('/bin/') }
	for line in result.output.split_into_lines() {
		if !line.contains('(NEEDED)') { continue }
		name := line.all_after('[').all_before(']')
		elf_closure(library_path(name, roots)!, '${base}/usr/lib/${name}', roots, mut copied)!
	}
}

fn assemble(repository string, state string) !string {
	guest := '${state}/rootfs'
	os.mkdir_all(guest)!
	stable := '${repository}/build-aarch64-userland/staging'
	x11 := '${repository}/build-aarch64-x11/staging'
	zed := '${repository}/build-aarch64-zed/staging'
	roots := [x11, stable]
	mut copied := map[string]bool{}
	for name in ['bin/busybox', 'bin/zsh'] {
		println('Guest binary: ${name}')
		elf_closure('${stable}/${name}', '${guest}/${name}', roots, mut copied)!
	}
	for name in ['usr/bin/Xvfb', 'usr/bin/vinix-wine-host', 'usr/bin/vinix-xinput', 'usr/bin/xkbcomp'] {
		println('Guest binary: ${name}')
		source := if os.is_file('${x11}/${name}') { '${x11}/${name}' } else { '${stable}/${name}' }
		elf_closure(source, '${guest}/${name}', roots, mut copied)!
	}
	copy_file('${stable}/lib/ld-musl-aarch64.so.1', '${guest}/lib/ld-musl-aarch64.so.1')!
	for directory in ['usr/share/fonts', 'usr/share/X11', 'etc/X11', 'etc/fonts', 'var/lib/xkb'] {
		if os.is_dir('${x11}/${directory}') {
			println('Guest directory: ${directory}')
			copy_tree('${x11}/${directory}', '${guest}/${directory}')!
		}
	}
	println('Guest directory: private Zed runtime')
	copy_tree('${zed}/usr/libexec', '${guest}/usr/libexec')!
	copy_file('${zed}/usr/bin/run-zed', '${guest}/usr/bin/run-zed-app')!
	copy_file('${repository}/build-aarch64-zed/build/open-zed', '${guest}/usr/bin/run-zed')!
	copy_file('${repository}/build-aarch64-zed/build/vinix-desktop', '${guest}/usr/bin/vinix-desktop')!
	copy_file('${repository}/build-aarch64-zed/build/init', '${guest}/sbin/init')!
	for name in ['sh', 'mkdir', 'sleep', 'cat', 'rm', 'env'] {
		os.symlink('/bin/busybox', '${guest}/bin/${name}') or {}
	}
	os.symlink('vinix-desktop', '${guest}/usr/bin/vinix-zed') or {}
	os.mkdir_all('${guest}/etc')!
	os.write_file('${guest}/etc/passwd', 'root:x:0:0:root:/root:/bin/zsh\n')!
	os.write_file('${guest}/etc/group', 'root:x:0:\n')!
	os.write_file('${guest}/etc/resolv.conf', 'nameserver 10.0.2.3\n')!
	os.setenv('COPYFILE_DISABLE', '1', true)
	archive := '${state}/initramfs.tar'
	run('tar', ['--format=ustar', '-cf', archive, '-C', guest, '.'])!
	return archive
}

fn main() {
	repository := os.real_path('.')
	state := '${repository}/build-aarch64-zed/vm'
	os.mkdir_all(state)!
	if os.args.len > 1 && os.args[1] == 'shot' {
		mut monitor := qmpclient.connect('/tmp/vinix-zed-qmp')!
		defer { monitor.close() }
		monitor.command('screendump', {
			'filename': json2.Any('${repository}/docs/screenshots/zed-vinix-qemu.png')
			'format':   json2.Any('png')
		})!
		return
	}
	if os.args.len > 1 && os.args[1] == 'quit' {
		mut monitor := qmpclient.connect('/tmp/vinix-zed-qmp')!
		monitor.command('quit', {})!
		monitor.close()
		return
	}
	if os.args.len == 3 && os.args[1] == 'key' {
		mut monitor := qmpclient.connect('/tmp/vinix-zed-qmp')!
		defer { monitor.close() }
		monitor.command('human-monitor-command', {
			'command-line': json2.Any('sendkey ' + os.args[2])
		})!
		return
	}
	if os.args.len == 3 && os.args[1] == 'type' {
		mut monitor := qmpclient.connect('/tmp/vinix-zed-qmp')!
		defer { monitor.close() }
		for character in os.args[2].bytes() {
			monitor.command('human-monitor-command', {
				'command-line': json2.Any('sendkey ' + key_name(character)!)
			})!
			time.sleep(150 * time.millisecond)
		}
		return
	}
	archive := assemble(repository, state) or {
		eprintln('Guest assembly failed: ${err}')
		exit(1)
	}
	host := hwhost.Host{
		root:          repository
		arch:          'aarch64'
		qemu:          '/opt/homebrew/bin/qemu-system-aarch64'
		firmware:      '${repository}/boot-image/edk2-aarch64-code-2048x1536.fd'
		firmware_vars: '/opt/homebrew/share/qemu/edk2-arm-vars.fd'
	}
	kernel := os.getenv_opt('VINIX_ZED_KERNEL') or { '${repository}/build-aarch64-zed/kernel-aarch64' }
	copy_file(kernel, '${state}/kernel')!
	media := hwhost.boot_media(host, '${state}/kernel', archive, 'quiet', state)!
	println('Booting native ARM64 Zed and Vinix; QMP /tmp/vinix-zed-qmp')
	run(host.qemu, ['-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', '8192',
		'-smp', '4', ...media, '-object', 'rng-random,filename=/dev/urandom,id=rng0', '-device',
		'virtio-rng-device,rng=rng0', '-device', 'virtio-keyboard-device', '-device',
		'virtio-tablet-device', '-device', 'ramfb', '-display', 'none', '-serial', 'mon:stdio',
		'-qmp', 'unix:/tmp/vinix-zed-qmp,server=on,wait=off', '-no-reboot'])!
}
