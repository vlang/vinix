// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Topology from ACPI: SRAT places CPUs and memory into proximity domains, and
// SLIT gives the distances between them.
//
// This walks the R/XSDT itself rather than going through the acpi module. That
// module is written around the local APIC and the aarch64 build does not compile
// it -- and aarch64 under UEFI is exactly where this path matters, because QEMU's
// virt machine hands its guest ACPI tables and no device tree. One walker
// compiled for both architectures is also one walker that gets exercised.
//
// Every field is read byte-wise from a base address. ACPI tables are packed and
// none of their multi-byte fields is guaranteed to be aligned, which on aarch64
// is not a thing to discover at runtime.
@[has_globals]
module numa

import memory

// SRAT entry types.
const srat_processor_apic = u8(0)
const srat_memory = u8(1)
const srat_processor_x2apic = u8(2)
const srat_gicc = u8(3)

// MADT entry type for an ARM GIC CPU interface, the only structure where a
// processor's ACPI UID and its MPIDR appear together.
const madt_gicc = u8(0xb)

// Flag bit zero of an SRAT affinity structure: "enabled". A clear bit describes
// a socket or a memory range that is not populated.
const srat_enabled = u32(1)

struct AcpiTable {
	base   u64
	length u32
}

fn read_u8(base u64, offset u64) u8 {
	return unsafe { (&u8(base))[offset] }
}

fn read_u32(base u64, offset u64) u32 {
	mut value := u32(0)
	for i := u64(0); i < 4; i++ {
		value |= u32(read_u8(base, offset + i)) << u32(i * 8)
	}
	return value
}

fn read_u64(base u64, offset u64) u64 {
	mut value := u64(0)
	for i := u64(0); i < 8; i++ {
		value |= u64(read_u8(base, offset + i)) << u64(i * 8)
	}
	return value
}

// Limine reports the RSDP by the address the firmware used, and the tables it
// points at by physical address. Accept either, since which one the bootloader
// hands over depends on its revision.
fn table_virt(address u64) u64 {
	offset := memory.get_hhdm_offset()
	if address >= offset {
		return address
	}
	return address + offset
}

fn signature_at(base u64, signature string) bool {
	if signature.len != 4 {
		return false
	}
	for i := 0; i < 4; i++ {
		if read_u8(base, u64(i)) != signature[i] {
			return false
		}
	}
	return true
}

// Walk the R/XSDT for a table by signature.
fn find_acpi_table(signature string) ?AcpiTable {
	rsdp_address := acpi_rsdp_address()
	if rsdp_address == 0 {
		return none
	}
	rsdp := table_virt(rsdp_address)
	if !signature_at(rsdp, 'RSD ') || read_u8(rsdp, 4) != `P` || read_u8(rsdp, 5) != `T`
		|| read_u8(rsdp, 6) != `R` || read_u8(rsdp, 7) != ` ` {
		return none
	}

	revision := read_u8(rsdp, 15)
	xsdt_address := read_u64(rsdp, 24)
	use_xsdt := revision >= 2 && xsdt_address != 0
	root := if use_xsdt {
		table_virt(xsdt_address)
	} else {
		table_virt(u64(read_u32(rsdp, 16)))
	}

	length := read_u32(root, 4)
	if length <= 36 {
		return none
	}
	pointer_width := u32(if use_xsdt { 8 } else { 4 })
	count := (length - 36) / pointer_width

	for i := u32(0); i < count; i++ {
		offset := u64(36) + u64(i) * u64(pointer_width)
		entry := if use_xsdt {
			read_u64(root, offset)
		} else {
			u64(read_u32(root, offset))
		}
		if entry == 0 {
			continue
		}
		candidate := table_virt(entry)
		if signature_at(candidate, signature) {
			return AcpiTable{
				base:   candidate
				length: read_u32(candidate, 4)
			}
		}
	}
	return none
}

