// SPDX-License-Identifier: GPL-2.0-or-later
// Check the real app protocol, USB interactions and repeated window closure.
// Semantic text/results are also reviewed in the preserved screenshots.
module main

import os

fn pixel(data []u8, x int, y int) u32 {
	at := 'P6\n800 600\n255\n'.len + (y * 800 + x) * 3
	return u32(data[at]) << 16 | u32(data[at + 1]) << 8 | data[at + 2]
}

fn screen(path string) ![]u8 {
	data := os.read_bytes(path)!
	header := 'P6\n800 600\n255\n'
	if data.len != header.len + 800 * 600 * 3 || data[..header.len].bytestr() != header {
		return error('Invalid 800x600 screenshot: ' + path)
	}
	if pixel(data, 725, 20) == 0xff0000 && pixel(data, 749, 20) == 0x00ff00 && pixel(data, 773, 20) == 0x0000ff {
		return error('Kernel console replaced the desktop: ' + path)
	}
	return data
}

fn changed(a []u8, b []u8, x int, y int, w int, h int) int {
	mut count := 0
	for yy in y .. y + h {
		for xx in x .. x + w { if pixel(a, xx, yy) != pixel(b, xx, yy) { count++ } }
	}
	return count
}

fn check(directory string) ! {
	log := os.read_file(directory + '/program.log')!
	marker := 'vinix-desktop: GPU init: first canvas presented'
	if !log.contains(marker) { return error('Compositor did not start') }
	for bad in ['VINIX-PPC: PANIC', 'init exited', 'user fault', 'cannot start ', 'transport failure'] {
		if log.contains(bad) { return error('Unexpected application failure: ' + bad) }
	}
	after := log.all_after(marker)
	if after.contains('mapping framebuffer memory') || after.contains('calling presenter creation') {
		return error('Compositor lost framebuffer ownership while launching apps')
	}
	for app, title in {'files': 'Files', 'settings': 'Settings', 'editor': 'Text Editor', 'calculator': 'Calculator', 'terminal': 'Terminal'} {
		expected := if app == 'calculator' { 9 } else { 1 }
		if log.count('vinix-desktop: opened ' + title) != expected
			|| log.count('/usr/bin/vinix-' + app + '\r\n') != expected {
			return error('Missing or repeated process launch: ' + title)
		}
		before := screen(directory + '/apps-' + app + '.ppm')!
		if app in ['editor', 'calculator', 'terminal'] {
			typed := screen(directory + '/apps-' + app + '-typed.ppm')!
			rect := match app {
				'editor' { [110, 225, 200, 40] }
				'calculator' { [280, 150, 230, 42] }
				else { [248, 220, 500, 180] }
			}
			if changed(before, typed, rect[0], rect[1], rect[2], rect[3]) < 60 {
				return error('No keyboard response inside ' + title)
			}
		}
	}
	if !log.contains(' /bin/sh\r\n') { return error('Terminal did not execute the native shell') }
	for cycle in 0 .. 8 {
		opened := screen(directory + '/apps-reopen-${cycle}.ppm')!
		closed := screen(directory + '/apps-closed-${cycle}.ppm')!
		if changed(opened, closed, 130 + (cycle % 6) * 26, 100, 300, 400) < 50000 {
			return error('Calculator close did not remove its window in cycle ${cycle}')
		}
	}
	println('PASS apps: five real app launches, three keyboard responses, native shell, eight close/reopen cycles, stable framebuffer ownership')
}

fn main() {
	if os.args.len != 2 { eprintln('Usage: v run tests/powerpc/check-apps.v CAPTURE_DIRECTORY'); exit(2) }
	check(os.args[1]) or { eprintln(err); exit(1) }
}
