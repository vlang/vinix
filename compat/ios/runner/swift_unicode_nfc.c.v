// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftNfcDecomposition {
	scalar u32
	first  u32
	second u32
}

fn swift_nfc_class(scalar u32) int {
	mut low := 0
	mut high := swift_nfc_classes.len
	for low < high {
		mid := low + (high - low) / 2
		if swift_nfc_classes[mid] >> 8 < scalar { low = mid + 1 } else { high = mid }
	}
	return if low < swift_nfc_classes.len && swift_nfc_classes[low] >> 8 == scalar {
		int(swift_nfc_classes[low] & 255)
	} else {
		0
	}
}

fn swift_nfc_decompose(scalar u32, mut output []u32) {
	if scalar >= 0xac00 && scalar < 0xd7a4 {
		index := scalar - 0xac00
		output << 0x1100 + index / 588
		output << 0x1161 + (index % 588) / 28
		if index % 28 != 0 { output << 0x11a7 + index % 28 }
		return
	}
	mut low := 0
	mut high := swift_nfc_decompositions.len
	for low < high {
		mid := low + (high - low) / 2
		if swift_nfc_decompositions[mid].scalar < scalar { low = mid + 1 } else { high = mid }
	}
	if low < swift_nfc_decompositions.len && swift_nfc_decompositions[low].scalar == scalar {
		entry := swift_nfc_decompositions[low]
		swift_nfc_decompose(entry.first, mut output)
		if entry.second != 0 { swift_nfc_decompose(entry.second, mut output) }
	} else {
		output << scalar
	}
}

fn swift_nfc_compose(first u32, second u32) u32 {
	if first >= 0x1100 && first < 0x1113 && second >= 0x1161 && second < 0x1176 {
		return 0xac00 + ((first - 0x1100) * 21 + second - 0x1161) * 28
	}
	if first >= 0xac00 && first < 0xd7a4 && (first - 0xac00) % 28 == 0 && second > 0x11a7 && second < 0x11c3 {
		return first + second - 0x11a7
	}
	key := (u64(first) << 21) | second
	mut low := 0
	mut high := swift_nfc_compositions.len
	for low < high {
		mid := low + (high - low) / 2
		entry := swift_nfc_compositions[mid]
		if (u64(entry.first) << 21) | entry.second < key { low = mid + 1 } else { high = mid }
	}
	if low < swift_nfc_compositions.len {
		entry := swift_nfc_compositions[low]
		if entry.first == first && entry.second == second { return entry.scalar }
	}
	return 0
}

// Input has already passed UTF-8 validation and the caller's size bound.
// Canonical decomposition, stable class ordering and blocked composition
// implement NFC (including algorithmic Hangul), never compatibility folding.
fn swift_nfc_normalize(text string) []u32 {
	mut output := []u32{cap: text.len}
	output.flags |= .noslices
	mut at := 0
	for at < text.len {
		lead := text[at]
		width := if lead < 128 {
			1
		} else if lead < 224 {
			2
		} else if lead < 240 {
			3
		} else {
			4
		}
		mut scalar := u32(lead & if width == 1 {
			u8(127)
		} else if width == 2 {
			u8(31)
		} else if width == 3 {
			u8(15)
		} else {
			u8(7)
		})
		for i in 1 .. width { scalar = (scalar << 6) | (text[at + i] & 63) }
		swift_nfc_decompose(scalar, mut output)
		at += width
	}
	mut start := 0
	for start < output.len {
		if swift_nfc_class(output[start]) == 0 {
			start++
			continue
		}
		mut end := start + 1
		mut previous := swift_nfc_class(output[start])
		mut sorted := true
		for end < output.len {
			class := swift_nfc_class(output[end])
			if class == 0 { break }
			if class < previous { sorted = false }
			previous = class
			end++
		}
		if !sorted {
			// Counting sort is stable and linear even for long combining runs.
			mut counts := [256]int{}
			for i in start .. end { counts[swift_nfc_class(output[i])]++ }
			mut offset := 0
			for i in 0 .. 256 {
				count := counts[i]
				counts[i] = offset
				offset += count
			}
			mut ordered := []u32{len: end - start}
			for i in start .. end {
				class := swift_nfc_class(output[i])
				ordered[counts[class]] = output[i]
				counts[class]++
			}
			for i in 0 .. ordered.len { output[start + i] = ordered[i] }
			unsafe { ordered.free() }
		}
		start = end
	}
	mut starter := -1
	mut previous_class := 0
	mut length := 0
	for i in 0 .. output.len {
		scalar := output[i]
		class := swift_nfc_class(scalar)
		if starter >= 0 && (previous_class == 0 || previous_class < class) {
			combined := swift_nfc_compose(output[starter], scalar)
			if combined != 0 {
				output[starter] = combined
				continue
			}
		}
		if class == 0 { starter = length }
		output[length] = scalar
		length++
		previous_class = class
	}
	output.trim(length)
	return output
}
