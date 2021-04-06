module lib

// One could use the builtin panic, but it again uses runtime
// services.

pub fn panic_kernel(message string) {
	outb_puts('PANIC: ')
	outb_puts(message)
	outb_puts('\n')
	for {}
}

fn outb_puts(message string) {
	for i := 0; i < message.len; i++ {
		asm amd64 {
			out port, c
			; ; Nd (0xe9) as port
			  a (message[i]) as c
		}
	}
}
