// SPDX-License-Identifier: GPL-2.0-or-later
module g17expr

import traceanalysis as j

fn test_visibility_buffer_copy_instructions() {
	mut code := []u8{len: 0x1f88}
	// Three original AArch64 instructions, in little-endian image order.
	bytes := [u8(0x48), 0x0f, 0x40, 0xf9, 0x09, 0x61, 0x43, 0xf9, 0x29, 0x63, 0x02, 0xf9]!
	for index, byte in bytes { code[0x1f7c + index] = byte }
	visibility_copy(code) or { panic(err) }
	for index in 0x1f7c .. 0x1f88 {
		code[index] ^= u8(1)
		if _ := visibility_copy(code) { assert false }
		code[index] ^= u8(1)
	}
	if _ := visibility_copy(code[..0x1f87]) { assert false }
}

// Sanitized observations from the pinned image, independent of kernel member
// constants. Mutations must not silently promote a different pointer field.
fn visibility_fixture() (map[string]j.Value, map[string]j.Value) {
	copy := j.decode('{"post_common_copy_ranges":[{"source_offset":1728,"descriptor_member":1216,"bytes":8}]}') or { panic(err) }
	selectors := j.decode('{"producers":{"3D":{"encoder_entries":[{"selector":86800,"mode":1,"value_source":{"expression":{"kind":"expression","operation":"and","bytes":8,"immediate":18446744073709551600,"source":{"kind":"descriptor_load","member":1216,"bytes":8,"signed":false}}}}]}}}') or { panic(err) }
	return copy.as_map(), selectors.as_map()
}

fn test_visibility_buffer_copy_and_consumer_agree() {
	copy, selectors := visibility_fixture()
	layout := visibility_layout(copy, selectors) or { panic(err) }
	expected := j.decode('{"field":"visibility_result_buffer","payload_offset":1728,"descriptor_member":1216,"bytes":8,"selector":86800,"mode":1,"value_mask":18446744073709551600}') or { panic(err) }
	assert j.decode(j.encode(layout, false)) or { panic(err) } == expected
}

fn test_visibility_buffer_rejects_changed_copy() {
	copy, selectors := visibility_fixture()
	serialized := j.encode(expr(copy), false)
	for changed in [serialized.replace('1728', '1736'), serialized.replace('1216', '1224'),
		serialized.replace('"bytes":8', '"bytes":4'),
		serialized.replace('post_common_copy_ranges', 'missing')] {
		result := j.decode(changed) or { panic(err) }
		if _ := visibility_layout(result.as_map(), selectors) {
			assert false
		}
	}
}

fn test_visibility_buffer_rejects_changed_consumer() {
	copy, selectors := visibility_fixture()
	serialized := j.encode(expr(selectors), false)
	for changed in [serialized.replace('86800', '86808'), serialized.replace('1216', '1224'),
		serialized.replace('"mode":1', '"mode":0'),
		serialized.replace('18446744073709551600', '18446744073709551608'),
		serialized.replace('"signed":false', '"signed":true'),
		serialized.replace('"bytes":8', '"bytes":4'), serialized.replace('"and"', '"orr"')] {
		result := j.decode(changed) or { panic(err) }
		if _ := visibility_layout(copy, result.as_map()) {
			assert false
		}
	}
}
