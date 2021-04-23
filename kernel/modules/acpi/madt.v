module acpi

[packed]
struct MADT {
	header               SDT
	local_contoller_addr u32
	flags                u32
	entries_begin        byte
}

[packed]
struct MADTHeader {
	id     u8
	length u8
}

[packed]
struct MADTLocalApic {
	header       MADTHeader
	processor_id u8
	apic_id      u8
	flags        u32
}

[packed]
struct MADTIoApic {
	header   MADTHeader
	apic_id  u8
	reserved u8
	address  u32
	gsib     u32
}

[packed]
struct MADTISO {
	header     MADTHeader
	bus_source u8
	irq_source u8
	gsi        u32
	flags      u16
}

[packed]
struct MADTNMI {
	header    MADTHeader
	processor u8
	flags     u16
	lint      u8
}

__global (
	madt &MADT
	madt_local_apics []&MADTLocalApic
	madt_io_apics []&MADTIoApic
	madt_isos []&MADTISO
	madt_nmis []&MADTNMI
)

fn madt_init() {
	madt_local_apics = []&MADTLocalApic{}
	madt_io_apics = []&MADTIoApic{}
	madt_isos = []&MADTISO{}
	madt_nmis = []&MADTNMI{}

	madt := unsafe { &MADT(find_sdt('APIC', 0)) }
	mut current := u32(0)

	for {
		if current >= madt.header.length {
			break
		}

		header := unsafe { &MADTHeader(byteptr(&madt.entries_begin) + current) }

		match header.id {
			0 {
				println('acpi/madt: Found local APIC #${madt_local_apics.len}')
				madt_local_apics << unsafe { &MADTLocalApic(header) }
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

		current += u32(header.length)
	}
}
