// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module wsloader

// PT_LOAD segments may share a page. Account for the highest mapped offset,
// rather than adding page-rounded lengths and counting shared pages twice.
// Invalid ranges return a sentinel that the upstream sanity check rejects.
@[export: 'vinix_ws_segment_extent']
pub fn segment_extent(base usize, reserved usize, address usize, length usize, previous usize) usize {
	if address < base || address - base > reserved || length > reserved - (address - base) {
		return ~usize(0)
	}
	end := address - base + length
	return if previous > end { previous } else { end }
}
