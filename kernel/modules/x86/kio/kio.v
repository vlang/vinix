// kio.v: MMIO and Port IO.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module kio

pub fn port_in[T](port u16) T {
	mut ret := T(0)
	asm volatile amd64 {
		in ret, port
		; =a (ret)
		; Nd (port)
		; memory
	}
	return ret
}

pub fn port_out[T](port u16, value T) {
	asm volatile amd64 {
		out port, value
		; ; a (value)
		  Nd (port)
		; memory
	}
}

pub fn mmin[T](addr &T) T {
	mut ret := T(0)
	asm volatile amd64 {
		mov ret, [addr]
		; =r (ret)
		; r (addr)
		; memory
	}
	return ret
}

pub fn mmout[T](addr &T, value T) {
	asm volatile amd64 {
		mov [addr], value
		; ; r (addr)
		  r (value)
		; memory
	}
}
