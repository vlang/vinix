module uart

// PL011/SBSA registers support word accesses. Keep the MMIO boundary separate
// so host fixtures can exercise the actual polled driver with fake registers.
fn read_register(offset u64) u32 {
	value := unsafe { *&u32(uart_base + offset) }
	tx_relax()
	return value
}

fn write_register(offset u64, value u32) {
	unsafe { *&u32(uart_base + offset) = value }
	tx_relax()
}

fn tx_relax() {
	asm volatile aarch64 {
		yield
		; ; ; memory
	}
}
