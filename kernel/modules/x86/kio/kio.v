module kio

pub fn inb(port u16) byte {
	mut ret := byte(0)
	asm volatile amd64 {
		in ret, port
		; =a (ret)
		; Nd (port)
		; memory
	}
	return ret
}

pub fn outb(port u16, value byte) {
	asm volatile amd64 {
		out port, value
		;
		; a (value)
		  Nd (port)
		; memory
	}
}

pub fn mmind(addr u64) u32 {
	mut ret := u32(0)
	asm volatile amd64 {
		mov ret, [addr]
		; =r (ret)
		; r (addr)
		; memory
	}
	return ret
}

pub fn mmoutd(addr u64, value u32) {
	asm volatile amd64 {
		mov [addr], value
		;
		; r (addr)
		  r (value)
		; memory
	}
}
