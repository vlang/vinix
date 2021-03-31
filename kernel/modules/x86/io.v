module x86

pub fn inb(port u16) byte {
	mut ret := byte(0)
	asm amd64 {
		in ret, port
		; =a (ret)
		; Nd (port)
	}
	return ret
}

pub fn outb(port u16, value byte) {
	asm amd64 {
		out port, value
		; ; a (value)
		  Nd (port)
	}
}
