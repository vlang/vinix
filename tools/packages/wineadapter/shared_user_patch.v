// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

struct SharedUserSite {
	start int
	field int
	before string
}

// Enlarge only Wine's private KUSER section and its three views to one 16 KiB
// host page. Windows' ordinary page size and other mappings stay unchanged.
// All four sites are needed: a copied 4 KiB reader cannot see later writes.
// This exact local adaptation is not general partial-page mapping support.
fn patch_shared_user_sites(original string, output string, part string) ! {
	expected := match part {
		'server' { wine_server_input }
		'client' { wine_client_input }
		'boot' { wine_boot_input }
		else { return error('unknown Wine shared-user-data component') }
	}
	digest := patch_digest(original)
	defer { unsafe { digest.free() } }
	if digest != expected || output.len < original.len { return error('Wine shared-user-data input differs') }
	sites := match part {
		'server' { [SharedUserSite{0x1dea0, 0x1deac, '\x53\x45\x31\xc9\x41\xb8\x00\x00\x00\x08\x51\xb9\x10\x07\x00\x00\x6a\x03\xe8\x09\xf1\xff\xff'}] }
		'boot' { [SharedUserSite{0x62bf, 0x62d2, '\x48\x8b\x8c\x24\x10\x01\x00\x00\x45\x31\xc9\x45\x31\xc0\x48\xc7\x44\x24\x20\x10\x07\x00\x00\xba\x02\x00\x00\x00\xff\x15\x87\x44\x01\x00'}] }
		else { [
			SharedUserSite{0x3c3f1, 0x3c3f9, '\x31\xc9\xba\x03\x00\x00\x00\xbe\x00\x10\x00\x00\x89\xa8\x3c\x03\x00\x00\x48\x8d\x05\xee\x70\x04\x00\x48\x8b\x28\x48\x8d\xbd\x00\x10\x00\x00\x67\xe8\xb6\xfc\x01\x00\x48\x8d\x05\x1f\xa2\xff\xff\x48\x89\x85\x00\x10\x00\x00'},
			SharedUserSite{0x3c3f1, 0x3c410, '\x31\xc9\xba\x03\x00\x00\x00\xbe\x00\x10\x00\x00\x89\xa8\x3c\x03\x00\x00\x48\x8d\x05\xee\x70\x04\x00\x48\x8b\x28\x48\x8d\xbd\x00\x10\x00\x00\x67\xe8\xb6\xfc\x01\x00\x48\x8d\x05\x1f\xa2\xff\xff\x48\x89\x85\x00\x10\x00\x00'},
			SharedUserSite{0x3c3f1, 0x3c424, '\x31\xc9\xba\x03\x00\x00\x00\xbe\x00\x10\x00\x00\x89\xa8\x3c\x03\x00\x00\x48\x8d\x05\xee\x70\x04\x00\x48\x8b\x28\x48\x8d\xbd\x00\x10\x00\x00\x67\xe8\xb6\xfc\x01\x00\x48\x8d\x05\x1f\xa2\xff\xff\x48\x89\x85\x00\x10\x00\x00'},
			SharedUserSite{0x5e50e, 0x5e517, '\x48\x83\xec\x28\x48\xc7\x44\x24\x10\x00\x10\x00\x00\x48\x8d\x5c\x24\x10\x48\xc7\x44\x24\x18\x00\x00\x20\x00\x48\x89\xd9\x67\xe8\xfe\xfc\xff\xff'},
			SharedUserSite{0x5ce1c, 0x5ce35, '\x45\x31\xc9\x44\x8b\x04\x24\xb9\x11\x00\x00\x00\x48\x8b\x3d\xc9\x66\x02\x00\xba\x01\x00\x00\x00\xbe\x00\x10\x00\x00\xff\x15\xe9\x5d\x02\x00\x48\x39\x05\xb2\x66\x02\x00'},
		] }
	}
	defer { unsafe { sites.free() } }
	// Validate the whole group before touching the caller's owned output.
	for site in sites {
		if site.start + site.before.len > original.len
			|| unsafe { tos(original.str + site.start, site.before.len) } != site.before
			|| unsafe { tos(output.str + site.start, site.before.len) } != site.before { return error('Wine shared-user-data instruction site differs') }
		mut matches := 0
		for at in 0 .. original.len - site.before.len + 1 {
			if original[at] == site.before[0] && unsafe { tos(original.str + at, site.before.len) } == site.before { matches++ }
		}
		if matches != 1 { return error('Wine shared-user-data instruction site is ambiguous') }
	}
	for site in sites {
		value := '\x00\x40\x00\x00'
		unsafe { vmemcpy(output.str + site.field, value.str, value.len) }
	}
}

// Wine's generated PE syscall stubs reference the private dispatcher, not
// architectural KUSER fields. Put that private page at the next host-page
// boundary. The unrelated WOW64 debug-breakin sentinel remains untouched.
pub fn private_dispatcher_pe_patch(input string, ntdll bool) !string {
	expected := if ntdll { 'd93bffca52cbb1b730cb2e2e01dc7fe902abc22fe3b2d08190eba1c7f5c7e29f' }
		else { '4868ac289be612fd7b6485e2ce440bd65429b39c651db8f6882c987728f6f6ec' }
	digest := patch_digest(input)
	defer { unsafe { digest.free() } }
	if digest != expected { return error('Wine dispatcher PE input differs') }
	count := if ntdll { 237 } else { 426 }
	first := if ntdll { 0x54740 } else { 0x96c0 }
	pattern := '\x4c\x8b\xd1\xb8\x00\x00\x00\x00\xf6\x04\x25\x08\x03\xfe\x7f\x01\x75\x03\x0f\x05\xc3\xeb\x01\xc3\xff\x14\x25\x00\x10\xfe\x7f\xc3'
	for index in 0 .. count {
		at := first + index * 32
		number := u32(index) + if ntdll { u32(0) } else { u32(0x1000) }
		if at + 32 > input.len { return error('Wine dispatcher stub is truncated') }
		for byte in 0 .. 32 {
			wanted := if byte >= 4 && byte < 8 { u8(number >> u32((byte - 4) * 8)) } else { pattern[byte] }
			if input[at + byte] != wanted { return error('Wine dispatcher stub sequence differs') }
		}
	}
	// Close the inventory over every literal occurrence, including the one
	// known non-dispatcher use. No unexamined old address may slip through.
	mut references := 0
	for at in 0 .. input.len - 3 {
		if unsafe { tos(input.str + at, 4) } != '\x00\x10\xfe\x7f' { continue }
		if ntdll && at == 0x4631d {
			if input[at - 5..at] != '\x48\xc7\x44\x24\x20' { return error('Wine WOW64 debug sentinel differs') }
			continue
		}
		if at < first + 27 || at >= first + count * 32 || (at - first - 27) % 32 != 0 { return error('unexamined Wine dispatcher reference') }
		references++
	}
	if references != count { return error('Wine dispatcher reference count differs') }
	result := input.clone()
	for index in 0 .. count { unsafe { result.str[first + index * 32 + 28] = 0x40 } }
	return result
}

// Standalone byte checker entry; production composes these sites with the
// existing private-prefix, NLS, W^X/unwind and offline-bootstrap adaptations.
pub fn shared_user_data_patch(input string, part string) !string {
	result := input.clone()
	patch_shared_user_sites(input, result, part) or { unsafe { result.free() }; return err }
	return result
}
