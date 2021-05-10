module acpi

pub struct SDT {
	signature        [4]byte
	length           u32
	revision         byte
	checksum         byte
	oem_id           [6]byte
	oem_table_id     [8]byte
	oem_revision     u32
	creator_id       u32
	creator_revision u32
}

pub struct RSDP {
	signature    [8]byte
	checksum     byte
	oem_id       [6]byte
	revision     byte
	rsdt_addr    u32
	length       u32
	xsdt_addr    u64
	ext_checksum byte
	reserved     [3]byte
}

struct RSDT {
	header     SDT
	ptrs_start byte
}

__global (
	rsdp &RSDP
	rsdt &RSDT
)

fn use_xsdt() bool {
	return rsdp.revision >= 2 && rsdp.xsdt_addr != 0
}

pub fn init(rsdp_ptr &RSDP) {
	if rsdp_ptr == 0 {
		panic('acpi: ACPI not supported on this machine.')
	}

	rsdp = unsafe { rsdp_ptr }

	oem := C.byteptr_vstring_with_len(byteptr(&rsdp.oem_id), 6)

	if use_xsdt() == true {
		rsdt = unsafe { &RSDT(byteptr(size_t(rsdp.xsdt_addr)) + higher_half) }
	} else {
		rsdt = unsafe { &RSDT(byteptr(size_t(rsdp.rsdt_addr)) + higher_half) }
	}

	println('acpi: Revision:  ${rsdp.revision}')
	println('acpi: OEM ID:    ${oem}')
	println('acpi: Use XSDT:  ${use_xsdt()}')
	println('acpi: R/XSDT at: 0x${voidptr(rsdt):x}')

	// We won't support HW reduced ACPI systems
	fadt := find_sdt('FACP', 0)
	if fadt != 0 && &SDT(fadt).length >= 116 {
		fadt_flags := unsafe { (&u32(fadt))[28] }
		if fadt_flags & (1 << 20) != 0 {
			panic('acpi: OS does not support HW reduced ACPI systems.')
		}
	}

	madt_init()
}

pub fn find_sdt(signature string, index int) voidptr {
	mut count := 0

	entry_count := (rsdt.header.length - sizeof(SDT)) / u32(if use_xsdt() { 8 } else { 4 })

	for i := 0; i < entry_count; i++ {
		ptr := if use_xsdt() == true {
			unsafe { &SDT(byteptr(size_t(&u64(&rsdt.ptrs_start)[i])) + higher_half) }
		} else {
			unsafe { &SDT(byteptr(size_t(&u32(&rsdt.ptrs_start)[i])) + higher_half) }
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

	println('acpi: "${signature}" not found')
	return 0
}
