// SPDX-License-Identifier: GPL-2.0-or-later
// v -path '@vlib|@vmodules|.|tools|tests/hardware-platform|build-support' run tests/packages/software-maintenance-check.v ...
// Inputs are an unbooted root from native-catalog-check --software --image,
// a production framebuffer compositor ELF, and its matching architecture kernel.
module main

import crypto.sha256
import hwhost
import json2
import net.unix
import os
import plainiso
import qmpclient
import screenshotcore
import stbi
import time
import tools.packages.pkgcore

#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <errno.h>

struct C.pollfd { pub mut: fd i32 events i16 revents i16 }
fn C.poll(&C.pollfd, usize, i32) i32

fn shutdown_line(mut connection unix.StreamConn, deadline u64) !string {
	mut line := []u8{}
	for {
		if time.sys_mono_now() >= deadline { return error('QMP shutdown deadline expired') }
		mut descriptor := C.pollfd{fd: connection.sock.handle, events: i16(C.POLLIN)}
		ready := C.poll(&descriptor, 1, 50)
		if ready == 0 { continue }
		if ready < 0 { if C.errno == C.EINTR { continue }; return os.error_posix() }
		mut byte := u8(0)
		count := C.recv(connection.sock.handle, &byte, 1, 0)
		if count == 0 { return error('QMP closed before guest shutdown') }
		if count < 0 { if C.errno in [C.EAGAIN, C.EINTR] { continue }; return os.error_posix() }
		if byte == `\n` { return line.bytestr() }
		if line.len >= 1024 * 1024 { return error('QMP shutdown line exceeds limit') }
		line << byte
	}
	return error('QMP shutdown stream ended')
}

fn shutdown_record(mut connection unix.StreamConn, mut transcript os.File, deadline u64) !map[string]json2.Any {
	line := shutdown_line(mut connection, deadline)!
	transcript.writeln(line)!
	return json2.decode[json2.Any](line)!.as_map()
}

fn shutdown_connect(path string, mut transcript os.File, deadline u64, boot int) !&unix.StreamConn {
	mut connection := unix.connect_stream(path)!
	mut admitted := false
	defer { if !admitted { connection.close() or {} } }
	if C.fcntl(connection.sock.handle, C.F_SETFD, C.FD_CLOEXEC) != 0 ||
		C.fcntl(connection.sock.handle, C.F_SETFL, C.O_NONBLOCK) != 0 { return os.error_posix() }
	transcript.writeln(json2.encode({'graphical_boot': boot}))!
	greeting := shutdown_record(mut connection, mut transcript, deadline)!
	if 'QMP' !in greeting { return error('invalid shutdown QMP greeting') }
	request := '{"execute":"qmp_capabilities"}\n'
	if C.send(connection.sock.handle, request.str, usize(request.len), 0) != request.len {
		return error('could not enable shutdown QMP events')
	}
	reply := shutdown_record(mut connection, mut transcript, deadline)!
	if 'return' !in reply { return error('shutdown QMP capabilities refused') }
	admitted = true
	return connection
}

fn shutdown_event(mut connection unix.StreamConn, mut transcript os.File, deadline u64) ! {
	for _ in 0 .. 128 {
		reply := shutdown_record(mut connection, mut transcript, deadline)!
		event := (reply['event'] or { json2.Any('') }).str()
		if event in ['RESET', 'GUEST_PANICKED'] { return error('forbidden QMP power event: ' + event) }
		if event == 'SHUTDOWN' {
			data := (reply['data'] or { return error('QMP shutdown has no data') }).as_map()
			if (data['guest'] or { json2.Any(false) }) != json2.Any(true) ||
				(data['reason'] or { json2.Any('') }) != json2.Any('guest-shutdown') {
				return error('QMP did not report guest-initiated shutdown')
			}
			return
		}
	}
	return error('too many QMP shutdown events')
}

struct GraphicalReceipt {
	architecture string
	platform     string = 'qemu-framebuffer-root-compositor-ordinary-package'
	artifacts    map[string]string
	artifact_paths map[string]string
}

fn invoke(program string, arguments []string) ! {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(arguments)
	child.run()
	child.wait()
	if child.code != 0 { return error(program + ' failed') }
}

