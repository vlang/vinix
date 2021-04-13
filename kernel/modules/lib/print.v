module lib

import stivale2

pub fn kprint(message string) {
	for i := 0; i < message.len; i++ {
		asm volatile amd64 {
			out port, c
			; ; Nd (0xe9) as port
			  a (message[i]) as c
		}
	}

	stivale2.terminal_print(message)
}
