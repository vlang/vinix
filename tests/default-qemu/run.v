// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the PS/2 devices on the plain QEMU command line through their
// userspace ABI. The ISO contains guest/core.v as /sbin/init.
import os
import time
import json2
import screenshotcore

#include <stdlib.h>

fn C.mkdtemp(&char) &char

struct Test {
	qmp_tool string
	socket   string
	log      string
mut:
	offset int
}

fn command(argv []string) ! {
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio()
	child.run()
	child.wait()
	if child.code != 0 {
		return error('${argv[0]} failed: ${child.stdout_slurp()} ${child.stderr_slurp()}')
	}
}

fn (t &Test) qmp(request string) ! {
	command([t.qmp_tool, 'qmp', t.socket, request])!
}

fn (mut t Test) expect(marker string, seconds int) ! {
	deadline := time.sys_mono_now() + i64(seconds) * time.second
	for time.sys_mono_now() < deadline {
		log := os.read_file(t.log) or { '' }
		if log.len >= t.offset {
			fresh := log[t.offset..]
			if fresh.contains('INPUT FAIL') { return error(fresh) }
			if index := fresh.index(marker) {
				t.offset += index + marker.len
				return
			}
		}
		time.sleep(10 * time.millisecond)
	}
	return error('missing "${marker}"; see ${t.log}')
}

fn (t &Test) move(x int, y int) ! {
	t.qmp('{"execute":"input-send-event","arguments":{"events":[{"type":"rel","data":{"axis":"x","value":${x}}},{"type":"rel","data":{"axis":"y","value":${y}}}]}}')!
}

fn (t &Test) button(name string, down bool) ! {
	t.qmp('{"execute":"input-send-event","arguments":{"events":[{"type":"btn","data":{"button":"${name}","down":${down}}}]}}')!
}

fn (t &Test) screenshot(name string) !screenshotcore.Image {
	path := os.dir(t.log) + '/' + name + '.ppm'
	t.qmp('{"execute":"screendump","arguments":{"filename":${json2.encode(path)}}}')!
	return screenshotcore.read(path)!
}

fn changed_region(a screenshotcore.Image, b screenshotcore.Image, x int, y int, w int, h int) int {
	mut changed := 0
	for row in y .. y + h {
		for col in x .. x + w {
			i := (row * a.width + col) * 3
			if a.pixels[i..i + 3] != b.pixels[i..i + 3] { changed++ }
		}
	}
	return changed
}

fn (mut t Test) desktop() ! {
	t.expect('Vinix: starting the desktop', 180)!
	deadline := time.sys_mono_now() + 120 * time.second
	for {
		time.sleep(time.second)
		shot := t.screenshot('boot')!
		_, status := screenshotcore.verdict(shot)
		if status == 0 { break }
		if time.sys_mono_now() > deadline { return error('desktop never rendered') }
	}
	time.sleep(2 * time.second)
	before := t.screenshot('before')!
	if before.width != 1024 || before.height != 768 {
		return error('expected the ISO default 1024x768 framebuffer')
	}
	t.move(-150, -120)!
	time.sleep(time.second)
	moved := t.screenshot('moved')!
	// Check both cursor locations, excluding the blinking text caret and
	// clock: any screen-wide difference would allow a dead mouse to pass.
	if changed_region(before, moved, 508, 380, 32, 32) < 40
		|| changed_region(before, moved, 358, 260, 32, 32) < 40 {
		return error('cursor did not leave its initial position and appear at the requested position')
	}
	t.move(150, 120)!
	time.sleep(time.second)
	returned := t.screenshot('returned')!
	if changed_region(before, returned, 508, 380, 32, 32) != 0
		|| changed_region(before, returned, 358, 260, 32, 32) != 0 {
		return error('cursor did not return to its initial position')
	}
	for key in ['v', 'i', 'n', 'i', 'x'] {
		t.qmp('{"execute":"human-monitor-command","arguments":{"command-line":"sendkey ${key}"}}')!
		time.sleep(150 * time.millisecond)
	}
	time.sleep(time.second)
	typed := t.screenshot('typed')!
	if changed_region(returned, typed, 324, 300, 150, 35) < 100 {
		return error('keyboard did not type into the first-run name field')
	}
	println('PASS: plain QEMU desktop, visible cursor, relative movement and keyboard (2 GiB)')
}