fn required(options map[string]string, name string) !string {
	value := options[name] or { return error('required: ' + name) }
	if value == '' { return error('empty ' + name) }
	return os.abs_path(value)
}

fn point(mut monitor qmpclient.Monitor, x int, y int) ! {
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
	// QMP acknowledges queued input before the compositor repaints the pointer.
	// Keep canonical framebuffer captures and subsequent button events settled.
	time.sleep(200 * time.millisecond)
}

fn button(mut monitor qmpclient.Monitor, down bool) ! {
	monitor.command('input-send-event', {
		'events': json2.Any([json2.Any({
			'type': json2.Any('btn')
			'data': json2.Any({
				'button': json2.Any('left')
				'down':   json2.Any(down)
			})
		})])
	})!
}

fn press_before_shutdown(mut monitor qmpclient.Monitor, x int, y int) ! {
	point(mut monitor, x, y)!
	// USB HID samples button state: down/up in one request can coalesce before
	// the guest observes a press. Hold it across at least one device poll.
	button(mut monitor, true)!
	time.sleep(200 * time.millisecond)
	// The release reply may race a fast guest shutdown. The independent QMP
	// guest-SHUTDOWN event and successful process exit remain mandatory below.
	button(mut monitor, false) or {}
}

fn click(mut monitor qmpclient.Monitor, x int, y int) ! {
	point(mut monitor, x, y)!
	for down in [true, false] {
		button(mut monitor, down)!
		time.sleep(100 * time.millisecond)
	}
	time.sleep(500 * time.millisecond)
}

fn region_changes(before screenshotcore.Image, after screenshotcore.Image, x int, y int, width int, height int) int {
	mut changed := 0
	for row in y .. y + height {
		for col in x .. x + width {
			index := (row * before.width + col) * 3
			if before.pixels[index..index + 3] != after.pixels[index..index + 3] { changed++ }
		}
	}
	return changed
}

fn shot(mut monitor qmpclient.Monitor, work string, name string) !screenshotcore.Image {
	path := work + '/' + name + '.ppm'
	monitor.command('screendump', {
		'filename': json2.Any(path)
	})!
	image := screenshotcore.read(path)!
	if image.width != 1024 || image.height != 768 { return error('requires 1024x768 framebuffer') }
	stbi.stbi_write_png(work + '/' + name + '.png', image.width, image.height,
		image.channels, image.pixels.data, image.width * image.channels)!
	os.rm(path)!
	return image
}

