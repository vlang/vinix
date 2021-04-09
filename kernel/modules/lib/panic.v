module lib

// One could use the builtin panic, but it again uses runtime
// services.

pub fn panic_kernel(message string) {
	printline('PANIC: ', message)
	for {}
}
