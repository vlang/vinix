module x86

import lib
import klock

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
	idt_entries [256]IDTEntry
	idt_free_vector = byte(32)
	idt_lock klock.Lock
)

pub fn idt_allocate_vector() byte {
	idt_lock.acquire()
	ret := idt_free_vector++
	idt_lock.release()
	return ret
}

pub fn idt_init() {
	for i := u16(0); i < 256; i++ {
		idt_register_handler(i, &generic_exception, 0)
	}

	idt_reload()
}

pub fn idt_reload() {
	idt_pointer = IDTPointer{
		size: u16((sizeof(IDTEntry) * 256) - 1)
		address: &idt_entries
	}

	asm amd64 {
		lidt ptr
		;
		; m (idt_pointer) as ptr
		; memory
	}
}

pub fn idt_register_handler(vector u16, handler voidptr, ist byte) {
	address := u64(handler)

	idt_entries[vector] = IDTEntry{
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
