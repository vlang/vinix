@[has_globals]
module acpi

@[packed]
struct MADT {
pub:
	header               SDT
	local_contoller_addr u32
	flags                u32
	entries_begin        u8
}

@[packed]
struct MADTHeader {
pub:
	id     u8
	length u8
}

@[packed]
struct MADTLocalApic {
pub:
	header       MADTHeader
	processor_id u8
	apic_id      u8
	flags        u32
}

@[packed]
struct MADTLocalX2Apic {
pub:
	header       MADTHeader
	reserved     [2]u8
	x2apic_id    u32
	flags        u32
	processor_id u32
}

@[packed]
struct MADTIoApic {
pub:
	header   MADTHeader
	apic_id  u8
	reserved u8
	address  u32
	gsib     u32
}

@[packed]
struct MADTISO {
pub:
	header     MADTHeader
	bus_source u8
	irq_source u8
	gsi        u32
	flags      u16
}

@[packed]
struct MADTNMI {
pub:
	header    MADTHeader
	processor u8
	flags     u16
	lint      u8
}

__global (
	madt               &MADT
	madt_local_apics   []&MADTLocalApic
	madt_local_x2apics []&MADTLocalX2Apic
	madt_io_apics      []&MADTIoApic
	madt_isos          []&MADTISO
	madt_nmis          []&MADTNMI
)

fn madt_init() {
	madt = unsafe { &MADT(find_sdt('APIC', 0) or { panic('System does not have a MADT') }) }

	mut current := u64(0)

	for {
		if current + (sizeof(MADT) - 1) >= madt.header.length {
			break
		}

		header := unsafe { &MADTHeader(u64(&madt.entries_begin) + current) }

		match header.id {
			0 {
				println('acpi/madt: Found local APIC #${madt_local_apics.len}')
				madt_local_apics << unsafe { &MADTLocalApic(header) }
			}
			9 {
				if x2apic_mode {
					println('acpi/madt: Found local x2APIC #${madt_local_x2apics.len}')
					madt_local_x2apics << unsafe { &MADTLocalX2Apic(header) }
				}
			}
			1 {
				println('acpi/madt: Found IO APIC #${madt_io_apics.len}')
				madt_io_apics << unsafe { &MADTIoApic(header) }
			}
			2 {
				println('acpi/madt: Found ISO #${madt_isos.len}')
				madt_isos << unsafe { &MADTISO(header) }
			}
			4 {
				println('acpi/madt: Found NMI #${madt_nmis.len}')
				madt_nmis << unsafe { &MADTNMI(header) }
			}
			else {}
		}

		current += u64(header.length)
	}
}
