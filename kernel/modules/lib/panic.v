module lib

import trace

pub fn kpanic(message string) {
	asm volatile amd64 {
		cli
	}
	C.printf(c'KERNEL PANIC: %s\n', message.str)
	trace.stacktrace(voidptr(0))
	for {
		asm volatile amd64 {
			cli
			hlt
		}
	}
}

pub fn kpanicc(message charptr) {
	kpanic(unsafe { cstring_to_vstring(message) })
}
