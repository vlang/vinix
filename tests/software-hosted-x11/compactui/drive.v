// SPDX-License-Identifier: GPL-2.0-or-later
// Real QEMU input for the frozen current compact Software compositor.
module compactui

import json2
import optionsfixture
import os
import qmpclient
import screenshotcore
import stbi
import time

pub struct Frame {
pub:
	name string
	width int
	height int
}

pub fn frames() []Frame {
	return [
		Frame{'06-compact-catalog-320', 320, 240},
		Frame{'07-compact-catalog-180', 180, 220},
		Frame{'08-compact-arguments-180', 180, 220},
		Frame{'09-compact-arguments-320', 320, 240},
		Frame{'10-compact-add-file', 320, 240},
		Frame{'11-compact-files', 320, 240},
		Frame{'12-compact-folder', 320, 240},
		Frame{'13-compact-run', 320, 240},
	]
}

fn need(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn pixel(image screenshotcore.Image, x int, y int) u32 {
	index := (y * image.width + x) * image.channels
	return (u32(image.pixels[index]) << 16) | (u32(image.pixels[index + 1]) << 8)
		| u32(image.pixels[index + 2])
}

// The pinned flat chrome has a22px title and zero frame inset. The restored
// Software frame starts at(120,46); its body therefore starts at(120,68).
// The empty top/bottom margins identify the body edges independently of text.
fn geometry(image screenshotcore.Image, width int, height int) ! {
	need(image.width == 1024 && image.height == 768 && image.channels == 3
		&& image.pixels.len == 1024 * 768 * 3, 'compact proof framebuffer size differs')!
	need(width in [180, 320] && height == if width == 180 { 220 } else { 240 },
		'compact proof body geometry is unsupported')!
	background := u32(0xfbfcfe)
	for x in 120 .. 120 + width {
		need(pixel(image, x, 70) == background, 'compact body top margin differs')!
	}
	need(pixel(image, 119, 70) != background && pixel(image, 120 + width, 70) != background,
		'compact body horizontal extent differs')!
	need(pixel(image, 120 + width / 2, 68 + height - 1) == background
		&& pixel(image, 120 + width / 2, 68 + height) != background,
		'compact body vertical extent differs')!
}

pub fn validate_frames(work string) ! {
	for frame in frames() {
		geometry(screenshotcore.read(work + '/' + frame.name + '.png')!, frame.width, frame.height)!
	}
}

fn point(mut monitor qmpclient.Monitor, x int, y int) ! {
	monitor.command('input-send-event', {'events': json2.Any([
		json2.Any({'type': json2.Any('abs'), 'data': json2.Any({'axis': json2.Any('x'),
			'value': json2.Any(x * 32767 / 1024)})}),
		json2.Any({'type': json2.Any('abs'), 'data': json2.Any({'axis': json2.Any('y'),
			'value': json2.Any(y * 32767 / 768)})}),
	])})!
	time.sleep(200 * time.millisecond)
}

fn button(mut monitor qmpclient.Monitor, down bool) ! {
	monitor.command('input-send-event', {'events': json2.Any([json2.Any({
		'type': json2.Any('btn'), 'data': json2.Any({'button': json2.Any('left'), 'down': json2.Any(down)})
	})])})!
	time.sleep(100 * time.millisecond)
}

fn click(mut monitor qmpclient.Monitor, x int, y int) ! {
	point(mut monitor, x, y)!
	button(mut monitor, true)!
	button(mut monitor, false)!
	time.sleep(500 * time.millisecond)
}

fn key(mut monitor qmpclient.Monitor, code string, down bool) ! {
	monitor.command('input-send-event', {'events': json2.Any([json2.Any({
		'type': json2.Any('key'), 'data': json2.Any({'down': json2.Any(down),
			'key': json2.Any({'type': json2.Any('qcode'), 'data': json2.Any(code)})})
	})])})!
	time.sleep(60 * time.millisecond)
}

fn resize(mut monitor qmpclient.Monitor, from_x int, from_y int, to_x int, to_y int) ! {
	point(mut monitor, from_x, from_y)!
	button(mut monitor, true)!
	point(mut monitor, to_x, to_y)!
	button(mut monitor, false)!
	time.sleep(500 * time.millisecond)
}

fn shot(mut monitor qmpclient.Monitor, work string, name string, width int, height int) ! {
	point(mut monitor, 800, 650)!
	path := work + '/' + name + '.ppm'
	monitor.command('screendump', {'filename': json2.Any(path)})!
	image := screenshotcore.read(path)!
	geometry(image, width, height)!
	stbi.stbi_write_png(work + '/' + name + '.png', image.width, image.height,
		image.channels, image.pixels.data, image.width * image.channels)!
	os.rm(path)!
}

// Entry: Software maximized, installed fixture selected, no launch draft.
// Exit: real signed child was requested using the compact Run control.
pub fn drive(mut monitor qmpclient.Monitor, work string) ! {
	// Restore the actual900x690 window before dragging its lower-right grip.
	click(mut monitor, 984, 10)!
	resize(mut monitor, 1018, 734, 438, 306)!
	shot(mut monitor, work, '06-compact-catalog-320', 320, 240)!
	resize(mut monitor, 438, 306, 298, 286)!
	shot(mut monitor, work, '07-compact-catalog-180', 180, 220)!
	// At180px the catalog entry is on its own row, below Browse catalog.
	click(mut monitor, 210, 204)!
	click(mut monitor, 200, 128)!
	key(mut monitor, 'ctrl', true)!
	key(mut monitor, 'shift', true)!
	key(mut monitor, 'v', true)!
	key(mut monitor, 'v', false)!
	key(mut monitor, 'shift', false)!
	key(mut monitor, 'ctrl', false)!
	time.sleep(2 * time.second)
	shot(mut monitor, work, '08-compact-arguments-180', 180, 220)!
	// The focused literal draft must survive enlarging the real window.
	resize(mut monitor, 298, 286, 438, 306)!
	shot(mut monitor, work, '09-compact-arguments-320', 320, 240)!
	click(mut monitor, 380, 286)!
	click(mut monitor, 200, 128)!
	for byte in optionsfixture.document {
		code := match byte { `/` { 'slash' } `.` { 'dot' } else { byte.ascii_str() } }
		key(mut monitor, code, true)!
		key(mut monitor, code, false)!
	}
	click(mut monitor, 280, 166)!
	shot(mut monitor, work, '10-compact-add-file', 320, 240)!
	click(mut monitor, 380, 286)!
	shot(mut monitor, work, '11-compact-files', 320, 240)!
	click(mut monitor, 380, 286)!
	// Exercise both choices and restore private cwd for the signed child proof.
	click(mut monitor, 280, 128)!
	click(mut monitor, 280, 128)!
	shot(mut monitor, work, '12-compact-folder', 320, 240)!
	click(mut monitor, 380, 286)!
	shot(mut monitor, work, '13-compact-run', 320, 240)!
	shot(mut monitor, work, '05-launch-options', 320, 240)!
	click(mut monitor, 280, 128)!
}

// Invoke after independently checking real compact child paint. Remaining
// historical pointer/close checks then keep their full-window coordinates.
pub fn maximize_running(mut monitor qmpclient.Monitor) ! {
	click(mut monitor, 404, 57)!
}

pub fn source() string { return $embed_file('drive.v').to_string() }
