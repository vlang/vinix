module trace

fn C.printf_panic(charptr, ...voidptr)

pub fn stacktrace(_base_ptr voidptr) {
	mut base_ptr := &u64(_base_ptr)

	if voidptr(base_ptr) == voidptr(0) {
		asm volatile amd64 {
			mov base_ptr, rbp
			; =rm (base_ptr)
		}
	}

	C.printf_panic(c'Stacktrace:\n')

	for {
		unsafe {
			old_bp := base_ptr[0]
			ret_addr := base_ptr[1]
			if ret_addr == 0 {
				break
			}
			C.printf_panic(c'\t0x%llx\n', voidptr(ret_addr))
			if old_bp == 0 {
				break
			}
			base_ptr = &u64(old_bp)
		}
	}
}
