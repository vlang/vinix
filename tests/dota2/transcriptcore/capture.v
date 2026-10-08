// SPDX-License-Identifier: GPL-2.0-or-later
module transcriptcore

import crypto.sha256

pub struct DecodeError {
pub:
	kind    string
	message string
}

pub fn (failure DecodeError) msg() string { return failure.message }

pub fn (failure DecodeError) code() int { return 0 }

fn base64_value(ch u8) int {
	if ch >= `A` && ch <= `Z` { return int(ch - `A`) }
	if ch >= `a` && ch <= `z` { return int(ch - `a`) + 26 }
	if ch >= `0` && ch <= `9` { return int(ch - `0`) + 52 }
	if ch == `+` { return 62 }
	if ch == `/` { return 63 }
	return -1
}

// Python's strict decoder accepts noncanonical pad bits and up to two
// redundant terminal pads after a complete quartet. It rejects any data
// after padding and incomplete quartets that do not have enough padding.
fn strict_base64(encoded string) ![]u8 {
	end := encoded.index('=') or { encoded.len }
	if encoded[end..].bytes().any(it != `=`) { return error('Data after padding') }
	remaining := end % 4
	pads := encoded.len - end
	if remaining == 1 || (remaining == 2 && pads != 2) || (remaining == 3 && pads != 1) {
		return error('Invalid base64 padding')
	}
	mut output := []u8{cap: end * 3 / 4}
	mut bits := 0
	mut accumulator := u32(0)
	for ch in encoded[..end].bytes() {
		value := base64_value(ch)
		if value < 0 { return error('Invalid base64 character') }
		accumulator = (accumulator << 6) | u32(value)
		bits += 6
		if bits >= 8 {
			bits -= 8
			output << u8((accumulator >> bits) & 255)
		}
	}
	return output
}

pub fn decode_capture(transcript string) ![]u8 {
	begin := 'VINIX-DOTA2-VULKAN-SHOT-BEGIN\n'
	start := transcript.index(begin) or { return DecodeError{'IndexError', 'list index out of range'} }
	after := transcript[start + begin.len..]
	capture := after[..(after.index('VINIX-DOTA2-VULKAN-SHOT-END') or { after.len })]
	mut hashes := map[string]bool{}
	mut lines := map[string][]string{}
	mut last := ''
	for line in capture.split('\n') {
		hash_prefix := 'VINIX-DOTA2-VULKAN-SHOT-SHA256: '
		if line.starts_with(hash_prefix) {
			hash := line[hash_prefix.len..]
			if hash.len == 64 && hash.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
				hashes[hash] = true
			}
		}
		if !line.starts_with('S') { continue }
		separator := line.index(' ') or { continue }
		number := line[1..separator]
		encoded := line[separator + 1..]
		if number.len == 0 || number[0] < `1` || number[0] > `9` || !number.bytes().all(it >= `0` && it <= `9`) {
			continue
		}
		end := encoded.index('=') or { encoded.len }
		if end == 0 || encoded.len - end > 2 || !encoded[..end].bytes().all(base64_value(it) >= 0) || !encoded[end..].bytes().all(it == `=`) {
			continue
		}
		mut candidates := lines[number] or { []string{} }
		if encoded !in candidates {
			candidates << encoded.clone()
			lines[number] = candidates
		}
		if number.len > last.len || (number.len == last.len && number > last) {
			last = number.clone()
		}
	}
	if hashes.len != 1 || lines.len == 0 {
		return DecodeError{'SystemExit', 'the guest capture has no intact hash or image lines'}
	}
	mut chosen := []string{}
	mut index := i64(1)
	for index.str() != last {
		key := index.str()
		candidates := (lines[key] or { []string{} }).filter(it.len == 76)
		if candidates.len != 1 {
			return DecodeError{'SystemExit', 'capture line ' + key + ' is missing or corrupt in both copies'}
		}
		chosen << candidates[0]
		index++
	}
	mut finals := (lines[last] or { []string{} }).clone()
	finals.sort(a.len < b.len)
	for final in finals {
		contents := strict_base64(chosen.join('') + final) or { continue }
		if sha256.sum(contents).hex() in hashes { return contents }
	}
	return DecodeError{'SystemExit', "the reassembled capture does not match the guest's hash"}
}
