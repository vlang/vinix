// SPDX-License-Identifier: GPL-2.0-or-later
module emulatorhost

import fixturehost
import guesthost
import hosttest
import json2
import os
import policyhost
import time

pub struct Rect {
pub:
	x int
	y int
	width int
	height int
}
pub fn game_rect(kind string) Rect {
	return match kind { 'n64' { Rect{261, 94, 517, 387} } 'ps1' { Rect{167, 94, 706, 529} } else { Rect{176, 94, 688, 516} } }
}
fn byte_space(ch u8) bool { return ch in [u8(9), 10, 11, 12, 13, 32] }
fn ppm_space(data []u8, start int) !int {
	mut position := start
	for position < data.len && byte_space(data[position]) { position++ }
	if position == start { return error('unexpected QEMU screenshot header') }
	return position
}
fn ppm_number(data []u8, start int) !(int, int) {
	mut position := start
	mut value := 0
	for position < data.len && data[position].is_digit() {
		value = if value > 2048 { 2049 } else { value * 10 + int(data[position] - `0`) }
		position++
	}
	if position == start { return error('unexpected QEMU screenshot header') }
	return value, position
}
pub fn game_pixels(data []u8, kind string) ![]u8 {
	if data.len < 3 || data[..2] != [u8(`P`), `6`] { return error('unexpected QEMU screenshot header') }
	width, after_width := ppm_number(data, ppm_space(data, 2)!)!
	height, after_height := ppm_number(data, ppm_space(data, after_width)!)!
	mut offset := ppm_space(data, after_height)!
	if width != 2048 || height != 1536 || offset + 3 >= data.len || data[offset..offset + 3] != '255'.bytes()
		|| !byte_space(data[offset + 3]) { return error('unexpected QEMU screenshot header') }
	offset += 4
	if data.len - offset != width * height * 3 { return error('short QEMU screenshot') }
	rect := game_rect(kind)
	mut result := []u8{cap: rect.width * rect.height * 3}
	for row in 0 .. rect.height {
		start := offset + ((rect.y + row) * width + rect.x) * 3
		result << data[start..start + rect.width * 3]
	}
	return result
}
pub fn changed(left []u8, right []u8) int {
	mut count := 0
	for index := 0; index < left.len; index += 3 {
		end := if index + 3 < left.len { index + 3 } else { left.len }
		rstart := if index < right.len { index } else { right.len }
		rend := if index + 3 < right.len { index + 3 } else { right.len }
		if left[index..end] != right[rstart..rend] { count++ }
	}
	return count
}

// The native launcher supplies the same rootfs, init overlay, 64 MiB physical
// home, input devices and firmware directly to QEMU. Its source/package server
// is unnecessary for these isolated roots, and cannot require Python.
pub fn prepare_desktop(kind string, desktop string, build string, work string, qmp_path string) !guesthost.Launch {
	rootfs := work + '/rootfs'
	for name in ['run', 'root', 'sbin', 'usr/bin', 'usr/share/vinix/icons', 'dev', 'tmp', 'proc', 'sys'] { mkdir(rootfs + '/' + name)! }
	hosttest.module_copy_file_preserving_stat(desktop, rootfs + '/usr/bin/vinix-desktop')!
	stage_tree(build + '/staging/usr', rootfs + '/usr')!
	app := match kind { 'n64' { 'Nintendo 64' } 'ps2' { 'PlayStation 2' } else { 'PlayStation' } }
	sysroot := sdk(kind)
	run([...flags(sysroot), '-DIOS_TEST_APP="' + app + '"', guesthost.root() + '/tests/ios/desktop-init.c',
		'-L' + sysroot + '/lib', '-fuse-ld=lld', '-o', work + '/init'])!
	archive := guesthost.archive_tree(rootfs, work + '/rootfs.tar')!
	mut previous := map[string]?string{}
	for key, value in {'VINIX_QEMU_EXTRA': '', 'VINIX_QEMU_NETWORK': '0', 'VINIX_OVMF_CODE': guesthost.root() + '/boot-image/edk2-aarch64-code-2048x1536.fd'} {
		previous[key] = os.getenv_opt(key)
		os.setenv(key, value, true)
	}
	defer { for key, value in previous { if text := value { os.setenv(key, text, true) } else { os.unsetenv(key) } } }
	configured := guesthost.serial_arm_launch(work + '/init', archive, work,
		hosttest.module_resolve(os.getenv_opt('VINIX_KERNEL_DIR') or { guesthost.root() + '/kernel' })!, guesthost.root(), 2048, '')!
	config := work + '/limine.conf'
	mut config_lines := os.read_file(config)!.split_into_lines()
	for index, line in config_lines { if line.trim_space().starts_with('resolution:') { config_lines[index] = '    resolution: 2048x1536x32' } }
	os.write_file(config, config_lines.join('\n') + '\n')!
	run(['xorriso', '-indev', work + '/test.iso', '-outdev', work + '/desktop.iso', '-map', config, '/boot/limine.conf', '-boot_image', 'any', 'replay'])!
	os.mv(work + '/desktop.iso', work + '/test.iso')!
	mut command := configured.command.clone()
	command[command.index('-qmp') + 1] = 'unix:' + qmp_path + ',server=on,wait=off'
	return guesthost.Launch{command, configured.env}
}

