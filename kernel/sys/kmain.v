module sys

const (
	PHYS_BASE = 0xfffffeff00000000
)

fn C.memput(addr voidptr, off int, val byte)

pub fn kmain() {
	mut vga_base := voidptr(PHYS_BASE + u64(0xb8000))
	text := 'Hello from bare-metal V world!'

	for i := 0; i < text.len; i++ {
		memput(vga_base, i * 2, text.str[i])
	}

	for {
	}
}