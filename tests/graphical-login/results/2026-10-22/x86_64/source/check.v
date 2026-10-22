// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import loginproof
import os
import plainiso
import qmpclient
import screenshotcore
import stbi
import time

fn hash_file(path string) !string { return loginproof.digest(path)! }

fn guest_arguments(host hwhost.Host, work string, cc string) map[string][]string {
	c_file := work + '/build-guest/guest.c'
	binary := work + '/build-guest/guest'
	mut commands := {
		'v': [host.v, '-os', 'linux', '-arch', if host.arch == 'aarch64' { 'arm64' } else { 'amd64' },
			'-gc', 'none', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-new-compiler',
			'-manualfree', '-o', c_file, work + '/source/guest/main.v']
	}
	commands['c'] = if host.arch == 'aarch64' {
		sysroot := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { hwhost.shared_path(host.root, 'build-aarch64-userland/sysroot') }
		[cc, '--target=aarch64-linux-musl', '--sysroot=' + sysroot, '-static', '-O1', '-w',
			'-D_GNU_SOURCE', '-fno-stack-protector', '-L' + sysroot + '/lib', '-fuse-ld=lld',
			'-o', binary, c_file, '-lm', '-lpthread']
	} else {
		[cc, '-static', '-O1', '-w', '-fpermissive', '-D_GNU_SOURCE', '-o', binary, c_file, '-lm', '-lpthread']
	}
	return commands
}

fn wait_marker(mut child os.Process, serial string, marker string) ! {
	deadline := time.sys_mono_now() + 650 * time.second
	for time.sys_mono_now() < deadline {
		text := os.read_file(serial) or { '' }
		if text.contains('GRAPHICAL LOGIN FAIL:') || text.contains('V panic:') || text.contains('KERNEL PANIC') || text.contains('Assertion failed') {
			return error('guest refused qualification:\n' + text)
		}
		if marker in text.split_into_lines().map(it.trim_space()) { return }
		if !child.is_alive() { return error('QEMU exited before ' + marker) }
		time.sleep(100 * time.millisecond)
	}
	return error('timed out waiting for ' + marker)
}

fn key(mut monitor qmpclient.Monitor, code string) ! {
	for down in [true, false] {
		monitor.command('input-send-event', {
			'events': json2.Any([json2.Any({
				'type': json2.Any('key')
				'data': json2.Any({
					'down': json2.Any(down)
					'key':  json2.Any({
						'type': json2.Any('qcode')
						'data': json2.Any(code)
					})
				})
			})])
		})!
		time.sleep(50 * time.millisecond)
	}
}

fn type_text(mut monitor qmpclient.Monitor, text string) ! {
	for ch in text { key(mut monitor, [ch].bytestr())! }
}

fn click(mut monitor qmpclient.Monitor, x int, y int) ! {
	monitor.command('input-send-event', {
		'events': json2.Any([
			json2.Any({
				'type': json2.Any('abs')
				'data': json2.Any({
					'axis':  json2.Any('x')
					'value': json2.Any(x * 32767 / 1024)
				})
			}),
			json2.Any({
				'type': json2.Any('abs')
				'data': json2.Any({
					'axis':  json2.Any('y')
					'value': json2.Any(y * 32767 / 768)
				})
			}),
		])
	})!
	time.sleep(200 * time.millisecond)
	for down in [true, false] {
		monitor.command('input-send-event', {
			'events': json2.Any([json2.Any({
				'type': json2.Any('btn')
				'data': json2.Any({
					'down':   json2.Any(down)
					'button': json2.Any('left')
				})
			})])
		})!
		time.sleep(200 * time.millisecond)
	}
}

fn shot(mut monitor qmpclient.Monitor, work string, name string) ! {
	time.sleep(time.second)
	monitor.command('screendump', {
		'filename': json2.Any(work + '/' + name + '.ppm')
	})!
	image := screenshotcore.read(work + '/' + name + '.ppm')!
	if image.width != 1024 || image.height != 768 { return error('requires a 1024x768 framebuffer') }
	stbi.stbi_write_png(work + '/' + name + '.png', image.width, image.height,
		image.channels, image.pixels.data, image.width * image.channels)!
	os.rm(work + '/' + name + '.ppm')!
}

