// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

pub const wine_boot_input = 'b52d86ca9b5b6dc15954bc78dc63d02a75b4e1917c75b5d6eaa8296ccd7d23c3'

// Wine 9.17's create_computer_name_keys optionally canonicalizes gethostname
// through getaddrinfo. An offline package must not need DNS merely to create
// its private prefix. Select the existing nonzero-result fallback, retaining
// the literal host name and all subsequent registry initialization. This
// private runtime does not canonicalize its bootstrap computer name over DNS,
// including for applications that later receive network permission. It does
// not change Winsock APIs, pledge or the application's network permissions.
// Exact local binary adaptation; no redistribution/source-completeness claim.
pub fn private_bootstrap_patch(input string) !string {
	digest := patch_digest(input)
	defer { unsafe { digest.free() } }
	if digest != wine_boot_input { return error('Wine bootstrap input hash differs') }
	offset := 0x6864
	before := '\x31\xd2\x4c\x89\xf9\xc7\x84\x24\xa0\x05\x00\x00\x02\x00\x00\x00\xe8\x57\xd6\xff\xff\x85\xc0\x75\x30\x48\x8b\x84\x24\x40\x01\x00\x00'
	start := offset - 16
	if start + before.len > input.len || unsafe { tos(input.str + start, before.len) } != before { return error('Wine bootstrap canonical-name call site differs') }
	mut matches := 0
	for at in 0 .. input.len - before.len + 1 {
		if input[at] == before[0] && unsafe { tos(input.str + at, before.len) } == before { matches++ }
	}
	if matches != 1 { return error('Wine bootstrap canonical-name site must occur once') }
	result := input.clone()
	after := '\xb8\x01\x00\x00\x00' // mov eax,1: existing failure branch, same five bytes
	unsafe { vmemcpy(result.str + offset, after.str, after.len) }
	patch_shared_user_sites(input, result, 'boot') or { unsafe { result.free() }; return err }
	return result
}
