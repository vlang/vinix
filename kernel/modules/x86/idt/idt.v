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
	idt_pointer     IDTPointer
	idt_entries     [256]IDTEntry
	idt_free_vector = byte(32)
	idt_lock        klock.Lock
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
	interrupt_table  [256]voidptr
)

#include <symbols.h>

fn C.interrupt_thunk_begin()
fn C.interrupt_thunk_storage()
fn C.interrupt_thunk_offset()
fn C.interrupt_thunk_size()
fn C.interrupt_thunk_number()

fn prepare_interrupt_thunks() {
	v_interrupt_thunk_begin := voidptr(C.interrupt_thunk_begin)
	v_interrupt_thunk_storage := u64(C.interrupt_thunk_storage)
	v_interrupt_thunk_offset := &u64(C.interrupt_thunk_offset)
	v_interrupt_thunk_size := u64(C.interrupt_thunk_size)
	v_interrupt_thunk_number := &u32(C.interrupt_thunk_number)

	unsafe {
		for i := u64(0); i < interrupt_table.len; i++ {
			*v_interrupt_thunk_offset = u64(&interrupt_table[i])
			*v_interrupt_thunk_number = u32(i)
			ptr := &byte(v_interrupt_thunk_storage + v_interrupt_thunk_size * i)

			C.memcpy(ptr, v_interrupt_thunk_begin, v_interrupt_thunk_size)
			shift := match i {
				8, 10, 11, 12, 13, 14, 17, 30 { 2 }
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
		; ; m (idt_pointer) as ptr
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
