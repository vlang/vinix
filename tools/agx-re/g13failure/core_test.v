module g13failure

// Independent instruction fragments from the Air's disassembly. Empty space
// between the fragments is deliberately not interpreted as executable code.
fn event_fixture() []u8 {
	mut bytes := []u8{len: 0x3d0}
	for item in [
		[u32(0x48), 0xf943d809]!,
		[u32(0x4c), 0xb940012b]!,
		[u32(0x54), 0xb9402129]!,
		[u32(0x5c), 0xf943e80a]!,
		[u32(0x60), 0xeb0b015f]!,
		[u32(0x64), 0x540089c9]!,
		[u32(0x68), 0xeb09015f]!,
		[u32(0x6c), 0x54008a69]!,
		[u32(0x318), 0x7100201f]!,
		[u32(0x31c), 0x540004a0]!,
		[u32(0x3b0), 0xb94053e8]!,
		[u32(0x3b4), 0x7100211f]!,
		[u32(0x3b8), 0x54006661]!,
		[u32(0x3cc), 0x52800048]!,
	] {
		for i in 0 .. 4 { bytes[int(item[0]) + i] = u8(item[1] >> (i * 8)) }
	}
	return bytes
}

fn test_event_bounds_reject_drift_and_truncation() {
	bytes := event_fixture()
	check_event_code(bytes)!
	for offset in [0x48, 0x4c, 0x54, 0x5c, 0x60, 0x64, 0x68, 0x6c, 0x318, 0x31c, 0x3b0, 0x3b4,
		0x3b8, 0x3cc] {
		mut changed := bytes.clone()
		changed[offset] ^= 1
		if _ := check_event_code(changed) {
			assert false, 'accepted changed instruction at ${offset:x}'
		}
	}
	if _ := check_event_code(bytes[..0x3ce]) {
		assert false
	}
}

fn test_halt_load_cannot_be_confused_with_resume() {
	words := [u32(0xd503245f), 0xf9448008, 0x52894409, 0xb8696908, 0x7100011f, 0x1a9f07e0, 0xd65f03c0]!
	mut bytes := []u8{len: words.len * 4}
	for index, word in words {
		for byte in 0 .. 4 { bytes[index * 4 + byte] = u8(word >> (byte * 8)) }
	}
	check_halt_code(bytes)!
	// The next cache-line field is resume: changing the offset must fail.
	bytes[8] ^= 0x80
	if _ := check_halt_code(bytes) {
		assert false
	}
}
