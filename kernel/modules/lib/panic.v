module lib

// One could use the builtin panic, but it again uses runtime
// services.

pub fn kpanic(message string) {
	kprint('KERNEL PANIC: ')
	kprint(message)
	for {}
}
