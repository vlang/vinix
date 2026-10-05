module main

import katomic

struct Probe {
	value u64
}

fn C.vinix_consume(u16, voidptr)

fn main() {
	mut narrow := u16(0x55aa)
	small := katomic.load(&narrow)
	mut storage := Probe{value: 0x123456789abcdef0}
	mut slot := unsafe { &storage }
	loaded := katomic.load(&slot)
	C.vinix_consume(small, voidptr(loaded))
}
