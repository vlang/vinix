void katomic__sync(void) {
	__asm__ volatile (
		"mfence\n\t"
		: : : "memory"
	);
}
