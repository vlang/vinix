// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

// The caller owns the result. Include the persisted newline in the shared
// reader/writer limit, and retire growth buffers on success and refusal.
fn encode_administration_document[T](value T, limit_error string) !string {
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(value, mut bytes)
	if bytes.len >= max_metadata { return error(limit_error) }
	bytes << u8(`\n`)
	return bytes.bytestr()
}

fn write_administration_document[T](path string, value T, limit_error string) ! {
	text := encode_administration_document(value, limit_error)!
	defer { unsafe { text.free() } }
	write_administration_metadata(path, text)!
}