fn pin(mut artifacts map[string]string, mut paths map[string]string, name string, path string) ! {
	// Installed media is sparse but its logical size is 4 GiB. Hash in bounded
	// chunks instead of retaining one allocation as large as the whole disk.
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	defer { unsafe { digest.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	artifacts[name] = digest.sum([]u8{}).hex()
	paths[name] = os.real_path(path)
}

fn admit_desktop(desktop string, ordinary bool) ! {
	directory := os.dir(desktop)
	path := directory + '/desktop-build.json'
	if !os.is_file(path) {
		if ordinary { return error('ordinary seat requires a frozen desktop-build.json') }
		return
	}
	manifest := json2.decode[map[string]string](os.read_file(path)!)!
	if manifest['vinix-desktop'] != sha256.sum(os.read_bytes(desktop)!).hex() {
		return error('desktop build receipt does not match the supplied compositor')
	}
	for name, expected in manifest {
		if name in ['compiler', 'repository-head'] { continue }
		if name.starts_with('/') || '..' in name.split('/') {
			return error('desktop build receipt contains an invalid path')
		}
		input := directory + if name.starts_with('app/') || name == 'vinix-desktop' {
			'/' + name
		} else {
			'/source/' + name
		}
		if sha256.sum(os.read_bytes(input)!).hex() != expected {
			return error('desktop source/build input changed after compilation: ' + name)
		}
	}
}

fn healthy(mut child os.Process, log string, deadline u64) !string {
	transcript := os.read_file(log) or { '' }
	if ['SOFTWARE MAINTENANCE FAIL', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION'].any(transcript.contains(it)) {
		return error('guest failed: ' + log)
	}
	if !child.is_alive() || time.sys_mono_now() >= deadline {
		return error('guest exited or timed out: ' + log)
	}
	return transcript
}

fn key(mut monitor qmpclient.Monitor, code string) ! {
	for down in [true, false] {
		monitor.command('input-send-event', {'events': json2.Any([json2.Any({
			'type': json2.Any('key')
			'data': json2.Any({'down': json2.Any(down), 'key': json2.Any({
				'type': json2.Any('qcode'), 'data': json2.Any(code)})})
		})])})!
		time.sleep(30 * time.millisecond)
	}
}

fn wait_marker(mut child os.Process, log string, deadline u64, marker string) ! {
	for {
		if healthy(mut child, log, deadline)!.contains(marker) { return }
		time.sleep(200 * time.millisecond)
	}
}

fn label_ink(image screenshotcore.Image) bool {
	mut dark := 0
	for row in 120 .. 200 {
		for column in 50 .. 350 {
			index := (row * image.width + column) * 3
			if image.pixels[index] < 100 && image.pixels[index + 1] < 100 &&
				image.pixels[index + 2] < 100 { dark++ }
		}
	}
	return dark >= 8
}

fn wait_label(mut child os.Process, mut monitor qmpclient.Monitor, log string,
	deadline u64, work string, name string, expected screenshotcore.Image) !screenshotcore.Image {
	// Launch is asynchronous, especially under TCG. Keep the canonical image
	// only after the actual label appears; saved labels still require exact pixels.
	for {
		healthy(mut child, log, deadline)!
		image := shot(mut monitor, work, name)!
		if label_ink(image) && (expected.pixels.len == 0 ||
			region_changes(expected, image, 50, 120, 300, 80) == 0) { return image }
		time.sleep(200 * time.millisecond)
	}
	return error('Counter label did not render')
}

fn approve(mut monitor qmpclient.Monitor, work string, prefix string, confirm bool) ! {
	if confirm { click(mut monitor, 340, 600)! }
	time.sleep(time.second)
	shot(mut monitor, work, prefix + '-administrator')!
	click(mut monitor, 100, 166)!
	for byte in 'graphical acceptance password'.bytes() {
		key(mut monitor, if byte == ` ` { 'spc' } else { byte.ascii_str() })!
	}
	shot(mut monitor, work, prefix + '-password-mask')!
	key(mut monitor, 'ret')!
}

fn return_to_catalog(mut child os.Process, mut monitor qmpclient.Monitor, log string,
	deadline u64, work string, reference screenshotcore.Image) ! {
	point(mut monitor, 800, 500)!
	for {
		healthy(mut child, log, deadline)!
		image := shot(mut monitor, work, '03-counter-saved')!
		if region_changes(reference, image, 846, 30, 164, 28) >= 8 { break }
		time.sleep(200 * time.millisecond)
	}
	click(mut monitor, 930, 44)!
	time.sleep(time.second)
}

fn graphical_boot(arch string, qemu string, arguments []string, qmp string, work string,
	boot int, previous screenshotcore.Image) !screenshotcore.Image {
	log := work + if boot == 1 { '/serial.log' } else { '/serial-2.log' }
	mut child := os.new_process(qemu)
	defer {
		if child.is_alive() { child.signal_kill(); child.wait() }
		child.close()
		os.rm(qmp) or {}; os.rm(qmp + '.power') or {}
	}
	child.set_args([...arguments, '-serial', 'file:' + log])
	child.run()
	deadline := u64(time.sys_mono_now() + 1200 * time.second)
	wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE START')!
	mut monitor := qmpclient.connect_bounded(qmp, deadline, unsafe { nil })!
	defer { monitor.close() }
	mut shutdown_log := os.create(work + '/shutdown-' + boot.str() + '.jsonl')!
	defer { shutdown_log.close() }
	mut shutdown := shutdown_connect(qmp + '.power', mut shutdown_log, deadline, boot)!
	defer { shutdown.close() or {} }
	wait_marker(mut child, log, deadline, 'vinix-desktop: ready')!
	wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE ordinary-compositor uid=1000 home=/home/alex PASS')!
	time.sleep(2 * time.second)
	shot(mut monitor, work, if boot == 1 { '01-catalog' } else { '10-reboot-upgraded' })!
	click(mut monitor, 984, 57)!
	time.sleep(time.second)
	click(mut monitor, 140, 138)!
	mut checkpoint := previous
	if boot == 1 {
		click(mut monitor, 350, 562)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE review=install unchanged-state approvals=0 PASS')!
		shot(mut monitor, work, 'install-review')!
		approve(mut monitor, work, 'install', true)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE installed version=1.0.0 approvals=1')!
		time.sleep(time.second)
		click(mut monitor, 140, 138)!
		click(mut monitor, 930, 94)!
		point(mut monitor, 800, 500)!
		before := wait_label(mut child, mut monitor, log, deadline, work, '02-counter-zero', screenshotcore.Image{})!
		click(mut monitor, 250, 320)!
		click(mut monitor, 250, 320)!
		point(mut monitor, 800, 500)!
		two := shot(mut monitor, work, '03-counter-two')!
		if region_changes(before, two, 50, 120, 300, 80) < 8 { return error('Counter did not visibly increment twice') }
		click(mut monitor, 930, 56)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE newer signed medium available PASS')!
		return_to_catalog(mut child, mut monitor, log, deadline, work, two)!
		click(mut monitor, 970, 56)!
		approve(mut monitor, work, 'refresh', false)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE refreshed signed=1.1.0 active=1.0.0 approvals=2 PASS')!
		time.sleep(time.second)
		click(mut monitor, 254, 94)!
		click(mut monitor, 140, 138)!
		shot(mut monitor, work, '04-updates')!
		click(mut monitor, 330, 600)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE review=upgrade unchanged-state approvals=2 PASS')!
		time.sleep(time.second)
		shot(mut monitor, work, 'update-review')!
		approve(mut monitor, work, 'update', true)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE upgraded version=1.1.0 approvals=3')!
		time.sleep(time.second)
		click(mut monitor, 60, 94)!
		click(mut monitor, 140, 138)!
		shot(mut monitor, work, '05-upgraded')!
		click(mut monitor, 930, 94)!
		point(mut monitor, 800, 500)!
		wait_label(mut child, mut monitor, log, deadline, work, '06-upgraded-counter-two', two)!
		click(mut monitor, 250, 320)!
		point(mut monitor, 800, 500)!
		checkpoint = shot(mut monitor, work, '07-upgraded-counter-three')!
	} else {
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE BOOT 2 retained upgraded=1.1.0 approvals=3 private=3 PASS')!
		shot(mut monitor, work, '11-retained-upgraded')!
		click(mut monitor, 444, 600)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE review=rollback unchanged-state approvals=3 PASS')!
		time.sleep(time.second)
		shot(mut monitor, work, 'rollback-review')!
		approve(mut monitor, work, 'rollback', true)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE rolled-back version=1.0.0 approvals=4')!
		time.sleep(time.second)
		click(mut monitor, 140, 138)!
		shot(mut monitor, work, '12-rolled-back')!
		click(mut monitor, 510, 562)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE review=remove unchanged-state approvals=4 PASS')!
		time.sleep(time.second)
		shot(mut monitor, work, 'uninstall-review')!
		approve(mut monitor, work, 'uninstall', true)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE cache-only both repository payload directories absent PASS')!
		time.sleep(time.second)
		click(mut monitor, 140, 138)!
		shot(mut monitor, work, '13-uninstalled')!
		click(mut monitor, 350, 562)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE review=install unchanged-state approvals=5 PASS')!
		time.sleep(time.second)
		shot(mut monitor, work, 'reinstall-review')!
		approve(mut monitor, work, 'reinstall', true)!
		wait_marker(mut child, log, deadline, 'SOFTWARE MAINTENANCE cache-reinstalled version=1.1.0 approvals=6')!
		time.sleep(time.second)
		click(mut monitor, 140, 138)!
		shot(mut monitor, work, '14-cache-reinstalled')!
		click(mut monitor, 930, 94)!
		point(mut monitor, 800, 500)!
		wait_label(mut child, mut monitor, log, deadline, work, '15-reinstalled-counter-three', previous)!
		click(mut monitor, 250, 320)!
		point(mut monitor, 800, 500)!
		shot(mut monitor, work, '16-reinstalled-counter-four')!
	}
	press_before_shutdown(mut monitor, 930, 56)!
	shutdown_event(mut shutdown, mut shutdown_log, deadline)!
	wait_poweroff(mut child, log, deadline, boot, arch == 'aarch64')!
	return checkpoint
}

fn wait_poweroff(mut child os.Process, log string, deadline u64, boot int, kernel_serial bool) ! {
	for child.is_alive() {
		transcript := os.read_file(log) or { '' }
		if transcript.contains('SOFTWARE MAINTENANCE FAIL') || transcript.contains('KERNEL PANIC') ||
			u64(time.sys_mono_now()) >= deadline { return error('installed graphical boot failed: ' + log) }
		time.sleep(200 * time.millisecond)
	}
	child.wait()
	transcript := os.read_file(log)!
	marker := if boot == 1 {
		'SOFTWARE MAINTENANCE INSTALLED BOOT 1 acquired refreshed upgraded pointer-saved checkpoint PASS'
	} else {
		'SOFTWARE MAINTENANCE INSTALLED BOOT 2 retained rollback uninstall cache-reinstall pointer-saved PASS'
	}
	if child.code != 0 || !transcript.contains(marker) ||
		(kernel_serial && !transcript.contains('syspower: power off: stopping devices')) ||
		transcript.contains('sysdisk: running from memory') || transcript.contains('sysdisk: updating the system on') {
		return error('installed graphical boot did not complete from its admitted disk: ' + log)
	}
}

fn check() ! {
	$if prod {} $else { return error('compile the graphical controller with -prod to freeze its embedded source') }
	embedded_controller := $embed_file('software-maintenance-check.v').to_string()
	if sha256.sum(embedded_controller.bytes()).hex() != sha256.sum(os.read_bytes(@FILE)!).hex() {
		return error('controller source changed after controller compilation')
	}
	mut options := map[string]string{}
	for argument in os.args[1..] {
		if !argument.starts_with('--') || !argument.contains('=') {
			return error('use --arch=aarch64 --rootfs=DIR --desktop=ELF --kernel=ELF --out=DIR')
		}
		options[argument.all_before('=')] = argument.all_after('=')
	}
	arch := options['--arch'] or { 'aarch64' }
	ordinary := 'true'
	installed := 'true'
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, arch, '')!
	input := required(options, '--rootfs')!
	desktop := required(options, '--desktop')!
	kernel := required(options, '--kernel')!
	admit_desktop(desktop, ordinary == 'true')!
	work := required(options, '--out')!
	if os.exists(work) { return error('output directory must be new') }
	config := input + '/etc/vinix-packages/config.json'
	if !os.is_file(config) || os.exists(input + '/var/lib/vinix-packages/state.json') {
		return error('requires a fresh, production-staged signed native image root')
	}
	configuration := pkgcore.load_config(input)!
	if configuration.launch_user != 'alex' || configuration.architecture != arch {
		return error('staged image must target the selected architecture and launch_user alex')
	}
	os.mkdir_all(work + '/rootfs')!
	os.mkdir_all(work + '/source')!
	mut artifacts := map[string]string{}
	mut artifact_paths := map[string]string{}
	if arch == 'x86_64' {
		os.write_file(work + '/source/plainiso.v', plainiso.source())!
		pin(mut artifacts, mut artifact_paths, 'source/plainiso.v', work + '/source/plainiso.v')!
		for name, path in plainiso.inputs(root)! { pin(mut artifacts, mut artifact_paths, name, path)! }
	}
	for name, path in {
		'controller': os.executable()
		'compiler':   host.v
		'qemu':       host.qemu
		'firmware':   host.firmware
	} {
		pin(mut artifacts, mut artifact_paths, name, path)!
	}
	cc_name := if arch == 'aarch64' { 'CC_AARCH64' } else { 'CC_AMD64' }
	cc := os.getenv_opt(cc_name) or { if arch == 'aarch64' {
		'clang'
	} else {
		'x86_64-linux-musl-gcc'
	} }
	pin(mut artifacts, mut artifact_paths, 'cross-compiler', os.find_abs_path_of_executable(cc)!)!
	for name in ['software-maintenance-check.v', 'software-graphical-build.v'] {
		if name == 'software-maintenance-check.v' {
			os.write_file(work + '/source/' + name, embedded_controller)!
		} else {
			os.cp(root + '/tests/packages/' + name, work + '/source/' + name)!
		}
		pin(mut artifacts, mut artifact_paths, 'source/' + name, work + '/source/' + name)!
	}
	invoke('cp', ['-Rp', root + '/tests/packages/software-maintenance-guest', work + '/source/guest'])!
	for path in os.walk_ext(work + '/source/guest', '.v') {
		pin(mut artifacts, mut artifact_paths, 'source/guest/' + os.file_name(path), path)!
	}
	invoke('cp', ['-Rp', input + '/.', work + '/rootfs'])!

	os.write_file(work + '/rootfs/etc/software-maintenance-mode', if ordinary == 'true' {
		'ordinary\n'
	} else {
		'root\n'
	})!
	publisher := required(options, '--publisher')!
	{
		// Refresh this private fixture's validity with its original signing key.
		repository := work + '/rootfs/usr/share/vinix-packages/repositories/native'
		os.rmdir_all(repository)!
		// A fresh workspace avoids changing the original publisher's retained
		// anti-rollback history or reusing a sequence for different bytes.
		invoke('cp', ['-Rp', os.real_path(publisher) + '/workspace-1.0.0',
			work + '/publisher-workspace'])!
		sequence := u64(time.now().unix())
		pkgcore.publish_release(work + '/publisher-workspace', 'native', os.real_path(publisher) + '/seed', sequence, time.now().unix() + 86400, repository)!
		invoke('cp', ['-Rp', os.real_path(publisher) + '/workspace-1.1.0', work + '/publisher-workspace-newer'])!
		pkgcore.publish_release(work + '/publisher-workspace-newer', 'native', os.real_path(publisher) + '/seed',
			sequence + 1, time.now().unix() + 86400, work + '/rootfs/usr/share/software-maintenance-release-1.1.0')!
	}
	os.cp(desktop, work + '/rootfs/usr/bin/vinix-desktop')!
	os.chmod(work + '/rootfs/usr/bin/vinix-desktop', 0o755)!
	guest := hwhost.build_program(host, work + '/source/guest', work + '/guest-build', 'init', ['.'])!
	os.mkdir_all(work + '/rootfs/sbin')!
	os.cp(guest, work + '/rootfs/sbin/init')!
	os.chmod(work + '/rootfs/sbin/init', 0o755)!
	if installed == 'true' {
		os.write_file(work + '/rootfs/etc/software-maintenance-installed', '1\n')!
		os.write_file(work + '/rootfs/.vinix-image-id', 'vinix-software-maintenance-installed-1\n')!
		mut proof := map[string]string{}
		for path in ['/sbin/init', '/usr/bin/vinix-desktop', '/usr/bin/vinix-package',
			'/usr/bin/vinix-sandbox', '/usr/sbin/vinix-account', '/usr/sbin/vinix-authd',
			'/usr/sbin/vinix-session', '/usr/share/vinix/actions/packages-change',
			'/usr/share/vinix/actions/packages-launch', '/etc/vinix-packages/config.json'] {
			proof[path] = sha256.sum(os.read_bytes(work + '/rootfs' + path)!).hex()
		}
		os.write_file(work + '/rootfs/usr/share/software-maintenance-installed.json', json2.encode(proof) + '\n')!
		os.write_file(work + '/system.vjfs', '')!
		os.truncate(work + '/system.vjfs', u64(4096) << 20)!
	}
	os.setenv('COPYFILE_DISABLE', '1', true)
	invoke('tar', ['--format=ustar', '-cf', work + '/initramfs.tar', '-C', work + '/rootfs', '.'])!
	media_host := if arch == 'x86_64' {
		hwhost.Host{...host, root: plainiso.prepare(root, work)!}
	} else { host }
	media := hwhost.boot_media(media_host, kernel, work + '/initramfs.tar', if installed == 'true' && arch == 'aarch64' {
		'quiet vinix.disk=auto'
	} else { 'quiet' }, work)!
	qmp := '/tmp/vinix-software-maintenance-' + os.getpid().str() + '.qmp'
	defer { os.rm(qmp) or {}; os.rm(qmp + '.power') or {} }
	mut arguments := if arch == 'aarch64' {
		['-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-device', 'ramfb',
			'-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device']
	} else {
		// The pinned x86 kernel implements USB HID; virtio input is ARM-only.
		['-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-vga', 'std',
			'-device', 'qemu-xhci,id=gui-input', '-device', 'usb-kbd,bus=gui-input.0',
			'-device', 'usb-tablet,bus=gui-input.0']
	}
	arguments << ['-m', if arch == 'aarch64' { '2048' } else { '1024' }, '-smp', '2', ...media, '-display', 'none',
		'-qmp', 'unix:' + qmp + ',server=on,wait=off', '-no-reboot',
		'-qmp', 'unix:' + qmp + '.power,server=on,wait=off',
		'-nic', 'none']
	if installed == 'true' {
		arguments << if arch == 'aarch64' {
			['-drive', 'if=none,id=system,format=raw,cache=writeback,file=' + work + '/system.vjfs',
				'-device', 'virtio-blk-device,drive=system']
		} else { ['-drive', 'if=ide,format=raw,cache=writeback,file=' + work + '/system.vjfs'] }
	}
	checkpoint := graphical_boot(arch, host.qemu, arguments, qmp, work, 1, screenshotcore.Image{})!
	if installed == 'true' {
		graphical_boot(arch, host.qemu, arguments, qmp, work, 2, checkpoint)!
		pin(mut artifacts, mut artifact_paths, 'system-disk', work + '/system.vjfs')!
		pin(mut artifacts, mut artifact_paths, 'serial-2', work + '/serial-2.log')!
		pin(mut artifacts, mut artifact_paths, 'shutdown-2', work + '/shutdown-2.jsonl')!
		pin(mut artifacts, mut artifact_paths, 'installed-declaration', work + '/rootfs/usr/share/software-maintenance-installed.json')!
	}
	if arch == 'x86_64' {
		for name, path in {
			'boot-iso': work + '/test.iso'
			'boot-configuration': work + '/iso/iso-root/boot/limine.conf'
			'boot-image-commands': work + '/image-commands.json'
		} { pin(mut artifacts, mut artifact_paths, name, path)! }
	}
	build_receipt := os.dir(desktop) + '/desktop-build.json'
	if os.is_file(build_receipt) {
		manifest := json2.decode[map[string]string](os.read_file(build_receipt)!)!
		if manifest['vinix-desktop'] != sha256.sum(os.read_bytes(desktop)!).hex() {
			return error('desktop build receipt does not match the supplied compositor')
		}
		os.cp(build_receipt, work + '/desktop-build.json')!
		pin(mut artifacts, mut artifact_paths, 'desktop-build', work + '/desktop-build.json')!
		pin(mut artifacts, mut artifact_paths, 'desktop-build-original', build_receipt)!
	}
	for name, path in {
		'kernel':    kernel
		'desktop':   desktop
		'config':    work + '/rootfs/etc/vinix-packages/config.json'
		'initramfs': work + '/initramfs.tar'
		'serial':    work + '/serial.log'
		'guest':     guest
		'guest-c':   work + '/guest-build/init.c'
		'shutdown-1': work + '/shutdown-1.jsonl'
	} {
		pin(mut artifacts, mut artifact_paths, name, path)!
	}
	repository := work + '/rootfs/usr/share/vinix-packages/repositories/native'
	for path in os.walk_ext(repository, '') {
		if os.is_file(path) {
			pin(mut artifacts, mut artifact_paths, 'repository/' + path[repository.len + 1..], path)!
		}
	}
	newer := work + '/rootfs/usr/share/software-maintenance-release-1.1.0'
	for path in os.walk_ext(newer, '') {
		if os.is_file(path) { pin(mut artifacts, mut artifact_paths, 'repository-newer/' + path[newer.len + 1..], path)! }
	}
	for path in os.walk_ext(work, '.png') {
		if os.dir(path) == work { pin(mut artifacts, mut artifact_paths, os.file_name(path).all_before_last('.'), path)! }
	}
	os.write_file(work + '/qualification.json', json2.encode(GraphicalReceipt{
		architecture: arch
		platform: 'qemu-framebuffer-ordinary-seat-maintenance-installed-root-two-boots'
		artifacts:    artifacts
		artifact_paths: artifact_paths
	}) + '\n')!
	println('SOFTWARE MAINTENANCE PASS: production compositor, native pointer delivery, ordinary private data')
}

fn main() {
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	if plainiso.requested() {
		plainiso.build() or { eprintln(err); exit(1) }
		return
	}
	check() or {
		eprintln(err)
		exit(1)
	}
}
