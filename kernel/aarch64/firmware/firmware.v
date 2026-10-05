// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What an arm64 UEFI machine says about itself in its ACPI tables: which
// virtual machine it is, and where its interrupt controller, console UART and
// PCIe configuration space are.
//
// Apple hardware has no ACPI and is described by its device tree instead, so
// everything here returns none there. QEMU's virt machine and VirtualBox both
// boot through UEFI and hand over ACPI but no device tree.
//
// Every field is read byte-wise: ACPI tables are packed, and an unaligned
// multi-byte load is not something to find out about on aarch64 at runtime.
@[has_globals]
module firmware

import limine
import memory

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile firmware_rsdp_req = limine.LimineRSDPRequest{
		response: unsafe { nil }
	}
)

// MADT structure types.
const madt_gicd = u8(0xc)
const madt_gicr = u8(0xe)
const madt_gicc = u8(0xb)
const madt_its = u8(0xf)

// SPCR interface types that are a PL011 register-wise.
const spcr_pl011 = u8(3)
const spcr_sbsa = u8(0xe)

pub struct Gic {
pub:
	// Physical addresses. `redist` is the start of the redistributor frames,
	// one after another in CPU order, and `redist_len` how far they reach.
	dist       u64
	redist     u64
	redist_len u64
	its        u64
	// 3 or 4; 0 when the MADT does not say.
	version u8
}

