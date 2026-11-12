// SPDX-License-Identifier: GPL-2.0-or-later
module winegui

import crypto.sha256
import encoding.base64
import strconv

pub struct Frame {
pub:
	name string
	width int
	height int
	rgb []u8
}

pub fn frame_line(name string, width int, height int, rgb []u8) !string {
	if name !in ['before', 'after'] || width < 1 || width > 1024 || height < 1
		|| height > 768 || rgb.len != width * height * 3 { return error('invalid GUI frame shape') }
	mut packed := []u8{cap: rgb.len * 2}
	defer { unsafe { packed.free() } }
	mut at := 0
	for at < rgb.len {
		mut count := 1
		for count < 255 && at + count * 3 < rgb.len
			&& rgb[at] == rgb[at + count * 3] && rgb[at + 1] == rgb[at + count * 3 + 1]
			&& rgb[at + 2] == rgb[at + count * 3 + 2] { count++ }
		for byte in [u8(count), rgb[at], rgb[at + 1], rgb[at + 2]]! { packed << byte }
		at += count * 3
	}
	return 'WINE GUI FRAME ' + name + ' ' + width.str() + ' ' + height.str() + ' '
		+ sha256.sum(rgb).hex() + ' ' + base64.encode(packed)
}

// Decode only bounded, canonical captures. Run expansion cannot exceed the
// declared image; malformed input never grows storage based on a run count.
pub fn decode_frame(line string) !Frame {
	parts := line.split(' ')
	if parts.len != 8 || parts[0..3] != ['WINE', 'GUI', 'FRAME']
		|| parts[3] !in ['before', 'after'] { return error('invalid GUI frame record') }
	width := strconv.atoi(parts[4])!
	height := strconv.atoi(parts[5])!
	if width < 1 || width > 1024 || height < 1 || height > 768
		|| parts[6].len != 64 || parts[7].len > 4 * 1024 * 1024 { return error('GUI frame bounds differ') }
	packed := base64.decode(parts[7])
	defer { unsafe { packed.free() } }
	if packed.len == 0 || packed.len % 4 != 0 || base64.encode(packed) != parts[7] {
		return error('noncanonical GUI frame encoding')
	}
	mut rgb := []u8{len: width * height * 3}
	mut accepted := false
	defer { if !accepted { unsafe { rgb.free() } } }
	mut at := 0
	for offset := 0; offset < packed.len; offset += 4 {
		count := int(packed[offset]) * 3
		if count == 0 || count > rgb.len - at { return error('GUI frame run exceeds image') }
		for pixel := 0; pixel < count; pixel += 3 {
			for channel in 0 .. 3 { rgb[at + pixel + channel] = packed[offset + 1 + channel] }
		}
		at += count
	}
	if at != rgb.len || sha256.sum(rgb).hex() != parts[6] { return error('GUI frame bytes differ') }
	accepted = true
	return Frame{name: parts[3].clone(), width: width, height: height, rgb: rgb}
}
