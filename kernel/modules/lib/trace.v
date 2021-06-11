module lib

pub fn trace_address(addr u64) (u64, Symbol) {
	mut prev_sym := Symbol{}

	for sym in symbol_table {
		if sym.address >= addr {
			offset := addr - prev_sym.address
			return offset, prev_sym
		}

		prev_sym = sym
	}

	return 0, prev_sym
}

pub fn print_stacktrace() {
	mut base_ptr := &u64(0)

	asm volatile amd64 {
		mov base_ptr, rbp
		; =r (base_ptr)
	}
	C.printf(c'Stacktrace:')

	for {
		unsafe {
			old_bp := base_ptr[0]
			ret_addr := base_ptr[1]
			if ret_addr == 0 {
				break
			}
			off, sym := trace_address(ret_addr)
			C.printf(c'  [0x%llx] <%s+0x%llx>\n', ret_addr, sym.name.str, off)
			if old_bp == 0 {
				break
			}
			base_ptr = &u64(old_bp)
		}
	}
}
