module initramfs

fn C.aarch64__uart__putc(c u8)

fn uart_putc(c u8) {
	C.aarch64__uart__putc(c)
}
