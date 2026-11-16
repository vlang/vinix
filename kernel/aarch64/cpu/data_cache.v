module cpu

pub fn read_ctr_el0() u64 {
	mut value := u64(0)
	asm volatile aarch64 {
		mrs value, ctr_el0
		; =r (value)
		; ; memory
	}
	return value
}

pub fn clean_invalidate_data_cache_line(address u64) {
	asm volatile aarch64 {
		dc civac, address
		; ; r (address)
		; memory
	}
}

// The caller owns the complete range and excludes other cacheable aliases.
// DminLine describes the smallest data-cache line in the coherency domain.
pub fn clean_invalidate_data_cache_to_poc(address u64, length u64) {
	if length == 0 { return }
	if address > ~u64(0) - length { panic('cache maintenance range overflow') }
	line := u64(4) << ((read_ctr_el0() >> 16) & 15)
	end := address + length
	mut current := address & ~(line - 1)
	dsb_sy()
	for {
		clean_invalidate_data_cache_line(current)
		if end - current <= line { break }
		current += line
	}
	dsb_sy()
}
