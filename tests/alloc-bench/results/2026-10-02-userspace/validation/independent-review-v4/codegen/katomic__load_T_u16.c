u16 katomic__load_T_u16(u16* var) {
	u16 ret = (u16)(0);
	if (sizeof(u16) == 1) {
		u8* target = (u8*)(var);
		__asm__ volatile (
			"mov %[target], %[ret]\n\t"
			: [ret] "=r" (ret)
			: [target] "m" (*target)
			: "memory"
		);
		return ret;
	}
	if (sizeof(u16) == 2) {
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
	if (sizeof(u16) == 4) {
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
	if (sizeof(u16) == 8) {
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
	v_panic(_str_260);
}
