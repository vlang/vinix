module devcore

// What a CPU does between two looks at a register it is waiting on.
pub fn relax() {
	asm volatile aarch64 {
		yield
		; ; ; memory
	}
}
