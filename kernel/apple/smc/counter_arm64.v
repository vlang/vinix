module smc

// Same EL1 generic timer access and compiler barrier as the original binding.
@[export: 'vinix_smc_counter']
pub fn native_counter() u64 {
	mut counter := u64(0)
	asm volatile aarch64 {
		isb
		mrs counter, cntvct_el0
		; =r (counter)
		; ; memory
	}
	return counter
}
