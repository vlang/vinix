bool katomic__load_T_bool(bool* var) {
	bool ret = (bool)(0);
	if (sizeof(bool) == 1) {
		u8* target = (u8*)(var);
		__asm__ volatile (
			"mov %[target], %[ret]\n\t"
			: [ret] "=r" (ret)
			: [target] "m" (*target)
			: "memory"
		);
		return ret;
	}
	if (sizeof(bool) == 2) {
		u16* target = (u16*)(var);
		if (((size_t)(var) & 1) != 0) {
			__asm__ volatile (
				"lock xadd %[ret], %[target]\n\t"
				: [target] "+m" (*target),
				[ret] "+r" (ret)
				: : "memory"
			);
			return ret;
		}
		__asm__ volatile (
			"mov %[target], %[ret]\n\t"
			: [ret] "=r" (ret)
			: [target] "m" (*target)
			: "memory"
		);
		return ret;
	}
	if (sizeof(bool) == 4) {
		u32* target = (u32*)(var);
		if (((size_t)(var) & 3) != 0) {
			__asm__ volatile (
				"lock xadd %[ret], %[target]\n\t"
				: [target] "+m" (*target),
				[ret] "+r" (ret)
				: : "memory"
			);
			return ret;
		}
		__asm__ volatile (
			"mov %[target], %[ret]\n\t"
			: [ret] "=r" (ret)
			: [target] "m" (*target)
			: "memory"
		);
		return ret;
	}
	if (sizeof(bool) == 8) {
		u64* target = (u64*)(var);
		if (((size_t)(var) & 7) != 0) {
			__asm__ volatile (
				"lock xadd %[ret], %[target]\n\t"
				: [target] "+m" (*target),
				[ret] "+r" (ret)
				: : "memory"
			);
			return ret;
		}
		__asm__ volatile (
			"mov %[target], %[ret]\n\t"
			: [ret] "=r" (ret)
			: [target] "m" (*target)
			: "memory"
		);
		return ret;
	}
	v_panic(_str_1201);
}
