// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn signature_space(byte u8) bool {
	return byte in [u8(` `), `\n`, `\t`, `\v`, `\f`, `\r`]!
}

fn signature_digit(byte u8, position int) !u8 {
	if byte >= `0` && byte <= `9` { return byte - `0` }
	if byte >= `a` && byte <= `f` { return byte - `a` + 10 }
	if byte >= `A` && byte <= `F` { return byte - `A` + 10 }
	// Match the hex reader's byte/index diagnostic without retaining the
	// temporary byte and decimal strings under manual memory management.
	character := byte.ascii_str()
	index := position.str()
	defer { unsafe { character.free(); index.free() } }
	return error('invalid hex char ${character} at index ${index}')
}

// Preserve trim_space/hex.decode admission, including prefixes and an implicit
// leading zero for odd digit counts. Scan borrowed bytes; only an admitted
// 64-byte signature gets an owned output allocation. Wrong-length inputs still
// report the first invalid hex byte before reporting verification failure.
fn decode_repository_signature(repository string, encoded string) ![]u8 {
	mut start := 0
	mut end := encoded.len
	for start < end && signature_space(encoded[start]) { start++ }
	for end > start && signature_space(encoded[end - 1]) { end-- }
	mut begin := start
	if end - begin >= 2 && encoded[begin] == `0` && encoded[begin + 1] in [u8(`x`), `X`]! { begin += 2 }
	length := end - begin
	fits := length == 127 || length == 128
	mut decoded := [64]u8{}
	for i := begin; i < end; i++ {
		digit := signature_digit(encoded[i], i - start)!
		if fits {
			position := (i - begin + (length & 1)) / 2
			decoded[position] = (decoded[position] << 4) | digit
		}
	}
	if !fits {
		return error('${repository}: repository signature verification failed; check administrator key enrollment')
	}
	mut signature := []u8{len: 64}
	for i in 0 .. 64 { signature[i] = decoded[i] }
	return signature
}
