module serial

import x86.kio
import klock

__global (
	serial_lock klock.Lock
)

pub fn initialise() {
	serial_lock.acquire()
	kio.port_out<byte>(0x3f8 + 1, 0x00)
	kio.port_out<byte>(0x3f8 + 3, 0x80)
	kio.port_out<byte>(0x3f8 + 0, 0x01)
	kio.port_out<byte>(0x3f8 + 1, 0x00)
	kio.port_out<byte>(0x3f8 + 3, 0x03)
	kio.port_out<byte>(0x3f8 + 2, 0xc7)
	kio.port_out<byte>(0x3f8 + 4, 0x0b)
	serial_lock.release()
}

pub fn out(value byte) {
	serial_lock.acquire()
	if value == `\n` {
		for kio.port_in<byte>(0x3f8 + 5) & 0x20 == 0 {}
		kio.port_out<byte>(0x3f8, `\r`)
	}
	for kio.port_in<byte>(0x3f8 + 5) & 0x20 == 0 {}
	kio.port_out<byte>(0x3f8, value)
	serial_lock.release()
}
