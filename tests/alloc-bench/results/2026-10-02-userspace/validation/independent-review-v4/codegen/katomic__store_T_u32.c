void katomic__store_T_u32(u32* var, u32 value) {
	{
		__asm__ volatile (
			"lock xchg %[value], %[var]\n\t"
			: [var] "+m" (*var),
			[value] "+r" (value)
			: : "memory"
		);
	}
}
