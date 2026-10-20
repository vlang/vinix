@[has_globals]
module uart

// Early discovery precedes _vinit; it must not reset this state afterwards.
@[cinit]
__global (
	uart_base = u64(0) // HHDM-mapped UART base address
	uart_tx_failed = false
)

// Initialise the PL011 UART with a virtual (HHDM-mapped) base address.
pub fn initialise(virt_base u64) {
	uart_base = virt_base
	uart_tx_failed = false
}

// Try to read a character from the UART. Returns -1 if no data available.
pub fn getc() int {
	if uart_base == 0 {
		return -1
	}
	fr := read_register(0x18)
	if fr & 0x10 != 0 {
		return -1 // RX FIFO empty
	}
	return int(read_register(0x00) & 0xff)
}

pub fn get_base() u64 {
	return uart_base
}

// Write to UARTDR with a single UARTFR read (no loop). Used as HVF workaround.
// Both the read and write are MMIO operations that force HVF vmexits.
pub fn putc_raw(c u8) {
	if uart_base == 0 {
		return
	}
	// Read UARTFR (MMIO read → HVF trap)
	fr := read_register(0x18)
	_ = fr
	// Write UARTDR (MMIO write → HVF trap)
	write_register(0x00, u32(c))
	// Compiler barrier
	tx_relax()
}

// Keep the C ABI name used by the early console and initramfs bridges stable.
@[export: 'aarch64__uart__putc']
pub fn putc(c u8) {
	if uart_base == 0 || uart_tx_failed {
		return
	}
	// Wait until TX FIFO is not full.
	// The compiler barrier (asm volatile with memory clobber) is essential:
	// without it, -O2 optimizes the MMIO re-read into a dead spin because
	// V's unsafe pointer dereference generates a non-volatile C load.
	for poll := 0; poll < 65536; poll++ {
		fr := read_register(0x18)
		if fr == u32(0xffffffff) {
			break
		}
		if fr & 0x20 == 0 {
			write_register(0x00, u32(c))
			return
		}
		tx_relax()
	}
	// Keep the base for RX and mapping, but never stall on every later byte.
	uart_tx_failed = true
}

pub fn puts(s charptr) {
	if uart_base == 0 {
		return
	}
	mut p := s
	for unsafe { *p } != 0 {
		c := u8(unsafe { *p })
		if c == u8(`\n`) {
			putc(u8(`\r`))
		}
		putc(c)
		p = charptr(u64(p) + 1)
	}
}

pub fn put_hex(val u64) {
	puts(c'0x')
	if val == 0 {
		putc(u8(`0`))
		return
	}
	hex_chars := c'0123456789abcdef'
	mut started := false
	for i := 60; i >= 0; i -= 4 {
		nibble := u8((val >> u64(i)) & 0xf)
		if nibble != 0 || started {
			started = true
			putc(u8(unsafe { *(charptr(u64(hex_chars) + u64(nibble))) }))
		}
	}
}

pub fn put_dec(val u64) {
	if val == 0 {
		putc(u8(`0`))
		return
	}
	mut buf := [20]u8{}
	mut pos := 19
	mut v := val
	for v > 0 {
		buf[pos] = u8(v % 10) + u8(`0`)
		v /= 10
		pos--
	}
	for i := pos + 1; i <= 19; i++ {
		putc(buf[i])
	}
}

pub fn write(s charptr, len u64) {
	if uart_base == 0 {
		return
	}
	for i := u64(0); i < len; i++ {
		c := u8(unsafe { *(charptr(u64(s) + i)) })
		if c == u8(`\n`) {
			putc(u8(`\r`))
		}
		putc(c)
	}
}
