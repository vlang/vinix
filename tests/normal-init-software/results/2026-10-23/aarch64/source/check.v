// SPDX-License-Identifier: GPL-2.0-or-later
// v -path '@vlib|@vmodules|.|tools|tests/hardware-platform|build-support' run tests/packages/software-maintenance-check.v ...
// Inputs are an unbooted root from native-catalog-check --software --image,
// a production framebuffer compositor ELF, and its matching architecture kernel.
module main

import crypto.sha256
import hwhost
import json2
import net.unix
import normalproof
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
	platform     string = 'production-init-installed-ordinary-software-two-boots'
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

fn record_shot(mut monitor qmpclient.Monitor, work string, name string) ! {
	image := shot(mut monitor, work, name)!
	unsafe { image.pixels.free() }
}

fn pin(mut artifacts map[string]string, mut paths map[string]string, name string, path string) ! {
	// Installed media is sparse but its logical size is 4 GiB. Hash in bounded
	// chunks instead of retaining one allocation as large as the whole disk.
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	defer { unsafe { digest.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	bytes := digest.sum([]u8{})
	defer { unsafe { bytes.free() } }
	artifacts[name] = bytes.hex()
	paths[name] = os.real_path(path)
}

fn healthy(mut child os.Process, log string, deadline u64) !string {
	transcript := os.read_file(log) or { '' }
	if ['NORMAL INIT SOFTWARE FAIL', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION', 'crashed with'].any(transcript.contains(it)) {
		unsafe { transcript.free() }
		return error('guest failed: ' + log)
	}
	if !child.is_alive() || time.sys_mono_now() >= deadline {
		unsafe { transcript.free() }
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
		text := healthy(mut child, log, deadline)!
		matched := text.contains(marker)
		unsafe { text.free() }
		if matched { return }
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
		text := healthy(mut child, log, deadline)!
		unsafe { text.free() }
		image := shot(mut monitor, work, name)!
		if label_ink(image) && (expected.pixels.len == 0 ||
			region_changes(expected, image, 50, 120, 300, 80) == 0) { return image }
		unsafe { image.pixels.free() }
		time.sleep(200 * time.millisecond)
	}
	return error('Counter label did not render')
}

fn approve(mut monitor qmpclient.Monitor, work string, prefix string, confirm bool) ! {
	if confirm { click(mut monitor, 340, 600)! }
	time.sleep(time.second)
	record_shot(mut monitor, work, prefix + '-administrator')!
	click(mut monitor, 100, 166)!
	for byte in 'loginpass'.bytes() {
		key(mut monitor, if byte == ` ` { 'spc' } else { byte.ascii_str() })!
	}
	record_shot(mut monitor, work, prefix + '-password-mask')!
	key(mut monitor, 'ret')!
	time.sleep(2 * time.second)
	record_shot(mut monitor, work, prefix + '-submitted')!
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

fn type_text(mut monitor qmpclient.Monitor, text string) ! {
	for byte in text { key(mut monitor, if byte == ` ` { 'spc' } else { byte.ascii_str() })! }
}

fn graphical_boot(host hwhost.Host, arguments []string, qmp string, work string,
	boot int, previous screenshotcore.Image) !screenshotcore.Image {
	log := work + '/serial-' + boot.str() + '.log'
	mut child := os.new_process(host.qemu)
	defer {
		if child.is_alive() { child.signal_kill(); child.wait() }
		child.close()
		os.rm(qmp) or {}; os.rm(qmp + '.power') or {}
	}
	child.set_args([...arguments, '-serial', 'file:' + log])
	child.run()
	deadline := u64(time.sys_mono_now() + 1800 * time.second)
	wait_marker(mut child, log, deadline, 'NORMAL INIT SOFTWARE START optional-helper observer')!
	mut monitor := qmpclient.connect_bounded(qmp, deadline, unsafe { nil })!
	defer { monitor.close() }
	mut shutdown_log := os.create(work + '/shutdown-' + boot.str() + '.jsonl')!
	defer { shutdown_log.close() }
	mut shutdown := shutdown_connect(qmp + '.power', mut shutdown_log, deadline, boot)!
	defer { shutdown.close() or {} }
	if boot == 1 {
		wait_marker(mut child, log, deadline, 'NORMAL INIT SOFTWARE exclusive root registration READY')!
		time.sleep(time.second)
		record_shot(mut monitor, work, '01-registration')!
		type_text(mut monitor, 'alex')!; key(mut monitor, 'tab')!
		type_text(mut monitor, 'loginpass')!; key(mut monitor, 'tab')!
		type_text(mut monitor, 'loginpass')!; key(mut monitor, 'ret')!
	}
	wait_marker(mut child, log, deadline, 'NORMAL INIT SOFTWARE ordinary greeter uid=101 READY')!
	time.sleep(time.second)
	record_shot(mut monitor, work, if boot == 1 { '02-greeter' } else { '10-reboot-greeter' })!
	type_text(mut monitor, 'alex')!; key(mut monitor, 'tab')!
	type_text(mut monitor, 'loginpass')!; key(mut monitor, 'ret')!
	wait_marker(mut child, log, deadline, 'NORMAL INIT SOFTWARE authenticated ordinary compositor uid=1000 private-home-runtime PASS')!
	time.sleep(time.second)
	record_shot(mut monitor, work, if boot == 1 { '03-ordinary-desktop' } else { '11-reboot-desktop' })!
	click(mut monitor, 20, 750)!
	type_text(mut monitor, 'software')!
	record_shot(mut monitor, work, if boot == 1 { '04-start-software' } else { '12-start-software' })!
	key(mut monitor, 'ret')!
	time.sleep(3 * time.second)
	record_shot(mut monitor, work, if boot == 1 { '05-software' } else { '13-software-retained' })!
	click(mut monitor, 984, 57)! // Maximize the actual Software window.
	time.sleep(time.second)
	if boot == 1 {
		click(mut monitor, 970, 56)! // Refresh through the actual account approval.
		approve(mut monitor, work, 'refresh', false)!
		wait_marker(mut child, log, deadline, 'NORMAL INIT SOFTWARE signed catalog refreshed approvals=1 PASS')!
		wait_marker(mut child, log, deadline, 'NORMAL INIT SOFTWARE review=install unchanged-state approvals=1 PASS')!
		click(mut monitor, 140, 138)!
		click(mut monitor, 350, 562)!
		record_shot(mut monitor, work, 'install-review')!
		approve(mut monitor, work, 'install', true)!
		wait_marker(mut child, log, deadline, 'NORMAL INIT SOFTWARE installed signed=1.1.0 approvals=2 PASS')!
	} else {
		wait_marker(mut child, log, deadline, 'NORMAL INIT SOFTWARE review=remove unchanged-state approvals=2 PASS')!
		click(mut monitor, 140, 138)!
		click(mut monitor, 510, 562)!
		record_shot(mut monitor, work, 'uninstall-review')!
		approve(mut monitor, work, 'uninstall', true)!
		wait_marker(mut child, log, deadline, 'NORMAL INIT SOFTWARE uninstalled approvals=3 private=2 launcher-absent PASS')!
		wait_marker(mut child, log, deadline, 'NORMAL INIT SOFTWARE review=install unchanged-state approvals=3 PASS')!
		click(mut monitor, 140, 138)!
		click(mut monitor, 350, 562)!
		record_shot(mut monitor, work, 'reinstall-review')!
		approve(mut monitor, work, 'reinstall', true)!
		wait_marker(mut child, log, deadline, 'NORMAL INIT SOFTWARE reinstalled signed=1.1.0 approvals=4 private=2 PASS')!
	}
	time.sleep(time.second)
	click(mut monitor, 140, 138)!
	click(mut monitor, 930, 94)!
	point(mut monitor, 800, 500)!
	before := wait_label(mut child, mut monitor, log, deadline, work,
		if boot == 1 { '06-counter-zero' } else { '14-counter-retained-two' }, previous)!
	defer { unsafe { before.pixels.free() } }
	click(mut monitor, 250, 320)!
	if boot == 1 { click(mut monitor, 250, 320)! }
	point(mut monitor, 800, 500)!
	checkpoint := shot(mut monitor, work, if boot == 1 { '07-counter-two' } else { '15-counter-three' })!
	if region_changes(before, checkpoint, 50, 120, 300, 80) < 8 { return error('Counter value did not visibly change') }
	click(mut monitor, 930, 56)! // Counter's real Save and Close action.
	marker := if boot == 1 {
		'NORMAL INIT SOFTWARE BOOT 1 signed acquisition private=2 exact checkpoint ready for UI shutdown PASS'
	} else { 'NORMAL INIT SOFTWARE BOOT 2 exact retention uninstall reinstall private=3 ready for UI shutdown PASS' }
	wait_marker(mut child, log, deadline, marker)!
	click(mut monitor, 20, 750)!
	record_shot(mut monitor, work, if boot == 1 { '08-shutdown-menu' } else { '16-shutdown-menu' })!
	press_before_shutdown(mut monitor, 375, 700)!
	shutdown_event(mut shutdown, mut shutdown_log, deadline)!
	for child.is_alive() {
		if u64(time.sys_mono_now()) >= deadline { return error('guest did not power off after its QMP shutdown') }
		time.sleep(100 * time.millisecond)
	}
	child.wait()
	transcript := os.read_file(log)!
	if child.code != 0 || !transcript.contains(marker)
		|| ['NORMAL INIT SOFTWARE FAIL', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION', 'crashed with'].any(transcript.contains(it))
		|| transcript.contains('sysdisk: running from memory') || transcript.contains('sysdisk: updating the system on') {
		return error('production-init installed workflow did not finish cleanly')
	}
	return checkpoint
}

fn digest(path string) !string {
	mut hashes := map[string]string{}
	mut paths := map[string]string{}
	pin(mut hashes, mut paths, 'file', path)!
	return hashes['file']
}

fn inventory(directory string, prefix string, mut paths map[string]string) ! {
	for name in os.ls(directory)! {
		if name == '.git' { continue }
		path := directory + '/' + name
		if os.is_dir(path) && !os.is_link(path) { inventory(path, prefix + name + '/', mut paths)! }
		else if os.is_file(path) { paths[prefix + name] = path }
	}
}

fn produce(argv []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(argv))!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	os.write_file(log, output)!
	unsafe { output.free() }
	if child.code != 0 { return error('build failed: ' + log) }
}

fn build_session(host hwhost.Host, work string) !string {
	os.mkdir_all(work + '/session-build')!
	c := work + '/session-build/session.c'
	program := work + '/session-build/vinix-session'
	produce([host.v, '-new-compiler', '-enable-globals', '-path',
		'@vlib|@vmodules|' + host.root + '|' + host.root + '/tools/accounts', '-gc', 'none',
		'-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-os', 'linux', '-arch',
		if host.arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-o', c,
		host.root + '/tools/accounts/session.v'], work + '/session-build/v.log')!
	cc := '/opt/homebrew/bin/' + host.arch + '-linux-musl-gcc'
	produce([cc, '-static', '-O2', '-w', '-Wno-error=incompatible-pointer-types', '-Wno-error=int-conversion',
		'-std=gnu11', '-D_GNU_SOURCE', c, '-o', program, '-lm', '-lpthread'], work + '/session-build/c.log')!
	return program
}

fn build_init(host hwhost.Host, work string) !string {
	if host.arch == 'x86_64' { return host.root + '/build-support/init-amd64/desktop-init' }
	init := host.root + '/build-support/init-aarch64'
	os.mkdir_all(work + '/init-build')!
	produce(['sh', init + '/compile-init', 'desktop', work + '/init-build/init.c'], work + '/init-build/v.log')!
	clang := '/opt/homebrew/opt/llvm/bin/clang'
	produce([clang, '--target=aarch64-linux-none', '-nostdlib', '-ffreestanding', '-O2',
		'-fno-stack-protector', '-fno-builtin', '-ffunction-sections', '-fdata-sections', '-I', init,
		'-c', work + '/init-build/init.c', '-o', work + '/init-build/init.o'], work + '/init-build/c.log')!
	produce([clang, '--target=aarch64-linux-none', '-c', init + '/syscall_abi.S', '-o', work + '/init-build/abi.o'], work + '/init-build/abi.log')!
	program := work + '/init-build/init'
	produce(['/opt/homebrew/bin/ld.lld', '-m', 'aarch64elf', '--nostdlib', '-static', '--gc-sections',
		'-o', program, work + '/init-build/init.o', work + '/init-build/abi.o'], work + '/init-build/link.log')!
	return program
}

fn build_observer(host hwhost.Host, work string, cc string, sysroot string) !string {
	os.mkdir_all(work + '/observer-build')!
	c := work + '/observer-build/observer.c'
	program := work + '/observer-build/observer'
	produce([host.v, '-os', 'linux', '-arch', if host.arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-path', '@vlib|@vmodules|' + host.root, '-o', c, work + '/source/observer'], work + '/observer-build/v.log')!
	arguments := if host.arch == 'aarch64' {
		[cc, '--target=aarch64-linux-musl', '--sysroot=' + sysroot, '-static', '-O1', '-w',
			'-D_GNU_SOURCE', '-fno-stack-protector', '-L' + sysroot + '/lib', '-fuse-ld=lld',
			'-o', program, c, '-lm', '-lpthread']
	} else { [cc, '-static', '-O1', '-w', '-fpermissive', '-D_GNU_SOURCE', '-o', program, c, '-lm', '-lpthread'] }
	produce(arguments, work + '/observer-build/c.log')!
	return program
}

fn build_volume(host hwhost.Host, work string) !string {
	os.mkdir_all(work + '/volume-build')!
	c := work + '/volume-build/volume.c'
	program := work + '/volume-build/vinix-volume'
	headers := host.root + '/tools/volumes/volumecli'
	produce([host.root + '/build-support/compile-v-module', headers, c, '--arch', 'amd64'], work + '/volume-build/v.log')!
	mut file := os.open_append(c)!
	file.write_string('\n_Static_assert(sizeof(volumecli__Request)==32, "V request ABI");\n_Static_assert(sizeof(volumecli__Status)==128, "V status ABI");\n_Static_assert(sizeof(volumecli__Health)==1088, "V health ABI");\n_Static_assert(offsetof(volumecli__Health,data)==576, "V health data ABI");\n')!
	file.close()
	produce(['/opt/homebrew/bin/x86_64-linux-musl-gcc', '-static', '-std=c11', '-O2', '-Wall', '-Wextra',
		'-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-D_GNU_SOURCE',
		'-DVINIX_V_RUNTIME', '-I', headers, c, '-o', program], work + '/volume-build/c.log')!
	return program
}

fn generated_paths(work string, arch string) !map[string]string {
	mut paths := map[string]string{}
	for directory in ['source', 'session-build', 'init-build', 'observer-build', 'volume-build'] {
		if os.is_dir(work + '/' + directory) { normalproof.inventory(work + '/' + directory, directory + '/', mut paths)! }
	}
	for path in ['/sbin/init','/bin/busybox','/usr/bin/vinix-desktop','/usr/bin/vinix-package',
		'/usr/bin/vinix-sandbox','/usr/sbin/vinix-account','/usr/sbin/vinix-authd','/usr/sbin/vinix-session',
		'/usr/sbin/vinix-system','/usr/sbin/vinix-volume','/usr/libexec/vinix-version-check','/etc/vinix-packages/config.json',
		'/usr/share/vinix/actions/packages-change','/usr/share/vinix/actions/packages-launch','/usr/share/vinix/actions/power-off',
		'/usr/share/normal-init-software.json'] { paths['rootfs' + path] = work + '/rootfs' + path }
	paths['@link:rootfs/usr/bin/vinix-software'] = work + '/rootfs/usr/bin/vinix-software'
	paths['initramfs'] = work + '/initramfs.tar'
	normalproof.inventory(work + '/rootfs/usr/share/vinix-packages/repositories/native', 'repository/', mut paths)!
	if arch == 'x86_64' {
		for name in ['test.iso','image-commands.json','iso/iso-root/boot/limine.conf'] { paths[name] = work + '/' + name }
	} else { paths['boot.img'] = work + '/boot.img' }
	return paths
}

fn qualification_inputs(host hwhost.Host, input string, stage string, desktop string,
	kernel string, publisher string, observer_compiler string, sysroot string) !map[string]string {
	mut paths := normalproof.build_inputs(host.root, host.arch, host.v, observer_compiler, sysroot)!
	for name, path in normalproof.assembled(desktop, stage, host.arch, host.v)! { paths[name] = path }
	normalproof.inventory(input, 'image-root/', mut paths)!
	normalproof.inventory(publisher + '/workspace-1.1.0', 'publisher/workspace/', mut paths)!
	paths['publisher/image-config'] = publisher + '/image-config.json'
	paths['publisher/seed'] = publisher + '/seed'
	paths['runtime/kernel'] = kernel
	paths['runtime/qemu'] = host.qemu
	paths['runtime/firmware'] = host.firmware
	if host.firmware_vars != '' { paths['runtime/firmware-vars'] = host.firmware_vars }
	paths['runtime/busybox'] = hwhost.shared_path(host.root, if host.arch == 'aarch64' {
		'build-aarch64-userland/staging/bin/busybox' } else { 'build-amd64-userland/staging/bin/busybox' })
	if host.arch == 'x86_64' {
		for name, path in plainiso.inputs(host.root)! { paths['media/' + name] = path }
	} else {
		paths['runtime/volume'] = hwhost.shared_path(host.root, 'build-aarch64-userland/staging/usr/sbin/vinix-volume')
		paths['runtime/loader'] = hwhost.shared_path(host.root, 'boot-image/limine-bin/BOOTAA64.EFI')
	}
	return paths
}

fn check() ! {
	$if prod {} $else { return error('compile controller with -prod to freeze embedded inputs') }
	if digest(@FILE)! != sha256.hexhash($embed_file('check.v').to_string()) {
		return error('controller differs from embedded source')
	}
	if digest(os.dir(@FILE) + '/normalproof/admit.v')! != sha256.hexhash($embed_file('normalproof/admit.v').to_string()) {
		return error('proof module differs from embedded source')
	}
	mut options := map[string]string{}
	for argument in os.args[1..] {
		if !argument.starts_with('--') || !argument.contains('=') { return error('use --name=VALUE') }
		name := argument.all_before('=')
		if name !in ['--arch','--rootfs','--stage','--desktop','--kernel','--publisher','--out'] || name in options {
			return error('unknown or repeated option: ' + name)
		}
		options[name] = argument.all_after('=')
	}
	arch := options['--arch'] or { return error('--arch required') }
	if arch !in ['aarch64','x86_64'] { return error('unsupported architecture') }
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, arch, '')!
	work := required(options, '--out')!
	if os.exists(work) { return error('output directory must be new') }
	input := required(options, '--rootfs')!
	stage := required(options, '--stage')!
	desktop := required(options, '--desktop')!
	kernel := required(options, '--kernel')!
	publisher := required(options, '--publisher')!
	os.mkdir_all(work + '/source/observer')!
	observer_cc := if arch == 'aarch64' { os.getenv('CC_AARCH64') } else { os.getenv('CC_AMD64') }
	if arch == 'aarch64' && observer_cc == '' { return error('CC_AARCH64 must explicitly name the observer compiler') }
	observer_compiler := if observer_cc == '' { 'x86_64-linux-musl-gcc' } else { observer_cc }
	sysroot := if arch == 'aarch64' { os.getenv('VINIX_AARCH64_SYSROOT') } else { '' }
	if arch == 'aarch64' && sysroot == '' { return error('VINIX_AARCH64_SYSROOT must be explicit') }
	source_paths := qualification_inputs(host, input, stage, desktop, kernel, publisher, observer_compiler, sysroot)!
	source_hashes := normalproof.hashes(source_paths)!
	os.write_file(work + '/source-inputs.json', json2.encode(source_hashes))!
	os.write_file(work + '/source-paths.json', json2.encode(source_paths))!
	os.cp(@FILE, work + '/source/check.v')!
	os.mkdir_all(work + '/source/normalproof')!
	os.cp(root + '/tests/normal-init-software/normalproof/admit.v', work + '/source/normalproof/admit.v')!
	os.cp(root + '/tests/normal-init-software/observer/main.v', work + '/source/observer/main.v')!
	if digest(root + '/tests/normal-init-software/observer/main.v')! != sha256.hexhash($embed_file('observer/main.v').to_string()) {
		return error('observer differs from embedded source')
	}
	os.mkdir_all(work + '/rootfs')!
	invoke('cp', ['-Rp', input + '/.', work + '/rootfs'])!
	invoke('cp', ['-Rp', stage + '/root/.', work + '/rootfs'])!
	// The publisher's explicit fixture declaration binds this repository's key.
	// Production staging intentionally publishes an empty default configuration.
	os.cp(publisher + '/image-config.json', work + '/rootfs/etc/vinix-packages/config.json')!
	for name in os.ls(work + '/rootfs/etc')! {
		if name.starts_with('software-') { os.rm(work + '/rootfs/etc/' + name) or {} }
	}
	for path in ['/usr/share/vinix-packages/applications.json','/usr/libexec/vinix-version-check',
		'/usr/libexec/vinix-desktop-system','/usr/bin/vinix-desktop-gpu'] {
		os.rm(work + '/rootfs' + path) or {}
	}
	configuration := pkgcore.load_config(work + '/rootfs')!
	if configuration.architecture != arch || configuration.launch_user != 'alex' { return error('unexpected signed image configuration') }
	repository := work + '/rootfs/usr/share/vinix-packages/repositories/native'
	os.rmdir_all(repository)!
	invoke('cp', ['-Rp', publisher + '/workspace-1.1.0', work + '/publisher-workspace'])!
	pkgcore.publish_release(work + '/publisher-workspace', 'native', publisher + '/seed',
		u64(time.now().unix()), time.now().unix() + 86400, repository)!
	pkgcore.verify_index(configuration.repositories[0], os.read_file(repository + '/index.json')!,
		os.read_file(repository + '/index.sig')!, time.now().unix())!
	os.cp(desktop + '/vinix-desktop', work + '/rootfs/usr/bin/vinix-desktop')!
	os.chmod(work + '/rootfs/usr/bin/vinix-desktop', 0o755)!
	for directory in ['bin','sbin','usr/libexec','usr/share','root','proc','sys','dev','run','tmp'] {
		os.mkdir_all(work + '/rootfs/' + directory)!
	}
	busybox := hwhost.shared_path(root, if arch == 'aarch64' { 'build-aarch64-userland/staging/bin/busybox' }
		else { 'build-amd64-userland/staging/bin/busybox' })
	os.cp(busybox, work + '/rootfs/bin/busybox')!
	os.chmod(work + '/rootfs/bin/busybox', 0o755)!
	for applet in ['sh','mkdir','chmod','rm','ln','sleep','kill','mount','cat','sync','zsh'] {
		os.symlink('busybox', work + '/rootfs/bin/' + applet)!
	}
	session := build_session(host, work)!
	os.cp(session, work + '/rootfs/usr/sbin/vinix-session')!
	os.chmod(work + '/rootfs/usr/sbin/vinix-session', 0o755)!
	init := build_init(host, work)!
	os.cp(init, work + '/rootfs/sbin/init')!
	os.chmod(work + '/rootfs/sbin/init', 0o755)!
	if arch == 'aarch64' {
		os.cp(hwhost.shared_path(root, 'build-aarch64-userland/staging/usr/sbin/vinix-volume'), work + '/rootfs/usr/sbin/vinix-volume')!
	} else {
		os.cp(build_volume(host, work)!, work + '/rootfs/usr/sbin/vinix-volume')!
		os.chmod(work + '/rootfs/usr/sbin/vinix-volume', 0o755)!
	}
	observer := build_observer(host, work, observer_compiler, sysroot)!
	os.cp(observer, work + '/rootfs/usr/libexec/vinix-version-check')!
	os.chmod(work + '/rootfs/usr/libexec/vinix-version-check', 0o755)!
	os.write_file(work + '/rootfs/.vinix-image-id', 'vinix-normal-init-software-1\n')!
	mut proof := map[string]string{}
	for path in ['/sbin/init','/bin/busybox','/usr/bin/vinix-desktop','/usr/bin/vinix-package',
		'/usr/bin/vinix-sandbox','/usr/sbin/vinix-account','/usr/sbin/vinix-authd','/usr/sbin/vinix-session',
		'/usr/sbin/vinix-system','/usr/sbin/vinix-volume','/usr/libexec/vinix-version-check','/etc/vinix-packages/config.json',
		'/usr/share/vinix/actions/packages-change','/usr/share/vinix/actions/packages-launch','/usr/share/vinix/actions/power-off'] {
		proof[path] = digest(work + '/rootfs' + path)!
	}
	if os.readlink(work + '/rootfs/usr/bin/vinix-software')! != '/usr/bin/vinix-desktop' {
		return error('Software image entry is not the production compositor alias')
	}
	proof['@link:/usr/bin/vinix-software'] = '/usr/bin/vinix-desktop'
	os.write_file(work + '/rootfs/usr/share/normal-init-software.json', json2.encode(proof))!
	os.write_file(work + '/system.vjfs', '')!
	os.truncate(work + '/system.vjfs', u64(4096) << 20)!
	os.setenv('COPYFILE_DISABLE', '1', true)
	invoke('tar', ['--format=ustar', '-cf', work + '/initramfs.tar', '-C', work + '/rootfs', '.'])!
	media_host := if arch == 'x86_64' { hwhost.Host{...host, root: plainiso.prepare(root, work)!} } else { host }
	media := hwhost.boot_media(media_host, kernel, work + '/initramfs.tar', 'quiet vinix.disk=auto', work)!
	generated := generated_paths(work, arch)!
	generated_hashes := normalproof.hashes(generated)!
	os.write_file(work + '/generated-inputs.json', json2.encode(generated_hashes))!
	os.write_file(work + '/generated-paths.json', json2.encode(generated))!
	before_boot := qualification_inputs(host, input, stage, desktop, kernel, publisher, observer_compiler, sysroot)!
	if before_boot != source_paths { return error('build input inventory changed before boot') }
	normalproof.unchanged(source_hashes, before_boot)!
	qmp := '/tmp/vinix-normal-init-software-' + os.getpid().str() + '.qmp'
	mut arguments := if arch == 'aarch64' {
		['-machine','virt,gic-version=3','-accel','hvf','-cpu','host','-device','ramfb',
			'-device','virtio-keyboard-device','-device','virtio-tablet-device']
	} else { ['-machine','q35,smm=off','-accel','tcg','-cpu','max','-vga','std',
		'-device','qemu-xhci,id=gui-input','-device','usb-kbd,bus=gui-input.0','-device','usb-tablet,bus=gui-input.0'] }
	arguments << ['-m', if arch == 'aarch64' { '2048' } else { '1024' }, '-smp','2', ...media,
		'-display','none','-qmp','unix:' + qmp + ',server=on,wait=off',
		'-qmp','unix:' + qmp + '.power,server=on,wait=off','-no-reboot','-nic','none']
	arguments << if arch == 'aarch64' {
		['-drive','if=none,id=system,format=raw,cache=writeback,file=' + work + '/system.vjfs','-device','virtio-blk-device,drive=system']
	} else { ['-drive','if=ide,format=raw,cache=writeback,file=' + work + '/system.vjfs'] }
	os.write_file(work + '/qemu-argv.json', json2.encode([host.qemu, ...arguments]))!
	checkpoint := graphical_boot(host, arguments, qmp, work, 1, screenshotcore.Image{})!
	defer { unsafe { checkpoint.pixels.free() } }
	last := graphical_boot(host, arguments, qmp, work, 2, checkpoint)!
	unsafe { last.pixels.free() }
	after_paths := qualification_inputs(host, input, stage, desktop, kernel, publisher, observer_compiler, sysroot)!
	if after_paths != source_paths { return error('build input inventory changed during qualification') }
	normalproof.unchanged(source_hashes, after_paths)!
	completed_generated := generated_paths(work, arch)!
	if generated != completed_generated { return error('generated input inventory changed during qualification') }
	normalproof.unchanged(generated_hashes, completed_generated)!
	os.write_file(work + '/verified-source-inputs.json', json2.encode(source_hashes))!
	os.write_file(work + '/verified-generated-inputs.json', json2.encode(generated_hashes))!
	mut artifacts := map[string]string{}
	mut paths := map[string]string{}
	for name, path in {'kernel':kernel,'desktop':desktop + '/vinix-desktop','desktop-receipt':desktop + '/desktop-build.json',
		'stage-receipt':stage + '/stage-build.json','compiler':host.v,'qemu':host.qemu,'firmware':host.firmware,
		'controller':os.executable(),'busybox':busybox,'session':session,'init':init,'observer':observer,
		'volume':work + '/rootfs/usr/sbin/vinix-volume','initramfs':work + '/initramfs.tar','system-disk':work + '/system.vjfs',
		'declaration':work + '/rootfs/usr/share/normal-init-software.json','qemu-argv':work + '/qemu-argv.json',
		'source-inputs':work + '/source-inputs.json','source-paths':work + '/source-paths.json',
		'generated-inputs':work + '/generated-inputs.json','generated-paths':work + '/generated-paths.json',
		'verified-source-inputs':work + '/verified-source-inputs.json',
		'verified-generated-inputs':work + '/verified-generated-inputs.json'} {
		pin(mut artifacts, mut paths, name, path)!
	}
	for directory in ['source','session-build','init-build','observer-build','volume-build','rootfs/usr/share/vinix-packages/repositories/native'] {
		if !os.is_dir(work + '/' + directory) { continue }
		mut files := map[string]string{}
		inventory(work + '/' + directory, directory + '/', mut files)!
		for name, path in files { pin(mut artifacts, mut paths, name, path)! }
	}
	for path in os.walk_ext(work, '') {
		if os.dir(path) == work && (path.ends_with('.png') || path.ends_with('.log') || path.ends_with('.jsonl')) {
			pin(mut artifacts, mut paths, os.file_name(path), path)!
		}
	}
	if arch == 'x86_64' {
		for name, path in plainiso.inputs(root)! { pin(mut artifacts, mut paths, name, path)! }
		for name in ['test.iso','image-commands.json','iso/iso-root/boot/limine.conf'] { pin(mut artifacts, mut paths, name, work + '/' + name)! }
	} else { pin(mut artifacts, mut paths, 'loader', hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI'))! }
	os.write_file(work + '/qualification.json', json2.encode(GraphicalReceipt{architecture:arch,
		platform:'production-init-installed-ordinary-software-two-boots',artifacts:artifacts,artifact_paths:paths}))!
	println('PASS ' + arch + ' production init installed graphical registration login signed Software workflow: ' + work)
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err.msg()); exit(1) }; return }
	check() or { eprintln(err.msg()); exit(1) }
}

