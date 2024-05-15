// trace.v: Stack tracing for debug prints.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module trace

#include <symbols.h>

pub struct Symbol {
pub mut:
	address u64
	name    charptr
}

fn C.get_symbol_table() voidptr

fn C.printf_panic(charptr, ...voidptr)

pub fn address(addr u64) ?(u64, &Symbol) {
	mut prev_sym := &Symbol(unsafe { nil })

	symbol_table := unsafe { &Symbol(C.get_symbol_table()) }

	for i := u64(0); true; i++ {
		if unsafe { symbol_table[i].address } == 0xffffffffffffffff {
			return none
		}

		if unsafe { symbol_table[i].address } >= addr {
			offset := addr - prev_sym.address
			return offset, prev_sym
		}

		prev_sym = unsafe { &symbol_table[i] }
	}

	return none
}

pub fn address_print(addr u64) ? {
	off, sym := address(addr) or { return none }
	C.printf_panic(c'  [0x%llx] <%s+0x%llx>\n', addr, sym.name, off)
}

pub fn stacktrace(_base_ptr u64) {
	mut base_ptr := _base_ptr

	if base_ptr == 0 {
		asm volatile amd64 {
			mov base_ptr, rbp
			; =g (base_ptr)
			; ; memory
		}
	}

	if base_ptr == 0 {
		return
	}

	for {
		unsafe {
			old_bp := (&u64(base_ptr))[0]
			ret_addr := (&u64(base_ptr))[1]
			if ret_addr == 0 || old_bp == 0 {
				break
			}
			address_print(ret_addr) or { break }
			base_ptr = old_bp
		}
	}
}
