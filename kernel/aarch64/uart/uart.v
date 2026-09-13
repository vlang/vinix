@[has_globals]
module uart

// PL011 UART registers (offsets from base)
const uartdr = u64(0x00) // Data register
const uartfr = u64(0x18) // Flag register
const uartfr_txff = u8(0x20) // TX FIFO full (bit 5)
const uartfr_rxfe = u8(0x10) // RX FIFO empty (bit 4)

__global (
	uart_base = u64(0) // HHDM-mapped UART base address
)

// Initialise the PL011 UART with a virtual (HHDM-mapped) base address.
pub fn initialise(virt_base u64) {
	uart_base = virt_base
}

// Try to read a character from the UART. Returns -1 if no data available.
pub fn getc() int {
	if uart_base == 0 {
		return -1
	}
	fr := unsafe { *&u8(uart_base + uartfr) }
	if fr & uartfr_rxfe != 0 {
		return -1 // RX FIFO empty
	}
	return int(unsafe { *&u8(uart_base + uartdr) })
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
	fr := unsafe { *&u8(uart_base + uartfr) }
	_ = fr
	// Write UARTDR (MMIO write → HVF trap)
	unsafe {
		*&u8(uart_base + uartdr) = c
	}
	// Compiler barrier
	asm volatile aarch64 {
		yield
		; ; ; memory
	}
}

pub fn putc(c u8) {
	if uart_base == 0 {
		return
	}
	// Wait until TX FIFO is not full.
	// The compiler barrier (asm volatile with memory clobber) is essential:
	// without it, -O2 optimizes the MMIO re-read into a dead spin because
	// V's unsafe pointer dereference generates a non-volatile C load.
	for {
		fr := unsafe { *&u8(uart_base + uartfr) }
		if fr & uartfr_txff == 0 {
			break
		}
		asm volatile aarch64 {
			yield
			; ; ; memory
		}
	}
	unsafe {
		*&u8(uart_base + uartdr) = c
	}
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
