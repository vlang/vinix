// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

// Use the exact future generation, including its counter widths. Readers and
// writers share this size limit; reject before staging or retiring recovery data.
// The caller owns the returned encoding and writes those same bytes at activation.
fn encode_generation_state(state State) !string {
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(state, mut bytes)
	if bytes.len > max_metadata {
		return error('installed state exceeds metadata limit; reduce the requested package set or package metadata')
	}
	return bytes.bytestr()
}