struct Desktop {
	kind string
	build string
	log string
	deadline u64
mut:
	child fixturehost.LoggedChild
	qmp Qmp
}
fn (mut d Desktop) healthy() !string {
	policyhost.command_checkpoint()!
	transcript := os.read_bytes(d.log)!.bytestr()
	if ['FAIL:', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION'].any(transcript.contains(it)) || d.child.poll()! {
		return error('desktop failed; see ' + d.log)
	}
	if time.sys_mono_now() >= d.deadline { return error('desktop test timed out; see ' + d.log) }
	return transcript
}
fn (mut d Desktop) capture(name string) ![]u8 {
	d.healthy()!
	path := d.build + '/' + name
	d.qmp.call('screendump', {'filename': json2.Any(path)})!
	return game_pixels(os.read_bytes(path)!, d.kind) or { return error(err.msg() + ': ' + path) }
}
fn (d &Desktop) need(condition bool, message string) ! { if !condition { return error(message + '; see ' + d.log) } }

pub fn desktop_command(kind string, args []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	desktop_checked(kind, args) or { return report(err) }
	return 0
}
fn desktop_checked(kind string, args []string) ! {
	options := parse(args, [hosttest.Option{ name: '--desktop', value: true }, hosttest.Option{ name: '--timeout', value: true }],
		'Usage: ' + kind + '/desktop [--desktop ELF] [--timeout SECONDS]')!
	seconds := options.integer('--timeout', if kind == 'ps1' { 150 } else { 300 }) or { return error_with_code('invalid integer for --timeout', 2) }
	desktop := options.value('--desktop', guesthost.root() + '/build/vinix-desktop')
	build := build_dir(kind)!
	for path in [desktop, build + '/staging/usr/bin/vinix-' + kind, build + '/staging/usr/share/games/' + kind + '/' + demo_name(kind)] {
		if !os.is_file(path) { return error_with_code('missing desktop test input: ' + path, 2) }
	}
	if seconds <= 0 { return error_with_code('--timeout must be positive', 2) }
	qmp_path := '/tmp/vinix-' + kind + '-desktop-' + os.getpid().str() + '.qmp'
	work := hosttest.work_dir('', 'vinix-' + kind + '-desktop-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) }; os.rm(qmp_path) or {} }
	configured := prepare_desktop(kind, desktop, build, work, qmp_path)!
	mut child := fixturehost.spawn_logged(configured.command, configured.env, policyhost.caller_arch(), '', build + '/desktop.log')!
	defer { child.close() }
	desktop_scenario(kind, build, build + '/desktop.log', qmp_path, seconds, mut child)!
}

// The scenario uses the production child/log/QMP interfaces; controlled
// processes can qualify the complete orchestration without a guest emulator.
pub fn desktop_scenario(kind string, build string, log string, qmp_path string, seconds int, mut child fixturehost.LoggedChild) ! {
	mut d := Desktop{kind: kind, build: build, log: log, deadline: time.sys_mono_now() + u64(seconds) * u64(time.second), child: child}
	defer { d.qmp.close(); child = d.child }
	for {
		transcript := d.healthy()!
		if transcript.contains('vinix-desktop: ready') && transcript.contains(label(kind) + ': loaded') { break }
		pause(0.2)!
	}
	d.qmp = qmp_connect(qmp_path)!
	say(label(kind) + ' desktop: native emulator loaded in the compositor')
	gameplay(mut d)!
}
fn gameplay(mut d Desktop) ! {
	kind := d.kind
	prefix := label(kind) + ' desktop'
	pause(if kind == 'ps1' { 12 } else { 2 })!
	title := d.capture('desktop-title.ppm')!
	if kind == 'ps1' { d.qmp.click(667, 707)!; d.qmp.click(193, 745)! } else if kind == 'ps2' { d.qmp.click(558, 700)! } else { d.qmp.click(520, 581)! }
	pause(if kind == 'ps1' { 7 } else { 2 })!
	playing := d.capture('desktop-gameplay.ppm')!
	d.need(changed(title, playing) >= 1000, 'desktop pointer input did not start the game')!
	pause(2)!
	animated := d.capture('desktop-animated.ppm')!
	animation := changed(playing, animated)
	d.need(animation >= 16, 'desktop game did not animate')!
	say(prefix + ': pointer input started gameplay; ' + animation.str() + ' pixels animate')
	if kind != 'ps1' {
		d.qmp.hold(if kind == 'ps2' { 264 } else { 441 }, if kind == 'ps2' { 708 } else { 606 }, 0.8)!
		moved := d.capture('desktop-controller.ppm')!
		rect := game_rect(kind)
		start := rounded(f64(rect.height) * 0.835) * rect.width * 3
		end := rounded(f64(rect.height) * 0.905) * rect.width * 3
		movement := changed(animated[start..end], moved[start..end])
		d.need(movement >= 500, 'desktop controller did not move the emulated paddle')!
		say(prefix + ': pointer hold moves the ' + label(kind) + ' paddle; ' + movement.str() + ' court pixels changed')
		if kind == 'n64' {
			d.qmp.drag(520, 663, 380, 663, 0.8)!
			analog := d.capture('desktop-analog.ppm')!
			movement_ := changed(moved[start..end], analog[start..end])
			d.need(movement_ >= 500, 'desktop stick drag did not move the emulated paddle')!
			say(prefix + ': analog drag moves the paddle outside the stick well; ' + movement_.str() + ' court pixels changed')
		}
	}
	x := if kind == 'ps1' { 304 } else { 820 }
	y := if kind == 'ps1' { 669 } else if kind == 'ps2' { 632 } else { 504 }
	d.qmp.click(x, y)!
	pause(0.7)!
	paused := d.capture('desktop-paused.ppm')!
	pause(2)!
	still := d.capture('desktop-paused-later.ppm')!
	d.need(changed(paused, still) == 0, 'desktop pause did not freeze game pixels')!
	say(prefix + ': pause freezes game pixels')
	d.qmp.click(x, y)!
	pause(2)!
	if kind != 'ps1' { d.qmp.move(130, 350)!; pause(0.2)!; d.qmp.move(1940, 1400)!; pause(0.2)! }
	resumed := d.capture('desktop-gameplay.ppm')!
	d.need(changed(paused, resumed) >= 16, 'desktop resume did not animate')!
	d.qmp.click(903, 77)!
	close_deadline := time.sys_mono_now() + u64(10 * time.second)
	for {
		policyhost.command_checkpoint()!
		if os.read_bytes(d.log)!.bytestr().contains(label(kind) + ': clean shutdown') { break }
		d.need(time.sys_mono_now() < close_deadline && time.sys_mono_now() < d.deadline, 'desktop close did not shut down emulator')!
		pause(0.2)!
	}
	say(prefix + ' PASS: real pointer input starts ' + if kind == 'ps1' { 'Tetrade' } else { 'and plays PADDLE' } + '; ' + animation.str() + ' pixels animate; pause/resume and close work')
	say('Screenshot: ' + d.build + '/desktop-gameplay.ppm')
	d.qmp.call('quit', {})!
	d.child.wait_for(10, policyhost.command_interrupted)!
}
