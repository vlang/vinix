// acpi.v: Fetching of ACPI tables.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module acpi

import limine

pub struct SDT {
	signature        [4]u8
	length           u32
	revision         u8
	checksum         u8
	oem_id           [6]u8
	oem_table_id     [8]u8
	oem_revision     u32
	creator_id       u32
	creator_revision u32
}

pub struct RSDP {
	signature    [8]u8
	checksum     u8
	oem_id       [6]u8
	revision     u8
	rsdt_addr    u32
	length       u32
	xsdt_addr    u64
	ext_checksum u8
	reserved     [3]u8
}

struct RSDT {
	header     SDT
	ptrs_start u8
}

__global (
	rsdp &RSDP
	rsdt &RSDT
)

fn use_xsdt() bool {
	return rsdp.revision >= 2 && rsdp.xsdt_addr != 0
}

[cinit]
__global (
	volatile rsdp_req = limine.LimineRSDPRequest{
		response: 0
	}
)

pub fn initialise() {
	rsdp_ptr := rsdp_req.response.address

	if rsdp_ptr == 0 {
		panic('acpi: ACPI not supported on this machine.')
	}

	rsdp = unsafe { rsdp_ptr }

	if use_xsdt() == true {
		rsdt = unsafe { &RSDT(byteptr(usize(rsdp.xsdt_addr)) + higher_half) }
	} else {
		rsdt = unsafe { &RSDT(byteptr(usize(rsdp.rsdt_addr)) + higher_half) }
	}

	println('acpi: Revision:  ${rsdp.revision}')
	println('acpi: Use XSDT:  ${use_xsdt()}')
	println('acpi: R/XSDT at: 0x${voidptr(rsdt):x}')

	// We won't support HW reduced ACPI systems
	if fadt := find_sdt('FACP', 0) {
		if unsafe { &SDT(fadt).length >= 116 } {
			fadt_flags := unsafe { (&u32(fadt))[28] }
			if fadt_flags & (1 << 20) != 0 {
				panic('acpi: OS does not support HW reduced ACPI systems.')
			}
		}
	}

	madt_init()
}

pub fn find_sdt(signature string, index int) !voidptr {
	mut count := 0

	entry_count := (rsdt.header.length - sizeof(SDT)) / u32(if use_xsdt() { 8 } else { 4 })

	for i := 0; i < entry_count; i++ {
		ptr := if use_xsdt() == true {
			unsafe { &SDT(byteptr(usize(&u64(&rsdt.ptrs_start)[i])) + higher_half) }
		} else {
			unsafe { &SDT(byteptr(usize(&u32(&rsdt.ptrs_start)[i])) + higher_half) }
		}
		if unsafe { C.memcmp(voidptr(&ptr.signature), signature.str, 4) == 0 } {
			if count != index {
				count++
				continue
			}
			println('acpi: Found "${signature}" at 0x${voidptr(ptr):x}')
			return voidptr(ptr)
		}
	}

	return error('acpi: "${signature}" not found')
}
