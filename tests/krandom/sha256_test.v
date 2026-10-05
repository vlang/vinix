// SPDX-License-Identifier: GPL-2.0-or-later
module krandom

import crypto.sha256
import encoding.hex

fn test_sha256_known_answers() {
	// Standard SHA-256 examples; the final case requires two padding blocks.
	for message, expected in {
		'': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		'abc': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
		'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq': '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'
	} {
		mut output := [32]u8{}
		sha256_digest(message.str, u64(message.len), unsafe { &output })
		assert hex.encode(output[..]) == expected
	}
}

fn test_sha256_binary_padding_and_borrowed_buffers() {
	// All padding positions and the actual seed-buffer sizes, including
	// unaligned borrowed input and guarded output. The standard-library hash
	// is an independent implementation, used only by this host test.
	mut lengths := []int{len: 258, init: index}
	lengths << [509, 512, 1024, 4096, 4119, 32798, 65536]
	for length in lengths {
		mut input := []u8{len: length + 2, init: u8(0xa5)}
		for i in 0 .. length {
			input[i + 1] = u8((i * 131 + i / 7) & 255)
		}
		original := input.clone()
		expected := sha256.sum(input[1..length + 1])
		mut output := [34]u8{init: u8(0x5a)}
		sha256_digest(unsafe { &input[1] }, u64(length), unsafe { voidptr(&output[1]) })
		assert output[0] == 0x5a && output[33] == 0x5a
		assert input == original
		for i in 0 .. 32 {
			assert output[i + 1] == expected[i]
		}
		unsafe {
			input.free()
			original.free()
			expected.free()
		}
	}
	unsafe { lengths.free() }
}

fn test_sha256_empty_input_may_be_null() {
	mut output := [32]u8{}
	sha256_digest(unsafe { nil }, 0, unsafe { &output })
	assert hex.encode(output[..]) == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
}
