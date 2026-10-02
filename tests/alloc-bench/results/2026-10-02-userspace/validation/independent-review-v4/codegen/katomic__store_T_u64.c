void katomic__store_T_u64(u64* var, u64 value) {
	{
		__asm__ volatile (
			"lock xchg %[value], %[var]\n\t"
			: [var] "+m" (*var),
			[value] "+r" (value)
			: : "memory"
		);
	}
}
