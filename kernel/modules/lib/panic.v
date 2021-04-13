module lib

// One could use the builtin panic, but it again uses runtime
// services.

pub fn kpanic(message string) {
	asm volatile amd64 {
		cli
	}
	kprint('KERNEL PANIC: ')
	kprint(message)
	for {
		asm volatile amd64 {
			hlt
		}
	}
}
