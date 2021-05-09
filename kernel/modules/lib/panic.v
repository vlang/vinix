module lib

pub fn kpanic(message string) {
	asm volatile amd64 {
		cli
	}
	kprint('KERNEL PANIC: ')
	kprint(message)
	kprint('\n')
	print_stacktrace()
	for {
		asm volatile amd64 {
			hlt
		}
	}
}

pub fn kpanicc(message charptr) {
	kpanic(C.char_vstring(message))
}
