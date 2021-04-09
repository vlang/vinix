module lib

// One could use the builtin panic, but it again uses runtime
// services.

pub fn printline(message ...string) {
	for m in message {
		outb_puts(m)
	}
	outb_puts('\n')
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
