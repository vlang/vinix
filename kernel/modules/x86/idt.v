module x86

import lib

[packed]
struct IDTPointer {
	size    u16
	address voidptr
}

[packed]
struct IDTEntry {
	offset_low u16
	selector   u16
	ist        byte
	flags      byte
	offset_mid u16
	offset_hi  u32
	reserved   u32
}

__global (
	idt_pointer IDTPointer
)

__global (
	idt_entries [256]IDTEntry
)

pub fn idt_init() {
	// Register the common exceptions.
	idt_register_handler(0x0, &generic_exception, 0)
	idt_register_handler(0x1, &generic_exception, 0)
	idt_register_handler(0x2, &generic_exception, 0)
	idt_register_handler(0x3, &generic_exception, 0)
	idt_register_handler(0x4, &generic_exception, 0)
	idt_register_handler(0x5, &generic_exception, 0)
	idt_register_handler(0x6, &generic_exception, 0)
	idt_register_handler(0x7, &generic_exception, 0)
	idt_register_handler(0x8, &generic_exception, 0)
	idt_register_handler(0x9, &generic_exception, 0)
	idt_register_handler(0xa, &generic_exception, 0)
	idt_register_handler(0xb, &generic_exception, 0)
	idt_register_handler(0xc, &generic_exception, 0)
	idt_register_handler(0xd, &generic_exception, 0)
	idt_register_handler(0xe, &generic_exception, 0)

	idt_register_handler(0x10, &generic_exception, 0)
	idt_register_handler(0x11, &generic_exception, 0)
	idt_register_handler(0x12, &generic_exception, 0)
	idt_register_handler(0x13, &generic_exception, 0)
	idt_register_handler(0x14, &generic_exception, 0)
	idt_register_handler(0x1e, &generic_exception, 0)

	// Load IDT.
	idt_pointer = IDTPointer{
		size: u16((sizeof(IDTEntry) * 256) - 1)
		address: &idt_entries
	}

	asm amd64 {
		lidt ptr
		; ; m (idt_pointer) as ptr
		; memory
	}
}

pub fn idt_register_handler(num byte, callback voidptr, ist byte) {
	address := u64(callback)
	idt_entries[num] = IDTEntry{
		offset_low: u16(address)
		selector: kernel_code_seg
		ist: ist
		flags: 0x8e
		offset_mid: u16(address >> 16)
		offset_hi: u32(address >> 32)
		reserved: 0
	}
}

fn generic_exception() {
	lib.kpanic('Unhandled exception triggered')
}
