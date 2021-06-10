module gdt

import klock

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

__global (
	kernel_code_seg = u16(0x28)
	kernel_data_seg = u16(0x30)
	user_code_seg = u16(0x48)
	user_data_seg = u16(0x50)
	gdt_pointer     GDTPointer
	gdt_entries     [13]GDTEntry
)

__global (
	gdt_lock klock.Lock
)

pub fn initialise() {
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

	// Dummy entries
	gdt_entries[7] = GDTEntry{
		limit: 0
		base_low16: 0
		base_mid8: 0
		access: 0
		granularity: 0
		base_high8: 0
	}
	gdt_entries[8] = GDTEntry{
		limit: 0
		base_low16: 0
		base_mid8: 0
		access: 0
		granularity: 0
		base_high8: 0
	}

	// User 64 bit code.
	gdt_entries[9] = GDTEntry{
		limit: 0
		base_low16: 0
		base_mid8: 0
		access: 0b11111010
		granularity: 0b00100000
		base_high8: 0
	}

	// User 64 bit data.
	gdt_entries[10] = GDTEntry{
		limit: 0
		base_low16: 0
		base_mid8: 0
		access: 0b11110010
		granularity: 0
		base_high8: 0
	}

	reload()
}

pub fn reload() {
	gdt_pointer = GDTPointer{
		size: u16(sizeof(GDTPointer) * 13 - 1)
		address: &gdt_entries
	}

	asm volatile amd64 {
		lgdt ptr
		push rax
		push cseg
		lea rax, [rip + 0x03]
		push rax
		.short 0xcb48 // V does not have REX.W + retf, this is the opcode.
		pop rax
		mov ds, dseg
		mov es, dseg
		mov fs, dseg
		mov gs, dseg
		mov ss, dseg
		;
		; m (gdt_pointer) as ptr
		  rm (u64(kernel_code_seg)) as cseg
		  rm (u32(kernel_data_seg)) as dseg
		; memory
	}
}

pub fn load_tss(addr voidptr) {
	gdt_lock.acquire()

	gdt_entries[11] = GDTEntry{
		limit: u16(103)
		base_low16: u16(u64(addr))
		base_mid8: byte(u64(addr) >> 16)
		base_high8: byte(u64(addr) >> 24)
		access: 0b10001001
		granularity: 0b00000000
	}

	// High part of the GDT TSS entry, high 32 bits of base
	gdt_entries[12] = GDTEntry{
		limit: u16(u64(addr) >> 32)
		base_low16: u16(u64(addr) >> 48)
	}

	asm volatile amd64 {
		ltr offset
		;
		; rm (u16(0x58)) as offset
		; memory
	}

	gdt_lock.release()
}
