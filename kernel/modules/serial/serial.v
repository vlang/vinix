[manualfree] module serial

import x86.kio
import klock

__global (
	serial_lock klock.Lock
)

pub fn initialise() {
	serial_lock.acquire()
	kio.outb(0x3f8 + 1, 0x00)
	kio.outb(0x3f8 + 3, 0x80)
	kio.outb(0x3f8 + 0, 0x01)
	kio.outb(0x3f8 + 1, 0x00)
	kio.outb(0x3f8 + 3, 0x03)
	kio.outb(0x3f8 + 2, 0xc7)
	kio.outb(0x3f8 + 4, 0x0b)
	serial_lock.release()
}

pub fn out(value u8) {
	serial_lock.acquire()
	if value == `\n` {
		kio.outb(0x3f8, `\r`)
	}
	kio.outb(0x3f8, value)
	serial_lock.release()
}
