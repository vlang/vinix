module pit

import kio

pub fn set_freq(freq u32) {
	println('pit: Setting frequency to ${freq} Hz')

	dividend := u32(1193182)

	mut ticks := dividend / freq
	if dividend % freq > freq / 2 {
		ticks++
	}

	kio.outb(0x40, byte(ticks))
	kio.outb(0x40, byte(ticks >> 8))
}