pub struct Ecam {
pub:
	base      u64
	start_bus u8
	end_bus   u8
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

// Limine reports the RSDP by the address the firmware used and the tables by
// physical address; which one arrives depends on its revision.
fn table_virt(address u64) u64 {
	offset := memory.get_hhdm_offset()
	if address >= offset {
		return address
	}
	return address + offset
}

fn signature_at(base u64, signature string) bool {
	for i := 0; i < 4; i++ {
		if read_u8(base, u64(i)) != signature[i] {
			return false
		}
	}
	return true
}

// The RSDP as Limine reports it, or 0. Limine answers a request ID only once,
// so everything else on arm64 that wants the RSDP asks here.
pub fn rsdp_address() u64 {
	if firmware_rsdp_req.response == unsafe { nil } {
		return 0
	}
	return u64(firmware_rsdp_req.response.address)
}

// The XSDT, or the RSDT on an ACPI 1.0 machine, and the width of its entries.
fn root_table() (u64, u64) {
	rsdp := rsdp_address()
	if rsdp == 0 {
		return 0, 0
	}
	rsdp_virt := table_virt(rsdp)
	revision := read_u8(rsdp_virt, 15)
	if revision >= 2 {
		xsdt := read_u64(rsdp_virt, 24)
		if xsdt != 0 {
			return table_virt(xsdt), 8
		}
	}
	rsdt := u64(read_u32(rsdp_virt, 16))
	if rsdt == 0 {
		return 0, 0
	}
	return table_virt(rsdt), 4
}

pub fn has_acpi() bool {
	root, _ := root_table()
	return root != 0
}

// The first table with `signature`, as a virtual address.
pub fn find_table(signature string) ?u64 {
	root, width := root_table()
	if root == 0 || signature.len != 4 {
		return none
	}
	length := u64(read_u32(root, 4))
	for offset := u64(36); offset + width <= length; offset += width {
		address := if width == 8 { read_u64(root, offset) } else { u64(read_u32(root, offset)) }
		if address == 0 {
			continue
		}
		table := table_virt(address)
		if signature_at(table, signature) {
			return table
		}
	}
	return none
}

// The OEM ID of the root table, which names the firmware's author.
fn oem_starts_with(prefix string) bool {
	root, _ := root_table()
	if root == 0 {
		return false
	}
	for i := 0; i < prefix.len && i < 6; i++ {
		if read_u8(root, u64(10 + i)) != prefix[i] {
			return false
		}
	}
	return true
}

// QEMU's tables are all "BOCHS " / "BXPC".
pub fn is_qemu() bool {
	return oem_starts_with('BOCHS')
}

// VirtualBox's tables are "ORCLVB".
pub fn is_virtualbox() bool {
	return oem_starts_with('ORCLVB')
}

// The GIC as the MADT lays it out.
pub fn gic() ?Gic {
	madt := find_table('APIC')?
	length := u64(read_u32(madt, 4))
	mut dist := u64(0)
	mut redist := u64(0)
	mut redist_len := u64(0)
	mut gicc_count := u64(0)
	mut its := u64(0)
	mut version := u8(0)
	mut offset := u64(44)
	for offset + 2 <= length {
		kind := read_u8(madt, offset)
		size := u64(read_u8(madt, offset + 1))
		if size < 2 || offset + size > length {
			break
		}
		match kind {
			madt_gicd {
				if size >= 24 {
					dist = read_u64(madt, offset + 8)
					version = read_u8(madt, offset + 20)
				}
			}
			madt_gicr {
				if size >= 16 && redist_len == 0 {
					redist = read_u64(madt, offset + 4)
					redist_len = u64(read_u32(madt, offset + 12))
				}
			}
			madt_gicc {
				// Firmware that lists no GICR range gives each CPU's frame here
				// instead. The first CPU's is the start of the run.
				gicc_count++
				if size >= 68 && redist == 0 {
					redist = read_u64(madt, offset + 60)
				}
			}
			madt_its {
				if size >= 16 && its == 0 {
					its = read_u64(madt, offset + 8)
				}
			}
			else {}
		}
		offset += size
	}
	if dist == 0 || redist == 0 {
		return none
	}
	if redist_len == 0 {
		// Two 64 KiB frames, RD and SGI, per CPU.
		redist_len = gicc_count * 0x20000
	}
	return Gic{
		dist:       dist
		redist:     redist
		redist_len: redist_len
		its:        its
		version:    version
	}
}

// The console UART from the SPCR, if it is a PL011.
pub fn console_uart() ?u64 {
	spcr := find_table('SPCR')?
	if u64(read_u32(spcr, 4)) < 52 {
		return none
	}
	kind := read_u8(spcr, 36)
	if kind != spcr_pl011 && kind != spcr_sbsa {
		return none
	}
	// A Generic Address Structure: space, width, offset, access size, address.
	if read_u8(spcr, 40) != 0 {
		return none
	}
	address := read_u64(spcr, 44)
	if address == 0 {
		return none
	}
	return address
}

// The DSDT, through the FADT.
fn dsdt() ?u64 {
	fadt := find_table('FACP')?
	length := u64(read_u32(fadt, 4))
	mut address := u64(0)
	if length >= 148 {
		address = read_u64(fadt, 140)
	}
	if address == 0 {
		address = u64(read_u32(fadt, 40))
	}
	if address == 0 {
		return none
	}
	return table_virt(address)
}

// A PL011 the DSDT describes, for machines without an SPCR -- VirtualBox's.
// Rather than run AML, look for the device's _HID string, ARMH0011, and take
// the Memory32Fixed descriptor its _CRS starts with. QEMU and VirtualBox both
// describe the UART that way; anything else is left alone.
pub fn dsdt_pl011() ?u64 {
	table := dsdt()?
	length := u64(read_u32(table, 4))
	hid := 'ARMH0011'
	for offset := u64(36); offset + u64(hid.len) < length; offset++ {
		mut matched := true
		for i := 0; i < hid.len; i++ {
			if read_u8(table, offset + u64(i)) != hid[i] {
				matched = false
				break
			}
		}
		if !matched {
			continue
		}
		// Memory32Fixed: tag 0x86, length 9, then the read/write flag, the
		// base and the size.
		end := if offset + 256 < length { offset + 256 } else { length }
		for pos := offset + u64(hid.len); pos + 12 <= end; pos++ {
			if read_u8(table, pos) == 0x86 && read_u8(table, pos + 1) == 0x09
				&& read_u8(table, pos + 2) == 0 {
				base := u64(read_u32(table, pos + 4))
				if base != 0 {
					return base
				}
			}
		}
	}
	return none
}

// Segment 0's PCIe configuration space from the MCFG.
pub fn pcie_ecam() ?Ecam {
	mcfg := find_table('MCFG')?
	length := u64(read_u32(mcfg, 4))
	for offset := u64(44); offset + 16 <= length; offset += 16 {
		base := read_u64(mcfg, offset)
		segment := u32(read_u8(mcfg, offset + 8)) | (u32(read_u8(mcfg, offset + 9)) << 8)
		if base == 0 || segment != 0 {
			continue
		}
		return Ecam{
			base:      base
			start_bus: read_u8(mcfg, offset + 10)
			end_bus:   read_u8(mcfg, offset + 11)
		}
	}
	return none
}
