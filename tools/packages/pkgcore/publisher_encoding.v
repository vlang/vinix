// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

// json2.encode retains its builder in manual-free programs. Keep the encoder
// buffer local and return an independent, newline-terminated string instead.
fn publisher_json[T](value T) string {
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(value, mut bytes)
	bytes << `\n`
	return bytes.bytestr()
}
