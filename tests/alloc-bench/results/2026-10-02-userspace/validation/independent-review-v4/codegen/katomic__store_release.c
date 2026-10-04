void katomic__store_release(bool* var, bool value) {
	u8* target = (u8*)(var);
	u8 __if_val_0 = {0};
	if (value) {
		__if_val_0 = (u8)(1);
	} else {
		__if_val_0 = (u8)(0);
	}
	u8 byte = __if_val_0;
	__asm__ volatile (
		"mov %[byte], %[target]\n\t"
		: [target] "=m" (*target)
		: [byte] "r" (byte)
		: "memory"
	);
}
