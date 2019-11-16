module sys

pub fn printk(msg string) {
	for i := 0; i < text.len; i++ {
		outb(0xe9, text.str[i])
	}
}