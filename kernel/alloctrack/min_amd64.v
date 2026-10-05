module alloctrack

fn kernel_address_min() u64 {
	mut control := u64(0)
	asm volatile amd64 {
		mov control, cr4
		; =r (control)
		; ; memory
	}
	return if (control & (u64(1) << 12)) != 0 { u64(0xff00000000000000) } else { u64(0xffff800000000000) }
}
