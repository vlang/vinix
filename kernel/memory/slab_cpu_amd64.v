module memory

import x86.cpu

fn slab_cpu_number() u64 {
	ints := cpu.interrupt_toggle(false)
	number := xnu_heap_cpu_number()
	cpu.interrupt_toggle(ints)
	return number
}
