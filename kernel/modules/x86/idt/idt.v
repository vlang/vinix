module idt

import klock

[packed]
struct IDTPointer {
	size    u16
	address voidptr
}

[packed]
struct IDTEntry {
pub mut:
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

pub fn allocate_vector() byte {
	idt_lock.acquire()
	ret := idt_free_vector++
	idt_lock.release()
	return ret
}

__global (
	interrupt_thunks [256]voidptr
	interrupt_table [256]voidptr
)

fn C.prepare_interrupt_thunks()

pub fn initialise() {
	C.prepare_interrupt_thunks()

	reload()
}

pub fn reload() {
	idt_pointer = IDTPointer{
		size: u16((sizeof(IDTEntry) * 256) - 1)
		address: &idt_entries
	}

	asm volatile amd64 {
		lidt ptr
		;
		; m (idt_pointer) as ptr
		; memory
	}
}

pub fn set_ist(vector u16, ist u8) {
	idt_entries[vector].ist = ist
}

pub fn register_handler(vector u16, handler voidptr) {
	address := u64(handler)

	idt_entries[vector] = IDTEntry{
		offset_low: u16(address)
		selector: kernel_code_seg
		ist: 0
		flags: 0x8e
		offset_mid: u16(address >> 16)
		offset_hi: u32(address >> 32)
		reserved: 0
	}
}
