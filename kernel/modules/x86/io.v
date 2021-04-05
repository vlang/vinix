module x86

pub fn inb(port u16) byte {
	mut ret := byte(0)
	asm amd64 {
		in ret, port
		; =a (ret)
		; Nd (port)
		; memory
	}
	return ret
}

pub fn outb(port u16, value byte) {
	asm amd64 {
		out port, value
		; ; a (value)
		  Nd (port)
		; memory
	}
}

// dbg writes `s` to the qemu debug port
pub fn dbg(s string) {
	for i := 0; i < s.len; i++ {
		outb(0xe9, s[i]) // 0xe9 is qemu's debug port
	}
}

// dbg writes `s` to the qemu debug port, with a newline
pub fn dbgln(s string) {
	for i := 0; i < s.len; i++ {
		outb(0xe9, s[i]) // 0xe9 is qemu's debug port
	}
	outb(0xe9, `\n`)
}
