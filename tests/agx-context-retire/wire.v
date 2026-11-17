module gpu

import gpu.agx.fw
import gpu.agx.hw

fn expected_context(abi hw.FirmwareAbi, data &[64]u8, address u64) [48]u8 {
	mut result := [48]u8{}
	result[0] = if abi == .v12_3 { u8(23) } else { u8(24) }
	result[8] = data[35]
	ids := if abi == .v12_3 { 20 } else { 17 }
	result[ids] = data[0]; result[ids + 1] = data[1]; result[ids + 2] = data[4]
	pointer := if abi == .v12_3 { 28 } else { 20 }
	mut value := address
	for i in pointer .. pointer + 8 { result[i] = u8(value % 256); value /= 256 }
	return result
}
fn check_context_wire() {
	mut cases := 0
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! { for pattern in 0 .. 4 {
		for address in [u64(0x4000), 0xffffffa800004000, ~u64(0)]! {
			mut data := [64]u8{}
			for i in 0 .. 64 { data[i] = u8(7 * i + 43 * pattern) }
			if pattern == 0 { data[0] = 0xff; data[1] = 0xff; data[4] = 0; data[35] = 2 }
			expected := expected_context(abi, &data, address)
			message := fw.make_g13_context_invalidate(abi, &data[0], 64, address) or { panic('supported context ABI') }
			assert sizeof(message) == 48
			for i in 0 .. 48 { assert unsafe { (&u8(&message))[i] } == expected[i], 'every context command byte must match the independent ABI model' }
			data = [64]u8{init: 0x99}
			for i in 0 .. 48 { assert unsafe { (&u8(&message))[i] } == expected[i], 'context message must own its copied scalar fields' }
			cases++
		}
	} }
	for abi in [hw.FirmwareAbi.unknown, .v12_3_partial, .g17_26_5_partial]! {
		if _ := fw.make_g13_context_invalidate(abi, voidptr(1), 64, 1) { assert false }
	}
	for size := u64(0); size < 64; size++ { if _ := fw.make_g13_context_invalidate(.v12_3, voidptr(1), size, 1) { assert false } }
	if _ := fw.make_g13_context_invalidate(.v12_3, unsafe { nil }, 64, 1) { assert false }
	if _ := fw.make_g13_context_invalidate(.v12_3, voidptr(1), 64, 0) { assert false }
	assert cases == 24
	println('AGX context wire: 24 complete 48-byte ABI cases and 69 invalid-input cases preserve versioned IDs, packed pointer and zero padding')
}
