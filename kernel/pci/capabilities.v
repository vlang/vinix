// SPDX-License-Identifier: GPL-2.0-only
module pci

// Scalar observations only. Mutable MSI-X vector ownership belongs to the
// permanent native device; no bitmap is allocated while validating this list.
pub struct CapabilityInfo {
pub:
	msi_offset   u16
	msix_offset  u16
	msix_entries u16
}

// Validate the entire conventional capability chain before advertising either
// interrupt capability. The callback finishes each transport transaction before
// this function proceeds. No configuration writes, allocations or task queries
// are permitted here. This is not extended-capability or MSI IRQ registration.
pub fn capabilities_read(bdf u32, header_type u8, capability_reader TopologyRead) (CapabilityInfo, int) {
	if bdf > 0xffff || header_type > 2 || capability_reader == unsafe { nil } {
		return CapabilityInfo{}, topology_invalid
	}
	status, status_error := capability_reader(bdf, 0x06, 2)
	if status_error != 0 { return CapabilityInfo{}, topology_io_error }
	if status & (u32(1) << 4) == 0 { return CapabilityInfo{}, topology_ok }
	minimum := if header_type == 2 { u32(0x48) } else { u32(0x40) }
	pointer_register := if header_type == 2 { u16(0x14) } else { u16(0x34) }
	pointer, pointer_error := capability_reader(bdf, pointer_register, 1)
	if pointer_error != 0 { return CapabilityInfo{}, topology_io_error }
	mut offset := pointer
	mut seen := [4]u64{}
	mut occupied := [4]u64{}
	mut msi := u16(0)
	mut msix := u16(0)
	mut entries := u16(0)
	for offset != 0 {
		if offset < minimum || offset > 0xfc || offset & 3 != 0 {
			return CapabilityInfo{}, topology_malformed
		}
		word := offset >> 6
		bit := u64(1) << (offset & 63)
		if seen[word] & bit != 0 { return CapabilityInfo{}, topology_cycle }
		seen[word] |= bit
		header, header_error := capability_reader(bdf, u16(offset), 2)
		if header_error != 0 { return CapabilityInfo{}, topology_io_error }
		id := u8(header)
		mut length := u32(2)
		if id == 0x05 || id == 0x11 {
			if (id == 0x05 && msi != 0) || (id == 0x11 && msix != 0) {
				return CapabilityInfo{}, topology_malformed
			}
			control, control_error := capability_reader(bdf, u16(offset + 2), 2)
			if control_error != 0 { return CapabilityInfo{}, topology_io_error }
			length = 12
			if id == 0x05 {
				wide := control & 0x80 != 0
				maskable := control & 0x100 != 0
				length = if maskable {
					if wide { u32(24) } else { u32(20) }
				} else {
					if wide { u32(14) } else { u32(10) }
				}
			}
			if length > 256 - offset { return CapabilityInfo{}, topology_malformed }
			if id == 0x05 { msi = u16(offset) }
			else { msix = u16(offset); entries = u16((control & 0x7ff) + 1) }
		}
		// A later capability may precede this one in address order, but its
		// header/payload must not overlap a previously checked known extent.
		for byte := offset; byte < offset + length; byte++ {
			index := byte >> 6
			mask := u64(1) << (byte & 63)
			if occupied[index] & mask != 0 { return CapabilityInfo{}, topology_malformed }
			occupied[index] |= mask
		}
		offset = u32(u8(header >> 8))
	}
	return CapabilityInfo{ msi_offset: msi, msix_offset: msix, msix_entries: entries }, topology_ok
}
