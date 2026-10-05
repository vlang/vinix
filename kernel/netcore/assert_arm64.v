// SPDX-License-Identifier: GPL-2.0-or-later
module netcore

fn C.aarch64__uart__putc(u8)

fn uart_text(text &char) {
	unsafe { for p := text; *p != 0; p += 1 { C.aarch64__uart__putc(u8(*p)) }
	 }
}

fn assert_uart(message &char, file &char, line i32) {
	unsafe {
		mut number := [12]char{}
		mut n := line
		mut at := 11
		for {
			at--
			number[at] = char(48 + n % 10)
			n /= 10
			if n <= 0 || at == 0 { break }
		}
		uart_text(c"lwip: assertion '")
		uart_text(message)
		uart_text(c"' at ")
		uart_text(file)
		uart_text(c':')
		uart_text(&number[at])
		uart_text(c'\n')
	}
}