fn (mut t Test) exercise() ! {
	t.expect('POINTER 511 383 1023 767 0 0 0 0', 90)!
	// Optional comparison with a settled device, to distinguish startup
	// corruption from later protocol errors in an old kernel.
	delay := os.getenv('VINIX_INPUT_START_DELAY_MS').int()
	if delay > 0 { time.sleep(delay * time.millisecond) }
	// The first motion must work immediately after input is initialised.
	t.move(-200, 120)!
	t.expect('POINTER 311 503 1023 767 0 0 0 0', 10)!
	t.move(200, -120)!
	t.expect('POINTER 511 383 1023 767 0 0 0 0', 10)!
	println('PASS: initial position and movement in both directions')
	for name, mask in {
		'left':   1
		'right':  2
		'middle': 4
		'side':   8
		'extra':  16
	} {
		t.button(name, true)!
		t.expect('POINTER 511 383 1023 767 ${mask} ${mask} 0 0', 10)!
		t.button(name, false)!
		t.expect('POINTER 511 383 1023 767 0 0 ${mask} 0', 10)!
	}
	println('PASS: button press and release edges')
	// Alternate keyboard and mouse traffic through the shared i8042 buffer.
	for _ in 0 .. 20 {
		t.qmp('{"execute":"human-monitor-command","arguments":{"command-line":"sendkey a"}}')!
		t.move(1, 1)!
		t.expect('POINTER 512 384 1023 767 0 0 0 0', 10)!
		t.qmp('{"execute":"human-monitor-command","arguments":{"command-line":"sendkey ret"}}')!
		t.expect('KEY 97', 10)!
		t.expect('KEY 10', 10)!
		t.move(-1, -1)!
		t.expect('POINTER 511 383 1023 767 0 0 0 0', 10)!
	}
	println('PASS: interleaved keyboard and pointer input')
	for name, delta in {
		'wheel-up':   1
		'wheel-down': -1
	} {
		t.button(name, true)!
		t.button(name, false)!
		t.expect('POINTER 511 383 1023 767 0 0 0 ${delta}', 10)!
	}
	// A later motion must not replay the consumed scroll or button edges.
	t.move(5, 0)!
	t.expect('POINTER 516 383 1023 767 0 0 0 0', 10)!
	println('PASS: wheel directions and consumed deltas')
}

fn run() ! {
	mut options := os.args[1..].clone()
	desktop := options.len > 0 && options[0] == '--desktop'
	if desktop { options = options[1..] }
	state_parent := options.len > 0 && options[0] == '--state-parent'
	if state_parent { options = options[1..] }
	if options.len < 3 {
		eprintln('Usage: v run tests/default-qemu/run.v [--desktop] [--state-parent] ISO STATE-DIR QMP-CLIENT [QEMU options...]')
		exit(2)
	}
	iso := os.abs_path(options[0])
	mut state := os.abs_path(options[1])
	if state_parent {
		os.mkdir_all(state)!
		mut template := (state + '/run-XXXXXX\x00').bytes()
		if isnil(C.mkdtemp(&char(template.data))) {
			return error('cannot create state directory under ${state}: ${os.get_error_msg(int(C.errno))}')
		}
		state = template[..template.len - 1].bytestr()
	} else {
		if os.exists(state) { return error('state directory must be new: ${state}') }
		os.mkdir_all(state)!
	}
	println('Default QEMU evidence: ${state}')
	mut t := Test{
		qmp_tool: os.abs_path(options[2])
		socket:   state + '/qmp.sock'
		log:      state + '/serial.log'
	}
	configured := os.getenv('VINIX_QEMU_X86_64')
	qemu := os.find_abs_path_of_executable(if configured == '' {
		'qemu-system-x86_64'
	} else {
		configured
	})!
	mut machine := os.new_process(qemu)
	defer {
		machine.signal_kill()
		machine.wait()
		machine.close()
	}
	mut args := ['-m', '2048', '-cdrom', iso, '-display', 'none', '-no-reboot', '-serial',
		'file:' + t.log, '-qmp', 'unix:' + t.socket + ',server=on,wait=off']
	args << options[3..]
	os.write_file(state + '/command.txt', qemu + '\n' + args.join('\n') + '\n')!
	machine.set_args(args)
	machine.run()
	if desktop { t.desktop()! } else { t.exercise()! }
	println('PASS: default QEMU input (2 GiB); evidence: ${state}')
}

fn main() {
	run() or {
		eprintln('FAIL: ${err}')
		exit(1)
	}
}
