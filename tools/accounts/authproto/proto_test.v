// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module authproto

fn test_round_trip() ! {
	frame := text_frame(op_run, 'restart', 'pass word', '', 'a', 'b')
	data := encode(frame)!
	back := decode(data)!
	assert back.code == op_run
	assert back.fields.len == 5
	assert back.text(0) == 'restart' && back.text(1) == 'pass word' && back.text(2) == ''
	assert back.text(9) == ''
	empty := decode(encode(Frame{ code: status_ok })!)!
	assert empty.code == status_ok && empty.fields.len == 0
}

fn test_bounds() ! {
	mut big := Frame{
		code: op_verify
	}
	big.fields << []u8{len: max_field}
	decode(encode(big)!)!
	big.fields[0] << u8(1)
	encode(big) or {
		mut many := Frame{}
		for _ in 0 .. max_fields + 1 {
			many.fields << []u8{}
		}
		encode(many) or { return }
	}
	assert false
}

fn test_malformed_frames() ! {
	good := encode(text_frame(op_verify, 'alex', 'secret'))!
	// Every truncation and every single-byte extension is refused.
	for length in 0 .. good.len {
		decode(good[..length]) or { continue }
		assert false, 'accepted ${length} of ${good.len} bytes'
	}
	mut longer := good.clone()
	longer << u8(0)
	decode(longer) or {
		// A wrong magic, a wrong version, a count or a length that lies.
		for at, value in {
			0:  u8(0)
			4:  u8(2)
			8:  u8(3)
			11: u8(1)
			12: u8(200)
			15: u8(1)
		} {
			mut bad := good.clone()
			bad[at] = value
			decode(bad) or { continue }
			assert false, 'accepted byte ${at} = ${value}'
		}
		return
	}
	assert false
}

fn test_wipe() {
	mut frame := text_frame(op_verify, 'alex', 'secret')
	frame.wipe()
	assert frame.fields[1] == []u8{len: 6}
}

// Bytes nobody chose: decode must refuse or succeed, never read outside the
// buffer, and what it accepts must encode back to the same bytes.
fn test_fuzz_decode() ! {
	mut state := u64(0x9e3779b97f4a7c15)
	good := encode(text_frame(op_run, 'action', 'password', '', 'one', 'two'))!
	for round in 0 .. 20000 {
		mut data := good.clone()
		state ^= state << 13
		state ^= state >> 7
		state ^= state << 17
		flips := int(state % 4) + 1
		for _ in 0 .. flips {
			state ^= state << 13
			state ^= state >> 7
			state ^= state << 17
			data[int(state % u64(data.len))] = u8(state >> 32)
		}
		if round % 3 == 0 {
			state ^= state << 13
			state ^= state >> 7
			state ^= state << 17
			data = data[..int(state % u64(data.len + 1))].clone()
		}
		frame := decode(data) or { continue }
		assert encode(frame)! == data
	}
}
