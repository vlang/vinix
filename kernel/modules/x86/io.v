module x86

#include "modules/x86/io.h"

fn C.inb(u16) byte

pub fn inb(port u16) byte {
	return C.inb(port)
}

fn C.outb(u16, byte)

pub fn outb(port u16, value byte) {
	C.outb(port, value)
}
