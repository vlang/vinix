module trace

pub fn address(addr u64) (u64, Symbol) {
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

pub fn address_print(addr u64) {
	off, sym := address(addr)
	C.printf(c'  [0x%llx] <%s+0x%llx>\n', addr, sym.name.str, off)
}

pub fn stacktrace(_base_ptr voidptr) {
	mut base_ptr := &u64(_base_ptr)

	if voidptr(base_ptr) == voidptr(0) {
		asm volatile amd64 {
			mov base_ptr, rbp
			; =r (base_ptr)
		}
	}

	C.printf(c'Stacktrace:\n')

	for i := 0; i < 50; i++ {
		unsafe {
			old_bp := base_ptr[0]
			ret_addr := base_ptr[1]
			if ret_addr == 0 {
				break
			}
			address_print(ret_addr)
			if old_bp == 0 {
				break
			}
			base_ptr = &u64(old_bp)
		}
	}
}
