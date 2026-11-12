// SPDX-License-Identifier: GPL-2.0-or-later
module winegui

import crypto.sha256
import encoding.base64

fn refuse(line string) {
	decode_frame(line) or { return }
	panic('accepted malformed GUI frame')
}

fn test_bounded_frame_roundtrip_and_corruption_refusals() {
	mut rgb := []u8{len: 300 * 3}
	for at in 0 .. rgb.len { rgb[at] = u8(at % 3 * 80) }
	line := frame_line('before', 300, 1, rgb) or { panic(err) }
	frame := decode_frame(line) or { panic(err) }
	if frame.width != 300 || frame.height != 1 || frame.name != 'before' || frame.rgb != rgb { panic('long-run roundtrip differs') }
	refuse(line.replace('before', 'unknown'))
	refuse(line.replace('300 1', '1025 1'))
	refuse(line.replace('300 1', '300 769'))
	refuse(line.replace(sha256.sum(rgb).hex(), '0'.repeat(64)))
	refuse(line + '=')
	for bytes in [[u8(0), 1, 2, 3], [u8(255), 1, 2, 3], [u8(1), 1, 2], []u8{}] {
		refuse('WINE GUI FRAME after 1 1 ' + '0'.repeat(64) + ' ' + base64.encode(bytes))
	}
	refuse('WINE GUI FRAME after 2 1 ' + sha256.sum([u8(1), 2, 3]).hex() + ' ' + base64.encode([u8(1), 1, 2, 3]))
	refuse('WINE GUI FRAME')
	println('WINE GUI FRAME PASS bounded long-run roundtrip and 11 malformed record/run/hash refusals')
}
