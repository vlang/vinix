void katomic__store_T_bool(bool* var, bool value) {
	{
		__asm__ volatile (
			"lock xchg %[value], %[var]\n\t"
			: [var] "+m" (*var),
			[value] "+r" (value)
			: : "memory"
		);
	}
}
