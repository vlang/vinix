module init

const (
	PHYS_BASE = 0xfffffeff00000000
)

fn main() {
	// uck v
}

fn kmain() {
	mut vga_base := byteptr(PHYS_BASE + u64(0xb8000))
	text := 'Hello from bare-metal V world!'

	for i := 0; i < text.len; i++ {
		vga_base[i * 2] = byteptr(text[i])
	}

	for {

	}
}