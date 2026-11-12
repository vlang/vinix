// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

pub const wine_x11_input = 'f187ce85dbec1a29def88ec5c8725568eb74d75c8512ef90b8b6d90cf104ab97'

// Wine 9.17 bitblt.c tries shmget even when the X server disables MIT-SHM.
// Our private hosted display does not permit SysV IPC. Select Wine's existing
// XCreateImage fallback by returning -1 at this single optional allocation
// call. No segment is created, attached or shared, and pledge stays unchanged.
// This exact local binary adaptation is not a corresponding-source or
// redistribution acceptance assertion.
pub fn private_graphics_patch(input string) !string {
	digest := patch_digest(input)
	defer { unsafe { digest.free() } }
	if digest != wine_x11_input { return error('Wine private graphics input hash differs') }
	offset := 0x7e3a
	before := '\x41\x0f\xaf\xf4\x31\xff\xba\xc0\x03\x00\x00\x48\x63\xf6\xff\x15\x88\x51\x06\x00\x89\x43\x10\x89\xc7\x83\xf8\xff\x74\x7e'
	start := offset - 14
	if start + before.len > input.len || unsafe { tos(input.str + start, before.len) } != before { return error('Wine private graphics allocation site differs') }
	mut matches := 0
	for at in 0 .. input.len - before.len + 1 {
		if input[at] == before[0] && unsafe { tos(input.str + at, before.len) } == before { matches++ }
	}
	if matches != 1 { return error('Wine private graphics allocation site must occur once') }
	result := input.clone()
	after := '\xb8\xff\xff\xff\xff\x90' // mov eax,-1; nop, same six bytes
	unsafe { vmemcpy(result.str + offset, after.str, after.len) }
	return result
}
