// SPDX-License-Identifier: GPL-2.0-or-later
module guestvalidation

import cachecli
import os
import time

fn env(name string, fallback string) string { return os.getenv_opt(name) or { fallback } }

fn mkdir(name string) ! {
	if os.is_dir(name) { return }
	parent := name.all_before_last('/')
	if parent != name && parent != '' { mkdir(parent)! }
	os.mkdir(name)!
}

fn remove(name string) ! {
	if os.is_link(name) {
		os.rm(name)!
		return
	}
	if os.is_dir(name) {
		for entry in os.ls(name)! { remove(name + '/' + entry)! }
		os.rmdir(name)!
	} else if os.exists(name) {
		os.rm(name)!
	}
}

fn files(directory string) ![]string {
	mut result := []string{}
	if !os.is_dir(directory) { return result }
	for name in os.ls(directory)! {
		value := directory + '/' + name
		result << value
		if os.is_dir(value) && !os.is_link(value) { result << files(value)! }
	}
	return result
}

fn guest_pause(seconds f64) ! {
	until := time.sys_mono_now() + u64(seconds * f64(time.second))
	for time.sys_mono_now() < until {
		cachecli.checkpoint()!
		now := time.sys_mono_now()
		if now >= until { break }
		time.sleep(time.Duration(if until - now > 10 * time.millisecond {
			10 * time.millisecond
		} else {
			until - now
		}))
	}
}

fn unicode_space(point rune) bool {
	return (point >= 9 && point <= 13) || (point >= 0x1c && point <= 0x20) || point in [
		rune(0x85),
		0xa0,
		0x1680,
		0x2028,
		0x2029,
		0x202f,
		0x205f,
		0x3000,
	] || (point >= 0x2000 && point <= 0x200a)
}

// Count complete, valid UTF-8 sequences; consume the valid prefix of a broken
// sequence once, matching replacement decoding of serial and X11 titles.
fn utf8_span(bytes []u8, index int) (int, int) {
	first := bytes[index]
	width := if first < 0x80 {
		1
	} else if first >= 0xc2 && first <= 0xdf {
		2
	} else if first >= 0xe0 && first <= 0xef {
		3
	} else if first >= 0xf0 && first <= 0xf4 {
		4
	} else {
		0
	}
	mut consumed := 1
	for position in 1 .. width {
		if index + position >= bytes.len { break }
		value := bytes[index + position]
		if value < 0x80 || value > 0xbf || (position == 1 && ((first == 0xe0 && value < 0xa0) || (first == 0xed && value > 0x9f) || (first == 0xf0 && value < 0x90) || (first == 0xf4 && value > 0x8f))) {
			break
		}
		consumed++
	}
	return width, consumed
}

fn strict_utf8(text string) ! {
	bytes := text.bytes()
	mut index := 0
	for index < bytes.len {
		width, consumed := utf8_span(bytes, index)
		if width == 0 || consumed != width { return error('invalid UTF-8 text') }
		index += width
	}
}

fn decode_utf8(bytes []u8) string {
	mut result := []u8{}
	mut index := 0
	for index < bytes.len {
		width, consumed := utf8_span(bytes, index)
		if width > 0 && consumed == width {
			result << bytes[index..index + width]
		} else {
			result << '\ufffd'.bytes()
		}
		index += consumed
	}
	return result.bytestr()
}
