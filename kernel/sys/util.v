module sys

import debug

struct PtrHack {
	lol int
}

const (
	null = 0
	nullptr = voidptr(0)
)

[inline]
fn printk(str string) {
	debug.printk(str)
}

pub fn uni_to_ascii(runes voidptr, out byteptr) {
	mut c := *(&u16(runes))
	mut idx := 0

	for c != u16(0) {
		memput(voidptr(out), idx, byte(c))

		idx++
		c = *(&u16(runes + idx * 2))
	}
}

[inline]
pub fn phys_to_virtual(addr voidptr) voidptr {
	return voidptr(PHYS_BASE + u64(addr))
}

[inline]
pub fn phys_virt_offset(addr voidptr, offset i64) voidptr {
	return voidptr(i64(PHYS_BASE) + i64(addr) + offset)
}