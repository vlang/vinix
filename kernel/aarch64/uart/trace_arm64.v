module uart

// Preserve the original bounded decimal trace, including its seven-digit cap.
@[export: 'trace_syscall_nr']
pub fn trace_syscall_nr(number usize) {
	unsafe {
		putc(u8(`S`))
		putc(u8(`C`))
		putc(u8(`:`))
		mut buffer := [8]u8{}
		mut count := 0
		if number == 0 {
			buffer[count] = u8(`0`)
			count++
		} else {
			mut remaining := number
			for remaining > 0 && count < 7 {
				buffer[count] = u8(`0`) + u8(remaining % 10)
				count++
				remaining /= 10
			}
		}
		for count > 0 {
			count--
			putc(buffer[count])
		}
		putc(u8(` `))
	}
}
