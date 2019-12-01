module sys

pub fn panic(reason string) {
	printk('*** PANIC ***')
	printk(reason)
	// todo cpu state / backtrace?

	// todo halt
	for {

	}
}