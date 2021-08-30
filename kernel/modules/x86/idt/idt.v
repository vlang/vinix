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
	if idt_free_vector == 0xf0 {
		panic('IDT exhausted')
	}
	ret := idt_free_vector++
	idt_lock.release()
	return ret
}

__global (
	interrupt_thunks [256]voidptr
	interrupt_table [256]voidptr
	interrupt_thunk_begin [1]voidptr
	interrupt_thunk_end [1]voidptr
	interrupt_thunk_storage [1]voidptr
	interrupt_thunk_offset u64
	interrupt_thunk_size u64
	interrupt_thunk_number u32
)

fn prepare_interrupt_thunks() {
	unsafe {
		for i in 0..interrupt_table.len {
			interrupt_thunk_offset = u64(&interrupt_table[i])
			interrupt_thunk_number = u32(i)
			ptr := &byte(u64(&interrupt_thunk_storage[0]) + u64(interrupt_thunk_size * u64(i)))

			C.memcpy(ptr, voidptr(&interrupt_thunk_begin[0]), interrupt_thunk_size)
			shift := match i {
				8 { 2 }
				10 { 2 }
				11 { 2 }
				12 { 2 }
				13 { 2 }
				14 { 2 }
				17 { 2 }
				30 { 2 }
				
				else { 0 }
			}

			interrupt_thunks[i] = ptr + u64(shift)
		}
	}
}

pub fn initialise() {
	prepare_interrupt_thunks()

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

pub fn set_ist(vector u16, ist byte) {
	idt_entries[vector].ist = ist
}

pub fn register_handler(vector u16, handler voidptr, ist byte, flags byte) {
	address := u64(handler)

	idt_entries[vector] = IDTEntry{
		offset_low: u16(address)
		selector: kernel_code_seg
		ist: ist
		flags: flags
		offset_mid: u16(address >> 16)
		offset_hi: u32(address >> 32)
		reserved: 0
	}
}
