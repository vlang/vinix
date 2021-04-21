module x86

[packed]
struct GDTPointer {
	size    u16
	address voidptr
}

[packed]
struct GDTEntry {
	limit       u16
	base_low16  u16
	base_mid8   byte
	access      byte
	granularity byte
	base_high8  byte
}

// FIXME: Using this 2 globals as const will generate a runtime dependency on
// vinit, which we cannot call since vinit depends on malloc and other utilities
// not available in freestanding.
__global (
	kernel_code_seg = u16(0x28)
)

__global (
	kernel_data_seg = u16(0x30)
)

__global (
	gdt_pointer GDTPointer
)

__global (
	gdt_entries [9]GDTEntry
)

pub fn gdt_init() {
	// Initialize all the GDT entries.
	// Null descriptor.
	gdt_entries[0] = GDTEntry{
		limit: 0
		base_low16: 0
		base_mid8: 0
		access: 0
		granularity: 0
		base_high8: 0
	}

	// The following entries allow us to use the stivale2 terminal

	// Ring 0 16 bit code.
	gdt_entries[1] = GDTEntry{
		limit: 0xffff
		base_low16: 0
		base_mid8: 0
		access: 0b10011010
		granularity: 0b00000000
		base_high8: 0
	}

	// Ring 0 16 bit data.
	gdt_entries[2] = GDTEntry{
		limit: 0xffff
		base_low16: 0
		base_mid8: 0
		access: 0b10010010
		granularity: 0b00000000
		base_high8: 0
	}

	// Ring 0 32 bit code.
	gdt_entries[3] = GDTEntry{
		limit: 0xffff
		base_low16: 0
		base_mid8: 0
		access: 0b10011010
		granularity: 0b11001111
		base_high8: 0
	}

	// Ring 0 32 bit data.
	gdt_entries[4] = GDTEntry{
		limit: 0xffff
		base_low16: 0
		base_mid8: 0
		access: 0b10010010
		granularity: 0b11001111
		base_high8: 0
	}

	// Kernel 64 bit code.
	gdt_entries[5] = GDTEntry{
		limit: 0
		base_low16: 0
		base_mid8: 0
		access: 0b10011010
		granularity: 0b00100000
		base_high8: 0
	}

	// Kernel 64 bit data.
	gdt_entries[6] = GDTEntry{
		limit: 0
		base_low16: 0
		base_mid8: 0
		access: 0b10010010
		granularity: 0b00000000
		base_high8: 0
	}

	// User 64 bit data.
	gdt_entries[7] = GDTEntry{
		limit: 0
		base_low16: 0
		base_mid8: 0
		access: 0b11110010
		granularity: 0
		base_high8: 0
	}

	// User 64 bit code.
	gdt_entries[8] = GDTEntry{
		limit: 0
		base_low16: 0
		base_mid8: 0
		access: 0b11111010
		granularity: 0b00100000
		base_high8: 0
	}

	// Set the GDT pointer for load.
	gdt_pointer = GDTPointer{
		size: u16(sizeof(GDTPointer) * 9 - 1)
		address: &gdt_entries
	}

	// Random ASM vomit.
	asm amd64 {
		lgdt [ptr]
		push rax
		push cseg
		lea rax, [rip + reentry]
		push rax
		.short 0xcb48 // V does not have REX.W + retf, this is the opcode.
		reentry:
		pop rax
		mov ds, dseg
		mov es, dseg
		mov fs, dseg
		mov gs, dseg
		mov ss, dseg
		; ; r (&gdt_pointer) as ptr
		  rm (kernel_code_seg) as cseg
		  rm (kernel_data_seg) as dseg
		; memory
	}
}