// Read SRAT and SLIT. Returns the number of nodes found, or zero when this
// machine has no ACPI tables or its SRAT places nothing.
fn discover_acpi() int {
	srat := find_acpi_table('SRAT') or { return 0 }
	if srat.length <= 48 {
		return 0
	}
	base := srat.base
	end := u64(srat.length)

	// Entries begin after the 36-byte description header and SRAT's own twelve
	// reserved bytes.
	mut offset := u64(48)
	mut placed_cpus := 0
	mut placed_ranges := 0
	mut saw_gicc_affinity := false

	for offset + 2 <= end {
		kind := read_u8(base, offset)
		length := u64(read_u8(base, offset + 1))
		if length < 2 || offset + length > end {
			break
		}

		match kind {
			srat_processor_apic {
				if length >= 16 && (read_u32(base, offset + 4) & srat_enabled) != 0 {
					// The proximity domain is split in two by history: a low
					// byte right after the header, three high bytes late in the
					// structure. The high bytes are zero on anything that
					// predates ACPI 3.0, which is what makes that safe.
					low := u32(read_u8(base, offset + 2))
					mut high := u32(0)
					for i := u64(0); i < 3; i++ {
						high |= u32(read_u8(base, offset + 9 + i)) << u32(8 + i * 8)
					}
					id := intern_domain(low | high)
					if id >= 0 {
						add_hw_cpu(u64(read_u8(base, offset + 3)), id)
						placed_cpus++
					}
				}
			}
			srat_processor_x2apic {
				if length >= 16 && (read_u32(base, offset + 12) & srat_enabled) != 0 {
					id := intern_domain(read_u32(base, offset + 4))
					if id >= 0 {
						add_hw_cpu(u64(read_u32(base, offset + 8)), id)
						placed_cpus++
					}
				}
			}
			srat_gicc {
				if length >= 18 && (read_u32(base, offset + 10) & srat_enabled) != 0 {
					id := intern_domain(read_u32(base, offset + 2))
					if id >= 0 {
						// An ACPI processor UID, not an MPIDR. The MADT holds
						// the translation, and is read once below.
						add_acpi_uid(read_u32(base, offset + 6), id)
						saw_gicc_affinity = true
						placed_cpus++
					}
				}
			}
			srat_memory {
				if length >= 40 && (read_u32(base, offset + 28) & srat_enabled) != 0 {
					low_base := u64(read_u32(base, offset + 8))
					high_base := u64(read_u32(base, offset + 12))
					low_size := u64(read_u32(base, offset + 16))
					high_size := u64(read_u32(base, offset + 20))
					size := (high_size << 32) | low_size
					id := intern_domain(read_u32(base, offset + 2))
					if id >= 0 && size != 0 {
						add_node_range(id, (high_base << 32) | low_base, size)
						placed_ranges++
					}
				}
			}
			else {}
		}

		offset += length
	}

	if placed_cpus == 0 && placed_ranges == 0 {
		numa_node_count = 0
		numa_hw_count = 0
		numa_uid_count = 0
		return 0
	}

	if saw_gicc_affinity {
		resolve_acpi_uids()
	}
	read_acpi_distances()
	return numa_node_count
}

// ── ACPI processor UIDs ─────────────────────────────────────────────────────
//
// On ARM, SRAT places a CPU by its ACPI processor UID, while smp knows it by
// its MPIDR. The MADT's GIC CPU Interface structures carry both, so the UIDs
// are collected first and translated once the MADT has been read.

__global (
	numa_uid_count = int(0)
	numa_uids      [max_cpu_slots]u32
	numa_uid_nodes [max_cpu_slots]int
)

fn add_acpi_uid(uid u32, node int) {
	if numa_uid_count == max_cpu_slots {
		return
	}
	for i := 0; i < numa_uid_count; i++ {
		if numa_uids[i] == uid {
			numa_uid_nodes[i] = node
			return
		}
	}
	numa_uids[numa_uid_count] = uid
	numa_uid_nodes[numa_uid_count] = node
	numa_uid_count++
}

fn resolve_acpi_uids() {
	madt := find_acpi_table('APIC') or { return }
	if madt.length <= 44 {
		return
	}
	base := madt.base
	end := u64(madt.length)

	// Entries begin after the header, the local controller address and the flags.
	mut offset := u64(44)
	for offset + 2 <= end {
		kind := read_u8(base, offset)
		length := u64(read_u8(base, offset + 1))
		if length < 2 || offset + length > end {
			break
		}
		// A GICC structure is 80 bytes in ACPI 6.0, with the processor UID at
		// offset 8 and MPIDR at 68. An older, shorter revision has no MPIDR to
		// read, and a CPU whose UID cannot be translated just stays unplaced.
		if kind == madt_gicc && length >= 76 {
			uid := read_u32(base, offset + 8)
			mpidr := read_u64(base, offset + 68) & mpidr_affinity_mask
			for i := 0; i < numa_uid_count; i++ {
				if numa_uids[i] == uid {
					add_hw_cpu(mpidr, numa_uid_nodes[i])
					break
				}
			}
		}
		offset += length
	}
}

// ── SLIT ────────────────────────────────────────────────────────────────────

// A square matrix of one-byte distances, indexed by proximity domain rather
// than by this kernel's dense node numbering.
fn read_acpi_distances() {
	slit := find_acpi_table('SLIT') or { return }
	if slit.length <= 44 {
		return
	}
	localities := read_u64(slit.base, 36)
	if localities == 0 || localities > 256 {
		return
	}
	if u64(slit.length) < 44 + localities * localities {
		return
	}

	for a := u64(0); a < localities; a++ {
		node_a := node_of_domain(u32(a))
		if node_a < 0 {
			continue
		}
		for b := u64(0); b < localities; b++ {
			node_b := node_of_domain(u32(b))
			if node_b < 0 {
				continue
			}
			value := read_u8(slit.base, 44 + a * localities + b)
			if value == 0 || value == 255 {
				continue
			}
			set_distance(node_a, node_b, value)
		}
	}
}