fn login(mut monitor qmpclient.Monitor) ! {
	type_text(mut monitor, 'alex')!
	key(mut monitor, 'tab')!
	type_text(mut monitor, 'loginpass')!
	key(mut monitor, 'ret')!
}

fn account_action(mut monitor qmpclient.Monitor, serial string, logout bool) ! {
	click(mut monitor, 20, 750)! // Default theme's real Start button.
	click(mut monitor, 375, 222)! // Account… at the top of the right column.
	// The real power capability adds one row at the popup's bottom. Its
	// bottom remains fixed, so every other row moves up by 32 pixels.
	sleep_row := os.read_file(serial)!.split_into_lines().any(it.trim_space() == 'GRAPHICAL LOGIN Account menu includes sleep')
	y := (if logout { 664 } else { 632 }) - (if sleep_row { 32 } else { 0 })
	click(mut monitor, 365, y)!
}

fn check() ! {
	$if prod {
	} $else {
		return error('compile with -prod to freeze controller bytes')
	}
	if os.args.len != 8 {
		return error('usage: check ARCH KERNEL DESKTOP_BUILD ACCOUNTS_STAGE ACCOUNT_PROOF OUTPUT SHARED')
	}
	arch := os.args[1]
	kernel := os.abs_path(os.args[2])
	desktop_build := os.abs_path(os.args[3])
	accounts := os.abs_path(os.args[4])
	account_proof := os.abs_path(os.args[5])
	work := os.abs_path(os.args[6])
	shared := os.abs_path(os.args[7])
	if arch !in ['aarch64', 'x86_64'] || os.exists(work) {
		return error('unsupported architecture or output already exists')
	}
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, arch, '')!
	if hash_file(@FILE)! != sha256.hexhash($embed_file('check.v').to_string()) {
		return error('controller source changed')
	}
	loginproof.desktop(desktop_build, sha256.hexhash($embed_file('build.v').to_string()))!
	loginproof.accounts(account_proof, accounts, arch, sha256.hexhash($embed_file('../../tools/accounts/stage.v').to_string()))!
	os.mkdir_all(work + '/source/guest')!
	os.cp(@FILE, work + '/source/check.v')!
	os.cp(root + '/tests/graphical-login/guest/main.v', work + '/source/guest/main.v')!
	mut inputs := {
		'controller-source': @FILE
		'guest-source':      root + '/tests/graphical-login/guest/main.v'
		'controller':        os.executable()
		'compiler':          host.v
		'kernel':            kernel
		'qemu':              host.qemu
		'firmware':          host.firmware
		'desktop':           desktop_build + '/vinix-desktop'
		'desktop-build':     desktop_build + '/desktop-build.json'
		'desktop-inputs': desktop_build + '/build-inputs.json'
		'desktop-input-paths': desktop_build + '/build-input-paths.json'
		'desktop-argv': desktop_build + '/build-argv.json'
		'base-passwd':       root + '/base-files/etc/passwd'
		'base-group':        root + '/base-files/etc/group'
	}
	for name in ['inputs', 'input-paths', 'outputs', 'arguments', 'result'] {
		inputs['account-proof-' + name] = account_proof + '/receipt/' + name + '.json'
	}
	inputs['builder-source'] = root + '/tests/graphical-login/build.v'
	inputs['proof-source'] = root + '/tests/graphical-login/loginproof/proof.v'
	inputs['stager-source'] = root + '/tools/accounts/stage.v'
	for tool in ['cp', 'tar'] { inputs['tool/' + tool] = os.find_abs_path_of_executable(tool)! }
	cc_name := if arch == 'aarch64' { 'CC_AARCH64' } else { 'CC_AMD64' }
	inputs['guest-c-compiler'] = os.find_abs_path_of_executable(os.getenv(cc_name))!
	if os.getenv('VINIX_LOGIN_CROSS_DRIVER') != '' {
		inputs['guest-cross-driver'] = os.getenv('VINIX_LOGIN_CROSS_DRIVER')
	}
	if host.firmware_vars != '' { inputs['firmware-vars'] = host.firmware_vars }
	if arch == 'x86_64' {
		for name, path in plainiso.inputs(shared)! { inputs[name] = path }
	} else {
		inputs['limine-config'] = root + '/build-support/limine.conf'
		inputs['limine-loader'] = os.getenv_opt('VINIX_LIMINE_BOOTAA64') or { shared + '/boot-image/limine-bin/BOOTAA64.EFI' }
		for tool in ['mformat', 'mmd', 'mcopy'] { inputs['tool/' + tool] = os.find_abs_path_of_executable(tool)! }
	}
	for name in ['vinix-account', 'vinix-authd', 'vinix-session', 'vinix-system'] {
		inputs[name] = accounts + '/usr/sbin/' + name
	}
	inputs['vinix-auth'] = accounts + '/usr/bin/vinix-auth'
	for module_name in ['hwhost', 'plainiso'] {
		for name in os.ls(root + '/tests/hardware-platform/' + module_name)! {
			if name.ends_with('.v') && !name.ends_with('_test.v') {
				inputs[module_name + '/' + name] = root + '/tests/hardware-platform/' + module_name + '/' + name
			}
		}
	}
	for module_name, directory in {'qmpclient': root + '/tools/qmpclient', 'screenshotcore': root + '/build-support/screenshotcore'} {
		for name in os.ls(directory)! {
			if name.ends_with('.v') && !name.ends_with('_test.v') { inputs[module_name + '/' + name] = directory + '/' + name }
		}
	}
	mut hashes := map[string]string{}
	for name, path in inputs { hashes[name] = hash_file(path)! }
	if loginproof.strings(account_proof + '/receipt/inputs.json')!['compiler-v'] != hashes['compiler'] {
		return error('guest compiler differs from admitted account compiler')
	}
	os.write_file(work + '/inputs.json', json2.encode(hashes))!
	os.write_file(work + '/input-paths.json', json2.encode(inputs))!
	os.write_file(work + '/arguments.json', json2.encode(os.args))!
	os.write_file(work + '/guest-argv.json', json2.encode(guest_arguments(host, work, inputs['guest-c-compiler'])))!
	guest := hwhost.build_program_with_flags(host, work + '/source/guest/main.v', work + '/build-guest', 'guest', [], [
		'-new-compiler',
		'-manualfree',
	])!
	rootfs := work + '/extras'
	hwhost.run_tool(['cp', '-Rp', accounts, rootfs], {}, work + '/stage.log', 60)!
	for dir in ['usr/bin', 'tmp', 'run', 'home', 'var/log'] { os.mkdir_all(rootfs + '/' + dir)! }
	os.mkdir_all(rootfs + '/etc')!
	os.cp(inputs['base-passwd'], rootfs + '/etc/passwd')!
	os.cp(inputs['base-group'], rootfs + '/etc/group')!
	os.chmod(rootfs + '/tmp', 0o1777)!
	os.cp(desktop_build + '/vinix-desktop', rootfs + '/usr/bin/vinix-desktop')!
	os.chmod(rootfs + '/usr/bin/vinix-desktop', 0o755)!
	boot := work + '/boot'
	os.mkdir_all(boot)!
	archive := hwhost.build_initramfs(guest, 'graphical-login', boot, rootfs)!
	runtime_host := if arch == 'x86_64' {
		hwhost.Host{ ...host, root: plainiso.prepare(shared, work)! }
	} else {
		host
	}
	media := hwhost.boot_media(runtime_host, kernel, archive, '', boot)!
	mut args := if arch == 'aarch64' {
		['-machine', 'virt,gic-version=3', '-device', 'ramfb', '-device', 'virtio-keyboard-device',
			'-device', 'virtio-tablet-device']
	} else {
		['-machine', 'q35,smm=off', '-vga', 'std', '-device', 'qemu-xhci,id=gui-input', '-device',
			'usb-kbd,bus=gui-input.0', '-device', 'usb-tablet,bus=gui-input.0']
	}
	args << host.accelerator()
	args << media
	qmp := work + '/qmp.sock'
	serial := boot + '/serial.log'
	args << ['-m', '1024', '-smp', '2', '-display', 'none', '-no-reboot', '-nic', 'none', '-serial',
		'file:' + serial, '-qmp', 'unix:' + qmp + ',server=on,wait=off']
	os.write_file(work + '/qemu-argv.json', json2.encode([host.qemu, ...args]))!
	mut child := os.new_process(host.qemu)
	child.set_args(args)
	child.set_redirect_stdio()
	child.run()
	mut retired := false
	defer {
		if !retired {
			if child.is_alive() { child.signal_kill() }
			child.wait()
			os.write_file(work + '/qemu.log', child.stdout_slurp() + child.stderr_slurp()) or {}
			child.close()
		}
	}
	connect_deadline := time.sys_mono_now() + 30 * time.second
	for !os.exists(qmp) && child.is_alive() && time.sys_mono_now() < connect_deadline {
		time.sleep(50 * time.millisecond)
	}
	if !os.exists(qmp) { return error('QEMU did not create its control socket') }
	mut monitor := qmpclient.connect_bounded(qmp, u64(time.sys_mono_now() + 1800 * time.second), unsafe { nil })!
	defer { monitor.close() }
	wait_marker(mut child, serial, 'GRAPHICAL LOGIN fresh image exclusive registration READY')!
	shot(mut monitor, work, '01-registration')!
	type_text(mut monitor, 'alex')!
	key(mut monitor, 'tab')!
	type_text(mut monitor, 'loginpass')!
	key(mut monitor, 'tab')!
	type_text(mut monitor, 'loginpass')!
	key(mut monitor, 'ret')!
	wait_marker(mut child, serial, 'GRAPHICAL LOGIN registered account and ordinary greeter PASS')!
	shot(mut monitor, work, '02-greeter')!
	type_text(mut monitor, 'alex')!
	key(mut monitor, 'tab')!
	type_text(mut monitor, 'wrongpass')!
	key(mut monitor, 'ret')!
	wait_marker(mut child, serial, 'GRAPHICAL LOGIN wrong password creates no ordinary session PASS')!
	shot(mut monitor, work, '03-refused')!
	type_text(mut monitor, 'loginpass')!
	key(mut monitor, 'ret')!
	wait_marker(mut child, serial, 'GRAPHICAL LOGIN first ordinary desktop private home and runtime PASS')!
	shot(mut monitor, work, '04-ordinary')!
	account_action(mut monitor, serial, false)!
	wait_marker(mut child, serial, 'GRAPHICAL LOGIN switch stops prior session and returns ordinary greeter PASS')!
	shot(mut monitor, work, '05-switched')!
	login(mut monitor)!
	wait_marker(mut child, serial, 'GRAPHICAL LOGIN reauthentication resumes same process and kernel session PASS')!
	shot(mut monitor, work, '06-resumed')!
	account_action(mut monitor, serial, true)!
	wait_marker(mut child, serial, 'GRAPHICAL LOGIN logout reaps ordinary session and returns greeter PASS')!
	shot(mut monitor, work, '07-logged-out')!
	login(mut monitor)!
	wait_marker(mut child, serial, 'GRAPHICAL LOGIN new login has fresh process and preserved home PASS')!
	shot(mut monitor, work, '08-new-login')!
	wait_marker(mut child, serial, 'HWTEST PASS graphical-login')!
	// This fixture ends with a running PID 1 after manager cleanup. Retire our
	// owned VM explicitly; this is not a guest poweroff qualification.
	monitor.close()
	if child.is_alive() { child.signal_kill() }
	child.wait()
	os.write_file(work + '/qemu.log', child.stdout_slurp() + child.stderr_slurp())!
	child.close()
	retired = true
	loginproof.serial(os.read_file(serial)!)!
	loginproof.desktop(desktop_build, sha256.hexhash($embed_file('build.v').to_string()))!
	loginproof.accounts(account_proof, accounts, arch, sha256.hexhash($embed_file('../../tools/accounts/stage.v').to_string()))!
	for name, path in inputs {
		if hash_file(path)! != hashes[name] { return error('input changed: ' + name) }
	}
	os.write_file(work + '/inputs-verified.json', json2.encode(hashes))!
	os.write_file(work + '/result.json', json2.encode({
		'passed':   'true'
		'platform': 'direct-graphical-manager-registration-login-switch-logout'
		'arch':     arch
	}))!
	mut outputs := map[string]string{}
	for entry in loginproof.output_names(arch) {
		outputs[entry] = hash_file(work + '/' + entry)!
	}
	os.write_file(work + '/outputs.json', json2.encode(outputs))!
	println('PASS ' + arch + ' actual graphical registration/login/switch/logout: ' + work)
}

fn main() {
	if plainiso.requested() {
		plainiso.build() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	check() or {
		eprintln(err)
		exit(1)
	}
}
