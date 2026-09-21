module memory

// Only called with interrupts masked, after SMP publishes CPU readiness.
fn xnu_heap_cpu_number() u64 {
	mut number := u64(0)
	asm volatile aarch64 {
		mrs number, tpidr_el1
		; =r (number)
		; ; memory
	}
	return number
}
