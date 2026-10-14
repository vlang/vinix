// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

// Keep at most the accepted prefix and one bounded repository record in the
// encoder. Check the exact wrapper bytes, including the eventual closing ']'.
fn new_snapshot_encoding() []u8 {
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	bytes << u8(`[`)
	return bytes
}

fn append_snapshot_metadata(snapshot Snapshot, mut bytes []u8) ! {
	if bytes.len > 1 { bytes << u8(`,`) }
	json2.encode_append(snapshot, mut bytes)
	if bytes.len >= max_metadata {
		return error('combined repository metadata exceeds cache limit')
	}
}

fn finish_snapshot_encoding(mut bytes []u8) string {
	bytes << u8(`]`)
	return bytes.bytestr()
}
