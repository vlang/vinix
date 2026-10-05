#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64; typedef int64_t i64;
typedef struct main__Probe { u64 value; } main__Probe;
#define _str_1201 0
#define _str_260 0
__attribute__((noreturn)) static void v_panic(int unused) { (void)unused; __builtin_trap(); }
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

i64 katomic__load_T_i64(i64* var) {
	i64 ret = (i64)(0);
	if (sizeof(i64) == 1) {
		u8* target = (u8*)(var);
		__asm__ volatile (
			"mov %[target], %[ret]\n\t"
			: [ret] "=r" (ret)
			: [target] "m" (*target)
			: "memory"
		);
		return ret;
	}
	if (sizeof(i64) == 2) {
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
	if (sizeof(i64) == 4) {
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
	if (sizeof(i64) == 8) {
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

u32 katomic__load_T_u32(u32* var) {
	u32 ret = (u32)(0);
	if (sizeof(u32) == 1) {
		u8* target = (u8*)(var);
		__asm__ volatile (
			"mov %[target], %[ret]\n\t"
			: [ret] "=r" (ret)
			: [target] "m" (*target)
			: "memory"
		);
		return ret;
	}
	if (sizeof(u32) == 2) {
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
	if (sizeof(u32) == 4) {
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
	if (sizeof(u32) == 8) {
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

u64 katomic__load_T_u64(u64* var) {
	u64 ret = (u64)(0);
	if (sizeof(u64) == 1) {
		u8* target = (u8*)(var);
		__asm__ volatile (
			"mov %[target], %[ret]\n\t"
			: [ret] "=r" (ret)
			: [target] "m" (*target)
			: "memory"
		);
		return ret;
	}
	if (sizeof(u64) == 2) {
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
	if (sizeof(u64) == 4) {
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
	if (sizeof(u64) == 8) {
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

u8 katomic__load_T_u8(u8* var) {
	u8 ret = (u8)(0);
	if (sizeof(u8) == 1) {
		u8* target = (u8*)(var);
		__asm__ volatile (
			"mov %[target], %[ret]\n\t"
			: [ret] "=r" (ret)
			: [target] "m" (*target)
			: "memory"
		);
		return ret;
	}
	if (sizeof(u8) == 2) {
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
	if (sizeof(u8) == 4) {
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
	if (sizeof(u8) == 8) {
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

i64 katomic__load_T_v_int(i64* var) {
	i64 ret = (i64)(0);
	if (sizeof(i64) == 1) {
		u8* target = (u8*)(var);
		__asm__ volatile (
			"mov %[target], %[ret]\n\t"
			: [ret] "=r" (ret)
			: [target] "m" (*target)
			: "memory"
		);
		return ret;
	}
	if (sizeof(i64) == 2) {
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
	if (sizeof(i64) == 4) {
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
	if (sizeof(i64) == 8) {
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

main__Probe* katomic__load_T_ptr_Probe(main__Probe** var) {
	main__Probe* ret = (main__Probe*)(0);
	if (sizeof(main__Probe*) == 1) {
		u8* target = (u8*)(var);
		__asm__ volatile (
			"mov %[target], %[ret]\n\t"
			: [ret] "=r" (ret)
			: [target] "m" (*target)
			: "memory"
		);
		return ret;
	}
	if (sizeof(main__Probe*) == 2) {
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
	if (sizeof(main__Probe*) == 4) {
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
	if (sizeof(main__Probe*) == 8) {
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
