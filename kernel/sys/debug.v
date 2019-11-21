module sys

import io

pub fn printk(msg string) {
	for i := 0; i < msg.len; i++ {
		io.outb(0xe9, msg.str[i])
	}
	io.outb(0xe9, `\n`)
}