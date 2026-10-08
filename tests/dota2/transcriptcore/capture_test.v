// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the original four independent serial-damage fixture cases.
module transcriptcore

import crypto.sha256
import encoding.base64

enum Damage {
	clean
	kernel
	lost
	hash
}

fn fixture_image() []u8 {
	mut image := []u8{cap: 2308}
	for _ in 0 .. 9 {
		for value in 0 .. 256 { image << u8(value) }
	}
	image << 'tail'.bytes()
	return image
}

fn fixture_transcript(image []u8, damage Damage) string {
	encoded := base64.encode(image)
	mut output := ['VINIX-DOTA2-VULKAN-SHOT-BEGIN']
	for copy in [1, 2] {
		output << 'VINIX-DOTA2-VULKAN-SHOT-SHA256: ' + sha256.sum(image).hex()
		mut lines := []string{}
		mut offset := 0
		for offset < encoded.len {
			end := if offset + 76 < encoded.len { offset + 76 } else { encoded.len }
			lines << 'S' + (lines.len + 1).str() + ' ' + encoded[offset..end]
			offset = end
		}
		if damage == .kernel && copy == 1 {
			lines[3] = lines[3][..40] + 'net: lease A1' + lines[3][40..]
			lines[4] = lines[4][..20] + '\n.15' + lines[4][20..] + lines[5]
			lines.delete(5)
			last := lines.len - 1
			lines[last] = lines[last][..3] + 'exec: syscall handler entered\n' + lines[last][3..]
		}
		if damage == .lost { lines[2] += 'A' }
		if damage == .hash {
			replacement := if lines[1][4] != `B` { 'B' } else { 'C' }
			lines[1] = lines[1][..4] + replacement + lines[1][5..]
		}
		if damage == .kernel && copy == 2 { output << 'ELF auxval: base=0x5d800000' }
		output << lines
	}
	output << 'VINIX-DOTA2-VULKAN-SHOT-END'
	return output.join('\n')
}

fn test_clean_capture() {
	image := fixture_image()
	assert decode_capture(fixture_transcript(image, .clean)) or { panic(err) } == image
}

fn test_kernel_output_inside_one_copy() {
	image := fixture_image()
	assert decode_capture(fixture_transcript(image, .kernel)) or { panic(err) } == image
}

fn test_same_line_lost_in_both_copies_fails() {
	decode_capture(fixture_transcript(fixture_image(), .lost)) or {
		assert err is DecodeError
		assert err.msg().contains('line 3 is missing or corrupt')
		return
	}
	assert false
}

fn test_hash_mismatch_fails() {
	decode_capture(fixture_transcript(fixture_image(), .hash)) or {
		assert err is DecodeError
		assert err.msg().contains("does not match the guest's hash")
		return
	}
	assert false
}

fn test_capture_fixture_bytes_match_frozen_originals() {
	image := fixture_image()
	assert sha256.sum(fixture_transcript(image, .clean).bytes()).hex() == '7827801690c3a350ab4db3d98e8c13f27b93798a9a14d78e8f3acb55903535c3'
	assert sha256.sum(fixture_transcript(image, .kernel).bytes()).hex() == '52e8ef45d47cc5537c5be26f3da1e0d4237d4fd1b60920f8abd134b9c45f3387'
	assert sha256.sum(fixture_transcript(image, .lost).bytes()).hex() == '6e11f911169cca79fb70d32c9f08da1f3ad43b36f17152409be0719c9ea38501'
	assert sha256.sum(fixture_transcript(image, .hash).bytes()).hex() == 'aa68d3f7181fd561b9fed39e41dd6ded001af5fd6b8bfc7efe3c15a95dabd5e7'
}
