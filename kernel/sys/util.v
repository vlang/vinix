module sys

struct PtrHack {
	lol int
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