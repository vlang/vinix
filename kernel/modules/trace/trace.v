[manualfree] module trace

pub fn stacktrace(_base_ptr voidptr) {
	mut base_ptr := &u64(_base_ptr)

	if voidptr(base_ptr) == voidptr(0) {
		asm volatile amd64 {
			mov base_ptr, rbp
			; =rm (base_ptr)
		}
	}

	C.printf(c'Stacktrace:\n')

	for {
		unsafe {
			old_bp := base_ptr[0]
			ret_addr := base_ptr[1]
			if ret_addr == 0 {
				break
			}
			C.printf(c'\t0x%llx\n', ret_addr)
			if old_bp == 0 {
				break
			}
			base_ptr = &u64(old_bp)
		}
	}
}
