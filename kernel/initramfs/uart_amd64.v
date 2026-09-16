module initramfs

import dev.serial

fn uart_putc(c u8) {
	serial.out(c)
}
