// SPDX-License-Identifier: GPL-2.0-or-later
module fdtstrings

// clone_nul_list decodes an FDT string-list property. The returned array owns
// every string, so it remains valid independently of the firmware DT blob and
// can safely be released with `values.free()`.
pub fn clone_nul_list(data voidptr, data_len u32) ?[]string {
	if data_len == 0 {
		return none
	}
	mut result := []string{}
	mut offset := u32(0)
	for offset < data_len {
		value := unsafe { &u8(u64(data) + offset) }
		mut length := 0
		for offset + u32(length) < data_len && unsafe { value[length] } != 0 {
			length++
		}
		if length > 0 {
			// tos() only creates a view. Clone it because Array_string__free
			// recursively releases the strings stored in an owning []string.
			result << unsafe { tos(value, length).clone() }
		}
		offset += u32(length) + 1
	}
	return result
}
