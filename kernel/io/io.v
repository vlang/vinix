module io

fn C.outb(port u16, val byte)

fn C.outw(port u16, val u16)

fn C.outl(port u16, val u32)

fn C.inb(port u16) byte

fn C.inw(port u16) u16

fn C.inl(port u16) u32

pub fn outb(port u16, val byte) {
	C.outb(port, val)
}

pub fn outw(port u16, val u16) {
	C.outw(port, val)
}

pub fn outl(port u16, val u32) {
	C.outl(port, val)
}

pub fn inb(port u16) byte {
	return C.inb(port)
}

pub fn inw(port u16) u16 {
	return C.inw(port)
}

pub fn inl(port u16) u32 {
	return C.inl(port)
}