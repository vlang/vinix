module lib

pub fn kpanic(message string) {
	asm volatile amd64 {
		cli
	}
	C.printf(c'KERNEL PANIC: %s\n', message.str)
	print_stacktrace()
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
