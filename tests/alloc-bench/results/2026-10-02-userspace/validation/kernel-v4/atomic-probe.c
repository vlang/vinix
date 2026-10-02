// V comptime_definitions:
// V compile time defines by -d or -define flags:
//     All custom defines      : skip_fastc,skip_arm64,skip_wasm,skip_eval
//     Turned ON custom defines: skip_fastc,skip_arm64,skip_wasm,skip_eval
#define CUSTOM_DEFINE_skip_fastc
#define CUSTOM_DEFINE_skip_arm64
#define CUSTOM_DEFINE_skip_wasm
#define CUSTOM_DEFINE_skip_eval

#ifndef V_THREAD_STACK_SIZE
#define V_THREAD_STACK_SIZE 8388608
#endif
#if defined(_WIN32)
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#endif
#include <sys/mman.h>
#include <unistd.h>
#include <float.h>

#include <stdint.h>
#include <stddef.h>
typedef int8_t i8;
typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;
typedef uint8_t u8;
typedef uint8_t byte;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
static inline i64 __v_pow_i64(i64 base, i64 exponent) { if (exponent < 0) { if (base == 0) return -1; if (base != 1 && base != -1) return 0; return (exponent & 1) != 0 ? base : 1; } i64 value = 1; i64 power = base; for (; exponent > 0; exponent >>= 1) { if ((exponent & 1) != 0) value *= power; power *= power; } return value; }
static inline u64 __v_pow_u64(u64 base, i64 exponent) { if (exponent < 0) { if (base == 0) return (u64)-1; return base == 1 ? 1 : 0; } u64 value = 1; u64 power = base; for (; exponent > 0; exponent >>= 1) { if ((exponent & 1) != 0) value *= power; power *= power; } return value; }
static inline u64 _v_f64_to_u64(double x) { if (!(x >= 0.0)) return 0; if (x >= 18446744073709551616.0) return (u64)-1; return (u64)x; }
#if defined(__STDC_VERSION__) && __STDC_VERSION__ > 201710L
#include <stdbool.h>
#endif
#ifndef __bool_true_false_are_defined
#ifdef _MSC_VER
typedef unsigned char bool;
#else
typedef _Bool bool;
#endif
#define __bool_true_false_are_defined 1
#endif
typedef void* voidptr;
typedef i64 int_literal;
typedef double float_literal;
#if defined(_MSC_VER)
#define V_INT128_STRUCT_ATTR __declspec(align(16))
#else
#define V_INT128_STRUCT_ATTR __attribute__((aligned(16)))
#endif

#if defined(__SIZEOF_INT128__) && !defined(V_INT128_PORTABLE)

typedef unsigned __int128 u128;
typedef __int128 i128;

#define V_INT128_NATIVE 1

/* Generated code builds a wide literal from its halves, so this has to exist on
 * both representations. On the native type the halves are a shift and an or. */
static inline u128 __v_u128_make(u64 hi, u64 lo) {
	return ((u128)hi << 64) | (u128)lo;
}

/* A shift count, clamped to the one value the shift helpers have to recognise as
 * out of range. Reading only the low 64 bits let a count of 2^64 look like zero. */
static inline u64 __v_u128_shift_count(u128 a) {
	return a > (u128)(~(u64)0) ? (u64)128 : (u64)a;
}

/* The native type is two's complement, so every bit pattern is a value and the
 * conversions below are plain casts. */
static inline u128 __v_u128_zero(void) {
	return (u128)0;
}

static inline bool __v_u128_is_zero(u128 a) {
	return a == 0;
}

static inline bool __v_i128_is_zero(i128 a) {
	return a == 0;
}

static inline u128 __v_u128_from_u64(u64 x) {
	return (u128)x;
}

static inline u128 __v_u128_from_i64(i64 x) {
	return (u128)x;
}

static inline i128 __v_i128_from_u64(u64 x) {
	return (i128)x;
}

static inline i128 __v_i128_from_i64(i64 x) {
	return (i128)x;
}

static inline u128 __v_u128_from_i128(i128 x) {
	return (u128)x;
}

static inline i128 __v_i128_from_u128(u128 x) {
	return (i128)x;
}

static inline u64 __v_u128_to_u64(u128 x) {
	return (u64)x;
}

static inline i64 __v_u128_to_i64(u128 x) {
	return (i64)x;
}

static inline u64 __v_i128_to_u64(i128 x) {
	return (u64)x;
}

static inline i64 __v_i128_to_i64(i128 x) {
	return (i64)x;
}

static inline double __v_u128_to_f64(u128 a) {
	return (double)a;
}

static inline double __v_i128_to_f64(i128 a) {
	return (double)a;
}

static inline u128 __v_u128_from_f64(double d) {
	return (u128)d;
}

static inline i128 __v_i128_from_f64(double d) {
	return (i128)d;
}

static inline u128 __v_u128_add(u128 a, u128 b) {
	return a + b;
}

static inline u128 __v_u128_sub(u128 a, u128 b) {
	return a - b;
}

static inline u128 __v_u128_mul(u128 a, u128 b) {
	return a * b;
}

static inline u128 __v_u128_div(u128 a, u128 b) {
	return a / b;
}

static inline u128 __v_u128_rem(u128 a, u128 b) {
	return a % b;
}

static inline u128 __v_u128_neg(u128 a) {
	return (u128)0 - a;
}

static inline u128 __v_u128_and(u128 a, u128 b) {
	return a & b;
}

static inline u128 __v_u128_or(u128 a, u128 b) {
	return a | b;
}

static inline u128 __v_u128_xor(u128 a, u128 b) {
	return a ^ b;
}

static inline u128 __v_u128_not(u128 a) {
	return ~a;
}

static inline u128 __v_u128_shl(u128 a, u64 n) {
	return n >= 128 ? (u128)0 : a << n;
}

static inline u128 __v_u128_shr(u128 a, u64 n) {
	return n >= 128 ? (u128)0 : a >> n;
}

static inline i128 __v_i128_add(i128 a, i128 b) {
	return a + b;
}

static inline i128 __v_i128_sub(i128 a, i128 b) {
	return a - b;
}

static inline i128 __v_i128_mul(i128 a, i128 b) {
	return a * b;
}

/* min_i128 / -1 overflows a signed division in C and raises SIGFPE on x86, so
 * that one case is computed as a negation; every other pair divides directly.
 * The portable path answers the same way through its long division. */
static inline i128 __v_i128_div(i128 a, i128 b) {
	if (b == -1) {
		return (i128)((u128)0 - (u128)a);
	}
	return a / b;
}

static inline i128 __v_i128_rem(i128 a, i128 b) {
	if (b == -1) {
		return (i128)0;
	}
	return a % b;
}

static inline i128 __v_i128_and(i128 a, i128 b) {
	return a & b;
}

static inline i128 __v_i128_or(i128 a, i128 b) {
	return a | b;
}

static inline i128 __v_i128_xor(i128 a, i128 b) {
	return a ^ b;
}

static inline i128 __v_i128_not(i128 a) {
	return ~a;
}

/* Negating the minimum value has no representable result, so the negation is
 * computed in unsigned arithmetic and only then reinterpreted. That wraps to
 * the minimum again, the same answer the portable path gives. */
static inline i128 __v_i128_neg(i128 a) {
	return (i128)((u128)0 - (u128)a);
}

static inline i128 __v_i128_shl(i128 a, u64 n) {
	return n >= 128 ? (i128)0 : a << n;
}

static inline i128 __v_i128_shr(i128 a, u64 n) {
	if (n >= 128) {
		return a < 0 ? (i128)-1 : (i128)0;
	}
	return a >> n;
}

static inline bool __v_u128_eq(u128 a, u128 b) {
	return a == b;
}

static inline bool __v_u128_ne(u128 a, u128 b) {
	return a != b;
}

static inline bool __v_u128_lt(u128 a, u128 b) {
	return a < b;
}

static inline bool __v_u128_gt(u128 a, u128 b) {
	return a > b;
}

static inline bool __v_u128_le(u128 a, u128 b) {
	return a <= b;
}

static inline bool __v_u128_ge(u128 a, u128 b) {
	return a >= b;
}

static inline bool __v_i128_eq(i128 a, i128 b) {
	return a == b;
}

static inline bool __v_i128_ne(i128 a, i128 b) {
	return a != b;
}

static inline bool __v_i128_lt(i128 a, i128 b) {
	return a < b;
}

static inline bool __v_i128_gt(i128 a, i128 b) {
	return a > b;
}

static inline bool __v_i128_le(i128 a, i128 b) {
	return a <= b;
}

static inline bool __v_i128_ge(i128 a, i128 b) {
	return a >= b;
}

#else

typedef struct v_int128_s {
	u64 lo;
	u64 hi;
} V_INT128_STRUCT_ATTR v_int128_t;

/* The portable representation is the same C struct for both signednesses: the
 * bits are two's complement either way, and V keeps signedness in its own type
 * table, so there is nothing for C to distinguish. */
typedef v_int128_t u128;
typedef v_int128_t i128;

static inline u128 __v_u128_make(u64 hi, u64 lo) {
	u128 r;
	r.lo = lo;
	r.hi = hi;
	return r;
}

/* A shift count, clamped to the one value the shift helpers have to recognise as
 * out of range. Anything above the low 64 bits is at least 2^64, which is over
 * the 128 a shift can use. */
static inline u64 __v_u128_shift_count(u128 a) {
	return a.hi != 0 ? (u64)128 : a.lo;
}

static inline u128 __v_u128_zero(void) {
	return __v_u128_make(0, 0);
}

static inline u128 __v_u128_from_u64(u64 x) {
	return __v_u128_make(0, x);
}

/* A negative i64 sign-extends, because the struct holds a two's complement
 * pattern and the value keeps its sign when it widens. */
static inline u128 __v_u128_from_i64(i64 x) {
	return __v_u128_make(x < 0 ? ~(u64)0 : 0, (u64)x);
}

static inline i128 __v_i128_from_u64(u64 x) {
	return __v_u128_make(0, x);
}

static inline i128 __v_i128_from_i64(i64 x) {
	return __v_u128_make(x < 0 ? ~(u64)0 : 0, (u64)x);
}

static inline u128 __v_u128_from_i128(i128 x) {
	return x;
}

static inline i128 __v_i128_from_u128(u128 x) {
	return x;
}

static inline u64 __v_u128_to_u64(u128 x) {
	return x.lo;
}

static inline i64 __v_u128_to_i64(u128 x) {
	return (i64)x.lo;
}

static inline u64 __v_i128_to_u64(i128 x) {
	return x.lo;
}

static inline i64 __v_i128_to_i64(i128 x) {
	return (i64)x.lo;
}

/* 2^64 as a double, the weight of the high limb. */
#define V_INT128_TWO64 18446744073709551616.0

static inline u128 __v_u128_add(u128 a, u128 b) {
	u128 r;
	r.lo = a.lo + b.lo;
	r.hi = a.hi + b.hi + (r.lo < a.lo ? 1 : 0);
	return r;
}

static inline u128 __v_u128_sub(u128 a, u128 b) {
	u128 r;
	r.lo = a.lo - b.lo;
	r.hi = a.hi - b.hi - (a.lo < b.lo ? 1 : 0);
	return r;
}

static inline u128 __v_u128_neg(u128 a) {
	return __v_u128_sub(__v_u128_zero(), a);
}

/* The magnitude of a signed value as an unsigned one. */
static inline u128 __v_u128_abs_of(i128 a) {
	if ((a.hi >> 63) != 0) {
		return __v_u128_neg(a);
	}
	return a;
}

static inline bool __v_u128_is_zero(u128 a) {
	return a.lo == 0 && a.hi == 0;
}

static inline bool __v_i128_is_zero(i128 a) {
	return a.lo == 0 && a.hi == 0;
}

/* The low 64 bits come from the 32-bit limb products; the high 64 bits add the
 * cross products, which is everything a 128-bit result keeps. */
static inline u128 __v_u128_mul(u128 a, u128 b) {
	u64 a0 = a.lo & 0xFFFFFFFF;
	u64 a1 = a.lo >> 32;
	u64 b0 = b.lo & 0xFFFFFFFF;
	u64 b1 = b.lo >> 32;
	u64 c0 = a0 * b0;
	u64 c1 = a0 * b1 + (c0 >> 32);
	u64 c2 = a1 * b0 + (c1 & 0xFFFFFFFF);
	u128 r;
	r.lo = (c2 << 32) | (c0 & 0xFFFFFFFF);
	r.hi = a1 * b1 + (c1 >> 32) + (c2 >> 32) + a.lo * b.hi + a.hi * b.lo;
	return r;
}

static inline bool __v_u128_eq(u128 a, u128 b) {
	return a.lo == b.lo && a.hi == b.hi;
}

static inline bool __v_u128_ne(u128 a, u128 b) {
	return a.lo != b.lo || a.hi != b.hi;
}

static inline bool __v_u128_lt(u128 a, u128 b) {
	return a.hi < b.hi || (a.hi == b.hi && a.lo < b.lo);
}

static inline bool __v_u128_gt(u128 a, u128 b) {
	return a.hi > b.hi || (a.hi == b.hi && a.lo > b.lo);
}

static inline bool __v_u128_le(u128 a, u128 b) {
	return a.hi < b.hi || (a.hi == b.hi && a.lo <= b.lo);
}

static inline bool __v_u128_ge(u128 a, u128 b) {
	return a.hi > b.hi || (a.hi == b.hi && a.lo >= b.lo);
}

static inline u128 __v_u128_and(u128 a, u128 b) {
	return __v_u128_make(a.hi & b.hi, a.lo & b.lo);
}

static inline u128 __v_u128_or(u128 a, u128 b) {
	return __v_u128_make(a.hi | b.hi, a.lo | b.lo);
}

static inline u128 __v_u128_xor(u128 a, u128 b) {
	return __v_u128_make(a.hi ^ b.hi, a.lo ^ b.lo);
}

static inline u128 __v_u128_not(u128 a) {
	return __v_u128_make(~a.hi, ~a.lo);
}

static inline u128 __v_u128_shl(u128 a, u64 n) {
	if (n >= 128) {
		return __v_u128_zero();
	}
	if (n == 0) {
		return a;
	}
	if (n >= 64) {
		return __v_u128_make(a.lo << (n - 64), 0);
	}
	return __v_u128_make((a.hi << n) | (a.lo >> (64 - n)), a.lo << n);
}

static inline u128 __v_u128_shr(u128 a, u64 n) {
	if (n >= 128) {
		return __v_u128_zero();
	}
	if (n == 0) {
		return a;
	}
	if (n >= 64) {
		return __v_u128_make(0, a.hi >> (n - 64));
	}
	return __v_u128_make(a.hi >> n, (a.lo >> n) | (a.hi << (64 - n)));
}

static inline i128 __v_i128_shr(i128 a, u64 n) {
	u64 sign = (a.hi >> 63) != 0 ? ~(u64)0 : 0;
	if (n >= 128) {
		return __v_u128_make(sign, sign);
	}
	if (n == 0) {
		return a;
	}
	if (n == 64) {
		return __v_u128_make(sign, a.hi);
	}
	if (n > 64) {
		return __v_u128_make(sign, (a.hi >> (n - 64)) | (sign << (128 - n)));
	}
	return __v_u128_make((a.hi >> n) | (sign << (64 - n)), (a.lo >> n) | (a.hi << (64 - n)));
}

/* Binary long division, one quotient bit per pass. */
static inline void __v_u128_divmod(u128 a, u128 b, u128 *q, u128 *r) {
	u128 qq = __v_u128_zero();
	u128 rr = __v_u128_zero();
	int i;
	for (i = 127; i >= 0; i--) {
		u64 bit;
		if (i >= 64) {
			bit = (a.hi >> (i - 64)) & 1;
		} else {
			bit = (a.lo >> i) & 1;
		}
		rr.hi = (rr.hi << 1) | (rr.lo >> 63);
		rr.lo = (rr.lo << 1) | bit;
		if (__v_u128_ge(rr, b)) {
			rr = __v_u128_sub(rr, b);
			if (i >= 64) {
				qq.hi |= ((u64)1 << (i - 64));
			} else {
				qq.lo |= ((u64)1 << i);
			}
		}
	}
	*q = qq;
	*r = rr;
}

static inline u128 __v_u128_div(u128 a, u128 b) {
	u128 q;
	u128 r;
	__v_u128_divmod(a, b, &q, &r);
	return q;
}

static inline u128 __v_u128_rem(u128 a, u128 b) {
	u128 q;
	u128 r;
	__v_u128_divmod(a, b, &q, &r);
	return r;
}

/* A value wider than a double has to be rounded once, from the whole magnitude.
 * Converting each limb on its own rounds twice, and the first rounding throws away
 * the bit that decides the second: with hi = 2^53 + 1 and lo = 2^63, the high limb
 * rounds down to 2^117 and the answer lands 2^65 too low.
 *
 * Keep the top 53 bits and round on the guard bit below them plus every bit after
 * it, the way a hardware conversion does. The scale below is a power of two, which
 * multiplies exactly, so this decides the only rounding there is. */
static inline double __v_u128_scale_pow2(double m, int e) {
	while (e >= 32) {
		m *= 4294967296.0;
		e -= 32;
	}
	while (e > 0) {
		m *= 2.0;
		e--;
	}
	return m;
}

static inline double __v_u128_to_f64(u128 a) {
	int bits;
	int shift;
	u64 keep;
	bool guard;
	bool sticky;
	if (a.hi == 0) {
		return (double)a.lo;
	}
	/* The count of significant bits, 65 to 128 here, so that the top 53 of them
	 * are the ones a double can hold. */
	bits = 128;
	{
		u64 top = a.hi;
		while ((top >> 63) == 0) {
			top <<= 1;
			bits--;
		}
	}
	shift = bits - 53;
	if (shift >= 64) {
		/* Everything below the kept bits is in the low limb, plus `shift - 64`
		 * bits of the high one. */
		int dropped = shift - 64;
		if (dropped == 0) {
			keep = a.hi;
			guard = (a.lo >> 63) != 0;
			sticky = (a.lo & 0x7fffffffffffffffull) != 0;
		} else {
			keep = a.hi >> dropped;
			guard = ((a.hi >> (dropped - 1)) & 1) != 0;
			sticky = (a.hi & ((((u64)1) << (dropped - 1)) - 1)) != 0 || a.lo != 0;
		}
	} else {
		keep = (a.hi << (64 - shift)) | (a.lo >> shift);
		guard = ((a.lo >> (shift - 1)) & 1) != 0;
		sticky = (a.lo & ((((u64)1) << (shift - 1)) - 1)) != 0;
	}
	/* Round to nearest, ties to even, on the guard and sticky bits. */
	if (guard && (sticky || (keep & 1) != 0)) {
		keep++;
	}
	return __v_u128_scale_pow2((double)keep, shift);
}

static inline double __v_i128_to_f64(i128 a) {
	double v = __v_u128_to_f64(__v_u128_abs_of(a));
	return (a.hi >> 63) != 0 ? -v : v;
}

static inline u128 __v_u128_from_f64(double d) {
	u64 hi;
	double rest;
	if (d <= 0) {
		return __v_u128_zero();
	}
	hi = (u64)(d / V_INT128_TWO64);
	rest = d - (double)hi * V_INT128_TWO64;
	return __v_u128_make(hi, (u64)rest);
}

static inline i128 __v_i128_from_f64(double d) {
	u128 bits;
	double mag = d < 0 ? -d : d;
	u64 hi;
	double rest;
	if (mag <= 0) {
		return __v_i128_from_u64(0);
	}
	hi = (u64)(mag / V_INT128_TWO64);
	rest = mag - (double)hi * V_INT128_TWO64;
	bits = __v_u128_make(hi, (u64)rest);
	if (d < 0) {
		bits = __v_u128_neg(bits);
	}
	return bits;
}

static inline i128 __v_i128_add(i128 a, i128 b) {
	return __v_u128_add(a, b);
}

static inline i128 __v_i128_sub(i128 a, i128 b) {
	return __v_u128_sub(a, b);
}

/* Two's complement multiplication keeps its low 128 bits whatever the signs
 * are, so the unsigned product is the signed result. */
static inline i128 __v_i128_mul(i128 a, i128 b) {
	return __v_u128_mul(a, b);
}

static inline i128 __v_i128_and(i128 a, i128 b) {
	return __v_u128_and(a, b);
}

static inline i128 __v_i128_or(i128 a, i128 b) {
	return __v_u128_or(a, b);
}

static inline i128 __v_i128_xor(i128 a, i128 b) {
	return __v_u128_xor(a, b);
}

static inline i128 __v_i128_not(i128 a) {
	return __v_u128_not(a);
}

static inline i128 __v_i128_shl(i128 a, u64 n) {
	return __v_u128_shl(a, n);
}

static inline i128 __v_i128_neg(i128 a) {
	return __v_u128_neg(a);
}

static inline bool __v_i128_lt(i128 a, i128 b) {
	bool an = (a.hi >> 63) != 0;
	bool bn = (b.hi >> 63) != 0;
	if (an != bn) {
		return an;
	}
	return __v_u128_lt(a, b);
}

static inline bool __v_i128_eq(i128 a, i128 b) {
	return __v_u128_eq(a, b);
}

static inline bool __v_i128_ne(i128 a, i128 b) {
	return __v_u128_ne(a, b);
}

static inline bool __v_i128_gt(i128 a, i128 b) {
	return __v_i128_lt(b, a);
}

static inline bool __v_i128_le(i128 a, i128 b) {
	return !__v_i128_lt(b, a);
}

static inline bool __v_i128_ge(i128 a, i128 b) {
	return !__v_i128_lt(a, b);
}

static inline i128 __v_i128_div(i128 a, i128 b) {
	bool neg = ((a.hi ^ b.hi) >> 63) != 0;
	u128 q;
	u128 r;
	__v_u128_divmod(__v_u128_abs_of(a), __v_u128_abs_of(b), &q, &r);
	return neg ? __v_u128_neg(q) : q;
}

/* The remainder takes the sign of the dividend, which is what C and V both
 * specify. */
static inline i128 __v_i128_rem(i128 a, i128 b) {
	bool neg = (a.hi >> 63) != 0;
	u128 q;
	u128 r;
	__v_u128_divmod(__v_u128_abs_of(a), __v_u128_abs_of(b), &q, &r);
	return neg ? __v_u128_neg(r) : r;
}

#endif

/* Decimal text for the assert and panic printers.
 *
 * This comes after the main helper block, so it can call the arithmetic helpers
 * whatever representation the build picked. The buffer is static and the text is
 * written back-to-front, which keeps a failing path free of allocation. */
static inline const char* __v_u128_str(u128 v) {
	static char buf[64];
	char* p = buf + sizeof(buf) - 1;
	*p = '\0';
	while (!__v_u128_is_zero(v)) {
		u64 digit = __v_u128_to_u64(__v_u128_rem(v, __v_u128_from_u64(10)));
		*(--p) = (char)('0' + (char)digit);
		v = __v_u128_div(v, __v_u128_from_u64(10));
	}
	if (*p == '\0') {
		*(--p) = '0';
	}
	return p;
}

/* Signed decimal. The magnitude comes from the unsigned negation, which is also
 * the only way to print the minimum value. */
static inline const char* __v_i128_str(i128 v) {
	static char buf[64];
	char* p = buf + sizeof(buf) - 1;
	*p = '\0';
	bool neg = __v_i128_lt(v, __v_i128_from_i64(0));
	u128 mag = neg ? __v_u128_neg(__v_u128_from_i128(v)) : __v_u128_from_i128(v);
	while (!__v_u128_is_zero(mag)) {
		u64 digit = __v_u128_to_u64(__v_u128_rem(mag, __v_u128_from_u64(10)));
		*(--p) = (char)('0' + (char)digit);
		mag = __v_u128_div(mag, __v_u128_from_u64(10));
	}
	if (*p == '\0') {
		*(--p) = '0';
	}
	if (neg) {
		*(--p) = '-';
	}
	return p;
}

struct sync__Channel;
typedef struct sync__Channel* chan;
#if !defined(__STDC_VERSION__) || __STDC_VERSION__ <= 201710L
#ifndef true
#define true 1
#endif
#ifndef false
#define false 0
#endif
#endif
#if defined(__TINYC__) || defined(_MSC_VER)
#define E_STRUCT_DECL unsigned char _dummy_pad
#define E_STRUCT 0
#else
#define E_STRUCT_DECL
#define E_STRUCT
#endif
#define _S(s) ((string){.str=(u8*)("" s), .len=(sizeof(s)-1), .is_lit=1})
#if !defined(VNORETURN)
#if defined(__TINYC__)
#define VNORETURN __attribute__((noreturn))
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#define VNORETURN _Noreturn
#elif defined(__GNUC__) && __GNUC__ >= 2
#define VNORETURN __attribute__((noreturn))
#endif
#ifndef VNORETURN
#define VNORETURN
#endif
#endif
#if defined(_MSC_VER) && !defined(__clang__)
#define __attribute__(x)
#ifndef _Thread_local
#define _Thread_local __declspec(thread)
#endif
#define _Atomic volatile
#define __alignof__(x) __alignof(x)
#endif
typedef ptrdiff_t isize;
typedef size_t usize;
typedef char* charptr;
typedef unsigned char* byteptr;
typedef int (*qsort_callback_func)(const void*, const void*);
#ifndef VCALLCONV
#define VCALLCONV(x)
#endif
#if defined(__linux__) && !defined(__ANDROID__)
#include <features.h>
#endif
#ifdef sprintf
#undef sprintf
#endif
#ifdef snprintf
#undef snprintf
#endif
#ifdef vsnprintf
#undef vsnprintf
#endif
#ifdef memcpy
#undef memcpy
#endif
#ifdef memmove
#undef memmove
#endif
#ifdef memset
#undef memset
#endif
// GCC-compatible compilers also define __GNUC__, so keep V's discriminator
// in sync with the compiler that will consume a portable generated C file.
#if defined(__GNUC__) && !defined(__TINYC__) && !defined(__cplusplus) && !defined(__clang__)
	#define __V_GCC__
#endif
// c_headers
typedef int (*qsort_callback_func)(const void*, const void*);
#if defined(_MSC_VER) && !defined(__clang__)
	#define V_CRT_LINKAGE __declspec(dllimport)
	#define V_CRT_CALL VCALLCONV(cdecl)
#else
	#define V_CRT_LINKAGE
	#define V_CRT_CALL
#endif
#if (defined(__MINGW32__) || defined(__MINGW64__)) && defined(__V_GCC__)
	#define V_CRT_STDIO_LINKAGE __attribute__((dllimport))
#else
	#define V_CRT_STDIO_LINKAGE V_CRT_LINKAGE
#endif
#if (defined(_MSC_VER) && !defined(__clang__)) || defined(__cplusplus)
// Under C++ (g++/clang++), let libc declare FILE/stdio/string/stdlib to keep
// noexcept specifiers consistent — the manual extern "C" prototypes below
// would otherwise conflict with system headers under -std=c++NN.
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef va_copy
	#define va_copy(dest, src) ((dest) = (src))
#endif
#ifndef _TRUNCATE
	#define _TRUNCATE ((size_t)-1)
#endif
#elif defined(__NetBSD__)
// NetBSD exposes stdin/stdout/stderr as macros into a single `__sF[3]`
// array whose element size (sizeof(FILE)) depends on the platform and libc
// version, so we cannot forward-declare them. The FreeBSD-style
// `__stdinp/__stdoutp/__stderrp` symbols also do not exist on NetBSD (see
// vlang/v#27190). Defer to the system headers for FILE, the stdio streams,
// and the libc prototypes that would otherwise clash with the
// `__restrict`-qualified declarations in NetBSD libc.
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#elif defined(__TINYC__) && (defined(__FreeBSD__) || defined(__OpenBSD__))
// TinyCC reports a hard redefinition error if system OpenSSL pulls in
// <stdarg.h> after V has provided its own va_start macro. Include it first,
// but keep V manual FILE declarations on these BSD libc variants.
#include <stdarg.h>
#if defined(__FreeBSD__)
typedef struct __sFILE FILE;
extern FILE* __stdinp;
extern FILE* __stdoutp;
extern FILE* __stderrp;
#define stdin __stdinp
#define stdout __stdoutp
#define stderr __stderrp
#else
typedef struct __sFILE FILE;
#ifndef _STDFILES_DECLARED
	#define _STDFILES_DECLARED
struct __sFstub { long _stub; };
extern struct __sFstub __stdin[];
extern struct __sFstub __stdout[];
extern struct __sFstub __stderr[];
#endif
#define stdin ((struct __sFILE *)__stdin)
#define stdout ((struct __sFILE *)__stdout)
#define stderr ((struct __sFILE *)__stderr)
#endif
#elif (defined(__MINGW32__) || defined(__MINGW64__)) && defined(__V_GCC__)
// mingw-w64 stdio.h provides fprintf/vfprintf as static inline overrides
// when __USE_MINGW_ANSI_STDIO is enabled, so use the system declarations
// instead of the manual formatted-stdio prototypes below.
#include <stdarg.h>
#include <stdio.h>
#elif defined(__MINGW32__) || defined(__MINGW64__) || (defined(__clang__) && (defined(_WIN32) || defined(_WIN64)))
typedef struct _iobuf FILE;
FILE* __cdecl __acrt_iob_func(unsigned index);
#define stdin  (__acrt_iob_func(0))
#define stdout (__acrt_iob_func(1))
#define stderr (__acrt_iob_func(2))
#elif defined(__TINYC__) && (defined(_WIN32) || defined(_WIN64))
#ifndef _FILE_DEFINED
struct _iobuf {
	char *_ptr;
	int _cnt;
	char *_base;
	int _flag;
	int _file;
	int _charbuf;
	int _bufsiz;
	char *_tmpfname;
};
typedef struct _iobuf FILE;
#define _FILE_DEFINED
#endif
	#if defined(_WIN64)
FILE* __cdecl __iob_func(void);
	#else
		#ifdef _MSVCRT_
extern FILE _iob[];
			#define __iob_func() (_iob)
		#else
extern FILE (*_imp___iob)[];
			#define __iob_func() (*_imp___iob)
			#define _iob __iob_func()
		#endif
	#endif
#define stdin (&__iob_func()[0])
#define stdout (&__iob_func()[1])
#define stderr (&__iob_func()[2])
#elif defined(__vinix__)
typedef struct __file FILE;
extern FILE* stdin;
extern FILE* stdout;
extern FILE* stderr;
struct __thread_data;
struct __threadattr;
// pthread_t handling for vinix builds:
//  - Vinix kernel (freestanding, __STDC_HOSTED__=0): no libc, define
//    pthread_t ourselves so V code that references it compiles.
//  - util-vinix cross-compiled on a libc-providing host (hosted, e.g.
//    glibc on Linux or macOS with -D__vinix__): pull pthread_t from
//    libc to avoid colliding with the libc typedef.
#if defined(__STDC_HOSTED__) && __STDC_HOSTED__ && defined(__has_include) && __has_include(<pthread.h>)
#include <pthread.h>
#else
typedef struct __thread_data *pthread_t;
#endif
typedef __builtin_va_list va_list;
#ifndef va_start
	#define va_start(ap, v) __builtin_va_start(ap, v)
#endif
#ifndef va_arg
	#define va_arg(ap, t) __builtin_va_arg(ap, t)
#endif
#ifndef va_end
	#define va_end(ap) __builtin_va_end(ap)
#endif
#ifndef va_copy
	#define va_copy(dest, src) __builtin_va_copy(dest, src)
#endif
#else
	#if defined(__APPLE__) || defined(__FreeBSD__)
typedef struct __sFILE FILE;
extern FILE* __stdinp;
extern FILE* __stdoutp;
extern FILE* __stderrp;
#define stdin __stdinp
#define stdout __stdoutp
#define stderr __stderrp
	#elif defined(__DragonFly__)
typedef struct __sFILE FILE;
extern FILE* __stdinp;
extern FILE* __stdoutp;
extern FILE* __stderrp;
#define stdin __stdinp
#define stdout __stdoutp
#define stderr __stderrp
	#elif defined(__OpenBSD__)
typedef struct __sFILE FILE;
#ifndef _STDFILES_DECLARED
	#define _STDFILES_DECLARED
struct __sFstub { long _stub; };
extern struct __sFstub __stdin[];
extern struct __sFstub __stdout[];
extern struct __sFstub __stderr[];
#endif
#define stdin ((struct __sFILE *)__stdin)
#define stdout ((struct __sFILE *)__stdout)
#define stderr ((struct __sFILE *)__stderr)
	#elif defined(__BIONIC__)
struct __sFILE;
typedef struct __sFILE FILE;
extern FILE* stdin;
extern FILE* stdout;
extern FILE* stderr;
	#elif defined(__linux__) && !defined(__GLIBC__) && !defined(__GNU_LIBRARY__) && !defined(__BIONIC__) && !defined(__UCLIBC__)
typedef struct _IO_FILE FILE;
// musl exposes the stdio streams as `FILE *const`, so match that to stay
// compatible with later <stdio.h> includes from headers like miniz.h.
extern FILE* const stdin;
extern FILE* const stdout;
extern FILE* const stderr;
	#else
typedef struct _IO_FILE FILE;
extern FILE* stdin;
extern FILE* stdout;
extern FILE* stderr;
#if defined(__GLIBC__) || defined(__GNU_LIBRARY__)
// V declares the stdio functions manually here, instead of including <stdio.h>.
// glibc defines L_tmpnam only while <stdio.h> is being processed (it sits behind
// `#ifdef _STDIO_H` in <bits/stdio_lim.h>), and it is the one stdio limit macro that
// <stdio.h> itself uses in a prototype: char *tmpnam(char[L_tmpnam]). So a <stdio.h>
// pulled in later by a module header (sqlite3.h, gc.h, ...) can fail with L_tmpnam
// being undeclared; see vlang/v#28108. Define it here, to the stable glibc value,
// without adding an include. A later identical redefinition by glibc is a no-op.
#ifndef L_tmpnam
#define L_tmpnam 20
#endif
#endif
	#endif
typedef __builtin_va_list va_list;
#ifndef va_start
	#define va_start(ap, v) __builtin_va_start(ap, v)
#endif
#ifndef va_arg
	#define va_arg(ap, t) __builtin_va_arg(ap, t)
#endif
#ifndef va_end
	#define va_end(ap) __builtin_va_end(ap)
#endif
#ifndef va_copy
	#define va_copy(dest, src) __builtin_va_copy(dest, src)
#endif
#endif
#if (!defined(_MSC_VER) || defined(__clang__)) && !defined(__cplusplus) && !defined(__NetBSD__)
// mingw-w64 stdio.h declares these as static __mingw_ovr inline overrides
// when __USE_MINGW_ANSI_STDIO is on. Skip them under gcc+mingw to avoid
// static-after-extern conflicts; clang+mingw needs them because it builds
// with -Werror=implicit-function-declaration and does not hit the conflict.
// NetBSD pulls these prototypes from <stdio.h>/<stdlib.h>/<string.h> via
// the include block above to avoid `__restrict` qualifier conflicts.
#if !((defined(__MINGW32__) || defined(__MINGW64__)) && !defined(__clang__))
V_CRT_LINKAGE int V_CRT_CALL vfprintf(FILE *stream, const char *format, va_list ap);
V_CRT_LINKAGE int V_CRT_CALL vsnprintf(char *str, size_t size, const char *format, va_list ap);
V_CRT_LINKAGE int V_CRT_CALL fprintf(FILE *stream, const char *format, ...);
V_CRT_LINKAGE int V_CRT_CALL printf(const char *format, ...);
V_CRT_LINKAGE int V_CRT_CALL snprintf(char *str, size_t size, const char *format, ...);
V_CRT_LINKAGE int V_CRT_CALL sprintf(char *str, const char *format, ...);
V_CRT_LINKAGE int V_CRT_CALL sscanf(const char *str, const char *format, ...);
V_CRT_LINKAGE int V_CRT_CALL scanf(const char *format, ...);
#endif
V_CRT_LINKAGE int V_CRT_CALL puts(const char *str);
V_CRT_LINKAGE void V_CRT_CALL perror(const char *str);
V_CRT_LINKAGE int V_CRT_CALL fputs(const char *str, FILE *stream);
V_CRT_LINKAGE int V_CRT_CALL getchar(void);
V_CRT_LINKAGE int V_CRT_CALL putchar(int ch);
V_CRT_LINKAGE int V_CRT_CALL getc(FILE *stream);
V_CRT_LINKAGE int V_CRT_CALL fgetc(FILE *stream);
V_CRT_LINKAGE int V_CRT_CALL ungetc(int ch, FILE *stream);
V_CRT_LINKAGE int V_CRT_CALL fflush(FILE *stream);
V_CRT_LINKAGE int V_CRT_CALL feof(FILE *stream);
V_CRT_LINKAGE int V_CRT_CALL ferror(FILE *stream);
V_CRT_LINKAGE void V_CRT_CALL clearerr(FILE *stream);
V_CRT_LINKAGE int V_CRT_CALL setvbuf(FILE *stream, char *buf, int mode, size_t size);
V_CRT_LINKAGE long V_CRT_CALL ftell(FILE *stream);
V_CRT_LINKAGE void V_CRT_CALL rewind(FILE *stream);
V_CRT_LINKAGE FILE * V_CRT_CALL fopen(const char *filename, const char *mode);
V_CRT_LINKAGE FILE * V_CRT_CALL fdopen(int fd, const char *mode);
V_CRT_LINKAGE FILE * V_CRT_CALL freopen(const char *filename, const char *mode, FILE *stream);
V_CRT_LINKAGE int V_CRT_CALL fileno(FILE *stream);
V_CRT_LINKAGE size_t V_CRT_CALL fread(void *ptr, size_t size, size_t items, FILE *stream);
V_CRT_LINKAGE size_t V_CRT_CALL fwrite(const void *ptr, size_t size, size_t items, FILE *stream);
#if defined(__vinix__)
V_CRT_LINKAGE char * V_CRT_CALL fgets(char *str, size_t size, FILE *stream);
#else
V_CRT_LINKAGE char * V_CRT_CALL fgets(char *str, int size, FILE *stream);
#endif
V_CRT_LINKAGE int V_CRT_CALL fclose(FILE *stream);
#if defined(__vinix__)
V_CRT_LINKAGE FILE * V_CRT_CALL popen(char *command, char *mode);
#else
V_CRT_STDIO_LINKAGE FILE * V_CRT_CALL popen(const char *command, const char *mode);
#endif
V_CRT_STDIO_LINKAGE int V_CRT_CALL pclose(FILE *stream);
V_CRT_LINKAGE void * V_CRT_CALL malloc(size_t size);
V_CRT_LINKAGE void * V_CRT_CALL calloc(size_t nitems, size_t size);
V_CRT_LINKAGE void * V_CRT_CALL realloc(void *ptr, size_t size);
V_CRT_LINKAGE void * V_CRT_CALL aligned_alloc(size_t alignment, size_t size);
V_CRT_LINKAGE int V_CRT_CALL posix_memalign(void **memptr, size_t alignment, size_t size);
V_CRT_LINKAGE void V_CRT_CALL free(void *ptr);
V_CRT_LINKAGE int V_CRT_CALL rand(void);
V_CRT_LINKAGE void V_CRT_CALL srand(unsigned int seed);
V_CRT_LINKAGE int V_CRT_CALL atexit(void (*cb)(void));
V_CRT_LINKAGE void V_CRT_CALL exit(int status);
V_CRT_LINKAGE int V_CRT_CALL abs(int n);
V_CRT_LINKAGE int V_CRT_CALL atoi(const char *str);
V_CRT_LINKAGE double V_CRT_CALL atof(const char *str);
V_CRT_LINKAGE char * V_CRT_CALL getenv(const char *name);
V_CRT_LINKAGE int V_CRT_CALL setenv(const char *name, const char *value, int overwrite);
V_CRT_LINKAGE int V_CRT_CALL unsetenv(const char *name);
V_CRT_LINKAGE int V_CRT_CALL system(const char *command);
V_CRT_LINKAGE int V_CRT_CALL remove(const char *path);
V_CRT_LINKAGE int V_CRT_CALL rename(const char *old_path, const char *new_path);
V_CRT_LINKAGE char * V_CRT_CALL realpath(const char *path, char *resolved_path);
V_CRT_LINKAGE int V_CRT_CALL mkstemp(char *stemplate);
V_CRT_LINKAGE void V_CRT_CALL qsort(void *base, size_t items, size_t item_size, qsort_callback_func cb);
#if defined(__vinix__)
V_CRT_LINKAGE int V_CRT_CALL strcmp(char *left, char *right);
V_CRT_LINKAGE int V_CRT_CALL strncmp(char *left, char *right, size_t n);
#else
V_CRT_LINKAGE int V_CRT_CALL strcmp(const char *left, const char *right);
V_CRT_LINKAGE int V_CRT_CALL strncmp(const char *left, const char *right, size_t n);
#endif
#if !defined(_WIN32) && !defined(_WIN64) && !defined(__BIONIC__)
V_CRT_LINKAGE char * V_CRT_CALL strdup(const char *str);
#endif
#if !defined(_WIN32) && !defined(_WIN64)
V_CRT_LINKAGE int V_CRT_CALL strcasecmp(const char *left, const char *right);
V_CRT_LINKAGE int V_CRT_CALL strncasecmp(const char *left, const char *right, size_t n);
#endif
#if defined(__vinix__)
V_CRT_LINKAGE size_t V_CRT_CALL strlen(char *str);
#else
V_CRT_LINKAGE size_t V_CRT_CALL strlen(const char *str);
#endif
V_CRT_LINKAGE char * V_CRT_CALL strerror(int errnum);
V_CRT_LINKAGE void * V_CRT_CALL memcpy(void *dest, const void *src, size_t n);
V_CRT_LINKAGE void * V_CRT_CALL memmove(void *dest, const void *src, size_t n);
V_CRT_LINKAGE void * V_CRT_CALL memset(void *dest, int ch, size_t n);
V_CRT_LINKAGE int V_CRT_CALL memcmp(const void *left, const void *right, size_t n);
// memchr/strchr/strrchr/strstr are the C23 type-generic string functions, and
// glibc 2.42+ implements them as function-like macros over _Generic, so that a
// const-qualified argument yields a const-qualified return type. If any include
// above already pulled in <string.h> (mbedtls/net_sockets.h, netdb.h, dirent.h,
// ... all do, and gcc 15 defaults to -std=gnu23), the name is already a macro
// here, and a declaration like
// `void *memchr(const void *str, int c, size_t n);` expands into the middle of
// a _Generic expression, which fails to parse:
// `error: expected identifier or ( before _Generic`.
// A defined macro also means <string.h> has already declared the real function,
// so skipping the declaration below loses nothing in that case. The reverse
// order stays fine as-is: a <string.h> pulled in later by a module header
// defines the macro after these declarations, which C permits.
#ifndef memchr
V_CRT_LINKAGE void * V_CRT_CALL memchr(const void *str, int c, size_t n);
#endif
#ifndef strchr
V_CRT_LINKAGE char * V_CRT_CALL strchr(const char *str, int c);
#endif
#ifndef strrchr
V_CRT_LINKAGE char * V_CRT_CALL strrchr(const char *str, int c);
#endif
#ifndef strstr
V_CRT_LINKAGE char * V_CRT_CALL strstr(const char *haystack, const char *needle);
#endif
V_CRT_LINKAGE int V_CRT_CALL fseek(FILE *stream, long offset, int whence);
V_CRT_LINKAGE isize V_CRT_CALL getline(char **lineptr, size_t *n, FILE *stream);
#if defined(_WIN32) || defined(_WIN64)
V_CRT_STDIO_LINKAGE int V_CRT_CALL _fseeki64(FILE *stream, i64 offset, int whence);
V_CRT_LINKAGE int V_CRT_CALL fgetpos(FILE *stream, i64 *pos);
V_CRT_STDIO_LINKAGE int V_CRT_CALL _fileno(FILE *stream);
V_CRT_STDIO_LINKAGE FILE * V_CRT_CALL _wfopen(const unsigned short *filename, const unsigned short *mode);
V_CRT_STDIO_LINKAGE int V_CRT_CALL freopen_s(FILE **new_stream, const char *filename, const char *mode, FILE *stream);
V_CRT_STDIO_LINKAGE FILE * V_CRT_CALL _wfreopen(const unsigned short *filename, const unsigned short *mode, FILE *stream);
V_CRT_STDIO_LINKAGE FILE * V_CRT_CALL _wpopen(const unsigned short *command, const unsigned short *mode);
V_CRT_STDIO_LINKAGE int V_CRT_CALL _pclose(FILE *stream);
V_CRT_STDIO_LINKAGE int V_CRT_CALL _wremove(const unsigned short *path);
V_CRT_LINKAGE void * V_CRT_CALL _aligned_malloc(size_t size, size_t alignment);
V_CRT_LINKAGE void * V_CRT_CALL _aligned_realloc(void *memory, size_t size, size_t alignment);
V_CRT_LINKAGE void V_CRT_CALL _aligned_free(void *memory);
V_CRT_LINKAGE unsigned short * V_CRT_CALL _wgetenv(const unsigned short *varname);
V_CRT_LINKAGE int V_CRT_CALL _wputenv(const unsigned short *envstring);
#endif
#if defined(_MSC_VER) && !defined(__clang__)
#ifndef _TRUNCATE
	#define _TRUNCATE ((size_t)-1)
#endif
V_CRT_LINKAGE int V_CRT_CALL _vscprintf(const char *format, va_list ap);
V_CRT_LINKAGE int V_CRT_CALL _vsnprintf_s(char *buffer, size_t size, size_t count, const char *format, va_list ap);
#endif
#endif
#ifndef _IOFBF
	#define _IOFBF 0
#endif
#ifndef _IOLBF
	#define _IOLBF 1
#endif
#ifndef _IONBF
	#define _IONBF 2
#endif
#ifndef EOF
	#define EOF (-1)
#endif
#ifndef SEEK_SET
	#define SEEK_SET 0
#endif
#ifndef SEEK_CUR
	#define SEEK_CUR 1
#endif
#ifndef SEEK_END
	#define SEEK_END 2
#endif
#ifndef RAND_MAX
enum {
	#if defined(_MSC_VER)
		RAND_MAX = 0x7fff
	#else
		RAND_MAX = 2147483647
	#endif
};
#endif
#undef V_CRT_STDIO_LINKAGE
#undef V_CRT_LINKAGE
#undef V_CRT_CALL
#define V_MANUAL_STDLIB_HEADERS 1
void abort(void);
#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <inttypes.h>
#include <limits.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>
#if defined(__has_include)
#if __has_include(<wchar.h>)
#include <wchar.h>
#endif
#else
#include <wchar.h>
#endif
#if defined(_WIN32) && (defined(__TINYC__) || (defined(_MSC_VER) && !defined(__clang__)))
#include "/Users/alex/code/v/thirdparty/stdatomic/win/atomic.h"
#else
#if defined(__OBJC__) && defined(__GNUC__) && !defined(__clang__)
#define _Atomic volatile
#endif
#include <stdatomic.h>
#if defined(__OBJC__) && defined(__GNUC__) && !defined(__clang__)
#undef _Atomic
#endif
#endif
#if defined(__linux__) || defined(__ANDROID__)
#include <sys/syscall.h>
#endif
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
#include <sys/event.h>
#endif
#ifdef _WIN32
#include <io.h>
#include <process.h>
#include <windows.h>
#if defined(_MSC_VER)
#include <intrin.h>
#include <dbghelp.h>
#endif
#else
#include <dirent.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <pthread.h>
#include <arpa/inet.h>
#include <netinet/tcp.h>
#include <semaphore.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <utime.h>
#endif
#ifdef __APPLE__
#include <mach/mach_time.h>
#include <mach-o/dyld.h>
#endif
#if defined(__linux__) || defined(__ANDROID__)
#include <sys/epoll.h>
#endif
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__) || defined(__DragonFly__)
#include <sys/event.h>
#endif
#if defined(__has_include) && !defined(__TINYC__)
	#if __has_include(<execinfo.h>) && !defined(_WIN32)
		#define __V_HAVE_EXECINFO_H 1
		#include <execinfo.h>
	#endif
#elif (defined(__linux__) && (defined(__GLIBC__) || defined(__GNU_LIBRARY__))) || defined(__APPLE__) || defined(__NetBSD__) || defined(__FreeBSD__) || defined(__DragonFly__)
	#define __V_HAVE_EXECINFO_H 1
	#include <execinfo.h>
#endif
#if !defined(__V_HAVE_EXECINFO_H) && !defined(_WIN32)
int backtrace(void** __array, int __size);
char** backtrace_symbols(void* const* __array, int __size);
void backtrace_symbols_fd(void* const* __array, int __size, int __fd);
#endif

#ifndef _WIN32
extern char** environ;
#endif
static void* __v_thread_alloc(size_t size) {
#if defined(_VGCBOEHM) || defined(CUSTOM_DEFINE_gcboehm)
	void* p = GC_MALLOC_UNCOLLECTABLE(size);
#else
	void* p = malloc(size);
#endif
	if (!p) { fprintf(stderr, "V thread allocation failed\n"); abort(); }
	return p;
}
static void __v_thread_free(void* ptr) {
#if defined(_VGCBOEHM) || defined(CUSTOM_DEFINE_gcboehm)
	GC_FREE(ptr);
#else
	free(ptr);
#endif
}
#ifdef _WIN32
typedef struct { HANDLE handle; void* context; } __v_thread;
static bool __v_thread_equal(__v_thread a, __v_thread b) { return a.handle == b.handle; }
typedef void* (*__v_thread_start_fn)(void*);
typedef struct { __v_thread_start_fn start; void* arg; void* result; } __v_windows_thread_context;
static const size_t __v_thread_stack_size = V_THREAD_STACK_SIZE;
static DWORD WINAPI __v_windows_thread_start(void* raw_context) { __v_windows_thread_context* context = (__v_windows_thread_context*)raw_context; context->result = context->start(context->arg); return 0; }
static __v_thread __v_thread_spawn(__v_thread_start_fn start, void* arg, void (*cleanup)(void*)) {
	__v_thread result;
	__v_windows_thread_context* context = (__v_windows_thread_context*)__v_thread_alloc(sizeof(__v_windows_thread_context));
	context->start = start; context->arg = arg; context->result = NULL;
	result.context = context;
	result.handle = CreateThread(NULL, __v_thread_stack_size, __v_windows_thread_start, context, 0, NULL);
	if (!result.handle) { DWORD error = GetLastError(); free(context); if (cleanup) cleanup(arg); fprintf(stderr, "V thread creation failed: %lu\n", (unsigned long)error); abort(); }
	return result;
}
static void* __v_thread_join(__v_thread thread) {
	DWORD rc = WaitForSingleObject(thread.handle, INFINITE);
	if (rc != WAIT_OBJECT_0) { fprintf(stderr, "V thread join failed: %lu\n", (unsigned long)rc); abort(); }
	void* result = ((__v_windows_thread_context*)thread.context)->result;
	if (!CloseHandle(thread.handle)) { DWORD error = GetLastError(); __v_thread_free(thread.context); fprintf(stderr, "V thread handle cleanup failed: %lu\n", (unsigned long)error); abort(); }
	__v_thread_free(thread.context);
	return result;
}
static DWORD WINAPI __v_windows_detached_thread_start(void* raw_context) { __v_windows_thread_context context = *(__v_windows_thread_context*)raw_context; __v_thread_free(raw_context); void* result = context.start(context.arg); if (result) __v_thread_free(result); return 0; }
static __v_thread __v_thread_spawn_detached(__v_thread_start_fn start, void* arg, void (*cleanup)(void*)) {
	__v_windows_thread_context* context = (__v_windows_thread_context*)__v_thread_alloc(sizeof(__v_windows_thread_context));
	context->start = start; context->arg = arg; context->result = NULL;
	HANDLE handle = CreateThread(NULL, __v_thread_stack_size, __v_windows_detached_thread_start, context, 0, NULL);
	if (!handle) { DWORD error = GetLastError(); __v_thread_free(context); if (cleanup) cleanup(arg); fprintf(stderr, "V thread creation failed: %lu\n", (unsigned long)error); abort(); }
	if (!CloseHandle(handle)) { fprintf(stderr, "V thread handle cleanup failed: %lu\n", (unsigned long)GetLastError()); abort(); }
	return (__v_thread){0};
}
static __v_thread __v_thread_spawn_comparable(__v_thread_start_fn start, void* arg, void (*cleanup)(void*)) {
	__v_windows_thread_context* context = (__v_windows_thread_context*)__v_thread_alloc(sizeof(__v_windows_thread_context));
	context->start = start; context->arg = arg; context->result = NULL;
	HANDLE handle = CreateThread(NULL, __v_thread_stack_size, __v_windows_detached_thread_start, context, 0, NULL);
	if (!handle) { DWORD error = GetLastError(); __v_thread_free(context); if (cleanup) cleanup(arg); fprintf(stderr, "V thread creation failed: %lu\n", (unsigned long)error); abort(); }
	return (__v_thread){.handle = handle, .context = NULL};
}
static void __v_thread_release_comparable(__v_thread thread) { if (thread.handle && !CloseHandle(thread.handle)) { fprintf(stderr, "V thread handle cleanup failed: %lu\n", (unsigned long)GetLastError()); abort(); } }
#else
typedef struct { pthread_t handle; } __v_thread;
static bool __v_thread_equal(__v_thread a, __v_thread b) { return pthread_equal(a.handle, b.handle) != 0; }
typedef void* (*__v_thread_start_fn)(void*);
static const size_t __v_thread_stack_size = V_THREAD_STACK_SIZE;
static __v_thread __v_thread_spawn(__v_thread_start_fn start, void* arg, void (*cleanup)(void*)) {
	__v_thread result;
	pthread_attr_t attr;
	int rc = pthread_attr_init(&attr);
	if (rc != 0) { if (cleanup) cleanup(arg); fprintf(stderr, "V thread attribute initialization failed: %d\n", rc); abort(); }
	rc = pthread_attr_setstacksize(&attr, __v_thread_stack_size);
	if (rc != 0) { pthread_attr_destroy(&attr); if (cleanup) cleanup(arg); fprintf(stderr, "V thread stack size setup failed: %d\n", rc); abort(); }
	rc = pthread_create(&result.handle, &attr, (void*)start, arg);
	int attr_rc = pthread_attr_destroy(&attr);
	if (rc != 0) { if (cleanup) cleanup(arg); fprintf(stderr, "V thread creation failed: %d\n", rc); abort(); }
	if (attr_rc != 0) { fprintf(stderr, "V thread attribute cleanup failed: %d\n", attr_rc); abort(); }
	return result;
}
static void* __v_thread_join(__v_thread thread) { void* result = NULL; int rc = pthread_join(thread.handle, &result); if (rc != 0) { fprintf(stderr, "V thread join failed: %d\n", rc); abort(); } return result; }
typedef struct { __v_thread_start_fn start; void* arg; } __v_detached_thread_context;
static void* __v_detached_thread_start(void* raw_context) { __v_detached_thread_context context = *(__v_detached_thread_context*)raw_context; __v_thread_free(raw_context); void* result = context.start(context.arg); if (result) __v_thread_free(result); return NULL; }
static __v_thread __v_thread_spawn_detached(__v_thread_start_fn start, void* arg, void (*cleanup)(void*)) {
	__v_detached_thread_context* context = (__v_detached_thread_context*)__v_thread_alloc(sizeof(__v_detached_thread_context));
	context->start = start; context->arg = arg;
	pthread_t handle;
	pthread_attr_t attr;
	int rc = pthread_attr_init(&attr);
	if (rc != 0) { __v_thread_free(context); if (cleanup) cleanup(arg); fprintf(stderr, "V thread attribute initialization failed: %d\n", rc); abort(); }
	rc = pthread_attr_setstacksize(&attr, __v_thread_stack_size);
	if (rc == 0) rc = pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
	if (rc != 0) { pthread_attr_destroy(&attr); __v_thread_free(context); if (cleanup) cleanup(arg); fprintf(stderr, "V thread attribute setup failed: %d\n", rc); abort(); }
	rc = pthread_create(&handle, &attr, (void*)__v_detached_thread_start, context);
	int attr_rc = pthread_attr_destroy(&attr);
	if (rc != 0) { __v_thread_free(context); if (cleanup) cleanup(arg); fprintf(stderr, "V thread creation failed: %d\n", rc); abort(); }
	if (attr_rc != 0) { fprintf(stderr, "V thread attribute cleanup failed: %d\n", attr_rc); abort(); }
	return (__v_thread){0};
}
static __v_thread __v_thread_spawn_comparable(__v_thread_start_fn start, void* arg, void (*cleanup)(void*)) { return __v_thread_spawn(start, arg, cleanup); }
static void __v_thread_release_comparable(__v_thread thread) { if (thread.handle) { int rc = pthread_detach(thread.handle); if (rc != 0) { fprintf(stderr, "V thread detach failed: %d\n", rc); abort(); } } }
#endif
#ifndef __V_architecture
#define __V_architecture 0
#endif
#if defined(__x86_64__) || defined(_M_AMD64)
#define __V_amd64 1
#undef __V_architecture
#define __V_architecture 1
#endif
#if defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
#define __V_arm64 1
#undef __V_architecture
#define __V_architecture 2
#endif
#if defined(__arm__) || defined(_M_ARM)
#define __V_arm32 1
#undef __V_architecture
#define __V_architecture 3
#endif
#if defined(__riscv) && __riscv_xlen == 64
#define __V_rv64 1
#undef __V_architecture
#define __V_architecture 4
#endif
#if defined(__riscv) && __riscv_xlen == 32
#define __V_rv32 1
#undef __V_architecture
#define __V_architecture 5
#endif
#if defined(__i386__) || defined(_M_IX86)
#define __V_x86 1
#undef __V_architecture
#define __V_architecture 6
#endif
#if defined(__s390x__)
#define __V_s390x 1
#undef __V_architecture
#define __V_architecture 7
#endif
#if defined(__powerpc64__) && defined(__LITTLE_ENDIAN__)
#define __V_ppc64le 1
#undef __V_architecture
#define __V_architecture 8
#endif
#if defined(__loongarch64)
#define __V_loongarch64 1
#undef __V_architecture
#define __V_architecture 9
#endif
#if defined(__sparc__)
#define __V_sparc64 1
#undef __V_architecture
#define __V_architecture 10
#endif
#if defined(__powerpc64__) && defined(__BIG_ENDIAN__)
#define __V_ppc64 1
#undef __V_architecture
#define __V_architecture 11
#endif
#if (defined(__powerpc__) || defined(__powerpc) || defined(__POWERPC__) || defined(__ppc__) || defined(__ppc) || defined(__PPC__)) && !defined(__powerpc64__) && !defined(__ppc64__) && !defined(__PPC64__)
#define __V_ppc 1
#undef __V_architecture
#define __V_architecture 12
#endif
#if UINTPTR_MAX == 0xFFFFFFFFFFFFFFFFu
#define TARGET_IS_64BIT 1
#else
#define TARGET_IS_32BIT 1
#endif
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define TARGET_ORDER_IS_BIG 1
#else
#define TARGET_ORDER_IS_LITTLE 1
#endif

#define elem_size element_size
#define c_name types__c_name
#define builtin__string_clone string__clone
#define builtin__tos2 tos2
#include "/Users/alex/code/v/vlib/builtin/track_heap_checks.h"

typedef enum {
	ArrayFlags__noslices = 1,
	ArrayFlags__noshrink = 2,
	ArrayFlags__nogrow = 4,
	ArrayFlags__nofree = 8,
	ArrayFlags__managed = 16,
	ArrayFlags__noscan_data = 32,
	ArrayFlags__is_slice = 64,
} ArrayFlags;

typedef enum {
	ChanState__success = 0,
	ChanState__not_ready = 1,
	ChanState__closed = 2,
} ChanState;

typedef enum {
	GraphemeBreakProperty__other = 0,
	GraphemeBreakProperty__cr = 1,
	GraphemeBreakProperty__lf = 2,
	GraphemeBreakProperty__control = 3,
	GraphemeBreakProperty__extend = 4,
	GraphemeBreakProperty__regional_indicator = 5,
	GraphemeBreakProperty__prepend = 6,
	GraphemeBreakProperty__spacing_mark = 7,
	GraphemeBreakProperty__l = 8,
	GraphemeBreakProperty__v = 9,
	GraphemeBreakProperty__t = 10,
	GraphemeBreakProperty__lv = 11,
	GraphemeBreakProperty__lvt = 12,
	GraphemeBreakProperty__zwj = 13,
} GraphemeBreakProperty;

typedef enum {
	AttributeKind__plain = 0,
	AttributeKind__string = 1,
	AttributeKind__number = 2,
	AttributeKind__bool = 3,
	AttributeKind__comptime_define = 4,
} AttributeKind;

typedef enum {
	MapMode__to_upper = 0,
	MapMode__to_lower = 1,
	MapMode__to_title = 2,
} MapMode;

typedef enum {
	TrimMode__trim_left = 0,
	TrimMode__trim_right = 1,
	TrimMode__trim_both = 2,
} TrimMode;

typedef enum {
	StrIntpType__si_no_str = 0,
	StrIntpType__si_c = 1,
	StrIntpType__si_u8 = 2,
	StrIntpType__si_i8 = 3,
	StrIntpType__si_u16 = 4,
	StrIntpType__si_i16 = 5,
	StrIntpType__si_u32 = 6,
	StrIntpType__si_i32 = 7,
	StrIntpType__si_u64 = 8,
	StrIntpType__si_i64 = 9,
	StrIntpType__si_e32 = 10,
	StrIntpType__si_e64 = 11,
	StrIntpType__si_f32 = 12,
	StrIntpType__si_f64 = 13,
	StrIntpType__si_g32 = 14,
	StrIntpType__si_g64 = 15,
	StrIntpType__si_s = 16,
	StrIntpType__si_p = 17,
	StrIntpType__si_r = 18,
	StrIntpType__si_vp = 19,
} StrIntpType;

typedef enum {
	strings__IndentState__normal = 0,
	strings__IndentState__in_string = 1,
} strings__IndentState;

typedef enum {
	strconv__Align_text__right = 0,
	strconv__Align_text__left = 1,
	strconv__Align_text__center = 2,
} strconv__Align_text;

typedef enum {
	strconv__ParserState__ok = 0,
	strconv__ParserState__pzero = 1,
	strconv__ParserState__mzero = 2,
	strconv__ParserState__pinf = 3,
	strconv__ParserState__minf = 4,
	strconv__ParserState__invalid_number = 5,
	strconv__ParserState__extra_char = 6,
} strconv__ParserState;

typedef enum {
	strconv__Char_parse_state__start = 0,
	strconv__Char_parse_state__norm_char = 1,
	strconv__Char_parse_state__field_char = 2,
	strconv__Char_parse_state__pad_ch = 3,
	strconv__Char_parse_state__len_set_start = 4,
	strconv__Char_parse_state__len_set_in = 5,
	strconv__Char_parse_state__check_type = 6,
	strconv__Char_parse_state__check_float = 7,
	strconv__Char_parse_state__check_float_in = 8,
	strconv__Char_parse_state__reset_params = 9,
} strconv__Char_parse_state;

typedef struct AnonStruct__x2f_Users_x2f_alex_x2f_code_x2f_v_x2f_vlib_x2f_builtin_x2f_string_x2e_v_1 AnonStruct__x2f_Users_x2f_alex_x2f_code_x2f_v_x2f_vlib_x2f_builtin_x2f_string_x2e_v_1;
typedef struct ArrayDataHeader ArrayDataHeader;
typedef struct AutostrAddrStackState AutostrAddrStackState;
typedef struct DenseArray DenseArray;
typedef struct EnumData EnumData;
typedef struct Error Error;
typedef struct FieldData FieldData;
typedef struct FunctionData FunctionData;
typedef struct FunctionParam FunctionParam;
typedef struct GCHeapUsage GCHeapUsage;
typedef struct GraphemeState GraphemeState;
typedef struct InputRuneIterator InputRuneIterator;
typedef struct MessageError MessageError;
typedef struct None__ None__;
typedef struct Option Option;
typedef struct OwnershipIErrorPayload OwnershipIErrorPayload;
typedef struct OwnershipV3InterfacePayload OwnershipV3InterfacePayload;
typedef struct PanicDebugInfo PanicDebugInfo;
typedef struct PanicFrame PanicFrame;
typedef struct PanicRecord PanicRecord;
typedef struct PanicState PanicState;
typedef struct PreallocStats PreallocStats;
typedef struct main__Probe main__Probe;
typedef struct RepIndex RepIndex;
typedef struct RunesIterator RunesIterator;
typedef struct SliceIndex SliceIndex;
typedef struct SortedMap SortedMap;
typedef struct StrIntpCgenData StrIntpCgenData;
typedef struct StrIntpData StrIntpData;
typedef union StrIntpMem StrIntpMem;
typedef struct ToWideConfig ToWideConfig;
typedef struct VAssertMetaInfo VAssertMetaInfo;
typedef struct VAttribute VAttribute;
typedef struct VCastTypeIndexName VCastTypeIndexName;
typedef struct VContext VContext;
typedef struct VMapData VMapData;
typedef struct VMemoryBlock VMemoryBlock;
typedef struct VPreallocBlockCache VPreallocBlockCache;
typedef struct VPreallocRange VPreallocRange;
typedef struct VPreallocScope VPreallocScope;
typedef struct VariantData VariantData;
typedef struct WrapConfig WrapConfig;
typedef struct _option _option;
typedef struct array array;
typedef struct map map;
typedef struct mapnode mapnode;
typedef struct strconv__AtoF64Param strconv__AtoF64Param;
typedef struct strconv__BF_param strconv__BF_param;
typedef struct strconv__Dec32 strconv__Dec32;
typedef struct strconv__Dec64 strconv__Dec64;
typedef union strconv__Float32u strconv__Float32u;
typedef union strconv__Float64u strconv__Float64u;
typedef struct strconv__PrepNumber strconv__PrepNumber;
typedef struct strconv__Separator strconv__Separator;
typedef union strconv__Uf32 strconv__Uf32;
typedef union strconv__Uf64 strconv__Uf64;
typedef struct strconv__Uint128 strconv__Uint128;
typedef struct string string;
typedef struct strings__IndentParam strings__IndentParam;
typedef struct strconv__SeparatorOptions strconv__SeparatorOptions;
typedef struct IError IError;
typedef array Array;

typedef struct multi_return_u32_u32 multi_return_u32_u32;
typedef struct multi_return_u64_u64 multi_return_u64_u64;
typedef struct multi_return_strconv__Dec32_bool multi_return_strconv__Dec32_bool;
typedef struct multi_return_strconv__Dec64_bool multi_return_strconv__Dec64_bool;
typedef struct multi_return_u32_i64 multi_return_u32_i64;
typedef struct multi_return_string_string multi_return_string_string;
typedef struct multi_return_i64_i64 multi_return_i64_i64;
typedef struct multi_return_size_t_size_t multi_return_size_t_size_t;
typedef struct multi_return_size_t_size_t_size_t_size_t_size_t multi_return_size_t_size_t_size_t_size_t_size_t;
typedef struct multi_return_u64_i64 multi_return_u64_i64;
typedef struct multi_return_u32_u32_u32 multi_return_u32_u32_u32;
typedef struct multi_return_int_strconv__PrepNumber multi_return_int_strconv__PrepNumber;
typedef struct multi_return_double_i64 multi_return_double_i64;

typedef double Array_fixed_double_36[36];
typedef i32 Array_fixed_i32_1264[1264];
typedef i64 Array_fixed_i64_10[10];
typedef i64 Array_fixed_i64_20[20];
typedef i64 Array_fixed_i64_64[64];
typedef u32 Array_fixed_u32_10[10];
typedef u64 Array_fixed_u64_18[18];
typedef u64 Array_fixed_u64_2[2];
typedef u64 Array_fixed_u64_20[20];
typedef u64 Array_fixed_u64_309[309];
typedef u64 Array_fixed_u64_31[31];
typedef u64 Array_fixed_u64_324[324];
typedef u64 Array_fixed_u64_47[47];
typedef u64 Array_fixed_u64_584[584];
typedef u64 Array_fixed_u64_652[652];
typedef u8 Array_fixed_u8_17[17];
typedef u8 Array_fixed_u8_20[20];
typedef u8 Array_fixed_u8_256[256];
typedef u8 Array_fixed_u8_26[26];
typedef u8 Array_fixed_u8_32[32];
typedef u8 Array_fixed_u8_5[5];
typedef u8 Array_fixed_u8_512[512];
typedef u8 Array_fixed_u8_64[64];
typedef void* Array_fixed_voidptr_11[11];
typedef void* Array_fixed_voidptr_64[64];
typedef void* Array_fixed_voidptr_8[8];

typedef bool (*_fn_ptr_c95f092653bee64)(void*, void*);
typedef i64 (*_fn_ptr_ed95774d3a4e97ab)(void*, void*);
typedef u64 (*_fn_ptr_1e8d64a3d95a0da1)(void*);
typedef void (*_fn_ptr_a73f2ae88698453e)(char*, size_t);
typedef void (*_fn_ptr_39790037d38ea68)(void);
typedef void (*_fn_ptr_5373f7edc7b60e26)(void*);
typedef void (*_fn_ptr_1a3da2026b1489ea)(void*, void*);

typedef struct AnonStruct__x2f_Users_x2f_alex_x2f_code_x2f_v_x2f_vlib_x2f_builtin_x2f_string_x2e_v_1 AnonStruct__x2f_Users_x2f_alex_x2f_code_x2f_v_x2f_vlib_x2f_builtin_x2f_string_x2e_v_1;
typedef struct ArrayDataHeader ArrayDataHeader;
typedef struct AutostrAddrStackState AutostrAddrStackState;
typedef struct DenseArray DenseArray;
typedef struct EnumData EnumData;
typedef struct Error Error;
typedef struct FieldData FieldData;
typedef struct FunctionData FunctionData;
typedef struct FunctionParam FunctionParam;
typedef struct GCHeapUsage GCHeapUsage;
typedef struct GraphemeState GraphemeState;
typedef struct InputRuneIterator InputRuneIterator;
typedef struct MessageError MessageError;
typedef struct None__ None__;
typedef struct Option Option;
typedef struct OwnershipIErrorPayload OwnershipIErrorPayload;
typedef struct OwnershipV3InterfacePayload OwnershipV3InterfacePayload;
typedef struct PanicDebugInfo PanicDebugInfo;
typedef struct PanicFrame PanicFrame;
typedef struct PanicRecord PanicRecord;
typedef struct PanicState PanicState;
typedef struct PreallocStats PreallocStats;
typedef struct main__Probe main__Probe;
typedef struct RepIndex RepIndex;
typedef struct RunesIterator RunesIterator;
typedef struct SliceIndex SliceIndex;
typedef struct SortedMap SortedMap;
typedef struct StrIntpCgenData StrIntpCgenData;
typedef struct StrIntpData StrIntpData;
typedef union StrIntpMem StrIntpMem;
typedef struct ToWideConfig ToWideConfig;
typedef struct VAssertMetaInfo VAssertMetaInfo;
typedef struct VAttribute VAttribute;
typedef struct VCastTypeIndexName VCastTypeIndexName;
typedef struct VContext VContext;
typedef struct VMapData VMapData;
typedef struct VMemoryBlock VMemoryBlock;
typedef struct VPreallocBlockCache VPreallocBlockCache;
typedef struct VPreallocRange VPreallocRange;
typedef struct VPreallocScope VPreallocScope;
typedef struct VariantData VariantData;
typedef struct WrapConfig WrapConfig;
typedef struct _option _option;
typedef struct array array;
typedef struct map map;
typedef struct mapnode mapnode;
typedef struct strconv__AtoF64Param strconv__AtoF64Param;
typedef struct strconv__BF_param strconv__BF_param;
typedef struct strconv__Dec32 strconv__Dec32;
typedef struct strconv__Dec64 strconv__Dec64;
typedef union strconv__Float32u strconv__Float32u;
typedef union strconv__Float64u strconv__Float64u;
typedef struct strconv__PrepNumber strconv__PrepNumber;
typedef struct strconv__Separator strconv__Separator;
typedef union strconv__Uf32 strconv__Uf32;
typedef union strconv__Uf64 strconv__Uf64;
typedef struct strconv__Uint128 strconv__Uint128;
typedef struct string string;
typedef struct strings__IndentParam strings__IndentParam;
typedef struct strconv__SeparatorOptions strconv__SeparatorOptions;
typedef struct IError IError;
typedef array Array;
struct string {
	u8* str;
	i64 len;
	i64 is_lit;
};

struct IError {
	void* _object;
	union {
		void* _interface_meta;
		struct {
			u32 _typ : 31;
			u32 _object_is_boxed : 1;
		};
	};
};

typedef struct __v_option { bool ok; int value; } __v_option;
typedef struct __v_result { bool ok; union { IError err; int value; }; } __v_result;

struct array {
	void* data;
	i64 offset;
	i64 len;
	i64 cap;
	int flags;
	i64 element_size;
};

struct map {
	VMapData* data;
};

struct AnonStruct__x2f_Users_x2f_alex_x2f_code_x2f_v_x2f_vlib_x2f_builtin_x2f_string_x2e_v_1 {
	bool allow_extra_chars;
};

typedef string Array_fixed_string_11[11];
typedef ptrdiff_t Array_fixed_ptrdiff_t_8[8];
#pragma pack(push, 1)
struct ArrayDataHeader {
	void* allocation;
	bool has_slices;
};
#pragma pack(pop)

struct AutostrAddrStackState {
	void* addrs[64];
	i64 types[64];
	i64 len;
	i64 overflow_depth;
};

struct DenseArray {
	i64 key_bytes;
	i64 value_bytes;
	i64 cap;
	i64 len;
	u32 deletes;
	u8* all_deleted;
	u8* keys;
	u8* values;
};

struct EnumData {
	string name;
	i64 value;
	Array attrs;
};

struct Error {
	E_STRUCT_DECL;
};

struct FieldData {
	string name;
	i64 typ;
	i64 unaliased_typ;
	Array attrs;
	bool is_pub;
	bool is_mut;
	bool is_embed;
	bool is_shared;
	bool is_atomic;
	bool is_option;
	bool is_array;
	bool is_map;
	bool is_chan;
	bool is_enum;
	bool is_struct;
	bool is_alias;
	u8 indirections;
};

struct FunctionData {
	string name;
	string location;
	Array attrs;
	Array attributes;
	Array args;
	i64 return_type;
	i64 typ;
};

struct FunctionParam {
	i64 typ;
	string name;
};

struct GCHeapUsage {
	size_t heap_size;
	size_t free_bytes;
	size_t total_bytes;
	size_t unmapped_bytes;
	size_t bytes_since_gc;
};

struct GraphemeState {
	int prev_prop;
	i64 ri_count;
	u8 extended_pictographic_state;
};

struct InputRuneIterator {
	E_STRUCT_DECL;
};

struct MessageError {
	string msg;
	i64 code;
};

struct None__ {
	Error Error;
};

struct Option {
	u8 state;
};

struct OwnershipIErrorPayload {
	void* payload;
};

struct OwnershipV3InterfacePayload {
	void* payload;
	i64 typ;
	bool is_boxed;
};

struct PanicDebugInfo {
	i64 line_no;
	string file;
	string mod;
	string fn_name;
};

struct PanicFrame {
	PanicFrame* prev;
	void* owner;
	_fn_ptr_5373f7edc7b60e26 jump;
};

struct PanicRecord {
	string msg;
	PanicDebugInfo debug;
	PanicFrame* frame;
	PanicFrame* resume;
	bool recovered;
	bool aborted;
};

struct PanicState {
	PanicFrame* top;
	PanicRecord* records;
	i64 len;
	i64 cap;
};

struct PreallocStats {
	bool enabled;
	u64 allocation_count;
	u64 allocated_bytes;
};

struct main__Probe {
	u64 value;
};

struct RepIndex {
	i64 idx;
	i64 val_idx;
};

struct RunesIterator {
	string s;
	i64 i;
};

struct SliceIndex {
	bool is_range;
	i64 value;
	i64 low;
	i64 high;
	bool has_low;
	bool has_high;
};

struct SortedMap {
	i64 value_bytes;
	mapnode* root;
	i64 len;
};

struct StrIntpCgenData {
	string str;
	string fmt;
	string d;
};

union StrIntpMem {
	u32 d_c;
	u8 d_u8;
	i8 d_i8;
	u16 d_u16;
	i16 d_i16;
	u32 d_u32;
	i32 d_i32;
	u64 d_u64;
	i64 d_i64;
	float d_f32;
	double d_f64;
	string d_s;
	string d_r;
	void* d_p;
	void* d_vp;
};

struct ToWideConfig {
	bool from_ansi;
};

struct VAssertMetaInfo {
	string fpath;
	i64 line_nr;
	string fn_name;
	string src;
	string op;
	string llabel;
	string rlabel;
	string lvalue;
	string rvalue;
	string message;
	bool has_msg;
};

struct VAttribute {
	string name;
	bool has_arg;
	string arg;
	int kind;
};

struct VCastTypeIndexName {
	i64 tindex;
	string tname;
};

struct VContext {
	i64 allocator;
};

struct VMapData {
	i64 key_bytes;
	i64 value_bytes;
	u32 even_index;
	u8 cached_hashbits;
	u8 shift;
	DenseArray key_values;
	u32* metas;
	u32 extra_metas;
	bool has_string_keys;
	_fn_ptr_1e8d64a3d95a0da1 hash_fn;
	_fn_ptr_c95f092653bee64 key_eq_fn;
	_fn_ptr_1a3da2026b1489ea clone_fn;
	_fn_ptr_5373f7edc7b60e26 free_fn;
	i64 count;
};

struct VMemoryBlock {
	u8* current;
	u8* stop;
	u8* start;
	VMemoryBlock* previous;
	VMemoryBlock* next;
	VPreallocScope* scope;
	VPreallocBlockCache* recycle_cache;
	ptrdiff_t min_block_size;
	bool is_scope;
	bool mmap_allocated;
	i64 id;
	i64 mallocs;
};

struct VPreallocBlockCache {
	i64 count;
	ptrdiff_t bytes;
	void* starts[8];
	ptrdiff_t sizes[8];
};

struct VPreallocRange {
	size_t start;
	size_t stop;
};

struct VPreallocScope {
	VMemoryBlock* previous;
	VMemoryBlock* first;
	VMemoryBlock* saved_next;
	size_t min_address;
	size_t max_address;
	VPreallocRange* ranges;
	i64 ranges_len;
	i64 ranges_cap;
	i32 refs;
	i32 free_requested;
	i32 abandoned;
	i32 finalized;
};

struct VariantData {
	i64 typ;
};

struct WrapConfig {
	i64 width;
	string end;
};

struct _option {
	u8 state;
};

struct mapnode {
	void** children;
	i64 len;
	string keys[11];
	void* values[11];
};

struct strconv__AtoF64Param {
	bool allow_extra_chars;
};

struct strconv__BF_param {
	u8 pad_ch;
	i64 len0;
	i64 len1;
	bool positive;
	bool sign_flag;
	int align;
	bool rm_tail_zero;
};

struct strconv__Dec32 {
	u32 m;
	i64 e;
};

struct strconv__Dec64 {
	u64 m;
	i64 e;
};

union strconv__Float32u {
	float f;
	u32 u;
};

union strconv__Float64u {
	double f;
	u64 u;
};

struct strconv__PrepNumber {
	bool negative;
	i64 exponent;
	u64 mantissa;
};

struct strconv__Separator {
	string integer;
	string decimal;
};

union strconv__Uf32 {
	float f;
	u32 u;
};

union strconv__Uf64 {
	double f;
	u64 u;
};

struct strconv__Uint128 {
	u64 lo;
	u64 hi;
};

struct strings__IndentParam {
	u32 block_start;
	u32 block_end;
	u32 indent_char;
	i64 indent_count;
	i64 starting_level;
};

struct strconv__SeparatorOptions {
	int typ;
	u32 _pointer_variant_is_owned;
	union {
		string* _string;
		strconv__Separator* strconv__Separator;
	};
};

struct StrIntpData {
	string str;
	u32 fmt;
	StrIntpMem d;
	i64 dyn_width;
	i64 dyn_precision;
	u8 dyn_flags;
};

struct multi_return_u32_u32 {
	u32 arg0;
	u32 arg1;
};
struct multi_return_u64_u64 {
	u64 arg0;
	u64 arg1;
};
struct multi_return_strconv__Dec32_bool {
	strconv__Dec32 arg0;
	bool arg1;
};
struct multi_return_strconv__Dec64_bool {
	strconv__Dec64 arg0;
	bool arg1;
};
struct multi_return_u32_i64 {
	u32 arg0;
	i64 arg1;
};
struct multi_return_string_string {
	string arg0;
	string arg1;
};
struct multi_return_i64_i64 {
	i64 arg0;
	i64 arg1;
};
struct multi_return_size_t_size_t {
	size_t arg0;
	size_t arg1;
};
struct multi_return_size_t_size_t_size_t_size_t_size_t {
	size_t arg0;
	size_t arg1;
	size_t arg2;
	size_t arg3;
	size_t arg4;
};
struct multi_return_u64_i64 {
	u64 arg0;
	i64 arg1;
};
struct multi_return_u32_u32_u32 {
	u32 arg0;
	u32 arg1;
	u32 arg2;
};
struct multi_return_int_strconv__PrepNumber {
	int arg0;
	strconv__PrepNumber arg1;
};
struct multi_return_double_i64 {
	double arg0;
	i64 arg1;
};

typedef struct __v_option_i64 { bool ok; i64 value; } __v_option_i64;
typedef struct __v_option_multi_return_string_string { bool ok; multi_return_string_string value; } __v_option_multi_return_string_string;
typedef struct __v_option_string { bool ok; string value; } __v_option_string;
typedef struct __v_option_u32 { bool ok; u32 value; } __v_option_u32;
typedef struct __v_option_u8 { bool ok; u8 value; } __v_option_u8;
typedef struct __v_result_double { bool ok; union { IError err; double value; }; } __v_result_double;
typedef struct __v_result_i16 { bool ok; union { IError err; i16 value; }; } __v_result_i16;
typedef struct __v_result_i32 { bool ok; union { IError err; i32 value; }; } __v_result_i32;
typedef struct __v_result_i64 { bool ok; union { IError err; i64 value; }; } __v_result_i64;
typedef struct __v_result_i8 { bool ok; union { IError err; i8 value; }; } __v_result_i8;
typedef struct __v_result_multi_return_i64_i64 { bool ok; union { IError err; multi_return_i64_i64 value; }; } __v_result_multi_return_i64_i64;
typedef struct __v_result_string { bool ok; union { IError err; string value; }; } __v_result_string;
typedef struct __v_result_u16 { bool ok; union { IError err; u16 value; }; } __v_result_u16;
typedef struct __v_result_u32 { bool ok; union { IError err; u32 value; }; } __v_result_u32;
typedef struct __v_result_u64 { bool ok; union { IError err; u64 value; }; } __v_result_u64;
typedef struct __v_result_u8 { bool ok; union { IError err; u8 value; }; } __v_result_u8;

#ifdef __linux__
#ifndef SYS_gettid
#if defined(__x86_64__)
#define SYS_gettid 186
#elif defined(__aarch64__)
#define SYS_gettid 178
#elif defined(__i386__)
#define SYS_gettid 224
#elif defined(__arm__)
#define SYS_gettid 224
#elif defined(__riscv) && __riscv_xlen == 64
#define SYS_gettid 178
#elif defined(__loongarch_lp64)
#define SYS_gettid 178
#elif defined(__s390x__)
#define SYS_gettid 236
#else
#error unsupported Linux gettid syscall number for this architecture
#endif
#endif
long syscall(long number, ...);
static inline u32 v3_gettid(void) {
	return (u32)syscall(SYS_gettid);
}
#endif

#ifndef PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP
#define pthread_rwlockattr_setkind_np(attr, kind) (0)
#endif
array __new_array(i64 len, i64 cap, i64 elem_size);
static inline array __v3_internal_symbol_array_new(i64 elem_size, i64 len, i64 cap) { if (len == 0 && cap == 0) return (array){.element_size = elem_size, .flags = ArrayFlags__managed}; return __new_array(len, cap, elem_size); }
#define array_new(elem_size, len, cap) __v3_internal_symbol_array_new((elem_size), (len), (cap))
#define array_push array__push
void array__push_many(array* a, void* val, i64 size);
#define array_push_many_ptr(a, val, size) array__push_many((a), (void*)(val), (size))
#define array_get array__get
#define array_set(a, i, ...) array__set(&(a), (i), __VA_ARGS__)
array array__clone(array* a);
#define array_slice array__slice
#define array_delete array__delete
#define array_ensure_cap array__ensure_cap
#define map__get_or_set map__get_and_set
#ifndef V_COMMIT_HASH
#define V_COMMIT_HASH ""
#endif
#ifndef memory_order_relaxed
#define memory_order_relaxed 0
#define memory_order_acquire 2
#define memory_order_release 3
#define memory_order_acq_rel 4
#define memory_order_seq_cst 5
#endif
#if defined(_WIN32) && (defined(__TINYC__) || (defined(_MSC_VER) && !defined(__clang__)))
/* V atomic.h supplies atomic_thread_fence on Windows TCC and MSVC. */
#elif defined(__TINYC__) && (defined(__i386__) || defined(__arm__) || defined(__aarch64__) || defined(__riscv))
extern void _V_atomic_thread_fence(int order);
#define atomic_thread_fence(order) _V_atomic_thread_fence(order)
#define __atomic_thread_fence(order) _V_atomic_thread_fence(order)
#else
#define atomic_thread_fence(order) __atomic_thread_fence(order)
#endif
__attribute__((weak)) void vheap_alloc(void* p, u64 n) { (void)p; (void)n; }
__attribute__((weak)) void vheap_free(void* p) { (void)p; }
static inline int v3_sum_ptr_type_idx(const void* p) { return p == NULL ? 0 : *(const int*)p; }
#ifdef __TINYC__
extern byte __atomic_exchange_1(byte* ptr, byte val, int order);
extern u16 __atomic_exchange_2(u16* ptr, u16 val, int order);
extern u32 __atomic_exchange_4(u32* ptr, u32 val, int order);
extern u64 __atomic_exchange_8(u64* ptr, u64 val, int order);
extern byte __atomic_load_1(byte* ptr, int order);
extern u16 __atomic_load_2(u16* ptr, int order);
extern u32 __atomic_load_4(u32* ptr, int order);
extern u64 __atomic_load_8(u64* ptr, int order);
extern void __atomic_store_1(byte* ptr, byte val, int order);
extern void __atomic_store_2(u16* ptr, u16 val, int order);
extern void __atomic_store_4(u32* ptr, u32 val, int order);
extern void __atomic_store_8(u64* ptr, u64 val, int order);
extern _Bool __atomic_compare_exchange_1(byte* ptr, byte* expected, byte desired, int success_order, int failure_order);
extern _Bool __atomic_compare_exchange_2(u16* ptr, u16* expected, u16 desired, int success_order, int failure_order);
extern _Bool __atomic_compare_exchange_4(u32* ptr, u32* expected, u32 desired, int success_order, int failure_order);
extern _Bool __atomic_compare_exchange_8(u64* ptr, u64* expected, u64 desired, int success_order, int failure_order);
#endif
#if defined(_MSC_VER) && !defined(__clang__)
static inline int v_prealloc_atomic_add_i32(int *ptr, int delta) { return (int)InterlockedExchangeAdd((volatile LONG*)ptr, (LONG)delta) + delta; }
static inline int v_prealloc_atomic_load_i32(int *ptr) { return (int)InterlockedExchangeAdd((volatile LONG*)ptr, 0); }
static inline long long v_prealloc_atomic_add_i64(long long *ptr, long long delta) { return (long long)InterlockedExchangeAdd64((volatile LONG64*)ptr, (LONG64)delta) + delta; }
static inline long long v_prealloc_atomic_load_i64(long long *ptr) { return (long long)InterlockedExchangeAdd64((volatile LONG64*)ptr, 0); }
static inline int v_prealloc_atomic_store_i32(int *ptr, int val) { return (int)InterlockedExchange((volatile LONG*)ptr, (LONG)val); }
static inline int v_prealloc_atomic_cas_i32(int *ptr, int expected, int desired) { return InterlockedCompareExchange((volatile LONG*)ptr, (LONG)desired, (LONG)expected) == (LONG)expected; }
#else
static inline int v_prealloc_atomic_add_i32(int *ptr, int delta) { return __atomic_add_fetch(ptr, delta, 5); }
static inline long long v_prealloc_atomic_add_i64(long long *ptr, long long delta) { return __atomic_add_fetch(ptr, delta, 5); }
#ifdef __TINYC__
static inline int v_prealloc_atomic_load_i32(int *ptr) { return (int)__atomic_load_4((u32*)ptr, 5); }
static inline long long v_prealloc_atomic_load_i64(long long *ptr) { return (long long)__atomic_load_8((u64*)ptr, 5); }
static inline int v_prealloc_atomic_store_i32(int *ptr, int val) { return (int)__atomic_exchange_4((u32*)ptr, (u32)val, 5); }
static inline int v_prealloc_atomic_cas_i32(int *ptr, int expected, int desired) { u32 e = (u32)expected; return __atomic_compare_exchange_4((u32*)ptr, &e, (u32)desired, 5, 5); }
#else
static inline int v_prealloc_atomic_load_i32(int *ptr) { return __atomic_load_n(ptr, 5); }
static inline long long v_prealloc_atomic_load_i64(long long *ptr) { return __atomic_load_n(ptr, 5); }
static inline int v_prealloc_atomic_store_i32(int *ptr, int val) { return __atomic_exchange_n(ptr, val, 5); }
static inline int v_prealloc_atomic_cas_i32(int *ptr, int expected, int desired) { return __atomic_compare_exchange_n(ptr, &expected, desired, 0, 5, 5); }
#endif
#endif
static inline byte atomic_fetch_add_byte(void* ptr, byte delta) { return __atomic_fetch_add((byte*)ptr, delta, 5); }
static inline u16 atomic_fetch_add_u16(void* ptr, u16 delta) { return __atomic_fetch_add((u16*)ptr, delta, 5); }
static inline u32 atomic_fetch_add_u32(void* ptr, u32 delta) { return __atomic_fetch_add((u32*)ptr, delta, 5); }
static inline u64 atomic_fetch_add_u64(void* ptr, u64 delta) { return __atomic_fetch_add((u64*)ptr, delta, 5); }
static inline void* atomic_fetch_add_ptr(void* ptr, void* delta) { return (void*)(uintptr_t)__atomic_fetch_add((uintptr_t*)ptr, (uintptr_t)delta, 5); }
static inline byte atomic_fetch_sub_byte(void* ptr, byte delta) { return __atomic_fetch_sub((byte*)ptr, delta, 5); }
static inline u16 atomic_fetch_sub_u16(void* ptr, u16 delta) { return __atomic_fetch_sub((u16*)ptr, delta, 5); }
static inline u32 atomic_fetch_sub_u32(void* ptr, u32 delta) { return __atomic_fetch_sub((u32*)ptr, delta, 5); }
static inline u64 atomic_fetch_sub_u64(void* ptr, u64 delta) { return __atomic_fetch_sub((u64*)ptr, delta, 5); }
static inline void* atomic_fetch_sub_ptr(void* ptr, void* delta) { return (void*)(uintptr_t)__atomic_fetch_sub((uintptr_t*)ptr, (uintptr_t)delta, 5); }
#ifdef __TINYC__
static inline byte atomic_load_byte(void* ptr) { return __atomic_load_1((byte*)ptr, 5); }
static inline u16 atomic_load_u16(void* ptr) { return __atomic_load_2((u16*)ptr, 5); }
static inline u32 atomic_load_u32(void* ptr) { return __atomic_load_4((u32*)ptr, 5); }
static inline u64 atomic_load_u64(void* ptr) { return __atomic_load_8((u64*)ptr, 5); }
#if UINTPTR_MAX == 0xFFFFFFFF
static inline void* atomic_load_ptr(void* ptr) { return (void*)(size_t)__atomic_load_4((u32*)ptr, 5); }
#else
static inline void* atomic_load_ptr(void* ptr) { return (void*)(size_t)__atomic_load_8((u64*)ptr, 5); }
#endif
static inline byte atomic_exchange_byte(void* ptr, byte val) { return __atomic_exchange_1((byte*)ptr, val, 5); }
static inline u16 atomic_exchange_u16(void* ptr, u16 val) { return __atomic_exchange_2((u16*)ptr, val, 5); }
static inline u32 atomic_exchange_u32(void* ptr, u32 val) { return __atomic_exchange_4((u32*)ptr, val, 5); }
static inline u64 atomic_exchange_u64(void* ptr, u64 val) { return __atomic_exchange_8((u64*)ptr, val, 5); }
static inline void atomic_store_byte(void* ptr, byte val) { __atomic_store_1((byte*)ptr, val, 5); }
static inline void atomic_store_u16(void* ptr, u16 val) { __atomic_store_2((u16*)ptr, val, 5); }
static inline void atomic_store_u32(void* ptr, u32 val) { __atomic_store_4((u32*)ptr, val, 5); }
static inline void atomic_store_u64(void* ptr, u64 val) { __atomic_store_8((u64*)ptr, val, 5); }
#if UINTPTR_MAX == 0xFFFFFFFF
static inline void* atomic_exchange_ptr(void* ptr, void* val) { return (void*)(size_t)__atomic_exchange_4((u32*)ptr, (u32)(size_t)val, 5); }
static inline void atomic_store_ptr(void* ptr, void* val) { __atomic_store_4((u32*)ptr, (u32)(size_t)val, 5); }
#else
static inline void* atomic_exchange_ptr(void* ptr, void* val) { return (void*)(size_t)__atomic_exchange_8((u64*)ptr, (u64)(size_t)val, 5); }
static inline void atomic_store_ptr(void* ptr, void* val) { __atomic_store_8((u64*)ptr, (u64)(size_t)val, 5); }
#endif
static inline bool atomic_compare_exchange_strong_byte(void* ptr, byte* expected, byte desired) { return __atomic_compare_exchange_1((byte*)ptr, expected, desired, 5, 5); }
static inline bool atomic_compare_exchange_strong_u16(void* ptr, u16* expected, u16 desired) { return __atomic_compare_exchange_2((u16*)ptr, expected, desired, 5, 5); }
static inline bool atomic_compare_exchange_strong_u32(void* ptr, u32* expected, u32 desired) { return __atomic_compare_exchange_4((u32*)ptr, expected, desired, 5, 5); }
static inline bool atomic_compare_exchange_strong_u64(void* ptr, u64* expected, u64 desired) { return __atomic_compare_exchange_8((u64*)ptr, expected, desired, 5, 5); }
#if UINTPTR_MAX == 0xFFFFFFFF
static inline bool atomic_compare_exchange_strong_ptr(void* ptr, void* expected, ptrdiff_t desired) { return __atomic_compare_exchange_4((u32*)ptr, (u32*)expected, (u32)desired, 5, 5); }
#else
static inline bool atomic_compare_exchange_strong_ptr(void* ptr, void* expected, ptrdiff_t desired) { return __atomic_compare_exchange_8((u64*)ptr, (u64*)expected, (u64)desired, 5, 5); }
#endif
static inline bool atomic_compare_exchange_weak_byte(void* ptr, byte* expected, byte desired) { return __atomic_compare_exchange_1((byte*)ptr, expected, desired, 5, 5); }
static inline bool atomic_compare_exchange_weak_u16(void* ptr, u16* expected, u16 desired) { return __atomic_compare_exchange_2((u16*)ptr, expected, desired, 5, 5); }
static inline bool atomic_compare_exchange_weak_u32(void* ptr, u32* expected, u32 desired) { return __atomic_compare_exchange_4((u32*)ptr, expected, desired, 5, 5); }
static inline bool atomic_compare_exchange_weak_u64(void* ptr, u64* expected, u64 desired) { return __atomic_compare_exchange_8((u64*)ptr, expected, desired, 5, 5); }
#else
static inline byte atomic_load_byte(void* ptr) { return __atomic_load_n((byte*)ptr, 5); }
static inline u16 atomic_load_u16(void* ptr) { return __atomic_load_n((u16*)ptr, 5); }
static inline u32 atomic_load_u32(void* ptr) { return __atomic_load_n((u32*)ptr, 5); }
static inline u64 atomic_load_u64(void* ptr) { return __atomic_load_n((u64*)ptr, 5); }
static inline void* atomic_load_ptr(void* ptr) { return __atomic_load_n((void**)ptr, 5); }
static inline byte atomic_exchange_byte(void* ptr, byte val) { return __atomic_exchange_n((byte*)ptr, val, 5); }
static inline u16 atomic_exchange_u16(void* ptr, u16 val) { return __atomic_exchange_n((u16*)ptr, val, 5); }
static inline u32 atomic_exchange_u32(void* ptr, u32 val) { return __atomic_exchange_n((u32*)ptr, val, 5); }
static inline u64 atomic_exchange_u64(void* ptr, u64 val) { return __atomic_exchange_n((u64*)ptr, val, 5); }
static inline void* atomic_exchange_ptr(void* ptr, void* val) { return __atomic_exchange_n((void**)ptr, val, 5); }
static inline void atomic_store_byte(void* ptr, byte val) { __atomic_store_n((byte*)ptr, val, 5); }
static inline void atomic_store_u16(void* ptr, u16 val) { __atomic_store_n((u16*)ptr, val, 5); }
static inline void atomic_store_u32(void* ptr, u32 val) { __atomic_store_n((u32*)ptr, val, 5); }
static inline void atomic_store_u64(void* ptr, u64 val) { __atomic_store_n((u64*)ptr, val, 5); }
static inline void atomic_store_ptr(void* ptr, void* val) { __atomic_store_n((void**)ptr, val, 5); }
static inline bool atomic_compare_exchange_strong_byte(void* ptr, byte* expected, byte desired) { return __atomic_compare_exchange_n((byte*)ptr, expected, desired, 0, 5, 5); }
static inline bool atomic_compare_exchange_strong_u16(void* ptr, u16* expected, u16 desired) { return __atomic_compare_exchange_n((u16*)ptr, expected, desired, 0, 5, 5); }
static inline bool atomic_compare_exchange_strong_u32(void* ptr, u32* expected, u32 desired) { return __atomic_compare_exchange_n((u32*)ptr, expected, desired, 0, 5, 5); }
static inline bool atomic_compare_exchange_strong_u64(void* ptr, u64* expected, u64 desired) { return __atomic_compare_exchange_n((u64*)ptr, expected, desired, 0, 5, 5); }
static inline bool atomic_compare_exchange_strong_ptr(void* ptr, void* expected, ptrdiff_t desired) { return __atomic_compare_exchange_n((void**)ptr, (void**)expected, (void*)desired, 0, 5, 5); }
static inline bool atomic_compare_exchange_weak_byte(void* ptr, byte* expected, byte desired) { return __atomic_compare_exchange_n((byte*)ptr, expected, desired, 1, 5, 5); }
static inline bool atomic_compare_exchange_weak_u16(void* ptr, u16* expected, u16 desired) { return __atomic_compare_exchange_n((u16*)ptr, expected, desired, 1, 5, 5); }
static inline bool atomic_compare_exchange_weak_u32(void* ptr, u32* expected, u32 desired) { return __atomic_compare_exchange_n((u32*)ptr, expected, desired, 1, 5, 5); }
static inline bool atomic_compare_exchange_weak_u64(void* ptr, u64* expected, u64 desired) { return __atomic_compare_exchange_n((u64*)ptr, expected, desired, 1, 5, 5); }
#endif
static inline bool atomic_compare_exchange_weak_ptr(void* ptr, void* expected, ptrdiff_t desired) { return atomic_compare_exchange_strong_ptr(ptr, expected, desired); }
#ifdef __TINYC__
static inline void cpu_relax(void) { }
#else
static inline void cpu_relax(void) { __asm__ __volatile__("" ::: "memory"); }
#endif
static inline double math__abs(double a) { return a < 0 ? -a : a; }
static inline double math__min(double a, double b) { return a < b ? a : b; }
static const u64 _wyp[4] = {0x2d358dccaa6c78a5ull, 0x8bb84b93962eacc9ull, 0x4b33a62ed433d4a3ull, 0x4d5a2da51de1aa47ull};
static inline u64 _wymix(u64 a, u64 b) { u64 ha = a >> 32, hb = b >> 32, la = (u32)a, lb = (u32)b, hi, lo; u64 rh = ha * hb, rm0 = ha * lb, rm1 = hb * la, rl = la * lb, t = rl + (rm0 << 32), c = t < rl; lo = t + (rm1 << 32); c += lo < t; hi = rh + (rm0 >> 32) + (rm1 >> 32) + c; return lo ^ hi; }
static inline u64 wyhash64(u64 a, u64 b) { a ^= _wyp[0]; b ^= _wyp[1]; a *= 0xa0761d6478bd642full; b *= 0xe7037ed1a0b428dbull; return (a ^ (a >> 32)) ^ (b ^ (b >> 32)); }
#define V_WY_LOAD8(p) ((u64)(p)[0] | ((u64)(p)[1] << 8) | ((u64)(p)[2] << 16) | ((u64)(p)[3] << 24) | ((u64)(p)[4] << 32) | ((u64)(p)[5] << 40) | ((u64)(p)[6] << 48) | ((u64)(p)[7] << 56))
static inline u64 wyhash(const void* key, size_t len, u64 seed, const u64* secret) {
	const unsigned char* p = (const unsigned char*)key;
	size_t n = len;
	u64 h = seed ^ secret[0] ^ ((u64)len * 0x9e3779b97f4a7c15ull);
	while (n >= 8) { h = (h ^ V_WY_LOAD8(p)) * 0xa0761d6478bd642full; h ^= h >> 29; p += 8; n -= 8; }
	if (n > 0) {
		u64 v = 0;
		switch (n) {
			case 7: v |= (u64)p[6] << 48;
			case 6: v |= (u64)p[5] << 40;
			case 5: v |= (u64)p[4] << 32;
			case 4: v |= (u64)p[3] << 24;
			case 3: v |= (u64)p[2] << 16;
			case 2: v |= (u64)p[1] << 8;
			default: v |= (u64)p[0];
		}
		h = (h ^ v) * 0xe7037ed1a0b428dbull; h ^= h >> 29;
	}
	h *= 0x8ebc6af09c88c6e3ull; h ^= h >> 32; h *= 0x589965cc75374cc3ull; h ^= h >> 29;
	return h;
}
#define v_signal_with_handler_cast(sig, handler) signal((sig), ((void (*)(int))(handler)))
string string__clone(string a);
void string__free(string* s);
string string__plus(string s, string a);
string int__str(i64 n);
string i64__str(i64 n);
string u64__str(u64 nn);
string f64__str(double x);
string rune__str(u32 c);
u8* malloc_noscan(ptrdiff_t n);
void* memdup(void* src, ptrdiff_t sz);
static inline Array* v3_heap_array(Array value) { return (Array*)memdup(&value, sizeof(Array)); }
static int v3_array_sort_int_cmp(const void* a, const void* b) { i64 av = *(const i64*)a; i64 bv = *(const i64*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_int(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(i64), v3_array_sort_int_cmp); }
static int v3_array_sort_i8_cmp(const void* a, const void* b) { signed char av = *(const signed char*)a; signed char bv = *(const signed char*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_i8(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(signed char), v3_array_sort_i8_cmp); }
static int v3_array_sort_i16_cmp(const void* a, const void* b) { short av = *(const short*)a; short bv = *(const short*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_i16(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(short), v3_array_sort_i16_cmp); }
static int v3_array_sort_i64_cmp(const void* a, const void* b) { long long av = *(const long long*)a; long long bv = *(const long long*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_i64(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(long long), v3_array_sort_i64_cmp); }
static int v3_array_sort_u8_cmp(const void* a, const void* b) { unsigned char av = *(const unsigned char*)a; unsigned char bv = *(const unsigned char*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_u8(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(unsigned char), v3_array_sort_u8_cmp); }
static int v3_array_sort_u16_cmp(const void* a, const void* b) { unsigned short av = *(const unsigned short*)a; unsigned short bv = *(const unsigned short*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_u16(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(unsigned short), v3_array_sort_u16_cmp); }
static int v3_array_sort_u32_cmp(const void* a, const void* b) { unsigned av = *(const unsigned*)a; unsigned bv = *(const unsigned*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_u32(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(unsigned), v3_array_sort_u32_cmp); }
static int v3_array_sort_u64_cmp(const void* a, const void* b) { unsigned long long av = *(const unsigned long long*)a; unsigned long long bv = *(const unsigned long long*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_u64(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(unsigned long long), v3_array_sort_u64_cmp); }
static int v3_array_sort_isize_cmp(const void* a, const void* b) { ptrdiff_t av = *(const ptrdiff_t*)a; ptrdiff_t bv = *(const ptrdiff_t*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_isize(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(ptrdiff_t), v3_array_sort_isize_cmp); }
static int v3_array_sort_usize_cmp(const void* a, const void* b) { size_t av = *(const size_t*)a; size_t bv = *(const size_t*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_usize(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(size_t), v3_array_sort_usize_cmp); }
static int v3_array_sort_f32_cmp(const void* a, const void* b) { float av = *(const float*)a; float bv = *(const float*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_f32(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(float), v3_array_sort_f32_cmp); }
static int v3_array_sort_f64_cmp(const void* a, const void* b) { double av = *(const double*)a; double bv = *(const double*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_f64(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(double), v3_array_sort_f64_cmp); }
static int v3_array_sort_rune_cmp(const void* a, const void* b) { unsigned av = *(const unsigned*)a; unsigned bv = *(const unsigned*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_rune(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(unsigned), v3_array_sort_rune_cmp); }
static int v3_array_sort_char_cmp(const void* a, const void* b) { char av = *(const char*)a; char bv = *(const char*)b; return (av > bv) - (av < bv); }
static inline void v3_array_sort_char(Array* a) { if (a != NULL && a->len > 1) qsort(a->data, (size_t)a->len, sizeof(char), v3_array_sort_char_cmp); }
#ifndef V_MANUAL_STDLIB_HEADERS
#ifdef _WIN32
void* _aligned_malloc(size_t size, size_t alignment);
void _aligned_free(void* memblock);
#else
int posix_memalign(void** memptr, size_t alignment, size_t size);
#endif
#endif
void* memdup_align(void* src, ptrdiff_t sz, ptrdiff_t alignment);
void v_free(void* p);
static inline void* v3_aligned_memdup(void* src, ptrdiff_t sz, size_t alignment) {
#if defined(CUSTOM_DEFINE_prealloc) || defined(CUSTOM_DEFINE_vgc) || defined(_VGCBOEHM) || defined(CUSTOM_DEFINE_gcboehm)
return memdup_align(src, sz, (ptrdiff_t)alignment);
#else
void* p = NULL; if (alignment < sizeof(void*)) alignment = sizeof(void*);
#ifdef _WIN32
p = _aligned_malloc((size_t)sz, alignment);
#else
if (posix_memalign(&p, alignment, (size_t)sz) != 0) p = NULL;
#endif
if (p != NULL) memcpy(p, src, (size_t)sz); return p;
#endif
}
static inline void v3_aligned_free(void* p) {
#if defined(CUSTOM_DEFINE_prealloc) || defined(CUSTOM_DEFINE_vgc) || defined(_VGCBOEHM) || defined(CUSTOM_DEFINE_gcboehm)
v_free(p);
#elif defined(_WIN32)
_aligned_free(p);
#else
free(p);
#endif
}
static inline string v3_c_lit(const char* s, int len) { return (string){.str = (u8*)s, .len = len, .is_lit = 1}; }
static inline int v3_utf8_next_cp(const u8* s, int len, int* i) { u8 c = s[*i]; if (c < 0x80) { (*i)++; return c; } int n = (c & 0xE0) == 0xC0 ? 2 : ((c & 0xF0) == 0xE0 ? 3 : ((c & 0xF8) == 0xF0 ? 4 : 1)); if (*i + n > len) { (*i)++; return c; } int cp = c & (n == 2 ? 0x1F : (n == 3 ? 0x0F : (n == 4 ? 0x07 : 0x7F))); for (int j = 1; j < n; ++j) cp = (cp << 6) | (s[*i + j] & 0x3F); *i += n; return cp; }
static inline int v3_codepoint_is_combining(int cp) { return (cp >= 0x0300 && cp <= 0x036F) || (cp >= 0x1AB0 && cp <= 0x1AFF) || (cp >= 0x1DC0 && cp <= 0x1DFF) || (cp >= 0x20D0 && cp <= 0x20FF) || (cp >= 0xFE00 && cp <= 0xFE0F) || (cp >= 0xFE20 && cp <= 0xFE2F) || (cp >= 0x1F3FB && cp <= 0x1F3FF) || cp == 0x0E31 || (cp >= 0x0E34 && cp <= 0x0E3A) || (cp >= 0x0E47 && cp <= 0x0E4E); }
static inline int v3_codepoint_is_wide(int cp) { return (cp >= 0x1100 && cp <= 0x115F) || (cp >= 0x2329 && cp <= 0x232A) || (cp >= 0x2E80 && cp <= 0xA4CF) || (cp >= 0xAC00 && cp <= 0xD7A3) || (cp >= 0xF900 && cp <= 0xFAFF) || (cp >= 0xFE10 && cp <= 0xFE19) || (cp >= 0xFE30 && cp <= 0xFE6F) || (cp >= 0xFF00 && cp <= 0xFF60) || (cp >= 0xFFE0 && cp <= 0xFFE6) || (cp >= 0x1F000 && cp <= 0x1FAFF); }
static inline int v3_string_display_width(string s) { int width = 0; int join = 0; for (int i = 0; i < s.len;) { int cp = v3_utf8_next_cp(s.str, s.len, &i); if (cp == 0x200D) { join = 1; continue; } if (v3_codepoint_is_combining(cp)) continue; if (join) { join = 0; continue; } width += v3_codepoint_is_wide(cp) ? 2 : 1; } return width; }
static inline string v3_string_pad(string s, int width, int left) { if (width < 0) { left = 1; width = -width; } int visible = v3_string_display_width(s); if (visible >= width) return s; int pad = width - visible; int out_len = s.len + pad; u8* out = malloc_noscan((ptrdiff_t)out_len + 1); if (left) { memcpy(out, s.str, (size_t)s.len); memset(out + s.len, ' ', (size_t)pad); } else { memset(out, ' ', (size_t)pad); memcpy(out + pad, s.str, (size_t)s.len); } out[out_len] = 0; return (string){.str = out, .len = out_len, .is_lit = 0}; }
static inline string v3_string_upper_ascii(string s) { u8* out = malloc_noscan((ptrdiff_t)s.len + 1); for (int i = 0; i < s.len; ++i) { u8 c = s.str[i]; out[i] = c >= 'a' && c <= 'z' ? (u8)(c - ('a' - 'A')) : c; } out[s.len] = 0; return (string){.str = out, .len = s.len, .is_lit = 0}; }
static inline string v3_char_string(int c) { return rune__str((u32)c); }
static inline string v3_indent_multiline(string s) { int lines = 0; for (int i = 0; i < s.len; ++i) if (s.str[i] == '\n') ++lines; if (lines == 0) return s; int out_len = s.len + lines * 4; u8* out = malloc_noscan((ptrdiff_t)out_len + 1); int p = 0; for (int i = 0; i < s.len; ++i) { u8 c = s.str[i]; out[p++] = c; if (c == '\n') { memset(out + p, ' ', 4); p += 4; } } out[p] = 0; return (string){.str = out, .len = out_len, .is_lit = 0}; }
static inline string v3_f64_fixed(double x, int precision) {
	if (precision < 0) precision = 6;
	if (!isfinite(x)) return f64__str(x);
	int clamped_precision = precision > 35 ? 35 : precision;
	double rounder = 0.5 * pow(10.0, -clamped_precision);
	string decimal = f64__str(fabs(x) + rounder);
	u8 digits[32];
	int digit_count = 0;
	int decimal_pos = -1;
	int exponent = 0;
	int exponent_sign = 1;
	for (int i = 0; i < decimal.len; ++i) {
		u8 c = decimal.str[i];
		if (c >= '0' && c <= '9') {
			digits[digit_count++] = c;
		} else if (c == '.') {
			decimal_pos = digit_count;
		} else if (c == 'e' || c == 'E') {
			++i;
			if (i < decimal.len && decimal.str[i] == '-') {
				exponent_sign = -1;
				++i;
			} else if (i < decimal.len && decimal.str[i] == '+') {
				++i;
			}
			for (; i < decimal.len; ++i) exponent = exponent * 10 + decimal.str[i] - '0';
			break;
		}
	}
	if (decimal_pos < 0) decimal_pos = digit_count;
	decimal_pos += exponent_sign * exponent;
	int whole_digits = decimal_pos > 0 ? decimal_pos : 1;
	int negative = signbit(x) != 0;
	int out_len = negative + whole_digits + (precision > 0 ? precision + 1 : 0);
	u8* out = malloc_noscan((ptrdiff_t)out_len + 1);
	int pos = 0;
	if (negative) out[pos++] = '-';
	if (decimal_pos <= 0) out[pos++] = '0';
	else for (int i = 0; i < whole_digits; ++i) out[pos++] = i < digit_count ? digits[i] : '0';
	if (precision > 0) {
		out[pos++] = '.';
		for (int i = 0; i < precision; ++i) {
			int digit = decimal_pos + i;
			out[pos++] = digit >= 0 && digit < digit_count ? digits[digit] : '0';
		}
	}
	out[pos] = 0;
	return (string){.str = out, .len = out_len, .is_lit = 0};
}
static inline string v3_f64_exp(double x, int precision, int upper) { char tmp[128]; int n = upper ? snprintf(tmp, sizeof(tmp), "%.*E", precision, x) : snprintf(tmp, sizeof(tmp), "%.*e", precision, x); if (n < 0) return v3_c_lit("", 0); if (n < (int)sizeof(tmp)) { u8* out = malloc_noscan(n + 1); memcpy(out, tmp, n + 1); return (string){.str = out, .len = n, .is_lit = 0}; } u8* out = malloc_noscan(n + 1); if (upper) snprintf((char*)out, (size_t)n + 1, "%.*E", precision, x); else snprintf((char*)out, (size_t)n + 1, "%.*e", precision, x); return (string){.str = out, .len = n, .is_lit = 0}; }
static inline string v3_f64_general(double x, int precision, int upper) { char tmp[128]; int n = upper ? snprintf(tmp, sizeof(tmp), "%.*G", precision, x) : snprintf(tmp, sizeof(tmp), "%.*g", precision, x); if (n < 0) return v3_c_lit("", 0); if (n < (int)sizeof(tmp)) { u8* out = malloc_noscan(n + 1); memcpy(out, tmp, n + 1); return (string){.str = out, .len = n, .is_lit = 0}; } u8* out = malloc_noscan(n + 1); if (upper) snprintf((char*)out, (size_t)n + 1, "%.*G", precision, x); else snprintf((char*)out, (size_t)n + 1, "%.*g", precision, x); return (string){.str = out, .len = n, .is_lit = 0}; }
static inline string v3_string_zpad(string s, int width) { if (s.len >= width) return s; int sign = s.len > 0 && s.str[0] == '-'; int pad = width - s.len; u8* out = malloc_noscan((ptrdiff_t)width + 1); int pos = 0; if (sign) out[pos++] = '-'; memset(out + pos, '0', (size_t)pad); pos += pad; memcpy(out + pos, s.str + sign, (size_t)(s.len - sign)); out[width] = 0; return (string){.str = out, .len = width, .is_lit = 0}; }
static inline string v3_int_zpad(i64 n, int width) { return v3_string_zpad(int__str(n), width); }
static inline string v3_i64_zpad(i64 n, int width) { return v3_string_zpad(i64__str(n), width); }
static inline string v3_u64_zpad(u64 n, int width) { return v3_string_zpad(u64__str(n), width); }
static inline string v3_string_rpad_zero(string s, int width) { if (s.len >= width) return s; u8* out = malloc_noscan((ptrdiff_t)width + 1); memcpy(out, s.str, (size_t)s.len); memset(out + s.len, '0', (size_t)(width - s.len)); out[width] = 0; return (string){.str = out, .len = width, .is_lit = 0}; }
static inline string v3_wide_int_dec(void* p, int is_signed) {
	const char* s = is_signed ? __v_i128_str(*(i128*)p) : __v_u128_str(*(u128*)p);
	int n = (int)strlen(s);
	u8* out = malloc_noscan((ptrdiff_t)(n + 1));
	memcpy(out, s, (size_t)n);
	out[n] = 0;
	return (string){.str = (char*)out, .len = n, .is_lit = 0};
}
static inline i64 v3_map_signed(void* p, int bytes) { if (bytes == 1) return *(signed char*)p; if (bytes == 2) return *(short*)p; if (bytes == 8) return *(long long*)p; return *(int*)p; }
static inline u64 v3_map_unsigned(void* p, int bytes) { if (bytes == 1) return *(unsigned char*)p; if (bytes == 2) return *(unsigned short*)p; if (bytes == 8) return *(unsigned long long*)p; return *(unsigned int*)p; }
static inline string v3_f32_array_str(float* vals, int n) { string out = v3_c_lit("[", 1); for (int i = 0; i < n; ++i) { if (i > 0) out = string__plus(out, v3_c_lit(", ", 2)); out = string__plus(out, f64__str((double)vals[i])); } return string__plus(out, v3_c_lit("]", 1)); }
static inline string v3_f64_array_str(double* vals, int n) { string out = v3_c_lit("[", 1); for (int i = 0; i < n; ++i) { if (i > 0) out = string__plus(out, v3_c_lit(", ", 2)); out = string__plus(out, f64__str(vals[i])); } return string__plus(out, v3_c_lit("]", 1)); }
static inline string v3_map_str_piece(void* p, int kind, int bytes, int fixed_len) {
	if (kind == 1) { return string__plus(string__plus(v3_c_lit("'", 1), *(string*)p), v3_c_lit("'", 1)); }
	if (kind == 2) { return v3_i64_zpad(v3_map_signed(p, bytes), 0); }
	if (kind == 3) { return u64__str(v3_map_unsigned(p, bytes)); }
	if (kind == 4) { u32 r = bytes == 1 ? (u32)(*(u8*)p) : *(u32*)p; return string__plus(string__plus(v3_c_lit("`", 1), rune__str(r)), v3_c_lit("`", 1)); }
	if (kind == 5) { if (bytes == (int)sizeof(float)) return f64__str((double)*(float*)p); return f64__str(*(double*)p); }
	if (kind == 6) { if (fixed_len == 0 && bytes == (int)sizeof(Array)) { Array a = *(Array*)p; if (a.element_size == (int)sizeof(float)) return v3_f32_array_str((float*)a.data, a.len); if (a.element_size == (int)sizeof(double)) return v3_f64_array_str((double*)a.data, a.len); } if (fixed_len > 0 && bytes == fixed_len * (int)sizeof(float)) return v3_f32_array_str((float*)p, fixed_len); int n = fixed_len > 0 ? fixed_len : bytes / (int)sizeof(double); return v3_f64_array_str((double*)p, n); }
	if (kind == 8) { return f64__str((double)*(float*)p); }
	if (kind == 9) { int n = fixed_len > 0 ? fixed_len : bytes / (int)sizeof(float); return v3_f32_array_str((float*)p, n); }
	if (kind == 7) { return *(bool*)p ? v3_c_lit("true", 4) : v3_c_lit("false", 5); }
	if (kind == 10) { return v3_wide_int_dec(p, 0); }
	if (kind == 11) { return v3_wide_int_dec(p, 1); }
	return v3_c_lit("<map value>", 11);
}
static inline string v3_map_str(map m, int key_kind, int val_kind, int val_fixed_len) {
	string out = v3_c_lit("{", 1); bool first = true;
	for (int i = 0; i < m.data->key_values.len; ++i) {
		if (m.data->key_values.deletes != 0 && m.data->key_values.all_deleted != 0 && m.data->key_values.all_deleted[i] != 0) continue;
		if (!first) out = string__plus(out, v3_c_lit(", ", 2));
		void* key = (void*)(m.data->key_values.keys + i * m.data->key_values.key_bytes);
		void* val = (void*)(m.data->key_values.values + i * m.data->key_values.value_bytes);
		out = string__plus(out, v3_map_str_piece(key, key_kind, m.data->key_values.key_bytes, 0));
		out = string__plus(out, v3_c_lit(": ", 2));
		out = string__plus(out, v3_map_str_piece(val, val_kind, m.data->value_bytes, val_fixed_len));
		first = false;
	}
	return string__plus(out, v3_c_lit("}", 1));
}
static inline int array_index_int(Array a, i64 val) { for (int i = 0; i < a.len; i++) if (((i64*)a.data)[i] == val) return i; return -1; }
static inline int array_last_index_int(Array a, i64 val) { for (int i = a.len - 1; i >= 0; i--) if (((i64*)a.data)[i] == val) return i; return -1; }
static inline bool array_contains_int(Array a, i64 val) { return array_index_int(a, val) >= 0; }
static inline int array_index_u8(Array a, u8 val) { for (int i = 0; i < a.len; i++) if (((u8*)a.data)[i] == val) return i; return -1; }
static inline int array_last_index_u8(Array a, u8 val) { for (int i = a.len - 1; i >= 0; i--) if (((u8*)a.data)[i] == val) return i; return -1; }
static inline bool array_contains_u8(Array a, u8 val) { return array_index_u8(a, val) >= 0; }
static inline int array_index_string(Array a, string val) { string* data = (string*)a.data; for (int i = 0; i < a.len; i++) if (data[i].len == val.len && memcmp(data[i].str, val.str, val.len) == 0) return i; return -1; }
static inline int array_last_index_string(Array a, string val) { string* data = (string*)a.data; for (int i = a.len - 1; i >= 0; i--) if (data[i].len == val.len && memcmp(data[i].str, val.str, val.len) == 0) return i; return -1; }
static inline bool array_contains_string(Array a, string val) { return array_index_string(a, val) >= 0; }
static inline int array_last_index_raw(Array a, const void* val) { for (int i = a.len - 1; i >= 0; i--) if (memcmp((u8*)a.data + (size_t)i * (size_t)a.element_size, val, (size_t)a.element_size) == 0) return i; return -1; }
static inline bool array_eq_raw(Array a, Array b, int elem_size) { return a.len == b.len && (a.len == 0 || memcmp(a.data, b.data, (size_t)a.len * elem_size) == 0); }
static inline bool array_eq_string(Array a, Array b) { if (a.len != b.len) return false; string* ad = (string*)a.data; string* bd = (string*)b.data; for (int i = 0; i < a.len; i++) if (ad[i].len != bd[i].len || memcmp(ad[i].str, bd[i].str, ad[i].len) != 0) return false; return true; }
static inline bool array_eq_array(Array a, Array b, int depth) { if (a.len != b.len || a.element_size != b.element_size) return false; if (depth <= 1 || a.element_size != sizeof(Array)) { if (a.element_size == sizeof(string)) return array_eq_string(a, b); return array_eq_raw(a, b, a.element_size); } Array* ad = (Array*)a.data; Array* bd = (Array*)b.data; for (int i = 0; i < a.len; i++) { if (!array_eq_array(ad[i], bd[i], depth - 1)) return false; } return true; }
void* map__get(map* m, void* key, void* zero);
bool map__exists(map* m, void* key);
static inline bool v3_map_value_eq(void* a, void* b, int value_bytes) { return memcmp(a, b, value_bytes) == 0; }
static inline bool v3_map_map_eq(map a, map b) { if (a.data->count != b.data->count) return false; for (int i = 0; i < a.data->key_values.len; ++i) { if (a.data->key_values.deletes != 0 && a.data->key_values.all_deleted != 0 && a.data->key_values.all_deleted[i] != 0) continue; void* ak = (void*)(a.data->key_values.keys + i * a.data->key_values.key_bytes); if (!map__exists(&b, ak)) return false; void* av = (void*)(a.data->key_values.values + i * a.data->key_values.value_bytes); void* bv = map__get(&b, ak, av); if (!v3_map_value_eq(av, bv, a.data->value_bytes)) return false; } return true; }
static inline bool fixed_array_contains_string(const string* a, int len, string val) { for (int i = 0; i < len; i++) if (a[i].len == val.len && memcmp(a[i].str, val.str, val.len) == 0) return true; return false; }
static inline bool fixed_array_contains_u8(const u8* a, int len, u8 val) { for (int i = 0; i < len; i++) if (a[i] == val) return true; return false; }
static inline bool fixed_array_contains_int(const i64* a, int len, i64 val) { for (int i = 0; i < len; i++) if (a[i] == val) return true; return false; }
static inline string Array_str(Array a) { if (a.element_size == 1) { u8* buf = (u8*)malloc((size_t)a.len + 1); if (a.len > 0) memcpy(buf, a.data, (size_t)a.len); buf[a.len] = 0; return (string){buf, a.len, 0}; } return (string){(u8*)"[]", 2, 1}; }
#ifndef max_int
#define max_int max_i32
#endif
#ifndef min_int
#define min_int min_i32
#endif

static void v3_eprint_lit(const char* s) {
	fprintf(stderr, "%s", s);
}
static void v3_eprintln_string(string s) {
	fprintf(stderr, "%.*s\n", s.len, (char*)s.str);
}

i64 g_autostr_type_stack[64] = {0};
i64 g_autostr_type_stack_len = 0;
#if defined(__TINYC__) && defined(_WIN32)
typedef DWORD (WINAPI *g_autostr_addr_state_fls_alloc_fn)(void (WINAPI *)(void*));
typedef void* (WINAPI *g_autostr_addr_state_fls_get_fn)(DWORD);
typedef BOOL (WINAPI *g_autostr_addr_state_fls_set_fn)(DWORD, void*);
static DWORD g_autostr_addr_state_key = 0xFFFFFFFF;
static g_autostr_addr_state_fls_get_fn g_autostr_addr_state_fls_get;
static g_autostr_addr_state_fls_set_fn g_autostr_addr_state_fls_set;
static void WINAPI g_autostr_addr_state_slot_free(void* p) { free(p); }
static unsigned int g_autostr_addr_state_key_claim;
static unsigned int g_autostr_addr_state_key_ready;
#if defined(__x86_64__) || defined(__i386__)
#define g_autostr_addr_state_key_is_ready() (*(volatile unsigned int*)&g_autostr_addr_state_key_ready)
#else
#define g_autostr_addr_state_key_is_ready() __atomic_add_fetch(&g_autostr_addr_state_key_ready, 0, 5)
#endif
static void g_autostr_addr_state_key_init(void) {
	if (g_autostr_addr_state_key_is_ready()) { return; }
	if (__atomic_add_fetch(&g_autostr_addr_state_key_claim, 1, 5) == 1) {
		void* kernel32 = GetModuleHandleA("kernel32.dll");
		g_autostr_addr_state_fls_alloc_fn fls_alloc = (g_autostr_addr_state_fls_alloc_fn)GetProcAddress(kernel32, "FlsAlloc");
		g_autostr_addr_state_fls_get = (g_autostr_addr_state_fls_get_fn)GetProcAddress(kernel32, "FlsGetValue");
		g_autostr_addr_state_fls_set = (g_autostr_addr_state_fls_set_fn)GetProcAddress(kernel32, "FlsSetValue");
		g_autostr_addr_state_key = fls_alloc && g_autostr_addr_state_fls_get && g_autostr_addr_state_fls_set ? fls_alloc(g_autostr_addr_state_slot_free) : TlsAlloc();
		__atomic_add_fetch(&g_autostr_addr_state_key_ready, 1, 5);
	} else {
		while (!g_autostr_addr_state_key_is_ready()) { Sleep(0); }
	}
}
#undef g_autostr_addr_state_key_is_ready
static AutostrAddrStackState* g_autostr_addr_state_slot(void) { g_autostr_addr_state_key_init(); void* p = g_autostr_addr_state_fls_get ? g_autostr_addr_state_fls_get(g_autostr_addr_state_key) : TlsGetValue(g_autostr_addr_state_key); if (!p) { p = calloc(1, sizeof(AutostrAddrStackState)); if (g_autostr_addr_state_fls_set) g_autostr_addr_state_fls_set(g_autostr_addr_state_key, p); else TlsSetValue(g_autostr_addr_state_key, p); } return (AutostrAddrStackState*)p; }
#define g_autostr_addr_state (*g_autostr_addr_state_slot())
#elif defined(__TINYC__)
static pthread_key_t g_autostr_addr_state_key;
static pthread_once_t g_autostr_addr_state_key_once = PTHREAD_ONCE_INIT;
static void g_autostr_addr_state_key_create(void) { pthread_key_create(&g_autostr_addr_state_key, free); }
static void g_autostr_addr_state_key_init(void) { pthread_once(&g_autostr_addr_state_key_once, g_autostr_addr_state_key_create); }
static AutostrAddrStackState* g_autostr_addr_state_slot(void) { g_autostr_addr_state_key_init(); void* p = pthread_getspecific(g_autostr_addr_state_key); if (!p) { p = calloc(1, sizeof(AutostrAddrStackState)); pthread_setspecific(g_autostr_addr_state_key, p); } return (AutostrAddrStackState*)p; }
#define g_autostr_addr_state (*g_autostr_addr_state_slot())
#elif defined(_MSC_VER)
__declspec(thread) AutostrAddrStackState g_autostr_addr_state = {0};
#elif defined(__cplusplus)
thread_local AutostrAddrStackState g_autostr_addr_state = {0};
#else
_Thread_local AutostrAddrStackState g_autostr_addr_state = {0};
#endif
Array as_cast_type_indexes = {0};
VMapData map_empty_data = {0};
bool v_memory_panic = false;
i64 total_m = ((i64)(0));
i64 g_main_argc = ((i64)(0));
void* g_main_argv = NULL;
void* g_live_reload_info;
VMemoryBlock* g_memory_block;
i64 g_prealloc_allocation_count;
i64 g_prealloc_allocated_bytes;
#if defined(__TINYC__) && defined(_WIN32)
typedef DWORD (WINAPI *g_panic_state_fls_alloc_fn)(void (WINAPI *)(void*));
typedef void* (WINAPI *g_panic_state_fls_get_fn)(DWORD);
typedef BOOL (WINAPI *g_panic_state_fls_set_fn)(DWORD, void*);
static DWORD g_panic_state_key = 0xFFFFFFFF;
static g_panic_state_fls_get_fn g_panic_state_fls_get;
static g_panic_state_fls_set_fn g_panic_state_fls_set;
static void WINAPI g_panic_state_slot_free(void* p) { free(p); }
static unsigned int g_panic_state_key_claim;
static unsigned int g_panic_state_key_ready;
#if defined(__x86_64__) || defined(__i386__)
#define g_panic_state_key_is_ready() (*(volatile unsigned int*)&g_panic_state_key_ready)
#else
#define g_panic_state_key_is_ready() __atomic_add_fetch(&g_panic_state_key_ready, 0, 5)
#endif
static void g_panic_state_key_init(void) {
	if (g_panic_state_key_is_ready()) { return; }
	if (__atomic_add_fetch(&g_panic_state_key_claim, 1, 5) == 1) {
		void* kernel32 = GetModuleHandleA("kernel32.dll");
		g_panic_state_fls_alloc_fn fls_alloc = (g_panic_state_fls_alloc_fn)GetProcAddress(kernel32, "FlsAlloc");
		g_panic_state_fls_get = (g_panic_state_fls_get_fn)GetProcAddress(kernel32, "FlsGetValue");
		g_panic_state_fls_set = (g_panic_state_fls_set_fn)GetProcAddress(kernel32, "FlsSetValue");
		g_panic_state_key = fls_alloc && g_panic_state_fls_get && g_panic_state_fls_set ? fls_alloc(g_panic_state_slot_free) : TlsAlloc();
		__atomic_add_fetch(&g_panic_state_key_ready, 1, 5);
	} else {
		while (!g_panic_state_key_is_ready()) { Sleep(0); }
	}
}
#undef g_panic_state_key_is_ready
static PanicState* g_panic_state_slot(void) { g_panic_state_key_init(); void* p = g_panic_state_fls_get ? g_panic_state_fls_get(g_panic_state_key) : TlsGetValue(g_panic_state_key); if (!p) { p = calloc(1, sizeof(PanicState)); if (g_panic_state_fls_set) g_panic_state_fls_set(g_panic_state_key, p); else TlsSetValue(g_panic_state_key, p); } return (PanicState*)p; }
#define g_panic_state (*g_panic_state_slot())
#elif defined(__TINYC__)
static pthread_key_t g_panic_state_key;
static pthread_once_t g_panic_state_key_once = PTHREAD_ONCE_INIT;
static void g_panic_state_key_create(void) { pthread_key_create(&g_panic_state_key, free); }
static void g_panic_state_key_init(void) { pthread_once(&g_panic_state_key_once, g_panic_state_key_create); }
static PanicState* g_panic_state_slot(void) { g_panic_state_key_init(); void* p = pthread_getspecific(g_panic_state_key); if (!p) { p = calloc(1, sizeof(PanicState)); pthread_setspecific(g_panic_state_key, p); } return (PanicState*)p; }
#define g_panic_state (*g_panic_state_slot())
#elif defined(_MSC_VER)
__declspec(thread) PanicState g_panic_state = {0};
#elif defined(__cplusplus)
thread_local PanicState g_panic_state = {0};
#else
_Thread_local PanicState g_panic_state = {0};
#endif

string Array_rune__string(Array ra);
string Array_string__join(Array a, string sep);
string Array_u8__bytestr(Array b);
string Array_u8__hex(Array b);
DenseArray DenseArray__clone(DenseArray* d);
void DenseArray__delete(DenseArray* d, i64 i);
i64 DenseArray__expand(DenseArray* d);
bool DenseArray__has_index(DenseArray* d, i64 i);
void* DenseArray__key(DenseArray* d, i64 i);
void DenseArray__reserve(DenseArray* d, i64 n);
void DenseArray__trim_deleted_tail(DenseArray* d);
void* DenseArray__value(DenseArray* d, i64 i);
void DenseArray__zeros_to_end(DenseArray* d);
i64 Error__code(Error err);
string Error__msg(Error err);
string IError__str(IError err);
i64 MessageError__code(MessageError err);
string MessageError__msg(MessageError err);
string MessageError__str(MessageError err);
string None____str(None__ _0);
__v_option_u32 RunesIterator__next(RunesIterator* ri);
void VMapData__cached_rehash(VMapData* m, u32 old_cap);
void VMapData__clear(VMapData* m);
VMapData* VMapData__clone(VMapData* m);
void VMapData__delete(VMapData* m, void* key);
void VMapData__ensure_extra_metas(VMapData* m, u32 probe_count);
void VMapData__ensure_extra_metas_grow(VMapData* m);
bool VMapData__exists(VMapData* m, void* key);
void VMapData__expand(VMapData* m);
void VMapData__free(VMapData* m);
void* VMapData__get(VMapData* m, void* key, void* zero);
void* VMapData__get_and_set(VMapData* m, void* key, void* zero);
void* VMapData__get_check(VMapData* m, void* key);
multi_return_u32_u32 VMapData__key_to_index(VMapData* m, void* pkey);
array VMapData__keys(VMapData* m);
void VMapData__meta_greater(VMapData* m, u32 _index, u32 _metas, u32 kvi);
multi_return_u32_u32 VMapData__meta_less(VMapData* m, u32 _index, u32 _metas);
void VMapData__panic_nil_map_hash_fn(VMapData* m);
void VMapData__rehash(VMapData* m);
void VMapData__reserve(VMapData* m, u32 n);
void VMapData__reserve_metas(VMapData* m, u32 meta_bytes);
void VMapData__set(VMapData* m, void* key, void* value);
array VMapData__values(VMapData* m);
void* __as_cast(void* obj, i64 obj_type, i64 expected_type, string obj_name, string expected_name);
u64 __at_least_one(u64 how_many);
array __new_array(i64 mylen, i64 cap, i64 elm_size);
array __new_array_noscan(i64 mylen, i64 cap, i64 elm_size);
void _ht_alloc(u8* p, ptrdiff_t n);
void _ht_free(void* p);
void _memory_panic(string fname, ptrdiff_t size);
void _write_buf_to_fd(i64 fd, u8* buf, i64 buf_len);
void _writeln_to_fd(i64 fd, string s);
void* alloc_array_data(u64 total_size);
void* alloc_array_data_uninit(u64 total_size);
void* array__alloc_array_data_like(array a, u64 total_size);
void* array__alloc_array_data_like_uninit(array a, u64 total_size);
bool array__buffer_has_slices(array a);
void array__clear(array* a);
array array__clone(array* a);
void array__clone_shallow_to_cap(array* a, i64 new_cap);
array array__clone_to_depth(array* a, i64 depth);
ArrayDataHeader* array__data_header(array a);
void array__delete(array* a, i64 i);
void array__delete_last(array* a);
void array__delete_many(array* a, i64 i, i64 size);
void array__ensure_cap(array* a, i64 required);
void array__free(array* a);
void* array__get(array a, i64 i);
void* array__get_i64(array a, i64 i);
void* array__get_ni(array a, i64 i);
void* array__get_u64(array a, u64 i);
void* array__get_unsafe(array a, i64 i);
void* array__get_with_check(array a, i64 i);
void* array__get_with_check_i64(array a, i64 i);
void* array__get_with_check_ni(array a, i64 i);
void* array__get_with_check_u64(array a, u64 i);
void array__insert(array* a, i64 i, void* val);
void array__insert_many(array* a, i64 i, void* val, i64 size);
void array__mark_buffer_has_slices(array* a);
bool array__needs_unique_append(array a, i64 required);
bool array__needs_unique_shift(array a, i64 required);
bool array__needs_unique_shrink(array a);
void* array__pop_left(array* a);
void array__prepend(array* a, void* val);
void array__push(array* a, void* val);
void array__push_many(array* a, void* val, i64 size);
array array__reverse(array a);
void array__set(array* a, i64 i, void* val);
void array__set_i64(array* a, i64 i, void* val);
void array__set_managed_flags(array* a, bool is_slice);
void array__set_ni(array* a, i64 i, void* val);
void array__set_u64(array* a, u64 i, void* val);
void array__set_unsafe(array* a, i64 i, void* val);
array array__slice(array a, i64 start, i64 _end);
array array__slice_ni(array a, i64 _start, i64 _end);
bool array__uses_noscan_data(array a);
u64 array_data_allocation_size(u64 total_size);
i64 array_data_header_size(void);
void array_sort_move(void* dst, i64 di, void* src, i64 si, i64 count, size_t element_size);
bool autostr_addr_in_stack(void* addr);
void autostr_addr_pop(void);
void autostr_addr_push(void* addr);
bool autostr_addr_type_in_stack(void* addr, i64 typ);
void autostr_addr_type_push(void* addr, i64 typ);
string autostr_array_circular(i64 len);
bool autostr_type_in_stack(i64 typ);
void autostr_type_pop(void);
void autostr_type_push(i64 typ);
multi_return_u64_u64 bits__mul_64(u64 x, u64 y);
multi_return_u64_u64 bits__mul_64_default(u64 x, u64 y);
i64 bits__trailing_zeros_32(u32 x);
i64 bits__trailing_zeros_32_default(u32 x);
i64 bits__trailing_zeros_64(u64 x);
i64 bits__trailing_zeros_64_default(u64 x);
string bool__str(bool b);
void builtin_init(void);
Array byteptr__vbytes(u8* data, i64 len);
string byteptr__vstring(u8* bp);
string byteptr__vstring_with_len(u8* bp, i64 len);
string charptr__vstring(char* cp);
string charptr__vstring_with_len(char* cp, i64 len);
void copy_element_to(void* dest, void* src, i64 element_size);
string data_to_hex_string(u8* data, i64 len);
void eprint(string s);
void eprintln(string s);
IError error(string message);
IError error_with_code(string message, i64 code);
bool f32__eq_epsilon(float a, float b);
string f32__str(float x);
float f32_abs(float a);
float f32_max(float a, float b);
string f64__str(double x);
double f64_abs(double a);
bool fast_string_eq(string a, string b);
void flush_stderr(void);
void flush_stdout(void);
void gc_runtime_init(void);
string i16__str(i16 n);
string i32__str(i32 n);
string i64__str(i64 nn);
string i8__str(i8 n);
string impl_i64_to_string(i64 nn);
void* init_array_data(void* raw);
string int__str(i64 n);
string int__str_l(i64 nn, i64 max);
main__Probe* katomic__load_T_ptr_Probe(main__Probe** var);
u16 katomic__load_T_u16(u16* var);
u8* malloc_noscan(ptrdiff_t n);
u8* malloc_uninit(ptrdiff_t n);
void map__clear(map* m);
map map__clone(map* m);
void map__delete(map* m, void* key);
bool map__exists(map* m, void* key);
void map__free(map* m);
void* map__get(map* m, void* key, void* zero);
void* map__get_and_set(map* m, void* key, void* zero);
void* map__get_check(map* m, void* key);
array map__keys(map* m);
void map__reserve(map* m, u32 n);
void map__set(map* m, void* key, void* value);
array map__values(map* m);
void map_clone_int_1(void* dest, void* pkey);
void map_clone_int_16(void* dest, void* pkey);
void map_clone_int_2(void* dest, void* pkey);
void map_clone_int_4(void* dest, void* pkey);
void map_clone_int_8(void* dest, void* pkey);
void map_clone_string(void* dest, void* pkey);
bool map_eq_int_1(void* a, void* b);
bool map_eq_int_16(void* a, void* b);
bool map_eq_int_2(void* a, void* b);
bool map_eq_int_4(void* a, void* b);
bool map_eq_int_8(void* a, void* b);
bool map_eq_string(void* a, void* b);
void map_free_nop(void* _0);
void map_free_string(void* pkey);
u64 map_hash_int_1(void* pkey);
u64 map_hash_int_16(void* pkey);
u64 map_hash_int_2(void* pkey);
u64 map_hash_int_4(void* pkey);
u64 map_hash_int_8(void* pkey);
u64 map_hash_string(void* pkey);
bool map_map_eq(map a, map b);
void* memdup(void* src, ptrdiff_t sz);
void* memdup_align(void* src, ptrdiff_t sz, ptrdiff_t align);
void* memdup_noscan(void* src, ptrdiff_t sz);
array new_array_from_c_array(i64 len, i64 cap, i64 elm_size, void* c_array);
array new_array_from_c_array_noscan(i64 len, i64 cap, i64 elm_size, void* c_array);
DenseArray new_dense_array(i64 key_bytes, i64 value_bytes);
map new_map(i64 key_bytes, i64 value_bytes, _fn_ptr_1e8d64a3d95a0da1 hash_fn, _fn_ptr_c95f092653bee64 key_eq_fn, _fn_ptr_1a3da2026b1489ea clone_fn, _fn_ptr_5373f7edc7b60e26 free_fn);
VMapData* new_map_data(i64 key_bytes, i64 value_bytes, _fn_ptr_1e8d64a3d95a0da1 hash_fn, _fn_ptr_c95f092653bee64 key_eq_fn, _fn_ptr_1a3da2026b1489ea clone_fn, _fn_ptr_5373f7edc7b60e26 free_fn);
void panic_debug(i64 line_no, string file, string mod, string fn_name, string s);
void panic_fatal(void);
void panic_frame_done(void* frame);
void panic_frame_pop(void* frame);
void panic_frame_push(void* frame);
void panic_frame_relink(void* frame);
void panic_frames_reset(void);
void panic_jump_next(void);
void panic_n(string s, i64 number1);
void panic_n2(string s, i64 number1, i64 number2);
void panic_n3(string s, i64 number1, i64 number2, i64 number3);
void panic_on_negative_cap(i64 cap);
void panic_on_negative_len(i64 len);
PanicRecord* panic_record(i64 i);
void panic_record_drop(void);
__v_option_string panic_recover_frame(void* frame);
void panic_unwind(string msg, PanicDebugInfo debug);
bool print_backtrace_skipping_top_frames(i64 xskipframes);
bool print_backtrace_skipping_top_frames_linux(i64 skipframes);
string ptr_str(void* ptr);
void race_stdio_write(void);
u8* realloc_data(u8* old_data, i64 old_size, i64 new_size);
Array rune__bytes(u32 c);
u32 rune__map_to(u32 c, int mode);
string rune__str(u32 c);
u32 rune__to_lower(u32 c);
u32 rune__to_upper(u32 c);
void set_stream_unbuffered(FILE* stream);
string strconv__Dec32__get_string_32(strconv__Dec32 d, bool neg, i64 i_n_digit, i64 i_pad_digit);
string strconv__Dec64__get_string_64(strconv__Dec64 d, bool neg, i64 i_n_digit, i64 i_pad_digit);
void strconv__assert1(bool t, string msg);
u32 strconv__bool_to_u32(bool b);
u64 strconv__bool_to_u64(bool b);
i64 strconv__dec_digits(u64 n);
strconv__Dec32 strconv__f32_to_decimal(u32 mant, u32 exp);
multi_return_strconv__Dec32_bool strconv__f32_to_decimal_exact_int(u32 i_mant, u32 exp);
string strconv__f32_to_str(float f, i64 n_digit);
string strconv__f32_to_str_l(float f);
strconv__Dec64 strconv__f64_to_decimal(u64 mant, u64 exp);
multi_return_strconv__Dec64_bool strconv__f64_to_decimal_exact_int(u64 i_mant, u64 exp);
string strconv__f64_to_str(double f, i64 n_digit);
string strconv__f64_to_str_l(double f);
string strconv__format_int(i64 n, i64 radix);
string strconv__format_uint(u64 n, i64 radix);
string strconv__ftoa_32(float f);
string strconv__ftoa_64(double f);
string strconv__fxx_to_str_l_parse(string s);
string strconv__get_string_special(bool neg, bool expZero, bool mantZero);
u32 strconv__log10_pow2(i64 e);
u32 strconv__log10_pow5(i64 e);
u32 strconv__mul_pow5_div_pow2(u32 m, u32 i, i64 j);
u32 strconv__mul_pow5_invdiv_pow2(u32 m, u32 q, i64 j);
u32 strconv__mul_shift_32(u32 m, u64 mul, i64 ishift);
u64 strconv__mul_shift_64(u64 m, strconv__Uint128 mul, i64 shift);
bool strconv__multiple_of_power_of_five_32(u32 v, u32 p);
bool strconv__multiple_of_power_of_five_64(u64 v, u32 p);
bool strconv__multiple_of_power_of_two_32(u32 v, u32 p);
bool strconv__multiple_of_power_of_two_64(u64 v, u32 p);
i64 strconv__pow5_bits(i64 e);
u32 strconv__pow5_factor_32(u32 i_v);
u32 strconv__pow5_factor_64(u64 v_i);
u64 strconv__shift_right_128(strconv__Uint128 v, i64 shift);
string string__all_after(string s, string sub);
string string__all_after_last(string s, string sub);
string string__all_before(string s, string sub);
string string__all_before_last(string s, string sub);
u8 string__at(string s, i64 idx);
u8 string__at_i64(string s, i64 idx);
u8 string__at_ni(string s, i64 idx);
u8 string__at_u64(string s, u64 idx);
__v_option_u8 string__at_with_check(string s, i64 idx);
__v_option_u8 string__at_with_check_i64(string s, i64 idx);
__v_option_u8 string__at_with_check_ni(string s, i64 idx);
__v_option_u8 string__at_with_check_u64(string s, u64 idx);
string string__clone(string a);
bool string__contains(string s, string substr);
bool string__contains_u8(string s, u8 x);
bool string__eq(string s, string a);
void string__free(string* s);
i64 string__index_(string s, string p);
i64 string__index_kmp(string s, string p);
i64 string__index_last_(string s, string p);
bool string__is_capital(string s);
bool string__is_pure_ascii(string s);
bool string__lt(string s, string a);
string string__plus(string s, string a);
Array string__runes(string s);
string string__substr(string s, i64 start, i64 _end);
string string__substr_ni(string s, i64 _start, i64 _end);
string string__to_lower(string s);
string string__to_lower_ascii(string s);
string string__to_upper(string s);
string string__to_upper_ascii(string s);
string string_plus_many(i64 data_len, string* input_base);
void strings__Builder__free(Array* b);
string strings__Builder__str(Array* b);
void strings__Builder__write_ptr(Array* b, u8* ptr, i64 len);
void strings__Builder__write_runes(Array* b, Array runes);
void strings__Builder__write_string(Array* b, string s);
Array strings__new_builder(i64 initial_size);
string tos(u8* s, i64 len);
void trace_error(string x);
string u64__str(u64 nn);
string u64_to_hex_no_leading_zeros(u64 nn, u8 len);
string u8__ascii_str(u8 b);
bool u8__is_capital(u8 c);
bool u8__is_letter(u8 c);
string u8__vstring(u8* bp);
string u8__vstring_with_len(u8* bp, i64 len);
void unbuffer_stdout(void);
i64 utf32_decode_to_buffer(u32 code, u8** buf);
string utf32_to_str(u32 code);
string utf32_to_str_no_malloc(u32 code, u8** buf);
multi_return_u32_i64 utf8_decode_rune(u8* _bytes, i64 available_len);
bool utf8_is_continuation(u8 b);
void v_exit(i64 code);
i64 v_fixed_index(i64 i, i64 len);
i64 v_fixed_index_i64(i64 i, i64 len);
i64 v_fixed_index_ni(i64 i, i64 len);
i64 v_fixed_index_u64(u64 i, i64 len);
void v_free(void* ptr);
u64 v_getpid(void);
u64 v_gettid(void);
u8* v_malloc(ptrdiff_t n);
i64 v_ni_index(i64 i, i64 len);
void v_panic(string s);
u8* v_realloc(u8* b, ptrdiff_t n);
i64 v_slice_index_i64(i64 i);
i64 v_slice_index_u64(u64 i);
u8* vcalloc(ptrdiff_t n);
u8* vcalloc_noscan(ptrdiff_t n);
string vcurrent_hash(void);
i64 vmemcmp(void* const_s1, void* const_s2, ptrdiff_t n);
void* vmemcpy(void* dest, void* const_src, ptrdiff_t n);
void* vmemmove(void* dest, void* const_src, ptrdiff_t n);
void* vmemset(void* s, i64 c, ptrdiff_t n);
Array voidptr__vbytes(void* data, i64 len);
i64 vstrlen(u8* s);
i64 vstrlen_char(char* s);

string IError__msg(IError* i);
i64 IError__code(IError* i);


static const string _str_0 = {"\n", 1, 1};
static const string _str_1 = {" ", 1, 1};
static const string _str_2 = {".", 1, 1};
static const string _str_3 = {"array.ensure_cap: array with the flag `.nogrow` cannot grow in size, array required new size:", 93, 1};
static const string _str_4 = {"array.ensure_cap: array needs to grow to cap (which is > 2^31):", 63, 1};
static const string _str_5 = {"array.repeat: count is negative:", 32, 1};
static const string _str_6 = {"array.insert: index out of range (i,a.len):", 43, 1};
static const string _str_7 = {"array.insert: a.len reached max_int", 35, 1};
static const string _str_8 = {"array.insert_many: index out of range (i,a.len):", 48, 1};
static const string _str_9 = {"array.insert_many: max_int will be exceeded by a.len:", 53, 1};
static const string _str_10 = {"array.delete: index out of range (i,a.len):", 43, 1};
static const string _str_11 = {"array.delete: index out of range (i,i+size,a.len):", 50, 1};
static const string _str_12 = {"array.get: index out of range (i,a.len):", 40, 1};
static const string _str_13 = {"array.get: index out of range (i,a.len): ", 41, 1};
static const string _str_14 = {", ", 2, 1};
static const string _str_15 = {"array.first: array is empty", 27, 1};
static const string _str_16 = {"array.last: array is empty", 26, 1};
static const string _str_17 = {"array.pop_left: array is empty", 30, 1};
static const string _str_18 = {"array.pop: array is empty", 25, 1};
static const string _str_19 = {"array.delete_last: array is empty", 33, 1};
static const string _str_20 = {"array.slice: invalid slice index (start>end):", 45, 1};
static const string _str_21 = {"array.slice: slice bounds out of range (", 40, 1};
static const string _str_22 = {" >= ", 4, 1};
static const string _str_23 = {")", 1, 1};
static const string _str_24 = {"array.slice: slice bounds out of range (start<0):", 49, 1};
static const string _str_25 = {"array.set: index out of range (i,a.len):", 40, 1};
static const string _str_26 = {"array.set: index out of range (i,a.len): ", 41, 1};
static const string _str_27 = {"array.push: negative len", 24, 1};
static const string _str_28 = {"array.push: len bigger than max_int", 35, 1};
static const string _str_29 = {"array.push_many: new len exceeds max_int", 40, 1};
static const string _str_30 = {"", 0, 1};
static const string _str_31 = {"array.grow_cap: max_int will be exceeded by new cap:", 52, 1};
static const string _str_32 = {"array.grow_len: max_int will be exceeded by new len:", 52, 1};
static const string _str_33 = {"negative .len:", 14, 1};
static const string _str_34 = {"negative .cap:", 14, 1};
static const string _str_35 = {"[]", 2, 1};
static const string _str_36 = {"[", 1, 1};
static const string _str_37 = {"<circular>", 10, 1};
static const string _str_38 = {"]", 1, 1};
static const string _str_39 = {"as cast: cannot cast `", 22, 1};
static const string _str_40 = {"` to `", 6, 1};
static const string _str_41 = {"`", 1, 1};
static const string _str_42 = {"none", 4, 1};
static const string _str_43 = {"nil", 3, 1};
static const string _str_44 = {"; code: ", 8, 1};
static const string _str_45 = {" | code: ", 9, 1};
static const string _str_46 = {"error", 5, 1};
static const string _str_47 = {"00000000090000000b0000000c0000000e0000001f0000007f0000009f000000ad000000ad0000001c0600001c0600000e1800000e1800000b2000000b2000000e2000000f200000282000002820000029200000292000002a2000002e20000060200000642000006520000065200000662000006f200000fffe0000fffe0000f0ff0000f8ff0000f9ff0000fbff00003034010038340100a0bc0100a3bc010073d101007ad1010000000e0000000e0001000e0001000e0002000e001f000e0080000e00ff000e00f0010e00ff0f0e00", 416, 1};
static const string _str_48 = {"000300006f0300008304000087040000880400008904000091050000bd050000bf050000bf050000c1050000c2050000c4050000c5050000c7050000c7050000100600001a0600004b0600005f0600007006000070060000d6060000dc060000df060000e4060000e7060000e8060000ea060000ed0600001107000011070000300700004a070000a6070000b0070000eb070000f3070000fd070000fd07000016080000190800001b080000230800002508000027080000290800002d080000590800005b080000d3080000e1080000e3080000020900003a0900003a0900003c0900003c09000041090000480900004d0900004d090000510900005709000062090000630900008109000081090000bc090000bc090000be090000be090000c1090000c4090000cd090000cd090000d7090000d7090000e2090000e3090000fe090000fe090000010a0000020a00003c0a00003c0a0000410a0000420a0000470a0000480a00004b0a00004d0a0000510a0000510a0000700a0000710a0000750a0000750a0000810a0000820a0000bc0a0000bc0a0000c10a0000c50a0000c70a0000c80a0000cd0a0000cd0a0000e20a0000e30a0000fa0a0000ff0a0000010b0000010b00003c0b00003c0b00003e0b00003e0b00003f0b00003f0b0000410b0000440b00004d0b00004d0b0000550b0000560b0000570b0000570b0000620b0000630b0000820b0000820b0000be0b0000be0b0000c00b0000c00b0000cd0b0000cd0b0000d70b0000d70b0000000c0000000c0000040c0000040c00003e0c0000400c0000460c0000480c00004a0c00004d0c0000550c0000560c0000620c0000630c0000810c0000810c0000bc0c0000bc0c0000bf0c0000bf0c0000c20c0000c20c0000c60c0000c60c0000cc0c0000cd0c0000d50c0000d60c0000e20c0000e30c0000000d0000010d00003b0d00003c0d00003e0d00003e0d0000410d0000440d00004d0d00004d0d0000570d0000570d0000620d0000630d0000810d0000810d0000ca0d0000ca0d0000cf0d0000cf0d0000d20d0000d40d0000d60d0000d60d0000df0d0000df0d0000310e0000310e0000340e00003a0e0000470e00004e0e0000b10e0000b10e0000b40e0000bc0e0000c80e0000cd0e0000180f0000190f0000350f0000350f0000370f0000370f0000390f0000390f0000710f00007e0f0000800f0000840f0000860f0000870f00008d0f0000970f0000990f0000bc0f0000c60f0000c60f00002d100000301000003210000037100000391000003a1000003d1000003e10000058100000591000005e100000601000007110000074100000821000008210000085100000861000008d1000008d1000009d1000009d1000005d1300005f1300001217000014170000321700003417000052170000531700007217000073170000b4170000b5170000b7170000bd170000c6170000c6170000c9170000d3170000dd170000dd1700000b1800000d1800008518000086180000a9180000a9180000201900002219000027190000281900003219000032190000391900003b190000171a0000181a00001b1a00001b1a0000561a0000561a0000581a00005e1a0000601a0000601a0000621a0000621a0000651a00006c1a0000731a00007c1a00007f1a00007f1a0000b01a0000bd1a0000be1a0000be1a0000bf1a0000c01a0000001b0000031b0000341b0000341b0000351b0000351b0000361b00003a1b00003c1b00003c1b0000421b0000421b00006b1b0000731b0000801b0000811b0000a21b0000a51b0000a81b0000a91b0000ab1b0000ad1b0000e61b0000e61b0000e81b0000e91b0000ed1b0000ed1b0000ef1b0000f11b00002c1c0000331c0000361c0000371c0000d01c0000d21c0000d41c0000e01c0000e21c0000e81c0000ed1c0000ed1c0000f41c0000f41c0000f81c0000f91c0000c01d0000f91d0000fb1d0000ff1d00000c2000000c200000d0200000dc200000dd200000e0200000e1200000e1200000e2200000e4200000e5200000f0200000ef2c0000f12c00007f2d00007f2d0000e02d0000ff2d00002a3000002d3000002e3000002f300000993000009a3000006fa600006fa60000", 3072, 1};
static const string _str_49 = {"70a6000072a6000074a600007da600009ea600009fa60000f0a60000f1a6000002a8000002a8000006a8000006a800000ba800000ba8000025a8000026a800002ca800002ca80000c4a80000c5a80000e0a80000f1a80000ffa80000ffa8000026a900002da9000047a9000051a9000080a9000082a90000b3a90000b3a90000b6a90000b9a90000bca90000bda90000e5a90000e5a9000029aa00002eaa000031aa000032aa000035aa000036aa000043aa000043aa00004caa00004caa00007caa00007caa0000b0aa0000b0aa0000b2aa0000b4aa0000b7aa0000b8aa0000beaa0000bfaa0000c1aa0000c1aa0000ecaa0000edaa0000f6aa0000f6aa0000e5ab0000e5ab0000e8ab0000e8ab0000edab0000edab00001efb00001efb000000fe00000ffe000020fe00002ffe00009eff00009fff0000fd010100fd010100e0020100e0020100760301007a030100010a0100030a0100050a0100060a01000c0a01000f0a0100380a01003a0a01003f0a01003f0a0100e50a0100e60a0100240d0100270d0100ab0e0100ac0e0100460f0100500f0100011001000110010038100100461001007f10010081100100b3100100b6100100b9100100ba1001000011010002110100271101002b1101002d1101003411010073110100731101008011010081110100b6110100be110100c9110100cc110100cf110100cf1101002f12010031120100341201003412010036120100371201003e1201003e120100df120100df120100e3120100ea12010000130100011301003b1301003c1301003e1301003e13010040130100401301005713010057130100661301006c1301007013010074130100381401003f140100421401004414010046140100461401005e1401005e140100b0140100b0140100b3140100b8140100ba140100ba140100bd140100bd140100bf140100c0140100c2140100c3140100af150100af150100b2150100b5150100bc150100bd150100bf150100c0150100dc150100dd150100331601003a1601003d1601003d1601003f16010040160100ab160100ab160100ad160100ad160100b0160100b5160100b7160100b71601001d1701001f1701002217010025170100271701002b1701002f18010037180100391801003a18010030190100301901003b1901003c1901003e1901003e1901004319010043190100d4190100d7190100da190100db190100e0190100e0190100011a01000a1a0100331a0100381a01003b1a01003e1a0100471a0100471a0100511a0100561a0100591a01005b1a01008a1a0100961a0100981a0100991a0100301c0100361c0100381c01003d1c01003f1c01003f1c0100921c0100a71c0100aa1c0100b01c0100b21c0100b31c0100b51c0100b61c0100311d0100361d01003a1d01003a1d01003c1d01003d1d01003f1d0100451d0100471d0100471d0100901d0100911d0100951d0100951d0100971d0100971d0100f31e0100f41e0100f06a0100f46a0100306b0100366b01004f6f01004f6f01008f6f0100926f0100e46f0100e46f01009dbc01009ebc010065d1010065d1010067d1010069d101006ed1010072d101007bd1010082d1010085d101008bd10100aad10100add1010042d2010044d2010000da010036da01003bda01006cda010075da010075da010084da010084da01009bda01009fda0100a1da0100afda010000e0010006e0010008e0010018e001001be0010021e0010023e0010024e0010026e001002ae0010030e1010036e10100ece20100efe20100d0e80100d6e8010044e901004ae90100fbf30100fff3010020000e007f000e0000010e00ef010e00", 2656, 1};
static const string _str_50 = {"03090000030900003b0900003b0900003e09000040090000490900004c0900004e0900004f0900008209000083090000bf090000c0090000c7090000c8090000cb090000cc090000030a0000030a00003e0a0000400a0000830a0000830a0000be0a0000c00a0000c90a0000c90a0000cb0a0000cc0a0000020b0000030b0000400b0000400b0000470b0000480b00004b0b00004c0b0000bf0b0000bf0b0000c10b0000c20b0000c60b0000c80b0000ca0b0000cc0b0000010c0000030c0000410c0000440c0000820c0000830c0000be0c0000be0c0000c00c0000c10c0000c30c0000c40c0000c70c0000c80c0000ca0c0000cb0c0000020d0000030d00003f0d0000400d0000460d0000480d00004a0d00004c0d0000820d0000830d0000d00d0000d10d0000d80d0000de0d0000f20d0000f30d0000330e0000330e0000b30e0000b30e00003e0f00003f0f00007f0f00007f0f000031100000311000003b1000003c10000056100000571000008410000084100000b6170000b6170000be170000c5170000c7170000c81700002319000026190000291900002b19000030190000311900003319000038190000191a00001a1a0000551a0000551a0000571a0000571a00006d1a0000721a0000041b0000041b00003b1b00003b1b00003d1b0000411b0000431b0000441b0000821b0000821b0000a11b0000a11b0000a61b0000a71b0000aa1b0000aa1b0000e71b0000e71b0000ea1b0000ec1b0000ee1b0000ee1b0000f21b0000f31b0000241c00002b1c0000341c0000351c0000e11c0000e11c0000f71c0000f71c000023a8000024a8000027a8000027a8000080a8000081a80000b4a80000c3a8000052a9000053a9000083a9000083a90000b4a90000b5a90000baa90000bba90000bea90000c0a900002faa000030aa000033aa000034aa00004daa00004daa0000ebaa0000ebaa0000eeaa0000efaa0000f5aa0000f5aa0000e3ab0000e4ab0000e6ab0000e7ab0000e9ab0000eaab0000ecab0000ecab0000001001000010010002100100021001008210010082100100b0100100b2100100b7100100b81001002c1101002c11010045110100461101008211010082110100b3110100b5110100bf110100c0110100ce110100ce1101002c1201002e12010032120100331201003512010035120100e0120100e212010002130100031301003f1301003f130100411301004413010047130100481301004b1301004d1301006213010063130100351401003714010040140100411401004514010045140100b1140100b2140100b9140100b9140100bb140100bc140100be140100be140100c1140100c1140100b0150100b1150100b8150100bb150100be150100be15010030160100321601003b1601003c1601003e1601003e160100ac160100ac160100ae160100af160100b6160100b6160100201701002117010026170100261701002c1801002e1801003818010038180100311901003519010037190100381901003d1901003d19010040190100401901004219010042190100d1190100d3190100dc190100df190100e4190100e4190100391a0100391a0100571a0100581a0100971a0100971a01002f1c01002f1c01003e1c01003e1c0100a91c0100a91c0100b11c0100b11c0100b41c0100b41c01008a1d01008e1d0100931d0100941d0100961d0100961d0100f51e0100f61e0100516f0100876f0100f06f0100f16f010066d1010066d101006dd101006dd10100", 2544, 1};
static const string _str_51 = {"0006000005060000dd060000dd0600000f0700000f070000e2080000e20800004e0d00004e0d0000bd100100bd100100cd100100cd100100c2110100c31101003f1901003f19010041190100411901003a1a01003a1a0100841a0100891a0100461d0100461d0100", 208, 1};
static const string _str_52 = {"a9000000a9000000ae000000ae0000003c2000003c2000004920000049200000222100002221000039210000392100009421000099210000a9210000aa2100001a2300001b23000028230000282300008823000088230000cf230000cf230000e9230000ec230000ed230000ee230000ef230000ef230000f0230000f0230000f1230000f2230000f3230000f3230000f8230000fa230000c2240000c2240000aa250000ab250000b6250000b6250000c0250000c0250000fb250000fe2500000026000001260000022600000326000004260000042600000526000005260000072600000d2600000e2600000e2600000f2600001026000011260000112600001226000012260000142600001526000016260000172600001826000018260000192600001c2600001d2600001d2600001e2600001f2600002026000020260000212600002126000022260000232600002426000025260000262600002626000027260000292600002a2600002a2600002b2600002d2600002e2600002e2600002f2600002f260000302600003726000038260000392600003a2600003a2600003b2600003f26000040260000402600004126000041260000422600004226000043260000472600004826000053260000542600005e2600005f2600005f2600006026000060260000612600006226000063260000632600006426000064260000652600006626000067260000672600006826000068260000692600007a2600007b2600007b2600007c2600007d2600007e2600007e2600007f2600007f2600008026000085260000902600009126000092260000922600009326000093260000942600009426000095260000952600009626000097260000982600009826000099260000992600009a2600009a2600009b2600009c2600009d2600009f260000a0260000a1260000a2260000a6260000a7260000a7260000a8260000a9260000aa260000ab260000ac260000af260000b0260000b1260000b2260000bc260000bd260000be260000bf260000c3260000c4260000c5260000c6260000c7260000c8260000c8260000c9260000cd260000ce260000ce260000cf260000cf260000d0260000d0260000d1260000d1260000d2260000d2260000d3260000d3260000d4260000d4260000d5260000e8260000e9260000e9260000ea260000ea260000eb260000ef260000f0260000f1260000f2260000f3260000f4260000f4260000f5260000f5260000f6260000f6260000f7260000f9260000fa260000fa260000fb260000fc260000fd260000fd260000fe26000001270000022700000227000003270000042700000527000005270000082700000c2700000d2700000d2700000e2700000e2700000f2700000f27000010270000112700001227000012270000142700001427000016270000162700001d2700001d270000212700002127000028270000282700003327000034270000442700004427000047270000472700004c2700004c2700004e2700004e270000532700005527000057270000572700006327000063270000642700006427000065270000672700009527000097270000a1270000a1270000b0270000b0270000bf270000bf2700003429000035290000052b0000072b00001b2b00001c2b0000502b0000502b0000552b0000552b000030300000303000003d3000003d3000009732000097320000993200009932000000f0010003f0010004f0010004f0010005f00100cef00100cff00100cff00100d0f00100fff001000df101000ff101002ff101002ff101006cf101006ff1010070f1010071f101007ef101007ff101008ef101008ef1010091f101009af10100adf10100e5f1010001f2010002f2010003f201000ff201001af201001af201002ff201002ff2010032f201003af201003cf201003ff2010049f201004ff2010050f2010051f2010052f20100fff2010000f301000cf301000df301000ef301000ff301000ff3010010f3010010f3010011f3010011f3010012f3010012f3010013f3010015f3010016f3010018f3010019f3010019f301001af301001af301001bf301001bf301001cf301001cf301001df301001ef301001ff3010020f30100", 3072, 1};
static const string _str_53 = {"21f3010021f3010022f3010023f3010024f301002cf301002df301002ff3010030f3010031f3010032f3010033f3010034f3010035f3010036f3010036f3010037f301004af301004bf301004bf301004cf301004ff3010050f3010050f3010051f301007bf301007cf301007cf301007df301007df301007ef301007ff3010080f3010093f3010094f3010095f3010096f3010097f3010098f3010098f3010099f301009bf301009cf301009df301009ef301009ff30100a0f30100c4f30100c5f30100c5f30100c6f30100c6f30100c7f30100c7f30100c8f30100c8f30100c9f30100c9f30100caf30100caf30100cbf30100cef30100cff30100d3f30100d4f30100dff30100e0f30100e3f30100e4f30100e4f30100e5f30100f0f30100f1f30100f2f30100f3f30100f3f30100f4f30100f4f30100f5f30100f5f30100f6f30100f6f30100f7f30100f7f30100f8f30100faf3010000f4010007f4010008f4010008f4010009f401000bf401000cf401000ef401000ff4010010f4010011f4010012f4010013f4010013f4010014f4010014f4010015f4010015f4010016f4010016f4010017f4010029f401002af401002af401002bf401003ef401003ff401003ff4010040f4010040f4010041f4010041f4010042f4010064f4010065f4010065f4010066f401006bf401006cf401006df401006ef40100acf40100adf40100adf40100aef40100b5f40100b6f40100b7f40100b8f40100ebf40100ecf40100edf40100eef40100eef40100eff40100eff40100f0f40100f4f40100f5f40100f5f40100f6f40100f7f40100f8f40100f8f40100f9f40100fcf40100fdf40100fdf40100fef40100fef40100fff4010002f5010003f5010003f5010004f5010007f5010008f5010008f5010009f5010009f501000af5010014f5010015f5010015f5010016f501002bf501002cf501002df501002ef501003df5010046f5010048f5010049f501004af501004bf501004ef501004ff501004ff5010050f501005bf501005cf5010067f5010068f501006ef501006ff5010070f5010071f5010072f5010073f5010079f501007af501007af501007bf5010086f5010087f5010087f5010088f5010089f501008af501008df501008ef501008ff5010090f5010090f5010091f5010094f5010095f5010096f5010097f50100a3f50100a4f50100a4f50100a5f50100a5f50100a6f50100a7f50100a8f50100a8f50100a9f50100b0f50100b1f50100b2f50100b3f50100bbf50100bcf50100bcf50100bdf50100c1f50100c2f50100c4f50100c5f50100d0f50100d1f50100d3f50100d4f50100dbf50100dcf50100def50100dff50100e0f50100e1f50100e1f50100e2f50100e2f50100e3f50100e3f50100e4f50100e7f50100e8f50100e8f50100e9f50100eef50100eff50100eff50100f0f50100f2f50100f3f50100f3f50100f4f50100f9f50100faf50100faf50100fbf50100fff5010000f6010000f6010001f6010006f6010007f6010008f6010009f601000df601000ef601000ef601000ff601000ff6010010f6010010f6010011f6010011f6010012f6010014f6010015f6010015f6010016f6010016f6010017f6010017f6010018f6010018f6010019f6010019f601001af601001af601001bf601001bf601001cf601001ef601001ff601001ff6010020f6010025f6010026f6010027f6010028f601002bf601002cf601002cf601002df601002df601002ef601002ff6010030f6010033f6010034f6010034f6010035f6010035f6010036f6010036f6010037f6010040f6010041f6010044f6010045f601004ff6010080f6010080f6010081f6010082f6010083f6010085f6010086f6010086f6010087f6010087f6010088f6010088f6010089f6010089f601008af601008bf601008cf601008cf601008df601008df601008ef601008ef601008ff601008ff6010090f6010090f6010091f6010093f6010094f6010094f6010095f6010095f6010096f6010096f6010097f6010097f6010098f6010098f6010099f601009af601009bf60100a1f60100a2f60100a2f60100a3f60100a3f60100a4f60100a5f60100a6f60100a6f60100a7f60100adf60100", 3072, 1};
static const string _str_54 = {"aef60100b1f60100b2f60100b2f60100b3f60100b5f60100b6f60100b6f60100b7f60100b8f60100b9f60100bef60100bff60100bff60100c0f60100c0f60100c1f60100c5f60100c6f60100caf60100cbf60100cbf60100ccf60100ccf60100cdf60100cff60100d0f60100d0f60100d1f60100d2f60100d3f60100d4f60100d5f60100d5f60100d6f60100d7f60100d8f60100dff60100e0f60100e5f60100e6f60100e8f60100e9f60100e9f60100eaf60100eaf60100ebf60100ecf60100edf60100eff60100f0f60100f0f60100f1f60100f2f60100f3f60100f3f60100f4f60100f6f60100f7f60100f8f60100f9f60100f9f60100faf60100faf60100fbf60100fcf60100fdf60100fff6010074f701007ff70100d5f70100dff70100e0f70100ebf70100ecf70100fff701000cf801000ff8010048f801004ff801005af801005ff8010088f801008ff80100aef80100fff801000cf901000cf901000df901000ff9010010f9010018f9010019f901001ef901001ff901001ff9010020f9010027f9010028f901002ff9010030f9010030f9010031f9010032f9010033f901003af901003cf901003ef901003ff901003ff9010040f9010045f9010047f901004bf901004cf901004cf901004df901004ff9010050f901005ef901005ff901006bf901006cf9010070f9010071f9010071f9010072f9010072f9010073f9010076f9010077f9010078f9010079f9010079f901007af901007af901007bf901007bf901007cf901007ff9010080f9010084f9010085f9010091f9010092f9010097f9010098f90100a2f90100a3f90100a4f90100a5f90100aaf90100abf90100adf90100aef90100aff90100b0f90100b9f90100baf90100bff90100c0f90100c0f90100c1f90100c2f90100c3f90100caf90100cbf90100cbf90100ccf90100ccf90100cdf90100cff90100d0f90100e6f90100e7f90100fff9010000fa01006ffa010070fa010073fa010074fa010074fa010075fa010077fa010078fa01007afa01007bfa01007ffa010080fa010082fa010083fa010086fa010087fa01008ffa010090fa010095fa010096fa0100a8fa0100a9fa0100affa0100b0fa0100b6fa0100b7fa0100bffa0100c0fa0100c2fa0100c3fa0100cffa0100d0fa0100d6fa0100d7fa0100fffa010000fc0100fdff0100", 1712, 1};
static const string _str_55 = {"00102030405060708090011121314151617181910212223242526272829203132333435363738393041424344454647484940515253545556575859506162636465666768696071727374757677787970818283848586878889809192939495969798999", 200, 1};
static const string _str_56 = {"0", 1, 1};
static const string _str_57 = {"-9223372036854775808", 20, 1};
static const string _str_58 = {"true", 4, 1};
static const string _str_59 = {"false", 5, 1};
static const string _str_60 = {"00", 2, 1};
static const string _str_61 = {"0x", 2, 1};
static const string _str_62 = {"`\\0`", 4, 1};
static const string _str_63 = {"`\\a`", 4, 1};
static const string _str_64 = {"`\\b`", 4, 1};
static const string _str_65 = {"`\\t`", 4, 1};
static const string _str_66 = {"`\\n`", 4, 1};
static const string _str_67 = {"`\\v`", 4, 1};
static const string _str_68 = {"`\\f`", 4, 1};
static const string _str_69 = {"`\\r`", 4, 1};
static const string _str_70 = {"`\\e`", 4, 1};
static const string _str_71 = {"-", 1, 1};
static const string _str_72 = {"map.hash_fn is nil map_ptr=", 27, 1};
static const string _str_73 = {" key_bytes=", 11, 1};
static const string _str_74 = {" value_bytes=", 13, 1};
static const string _str_75 = {" even_index=", 12, 1};
static const string _str_76 = {" shift=", 7, 1};
static const string _str_77 = {" metas=", 7, 1};
static const string _str_78 = {" prev2=", 7, 1};
static const string _str_79 = {" prev1=", 7, 1};
static const string _str_80 = {" w0=", 4, 1};
static const string _str_81 = {" w1=", 4, 1};
static const string _str_82 = {" w2=", 4, 1};
static const string _str_83 = {" w3=", 4, 1};
static const string _str_84 = {" w4=", 4, 1};
static const string _str_85 = {" w5=", 4, 1};
static const string _str_86 = {" w6=", 4, 1};
static const string _str_87 = {" w7=", 4, 1};
static const string _str_88 = {" hash_fn=", 9, 1};
static const string _str_89 = {"Probe overflow", 14, 1};
static const string _str_90 = {"map.reserve: max_int will be exceeded", 37, 1};
static const string _str_91 = {":", 1, 1};
static const string _str_92 = {": FAIL: fn ", 11, 1};
static const string _str_93 = {": assert ", 9, 1};
static const string _str_94 = {"call", 4, 1};
static const string _str_95 = {"   left value: ", 15, 1};
static const string _str_96 = {" = ", 3, 1};
static const string _str_97 = {"  right value: ", 15, 1};
static const string _str_98 = {"      message: ", 15, 1};
static const string _str_99 = {"tos(): nil string", 17, 1};
static const string _str_100 = {"tos2: nil string", 16, 1};
static const string _str_101 = {"tos3: nil string", 16, 1};
static const string _str_102 = {"string.replace_each(): odd number of strings", 44, 1};
static const string _str_103 = {"string.replace_char(): tab length too short", 43, 1};
static const string _str_104 = {"t", 1, 1};
static const string _str_105 = {"_", 1, 1};
static const string _str_106 = {"0123456789abcdef", 16, 1};
static const string _str_107 = {"0b", 2, 1};
static const string _str_108 = {"01", 2, 1};
static const string _str_109 = {" \n\t\013\014\r", 6, 1};
static const string _str_110 = {"substr(", 7, 1};
static const string _str_111 = {") out of bounds (len=", 21, 1};
static const string _str_112 = {") s=", 4, 1};
static const string _str_113 = {"string index out of range(idx,s.len):", 37, 1};
static const string _str_114 = {"string index out of range(idx,s.len): ", 38, 1};
static const string _str_115 = {"Warning: `strip_margin` cannot use white-space as a delimiter", 61, 1};
static const string _str_116 = {"    Defaulting to `|`", 21, 1};
static const string _str_117 = {"no_str", 6, 1};
static const string _str_118 = {"c", 1, 1};
static const string _str_119 = {"u8", 2, 1};
static const string _str_120 = {"i8", 2, 1};
static const string _str_121 = {"u16", 3, 1};
static const string _str_122 = {"i16", 3, 1};
static const string _str_123 = {"u32", 3, 1};
static const string _str_124 = {"i32", 3, 1};
static const string _str_125 = {"u64", 3, 1};
static const string _str_126 = {"i64", 3, 1};
static const string _str_127 = {"f32", 3, 1};
static const string _str_128 = {"f64", 3, 1};
static const string _str_129 = {"s", 1, 1};
static const string _str_130 = {"p", 1, 1};
static const string _str_131 = {"r", 1, 1};
static const string _str_132 = {"vp", 2, 1};
static const string _str_133 = {"-0", 2, 1};
static const string _str_134 = {"+inf", 4, 1};
static const string _str_135 = {"+INF", 4, 1};
static const string _str_136 = {"-inf", 4, 1};
static const string _str_137 = {"-INF", 4, 1};
static const string _str_138 = {"***ERROR!***", 12, 1};
static const string _str_139 = {"0xfe10", 6, 1};
static const string _str_140 = {"0xfe0e", 6, 1};
static const string _str_141 = {"0xfe0f", 6, 1};
static const string _str_142 = {"builtin__str_intp(2, _MOV((StrIntpData[]){{_S(\"'\"), ", 52, 1};
static const string _str_143 = {", {.d_s = ", 10, 1};
static const string _str_144 = {"}, 0, 0, 0},{_S(\"'\"), 0, {0}, 0, 0, 0}}))", 41, 1};
static const string _str_145 = {"builtin__str_intp(2, _MOV((StrIntpData[]){{_S(\"\\`\"), ", 53, 1};
static const string _str_146 = {"}, 0, 0, 0},{_S(\"\\`\"), 0, {0}, 0, 0, 0}}))", 42, 1};
static const string _str_147 = {"builtin__str_intp(1, _MOV((StrIntpData[]){{_SLIT0, ", 51, 1};
static const string _str_148 = {", {.d_f32 = ", 12, 1};
static const string _str_149 = {" }, 0, 0, 0}}))", 15, 1};
static const string _str_150 = {", {.d_f64 = ", 12, 1};
static const string _str_151 = {"%%", 2, 1};
static const string _str_152 = {"No string interpolation %% parameters", 37, 1};
static const string _str_153 = {"builtin__str_intp(2, _MOV((StrIntpData[]){{_S(\"", 47, 1};
static const string _str_154 = {"\"), ", 4, 1};
static const string _str_155 = {" }, 0, 0, 0},{_S(\"", 18, 1};
static const string _str_156 = {"\"), 0, {0}, 0, 0, 0}}))", 23, 1};
static const string _str_157 = {"builtin__str_intp(1, _MOV((StrIntpData[]){{_S(\"", 47, 1};
static const string _str_158 = {"attempted to decode too many bytes, utf-8 is limited to four bytes maximum", 74, 1};
static const string _str_159 = {"(", 1, 1};
static const string _str_160 = {" < 0", 4, 1};
static const string _str_161 = {"memory allocation failure", 25, 1};
static const string _str_162 = {"malloc", 6, 1};
static const string _str_163 = {"malloc_noscan", 13, 1};
static const string _str_164 = {"malloc_uninit", 13, 1};
static const string _str_165 = {"malloc_noscan_uninit", 20, 1};
static const string _str_166 = {"malloc_uncollectable", 20, 1};
static const string _str_167 = {"v_realloc", 9, 1};
static const string _str_168 = {"realloc_data", 12, 1};
static const string _str_169 = {"vcalloc", 7, 1};
static const string _str_170 = {"memdup_align", 12, 1};
static const string _str_171 = {"builtin__", 9, 1};
static const string _str_172 = {"__ptr__", 7, 1};
static const string _str_173 = {"&", 1, 1};
static const string _str_174 = {"_T_", 3, 1};
static const string _str_175 = {"__", 2, 1};
static const string _str_176 = {"main.main", 9, 1};
static const string _str_177 = {"main", 4, 1};
static const string _str_178 = {"+", 1, 1};
static const string _str_179 = {"/proc/self/exe", 14, 1};
static const string _str_180 = {"/", 1, 1};
static const string _str_181 = {"'", 1, 1};
static const string _str_182 = {"'\\''", 4, 1};
static const string _str_183 = {"backtrace_symbols is missing => printing backtraces is not available.", 69, 1};
static const string _str_184 = {"Some libc implementations like musl simply do not provide it.", 61, 1};
static const string _str_185 = {"at_exit failed", 14, 1};
static const string _str_186 = {"fixed array index out of range (index: ", 39, 1};
static const string _str_187 = {", len: ", 7, 1};
static const string _str_188 = {"slice index out of range for int: ", 34, 1};
static const string _str_189 = {"e690943", 7, 1};
static const string _str_190 = {" unknown", 8, 1};
static const string _str_191 = {"-0.0", 4, 1};
static const string _str_192 = {"0.0", 3, 1};
static const string _str_193 = {"map_enum_fn: invalid kind", 25, 1};
static const string _str_194 = {"map_enum_fn: invalid esize", 26, 1};
static const string _str_195 = {"================ V panic ================", 41, 1};
static const string _str_196 = {"   module: ", 11, 1};
static const string _str_197 = {" function: ", 11, 1};
static const string _str_198 = {"()", 2, 1};
static const string _str_199 = {"  message: ", 11, 1};
static const string _str_200 = {"     file: ", 11, 1};
static const string _str_201 = {"   v hash: ", 11, 1};
static const string _str_202 = {"      pid: ", 11, 1};
static const string _str_203 = {"      tid: ", 11, 1};
static const string _str_204 = {"=========================================", 41, 1};
static const string _str_205 = {"option not set (", 16, 1};
static const string _str_206 = {"result not set (", 16, 1};
static const string _str_207 = {"V panic: ", 9, 1};
static const string _str_208 = {" v hash: ", 9, 1};
static const string _str_209 = {"    pid: ", 9, 1};
static const string _str_210 = {"    tid: ", 9, 1};
static const string _str_211 = {"\n\tpanic: ", 9, 1};
static const string _str_212 = {" [recovered]", 12, 1};
static const string _str_213 = {"common_parse_uint: wrong base ", 30, 1};
static const string _str_214 = {" for ", 5, 1};
static const string _str_215 = {"common_parse_uint: wrong bit size ", 34, 1};
static const string _str_216 = {"common_parse_uint: integer overflow ", 36, 1};
static const string _str_217 = {"common_parse_uint: syntax error ", 32, 1};
static const string _str_218 = {"common_parse_int: integer overflow ", 35, 1};
static const string _str_219 = {"strconv.atoi: parsing \"\": empty string", 38, 1};
static const string _str_220 = {"strconv.atoi: parsing \"", 23, 1};
static const string _str_221 = {"\": no number after sign", 23, 1};
static const string _str_222 = {"\": values cannot start or end with underscores", 46, 1};
static const string _str_223 = {"\": consecutives underscores are not allowed", 43, 1};
static const string _str_224 = {"\": invalid radix 10 character", 29, 1};
static const string _str_225 = {"\": integer overflow", 19, 1};
static const string _str_226 = {"\": integer underflow", 20, 1};
static const string _str_227 = {"strconv.atoi64: parsing \"", 25, 1};
static const string _str_228 = {"\": ", 3, 1};
static const string _str_229 = {"integer overflow", 16, 1};
static const string _str_230 = {"integer underflow", 17, 1};
static const string _str_231 = {"strconv.atou: parsing \"\": empty string", 38, 1};
static const string _str_232 = {"strconv.atou: parsing \"{s}\" : negative value", 44, 1};
static const string _str_233 = {"strconv.atou: parsing \"", 23, 1};
static const string _str_234 = {"0.", 2, 1};
static const string _str_235 = {".0", 2, 1};
static const string _str_236 = {"nan", 3, 1};
static const string _str_237 = {"-0e+00", 6, 1};
static const string _str_238 = {"0e+00", 5, 1};
static const string _str_239 = {"shiftedSum <= math.max_u32", 26, 1};
static const string _str_240 = {"q < pow5_inv_split_32.len", 25, 1};
static const string _str_241 = {"i < pow5_split_32.len", 21, 1};
static const string _str_242 = {"e >= 0", 6, 1};
static const string _str_243 = {"e <= 1650", 9, 1};
static const string _str_244 = {"e <= 2620", 9, 1};
static const string _str_245 = {"e <= 3528", 9, 1};
static const string _str_246 = {"shift < 64", 10, 1};
static const string _str_247 = {"expected a number found an empty string", 39, 1};
static const string _str_248 = {"extra char after number", 23, 1};
static const string _str_249 = {"not a number", 12, 1};
static const string _str_250 = {"[Float conversion error!!]", 26, 1};
static const string _str_251 = {"0123456789abcdefghijklmnopqrstuvwxyz", 36, 1};
static const string _str_252 = {"invalid radix, it should be => 2 and <= 36, actual:", 51, 1};
static const string _str_253 = {"Float conversion error!!", 24, 1};
static const string _str_254 = {"% conversion specifiers number mismatch (expected %, given args)", 64, 1};
static const string _str_255 = {"Overflow Error", 14, 1};
static const string _str_256 = {"Divide by Zero Error", 20, 1};
static const string _str_257 = {"000300006f0300008304000087040000880400008904000091050000bd050000bf050000bf050000c1050000c2050000c4050000c5050000c7050000c7050000100600001a0600004b0600005f0600007006000070060000d6060000dc060000df060000e4060000e7060000e8060000ea060000ed0600001107000011070000300700004a070000a6070000b0070000eb070000f3070000fd070000fd07000016080000190800001b080000230800002508000027080000290800002d080000590800005b080000d3080000e1080000e3080000020900003a0900003a0900003c0900003c09000041090000480900004d0900004d090000510900005709000062090000630900008109000081090000bc090000bc090000be090000be090000c1090000c4090000cd090000cd090000d7090000d7090000e2090000e3090000fe090000fe090000010a0000020a00003c0a00003c0a0000410a0000420a0000470a0000480a00004b0a00004d0a0000510a0000510a0000700a0000710a0000750a0000750a0000810a0000820a0000bc0a0000bc0a0000c10a0000c50a0000c70a0000c80a0000cd0a0000cd0a0000e20a0000e30a0000fa0a0000ff0a0000010b0000010b00003c0b00003c0b00003e0b00003e0b00003f0b00003f0b0000410b0000440b00004d0b00004d0b0000550b0000560b0000570b0000570b0000620b0000630b0000820b0000820b0000be0b0000be0b0000c00b0000c00b0000cd0b0000cd0b0000d70b0000d70b0000000c0000000c0000040c0000040c00003e0c0000400c0000460c0000480c00004a0c00004d0c0000550c0000560c0000620c0000630c0000810c0000810c0000bc0c0000bc0c0000bf0c0000bf0c0000c20c0000c20c0000c60c0000c60c0000cc0c0000cd0c0000d50c0000d60c0000e20c0000e30c0000000d0000010d00003b0d00003c0d00003e0d00003e0d0000410d0000440d00004d0d00004d0d0000570d0000570d0000620d0000630d0000810d0000810d0000ca0d0000ca0d0000cf0d0000cf0d0000d20d0000d40d0000d60d0000d60d0000df0d0000df0d0000310e0000310e0000340e00003a0e0000470e00004e0e0000b10e0000b10e0000b40e0000bc0e0000c80e0000cd0e0000180f0000190f0000350f0000350f0000370f0000370f0000390f0000390f0000710f00007e0f0000800f0000840f0000860f0000870f00008d0f0000970f0000990f0000bc0f0000c60f0000c60f00002d100000301000003210000037100000391000003a1000003d1000003e10000058100000591000005e100000601000007110000074100000821000008210000085100000861000008d1000008d1000009d1000009d1000005d1300005f1300001217000014170000321700003417000052170000531700007217000073170000b4170000b5170000b7170000bd170000c6170000c6170000c9170000d3170000dd170000dd1700000b1800000d1800008518000086180000a9180000a9180000201900002219000027190000281900003219000032190000391900003b190000171a0000181a00001b1a00001b1a0000561a0000561a0000581a00005e1a0000601a0000601a0000621a0000621a0000651a00006c1a0000731a00007c1a00007f1a00007f1a0000b01a0000bd1a0000be1a0000be1a0000bf1a0000c01a0000001b0000031b0000341b0000341b0000351b0000351b0000361b00003a1b00003c1b00003c1b0000421b0000421b00006b1b0000731b0000801b0000811b0000a21b0000a51b0000a81b0000a91b0000ab1b0000ad1b0000e61b0000e61b0000e81b0000e91b0000ed1b0000ed1b0000ef1b0000f11b00002c1c0000331c0000361c0000371c0000d01c0000d21c0000d41c0000e01c0000e21c0000e81c0000ed1c0000ed1c0000f41c0000f41c0000f81c0000f91c0000c01d0000f91d0000fb1d0000ff1d00000c2000000c200000d0200000dc200000dd200000e0200000e1200000e1200000e2200000e4200000e5200000f0200000ef2c0000f12c00007f2d00007f2d0000e02d0000ff2d00002a3000002d3000002e3000002f300000993000009a3000006fa600006fa6000070a6000072a6000074a600007da600009ea600009fa60000f0a60000f1a6000002a8000002a8000006a8000006a800000ba800000ba8000025a8000026a800002ca800002ca80000c4a80000c5a80000e0a80000f1a80000ffa80000ffa8000026a900002da9000047a9000051a9000080a9000082a90000b3a90000b3a90000b6a90000b9a90000bca90000bda90000e5a90000e5a9000029aa00002eaa000031aa000032aa000035aa000036aa000043aa000043aa00004caa00004caa00007caa00007caa0000b0aa0000b0aa0000b2aa0000b4aa0000b7aa0000b8aa0000beaa0000bfaa0000c1aa0000c1aa0000ecaa0000edaa0000f6aa0000f6aa0000e5ab0000e5ab0000e8ab0000e8ab0000edab0000edab00001efb00001efb000000fe00000ffe000020fe00002ffe00009eff00009fff0000fd010100fd010100e0020100e0020100760301007a030100010a0100030a0100050a0100060a01000c0a01000f0a0100380a01003a0a01003f0a01003f0a0100e50a0100e60a0100240d0100270d0100ab0e0100ac0e0100460f0100500f0100011001000110010038100100461001007f10010081100100b3100100b6100100b9100100ba1001000011010002110100271101002b1101002d1101003411010073110100731101008011010081110100b6110100be110100c9110100cc110100cf110100cf1101002f12010031120100341201003412010036120100371201003e1201003e120100df120100df120100e3120100ea12010000130100011301003b1301003c1301003e1301003e13010040130100401301005713010057130100661301006c1301007013010074130100381401003f140100421401004414010046140100461401005e1401005e140100b0140100b0140100b3140100b8140100ba140100ba140100bd140100bd140100bf140100c0140100c2140100c3140100af150100af150100b2150100b5150100bc150100bd150100bf150100c0150100dc150100dd150100331601003a1601003d1601003d1601003f16010040160100ab160100ab160100ad160100ad160100b0160100b5160100b7160100b71601001d1701001f1701002217010025170100271701002b1701002f18010037180100391801003a18010030190100301901003b1901003c1901003e1901003e1901004319010043190100d4190100d7190100da190100db190100e0190100e0190100011a01000a1a0100331a0100381a01003b1a01003e1a0100471a0100471a0100511a0100561a0100591a01005b1a01008a1a0100961a0100981a0100991a0100301c0100361c0100381c01003d1c01003f1c01003f1c0100921c0100a71c0100aa1c0100b01c0100b21c0100b31c0100b51c0100b61c0100311d0100361d01003a1d01003a1d01003c1d01003d1d01003f1d0100451d0100471d0100471d0100901d0100911d0100951d0100951d0100971d0100971d0100f31e0100f41e0100f06a0100f46a0100306b0100366b01004f6f01004f6f01008f6f0100926f0100e46f0100e46f01009dbc01009ebc010065d1010065d1010067d1010069d101006ed1010072d101007bd1010082d1010085d101008bd10100aad10100add1010042d2010044d2010000da010036da01003bda01006cda010075da010075da010084da010084da01009bda01009fda0100a1da0100afda010000e0010006e0010008e0010018e001001be0010021e0010023e0010024e0010026e001002ae0010030e1010036e10100ece20100efe20100d0e80100d6e8010044e901004ae90100fbf30100fff3010020000e007f000e0000010e00ef010e00", 5728, 1};
static const string _str_258 = {"a9000000a9000000ae000000ae0000003c2000003c2000004920000049200000222100002221000039210000392100009421000099210000a9210000aa2100001a2300001b23000028230000282300008823000088230000cf230000cf230000e9230000ec230000ed230000ee230000ef230000ef230000f0230000f0230000f1230000f2230000f3230000f3230000f8230000fa230000c2240000c2240000aa250000ab250000b6250000b6250000c0250000c0250000fb250000fe2500000026000001260000022600000326000004260000042600000526000005260000072600000d2600000e2600000e2600000f2600001026000011260000112600001226000012260000142600001526000016260000172600001826000018260000192600001c2600001d2600001d2600001e2600001f2600002026000020260000212600002126000022260000232600002426000025260000262600002626000027260000292600002a2600002a2600002b2600002d2600002e2600002e2600002f2600002f260000302600003726000038260000392600003a2600003a2600003b2600003f26000040260000402600004126000041260000422600004226000043260000472600004826000053260000542600005e2600005f2600005f2600006026000060260000612600006226000063260000632600006426000064260000652600006626000067260000672600006826000068260000692600007a2600007b2600007b2600007c2600007d2600007e2600007e2600007f2600007f2600008026000085260000902600009126000092260000922600009326000093260000942600009426000095260000952600009626000097260000982600009826000099260000992600009a2600009a2600009b2600009c2600009d2600009f260000a0260000a1260000a2260000a6260000a7260000a7260000a8260000a9260000aa260000ab260000ac260000af260000b0260000b1260000b2260000bc260000bd260000be260000bf260000c3260000c4260000c5260000c6260000c7260000c8260000c8260000c9260000cd260000ce260000ce260000cf260000cf260000d0260000d0260000d1260000d1260000d2260000d2260000d3260000d3260000d4260000d4260000d5260000e8260000e9260000e9260000ea260000ea260000eb260000ef260000f0260000f1260000f2260000f3260000f4260000f4260000f5260000f5260000f6260000f6260000f7260000f9260000fa260000fa260000fb260000fc260000fd260000fd260000fe26000001270000022700000227000003270000042700000527000005270000082700000c2700000d2700000d2700000e2700000e2700000f2700000f27000010270000112700001227000012270000142700001427000016270000162700001d2700001d270000212700002127000028270000282700003327000034270000442700004427000047270000472700004c2700004c2700004e2700004e270000532700005527000057270000572700006327000063270000642700006427000065270000672700009527000097270000a1270000a1270000b0270000b0270000bf270000bf2700003429000035290000052b0000072b00001b2b00001c2b0000502b0000502b0000552b0000552b000030300000303000003d3000003d3000009732000097320000993200009932000000f0010003f0010004f0010004f0010005f00100cef00100cff00100cff00100d0f00100fff001000df101000ff101002ff101002ff101006cf101006ff1010070f1010071f101007ef101007ff101008ef101008ef1010091f101009af10100adf10100e5f1010001f2010002f2010003f201000ff201001af201001af201002ff201002ff2010032f201003af201003cf201003ff2010049f201004ff2010050f2010051f2010052f20100fff2010000f301000cf301000df301000ef301000ff301000ff3010010f3010010f3010011f3010011f3010012f3010012f3010013f3010015f3010016f3010018f3010019f3010019f301001af301001af301001bf301001bf301001cf301001cf301001df301001ef301001ff3010020f3010021f3010021f3010022f3010023f3010024f301002cf301002df301002ff3010030f3010031f3010032f3010033f3010034f3010035f3010036f3010036f3010037f301004af301004bf301004bf301004cf301004ff3010050f3010050f3010051f301007bf301007cf301007cf301007df301007df301007ef301007ff3010080f3010093f3010094f3010095f3010096f3010097f3010098f3010098f3010099f301009bf301009cf301009df301009ef301009ff30100a0f30100c4f30100c5f30100c5f30100c6f30100c6f30100c7f30100c7f30100c8f30100c8f30100c9f30100c9f30100caf30100caf30100cbf30100cef30100cff30100d3f30100d4f30100dff30100e0f30100e3f30100e4f30100e4f30100e5f30100f0f30100f1f30100f2f30100f3f30100f3f30100f4f30100f4f30100f5f30100f5f30100f6f30100f6f30100f7f30100f7f30100f8f30100faf3010000f4010007f4010008f4010008f4010009f401000bf401000cf401000ef401000ff4010010f4010011f4010012f4010013f4010013f4010014f4010014f4010015f4010015f4010016f4010016f4010017f4010029f401002af401002af401002bf401003ef401003ff401003ff4010040f4010040f4010041f4010041f4010042f4010064f4010065f4010065f4010066f401006bf401006cf401006df401006ef40100acf40100adf40100adf40100aef40100b5f40100b6f40100b7f40100b8f40100ebf40100ecf40100edf40100eef40100eef40100eff40100eff40100f0f40100f4f40100f5f40100f5f40100f6f40100f7f40100f8f40100f8f40100f9f40100fcf40100fdf40100fdf40100fef40100fef40100fff4010002f5010003f5010003f5010004f5010007f5010008f5010008f5010009f5010009f501000af5010014f5010015f5010015f5010016f501002bf501002cf501002df501002ef501003df5010046f5010048f5010049f501004af501004bf501004ef501004ff501004ff5010050f501005bf501005cf5010067f5010068f501006ef501006ff5010070f5010071f5010072f5010073f5010079f501007af501007af501007bf5010086f5010087f5010087f5010088f5010089f501008af501008df501008ef501008ff5010090f5010090f5010091f5010094f5010095f5010096f5010097f50100a3f50100a4f50100a4f50100a5f50100a5f50100a6f50100a7f50100a8f50100a8f50100a9f50100b0f50100b1f50100b2f50100b3f50100bbf50100bcf50100bcf50100bdf50100c1f50100c2f50100c4f50100c5f50100d0f50100d1f50100d3f50100d4f50100dbf50100dcf50100def50100dff50100e0f50100e1f50100e1f50100e2f50100e2f50100e3f50100e3f50100e4f50100e7f50100e8f50100e8f50100e9f50100eef50100eff50100eff50100f0f50100f2f50100f3f50100f3f50100f4f50100f9f50100faf50100faf50100fbf50100fff5010000f6010000f6010001f6010006f6010007f6010008f6010009f601000df601000ef601000ef601000ff601000ff6010010f6010010f6010011f6010011f6010012f6010014f6010015f6010015f6010016f6010016f6010017f6010017f6010018f6010018f6010019f6010019f601001af601001af601001bf601001bf601001cf601001ef601001ff601001ff6010020f6010025f6010026f6010027f6010028f601002bf601002cf601002cf601002df601002df601002ef601002ff6010030f6010033f6010034f6010034f6010035f6010035f6010036f6010036f6010037f6010040f6010041f6010044f6010045f601004ff6010080f6010080f6010081f6010082f6010083f6010085f6010086f6010086f6010087f6010087f6010088f6010088f6010089f6010089f601008af601008bf601008cf601008cf601008df601008df601008ef601008ef601008ff601008ff6010090f6010090f6010091f6010093f6010094f6010094f6010095f6010095f6010096f6010096f6010097f6010097f6010098f6010098f6010099f601009af601009bf60100a1f60100a2f60100a2f60100a3f60100a3f60100a4f60100a5f60100a6f60100a6f60100a7f60100adf60100", 6144, 1};
static const string _str_259 = {"a9000000a9000000ae000000ae0000003c2000003c2000004920000049200000222100002221000039210000392100009421000099210000a9210000aa2100001a2300001b23000028230000282300008823000088230000cf230000cf230000e9230000ec230000ed230000ee230000ef230000ef230000f0230000f0230000f1230000f2230000f3230000f3230000f8230000fa230000c2240000c2240000aa250000ab250000b6250000b6250000c0250000c0250000fb250000fe2500000026000001260000022600000326000004260000042600000526000005260000072600000d2600000e2600000e2600000f2600001026000011260000112600001226000012260000142600001526000016260000172600001826000018260000192600001c2600001d2600001d2600001e2600001f2600002026000020260000212600002126000022260000232600002426000025260000262600002626000027260000292600002a2600002a2600002b2600002d2600002e2600002e2600002f2600002f260000302600003726000038260000392600003a2600003a2600003b2600003f26000040260000402600004126000041260000422600004226000043260000472600004826000053260000542600005e2600005f2600005f2600006026000060260000612600006226000063260000632600006426000064260000652600006626000067260000672600006826000068260000692600007a2600007b2600007b2600007c2600007d2600007e2600007e2600007f2600007f2600008026000085260000902600009126000092260000922600009326000093260000942600009426000095260000952600009626000097260000982600009826000099260000992600009a2600009a2600009b2600009c2600009d2600009f260000a0260000a1260000a2260000a6260000a7260000a7260000a8260000a9260000aa260000ab260000ac260000af260000b0260000b1260000b2260000bc260000bd260000be260000bf260000c3260000c4260000c5260000c6260000c7260000c8260000c8260000c9260000cd260000ce260000ce260000cf260000cf260000d0260000d0260000d1260000d1260000d2260000d2260000d3260000d3260000d4260000d4260000d5260000e8260000e9260000e9260000ea260000ea260000eb260000ef260000f0260000f1260000f2260000f3260000f4260000f4260000f5260000f5260000f6260000f6260000f7260000f9260000fa260000fa260000fb260000fc260000fd260000fd260000fe26000001270000022700000227000003270000042700000527000005270000082700000c2700000d2700000d2700000e2700000e2700000f2700000f27000010270000112700001227000012270000142700001427000016270000162700001d2700001d270000212700002127000028270000282700003327000034270000442700004427000047270000472700004c2700004c2700004e2700004e270000532700005527000057270000572700006327000063270000642700006427000065270000672700009527000097270000a1270000a1270000b0270000b0270000bf270000bf2700003429000035290000052b0000072b00001b2b00001c2b0000502b0000502b0000552b0000552b000030300000303000003d3000003d3000009732000097320000993200009932000000f0010003f0010004f0010004f0010005f00100cef00100cff00100cff00100d0f00100fff001000df101000ff101002ff101002ff101006cf101006ff1010070f1010071f101007ef101007ff101008ef101008ef1010091f101009af10100adf10100e5f1010001f2010002f2010003f201000ff201001af201001af201002ff201002ff2010032f201003af201003cf201003ff2010049f201004ff2010050f2010051f2010052f20100fff2010000f301000cf301000df301000ef301000ff301000ff3010010f3010010f3010011f3010011f3010012f3010012f3010013f3010015f3010016f3010018f3010019f3010019f301001af301001af301001bf301001bf301001cf301001cf301001df301001ef301001ff3010020f3010021f3010021f3010022f3010023f3010024f301002cf301002df301002ff3010030f3010031f3010032f3010033f3010034f3010035f3010036f3010036f3010037f301004af301004bf301004bf301004cf301004ff3010050f3010050f3010051f301007bf301007cf301007cf301007df301007df301007ef301007ff3010080f3010093f3010094f3010095f3010096f3010097f3010098f3010098f3010099f301009bf301009cf301009df301009ef301009ff30100a0f30100c4f30100c5f30100c5f30100c6f30100c6f30100c7f30100c7f30100c8f30100c8f30100c9f30100c9f30100caf30100caf30100cbf30100cef30100cff30100d3f30100d4f30100dff30100e0f30100e3f30100e4f30100e4f30100e5f30100f0f30100f1f30100f2f30100f3f30100f3f30100f4f30100f4f30100f5f30100f5f30100f6f30100f6f30100f7f30100f7f30100f8f30100faf3010000f4010007f4010008f4010008f4010009f401000bf401000cf401000ef401000ff4010010f4010011f4010012f4010013f4010013f4010014f4010014f4010015f4010015f4010016f4010016f4010017f4010029f401002af401002af401002bf401003ef401003ff401003ff4010040f4010040f4010041f4010041f4010042f4010064f4010065f4010065f4010066f401006bf401006cf401006df401006ef40100acf40100adf40100adf40100aef40100b5f40100b6f40100b7f40100b8f40100ebf40100ecf40100edf40100eef40100eef40100eff40100eff40100f0f40100f4f40100f5f40100f5f40100f6f40100f7f40100f8f40100f8f40100f9f40100fcf40100fdf40100fdf40100fef40100fef40100fff4010002f5010003f5010003f5010004f5010007f5010008f5010008f5010009f5010009f501000af5010014f5010015f5010015f5010016f501002bf501002cf501002df501002ef501003df5010046f5010048f5010049f501004af501004bf501004ef501004ff501004ff5010050f501005bf501005cf5010067f5010068f501006ef501006ff5010070f5010071f5010072f5010073f5010079f501007af501007af501007bf5010086f5010087f5010087f5010088f5010089f501008af501008df501008ef501008ff5010090f5010090f5010091f5010094f5010095f5010096f5010097f50100a3f50100a4f50100a4f50100a5f50100a5f50100a6f50100a7f50100a8f50100a8f50100a9f50100b0f50100b1f50100b2f50100b3f50100bbf50100bcf50100bcf50100bdf50100c1f50100c2f50100c4f50100c5f50100d0f50100d1f50100d3f50100d4f50100dbf50100dcf50100def50100dff50100e0f50100e1f50100e1f50100e2f50100e2f50100e3f50100e3f50100e4f50100e7f50100e8f50100e8f50100e9f50100eef50100eff50100eff50100f0f50100f2f50100f3f50100f3f50100f4f50100f9f50100faf50100faf50100fbf50100fff5010000f6010000f6010001f6010006f6010007f6010008f6010009f601000df601000ef601000ef601000ff601000ff6010010f6010010f6010011f6010011f6010012f6010014f6010015f6010015f6010016f6010016f6010017f6010017f6010018f6010018f6010019f6010019f601001af601001af601001bf601001bf601001cf601001ef601001ff601001ff6010020f6010025f6010026f6010027f6010028f601002bf601002cf601002cf601002df601002df601002ef601002ff6010030f6010033f6010034f6010034f6010035f6010035f6010036f6010036f6010037f6010040f6010041f6010044f6010045f601004ff6010080f6010080f6010081f6010082f6010083f6010085f6010086f6010086f6010087f6010087f6010088f6010088f6010089f6010089f601008af601008bf601008cf601008cf601008df601008df601008ef601008ef601008ff601008ff6010090f6010090f6010091f6010093f6010094f6010094f6010095f6010095f6010096f6010096f6010097f6010097f6010098f6010098f6010099f601009af601009bf60100a1f60100a2f60100a2f60100a3f60100a3f60100a4f60100a5f60100a6f60100a6f60100a7f60100adf60100aef60100b1f60100b2f60100b2f60100b3f60100b5f60100b6f60100b6f60100b7f60100b8f60100b9f60100bef60100bff60100bff60100c0f60100c0f60100c1f60100c5f60100c6f60100caf60100cbf60100cbf60100ccf60100ccf60100cdf60100cff60100d0f60100d0f60100d1f60100d2f60100d3f60100d4f60100d5f60100d5f60100d6f60100d7f60100d8f60100dff60100e0f60100e5f60100e6f60100e8f60100e9f60100e9f60100eaf60100eaf60100ebf60100ecf60100edf60100eff60100f0f60100f0f60100f1f60100f2f60100f3f60100f3f60100f4f60100f6f60100f7f60100f8f60100f9f60100f9f60100faf60100faf60100fbf60100fcf60100fdf60100fff6010074f701007ff70100d5f70100dff70100e0f70100ebf70100ecf70100fff701000cf801000ff8010048f801004ff801005af801005ff8010088f801008ff80100aef80100fff801000cf901000cf901000df901000ff9010010f9010018f9010019f901001ef901001ff901001ff9010020f9010027f9010028f901002ff9010030f9010030f9010031f9010032f9010033f901003af901003cf901003ef901003ff901003ff9010040f9010045f9010047f901004bf901004cf901004cf901004df901004ff9010050f901005ef901005ff901006bf901006cf9010070f9010071f9010071f9010072f9010072f9010073f9010076f9010077f9010078f9010079f9010079f901007af901007af901007bf901007bf901007cf901007ff9010080f9010084f9010085f9010091f9010092f9010097f9010098f90100a2f90100a3f90100a4f90100a5f90100aaf90100abf90100adf90100aef90100aff90100b0f90100b9f90100baf90100bff90100c0f90100c0f90100c1f90100c2f90100c3f90100caf90100cbf90100cbf90100ccf90100ccf90100cdf90100cff90100d0f90100e6f90100e7f90100fff9010000fa01006ffa010070fa010073fa010074fa010074fa010075fa010077fa010078fa01007afa01007bfa01007ffa010080fa010082fa010083fa010086fa010087fa01008ffa010090fa010095fa010096fa0100a8fa0100a9fa0100affa0100b0fa0100b6fa0100b7fa0100bffa0100c0fa0100c2fa0100c3fa0100cffa0100d0fa0100d6fa0100d7fa0100fffa010000fc0100fdff0100", 7856, 1};
static const string _str_260 = {"katomic.load: unsupported operand width", 39, 1};
static const string _str_261 = {"interface method IError.msg not implemented", 43, 1};
static const string _str_262 = {"interface method IError.code not implemented", 44, 1};

string IError__msg(IError* i) {
	if (i->_typ == 1938660593) return Error__msg(*(Error*)i->_object);
	if (i->_typ == 71273906) return MessageError__msg(*(MessageError*)i->_object);
	if (i->_typ == 2065246729) return Error__msg(((None__*)i->_object)->Error);
	v_panic(_str_261);
	return (string){0};
}
i64 IError__code(IError* i) {
	if (i->_typ == 1938660593) return Error__code(*(Error*)i->_object);
	if (i->_typ == 71273906) return MessageError__code(*(MessageError*)i->_object);
	if (i->_typ == 2065246729) return Error__code(((None__*)i->_object)->Error);
	v_panic(_str_262);
	return (i64){0};
}

#define bits__de_bruijn32 (((u32)(0x077CB531)))
const u8 bits__de_bruijn32tab[32] = {((u8)(0)), 1, 28, 2, 29, 14, 24, 3, 30, 22, 20, 15, 25, 17, 4, 8, 31, 27, 13, 23, 21, 19, 16, 7, 26, 12, 18, 6, 11, 5, 10, 9};
#define bits__de_bruijn64 (((u64)(0x03f79d71b4ca8b09)))
const u8 bits__de_bruijn64tab[64] = {((u8)(0)), 1, 56, 2, 57, 49, 28, 3, 61, 58, 42, 50, 38, 29, 17, 4, 62, 47, 59, 36, 45, 43, 51, 22, 53, 39, 33, 30, 24, 18, 12, 5, 63, 55, 48, 27, 60, 41, 37, 16, 46, 35, 44, 21, 52, 32, 23, 11, 54, 26, 40, 15, 34, 20, 31, 10, 25, 14, 19, 9, 13, 8, 7, 6};
#define bits__m0 (((u64)(0x5555555555555555)))
#define bits__m1 (((u64)(0x3333333333333333)))
#define bits__m2 (((u64)(0x0f0f0f0f0f0f0f0f)))
#define bits__m3 (((u64)(0x00ff00ff00ff00ff)))
#define bits__m4 (((u64)(0x0000ffff0000ffff)))
static const u8 bits__n8 = ((u8)(8));
#define bits__n16 (((u16)(16)))
#define bits__n32 (((u32)(32)))
#define bits__n64 (((u64)(64)))
#define bits__two32 (((u64)(0x100000000)))
#define bits__mask32 ((((u64)(0x100000000))) - (1))
string bits__overflow_error = (string){"Overflow Error", 14, 1};
string bits__divide_error = (string){"Divide by Zero Error", 20, 1};
const u8 bits__ntz_8_tab[256] = {((u8)(0x08)), 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x06, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x07, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x06, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00};
const u8 bits__pop_8_tab[256] = {((u8)(0x00)), 0x01, 0x01, 0x02, 0x01, 0x02, 0x02, 0x03, 0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07, 0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07, 0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07, 0x05, 0x06, 0x06, 0x07, 0x06, 0x07, 0x07, 0x08};
const u8 bits__rev_8_tab[256] = {((u8)(0x00)), 0x80, 0x40, 0xc0, 0x20, 0xa0, 0x60, 0xe0, 0x10, 0x90, 0x50, 0xd0, 0x30, 0xb0, 0x70, 0xf0, 0x08, 0x88, 0x48, 0xc8, 0x28, 0xa8, 0x68, 0xe8, 0x18, 0x98, 0x58, 0xd8, 0x38, 0xb8, 0x78, 0xf8, 0x04, 0x84, 0x44, 0xc4, 0x24, 0xa4, 0x64, 0xe4, 0x14, 0x94, 0x54, 0xd4, 0x34, 0xb4, 0x74, 0xf4, 0x0c, 0x8c, 0x4c, 0xcc, 0x2c, 0xac, 0x6c, 0xec, 0x1c, 0x9c, 0x5c, 0xdc, 0x3c, 0xbc, 0x7c, 0xfc, 0x02, 0x82, 0x42, 0xc2, 0x22, 0xa2, 0x62, 0xe2, 0x12, 0x92, 0x52, 0xd2, 0x32, 0xb2, 0x72, 0xf2, 0x0a, 0x8a, 0x4a, 0xca, 0x2a, 0xaa, 0x6a, 0xea, 0x1a, 0x9a, 0x5a, 0xda, 0x3a, 0xba, 0x7a, 0xfa, 0x06, 0x86, 0x46, 0xc6, 0x26, 0xa6, 0x66, 0xe6, 0x16, 0x96, 0x56, 0xd6, 0x36, 0xb6, 0x76, 0xf6, 0x0e, 0x8e, 0x4e, 0xce, 0x2e, 0xae, 0x6e, 0xee, 0x1e, 0x9e, 0x5e, 0xde, 0x3e, 0xbe, 0x7e, 0xfe, 0x01, 0x81, 0x41, 0xc1, 0x21, 0xa1, 0x61, 0xe1, 0x11, 0x91, 0x51, 0xd1, 0x31, 0xb1, 0x71, 0xf1, 0x09, 0x89, 0x49, 0xc9, 0x29, 0xa9, 0x69, 0xe9, 0x19, 0x99, 0x59, 0xd9, 0x39, 0xb9, 0x79, 0xf9, 0x05, 0x85, 0x45, 0xc5, 0x25, 0xa5, 0x65, 0xe5, 0x15, 0x95, 0x55, 0xd5, 0x35, 0xb5, 0x75, 0xf5, 0x0d, 0x8d, 0x4d, 0xcd, 0x2d, 0xad, 0x6d, 0xed, 0x1d, 0x9d, 0x5d, 0xdd, 0x3d, 0xbd, 0x7d, 0xfd, 0x03, 0x83, 0x43, 0xc3, 0x23, 0xa3, 0x63, 0xe3, 0x13, 0x93, 0x53, 0xd3, 0x33, 0xb3, 0x73, 0xf3, 0x0b, 0x8b, 0x4b, 0xcb, 0x2b, 0xab, 0x6b, 0xeb, 0x1b, 0x9b, 0x5b, 0xdb, 0x3b, 0xbb, 0x7b, 0xfb, 0x07, 0x87, 0x47, 0xc7, 0x27, 0xa7, 0x67, 0xe7, 0x17, 0x97, 0x57, 0xd7, 0x37, 0xb7, 0x77, 0xf7, 0x0f, 0x8f, 0x4f, 0xcf, 0x2f, 0xaf, 0x6f, 0xef, 0x1f, 0x9f, 0x5f, 0xdf, 0x3f, 0xbf, 0x7f, 0xff};
const u8 bits__len_8_tab[256] = {((u8)(0x00)), 0x01, 0x02, 0x02, 0x03, 0x03, 0x03, 0x03, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08};
#define strconv__int_size (32)
#define strconv__i64_min_int32 ((((i64)(-(2147483647)))) - (1))
#define strconv__i64_max_int32 ((((i64)(2147483646))) + (1))
const u64 strconv__ten_pow_table_64[20] = {((u64)(1)), ((u64)(10)), ((u64)(100)), ((u64)(1000)), ((u64)(10000)), ((u64)(100000)), ((u64)(1000000)), ((u64)(10000000)), ((u64)(100000000)), ((u64)(1000000000)), ((u64)(10000000000)), ((u64)(100000000000)), ((u64)(1000000000000)), ((u64)(10000000000000)), ((u64)(100000000000000)), ((u64)(1000000000000000)), ((u64)(10000000000000000)), ((u64)(100000000000000000)), ((u64)(1000000000000000000)), ((u64)(10000000000000000000))};
#define strconv__mantbits64 (((u32)(52)))
#define strconv__expbits64 (((u32)(11)))
#define strconv__bias64 (1023)
#define strconv__maxexp64 (((u64)(2047)))
const double strconv__dec_round[36] = {((double)(0.5)), 0.05, 0.005, 0.0005, 0.00005, 0.000005, 0.0000005, 0.00000005, 0.000000005, 0.0000000005, 0.00000000005, 0.000000000005, 0.0000000000005, 0.00000000000005, 0.000000000000005, 0.0000000000000005, 0.00000000000000005, 0.000000000000000005, 0.0000000000000000005, 0.00000000000000000005, 0.000000000000000000005, 0.0000000000000000000005, 0.00000000000000000000005, 0.000000000000000000000005, 0.0000000000000000000000005, 0.00000000000000000000000005, 0.000000000000000000000000005, 0.0000000000000000000000000005, 0.00000000000000000000000000005, 0.000000000000000000000000000005, 0.0000000000000000000000000000005, 0.00000000000000000000000000000005, 0.000000000000000000000000000000005, 0.0000000000000000000000000000000005, 0.00000000000000000000000000000000005, 0.000000000000000000000000000000000005};
#define strconv__pow5_num_bits_32 (61)
#define strconv__pow5_inv_num_bits_32 (59)
#define strconv__pow5_num_bits_64 (121)
#define strconv__pow5_inv_num_bits_64 (122)
const u64 strconv__powers_of_10[18] = {((u64)(1e0)), ((u64)(1e1)), ((u64)(1e2)), ((u64)(1e3)), ((u64)(1e4)), ((u64)(1e5)), ((u64)(1e6)), ((u64)(1e7)), ((u64)(1e8)), ((u64)(1e9)), ((u64)(1e10)), ((u64)(1e11)), ((u64)(1e12)), ((u64)(1e13)), ((u64)(1e14)), ((u64)(1e15)), ((u64)(1e16)), ((u64)(1e17))};
const u64 strconv__pow5_split_32[47] = {((u64)(1152921504606846976)), ((u64)(1441151880758558720)), ((u64)(1801439850948198400)), ((u64)(2251799813685248000)), ((u64)(1407374883553280000)), ((u64)(1759218604441600000)), ((u64)(2199023255552000000)), ((u64)(1374389534720000000)), ((u64)(1717986918400000000)), ((u64)(2147483648000000000)), ((u64)(1342177280000000000)), ((u64)(1677721600000000000)), ((u64)(2097152000000000000)), ((u64)(1310720000000000000)), ((u64)(1638400000000000000)), ((u64)(2048000000000000000)), ((u64)(1280000000000000000)), ((u64)(1600000000000000000)), ((u64)(2000000000000000000)), ((u64)(1250000000000000000)), ((u64)(1562500000000000000)), ((u64)(1953125000000000000)), ((u64)(1220703125000000000)), ((u64)(1525878906250000000)), ((u64)(1907348632812500000)), ((u64)(1192092895507812500)), ((u64)(1490116119384765625)), ((u64)(1862645149230957031)), ((u64)(1164153218269348144)), ((u64)(1455191522836685180)), ((u64)(1818989403545856475)), ((u64)(2273736754432320594)), ((u64)(1421085471520200371)), ((u64)(1776356839400250464)), ((u64)(2220446049250313080)), ((u64)(1387778780781445675)), ((u64)(1734723475976807094)), ((u64)(2168404344971008868)), ((u64)(1355252715606880542)), ((u64)(1694065894508600678)), ((u64)(2117582368135750847)), ((u64)(1323488980084844279)), ((u64)(1654361225106055349)), ((u64)(2067951531382569187)), ((u64)(1292469707114105741)), ((u64)(1615587133892632177)), ((u64)(2019483917365790221))};
const u64 strconv__pow5_inv_split_32[31] = {((u64)(576460752303423489)), ((u64)(461168601842738791)), ((u64)(368934881474191033)), ((u64)(295147905179352826)), ((u64)(472236648286964522)), ((u64)(377789318629571618)), ((u64)(302231454903657294)), ((u64)(483570327845851670)), ((u64)(386856262276681336)), ((u64)(309485009821345069)), ((u64)(495176015714152110)), ((u64)(396140812571321688)), ((u64)(316912650057057351)), ((u64)(507060240091291761)), ((u64)(405648192073033409)), ((u64)(324518553658426727)), ((u64)(519229685853482763)), ((u64)(415383748682786211)), ((u64)(332306998946228969)), ((u64)(531691198313966350)), ((u64)(425352958651173080)), ((u64)(340282366920938464)), ((u64)(544451787073501542)), ((u64)(435561429658801234)), ((u64)(348449143727040987)), ((u64)(557518629963265579)), ((u64)(446014903970612463)), ((u64)(356811923176489971)), ((u64)(570899077082383953)), ((u64)(456719261665907162)), ((u64)(365375409332725730))};
const u64 strconv__pow5_split_64_x[652] = {((u64)(0x0000000000000000)), ((u64)(0x0100000000000000)), ((u64)(0x0000000000000000)), ((u64)(0x0140000000000000)), ((u64)(0x0000000000000000)), ((u64)(0x0190000000000000)), ((u64)(0x0000000000000000)), ((u64)(0x01f4000000000000)), ((u64)(0x0000000000000000)), ((u64)(0x0138800000000000)), ((u64)(0x0000000000000000)), ((u64)(0x0186a00000000000)), ((u64)(0x0000000000000000)), ((u64)(0x01e8480000000000)), ((u64)(0x0000000000000000)), ((u64)(0x01312d0000000000)), ((u64)(0x0000000000000000)), ((u64)(0x017d784000000000)), ((u64)(0x0000000000000000)), ((u64)(0x01dcd65000000000)), ((u64)(0x0000000000000000)), ((u64)(0x012a05f200000000)), ((u64)(0x0000000000000000)), ((u64)(0x0174876e80000000)), ((u64)(0x0000000000000000)), ((u64)(0x01d1a94a20000000)), ((u64)(0x0000000000000000)), ((u64)(0x012309ce54000000)), ((u64)(0x0000000000000000)), ((u64)(0x016bcc41e9000000)), ((u64)(0x0000000000000000)), ((u64)(0x01c6bf5263400000)), ((u64)(0x0000000000000000)), ((u64)(0x011c37937e080000)), ((u64)(0x0000000000000000)), ((u64)(0x016345785d8a0000)), ((u64)(0x0000000000000000)), ((u64)(0x01bc16d674ec8000)), ((u64)(0x0000000000000000)), ((u64)(0x01158e460913d000)), ((u64)(0x0000000000000000)), ((u64)(0x015af1d78b58c400)), ((u64)(0x0000000000000000)), ((u64)(0x01b1ae4d6e2ef500)), ((u64)(0x0000000000000000)), ((u64)(0x010f0cf064dd5920)), ((u64)(0x0000000000000000)), ((u64)(0x0152d02c7e14af68)), ((u64)(0x0000000000000000)), ((u64)(0x01a784379d99db42)), ((u64)(0x4000000000000000)), ((u64)(0x0108b2a2c2802909)), ((u64)(0x9000000000000000)), ((u64)(0x014adf4b7320334b)), ((u64)(0x7400000000000000)), ((u64)(0x019d971e4fe8401e)), ((u64)(0x0880000000000000)), ((u64)(0x01027e72f1f12813)), ((u64)(0xcaa0000000000000)), ((u64)(0x01431e0fae6d7217)), ((u64)(0xbd48000000000000)), ((u64)(0x0193e5939a08ce9d)), ((u64)(0x2c9a000000000000)), ((u64)(0x01f8def8808b0245)), ((u64)(0x3be0400000000000)), ((u64)(0x013b8b5b5056e16b)), ((u64)(0x0ad8500000000000)), ((u64)(0x018a6e32246c99c6)), ((u64)(0x8d8e640000000000)), ((u64)(0x01ed09bead87c037)), ((u64)(0xb878fe8000000000)), ((u64)(0x013426172c74d822)), ((u64)(0x66973e2000000000)), ((u64)(0x01812f9cf7920e2b)), ((u64)(0x403d0da800000000)), ((u64)(0x01e17b84357691b6)), ((u64)(0xe826288900000000)), ((u64)(0x012ced32a16a1b11)), ((u64)(0x622fb2ab40000000)), ((u64)(0x0178287f49c4a1d6)), ((u64)(0xfabb9f5610000000)), ((u64)(0x01d6329f1c35ca4b)), ((u64)(0x7cb54395ca000000)), ((u64)(0x0125dfa371a19e6f)), ((u64)(0x5be2947b3c800000)), ((u64)(0x016f578c4e0a060b)), ((u64)(0x32db399a0ba00000)), ((u64)(0x01cb2d6f618c878e)), ((u64)(0xdfc9040047440000)), ((u64)(0x011efc659cf7d4b8)), ((u64)(0x17bb450059150000)), ((u64)(0x0166bb7f0435c9e7)), ((u64)(0xddaa16406f5a4000)), ((u64)(0x01c06a5ec5433c60)), ((u64)(0x8a8a4de845986800)), ((u64)(0x0118427b3b4a05bc)), ((u64)(0xad2ce16256fe8200)), ((u64)(0x015e531a0a1c872b)), ((u64)(0x987819baecbe2280)), ((u64)(0x01b5e7e08ca3a8f6)), ((u64)(0x1f4b1014d3f6d590)), ((u64)(0x0111b0ec57e6499a)), ((u64)(0xa71dd41a08f48af4)), ((u64)(0x01561d276ddfdc00)), ((u64)(0xd0e549208b31adb1)), ((u64)(0x01aba4714957d300)), ((u64)(0x828f4db456ff0c8e)), ((u64)(0x010b46c6cdd6e3e0)), ((u64)(0xa33321216cbecfb2)), ((u64)(0x014e1878814c9cd8)), ((u64)(0xcbffe969c7ee839e)), ((u64)(0x01a19e96a19fc40e)), ((u64)(0x3f7ff1e21cf51243)), ((u64)(0x0105031e2503da89)), ((u64)(0x8f5fee5aa43256d4)), ((u64)(0x014643e5ae44d12b)), ((u64)(0x7337e9f14d3eec89)), ((u64)(0x0197d4df19d60576)), ((u64)(0x1005e46da08ea7ab)), ((u64)(0x01fdca16e04b86d4)), ((u64)(0x8a03aec4845928cb)), ((u64)(0x013e9e4e4c2f3444)), ((u64)(0xac849a75a56f72fd)), ((u64)(0x018e45e1df3b0155)), ((u64)(0x17a5c1130ecb4fbd)), ((u64)(0x01f1d75a5709c1ab)), ((u64)(0xeec798abe93f11d6)), ((u64)(0x013726987666190a)), ((u64)(0xaa797ed6e38ed64b)), ((u64)(0x0184f03e93ff9f4d)), ((u64)(0x1517de8c9c728bde)), ((u64)(0x01e62c4e38ff8721)), ((u64)(0xad2eeb17e1c7976b)), ((u64)(0x012fdbb0e39fb474)), ((u64)(0xd87aa5ddda397d46)), ((u64)(0x017bd29d1c87a191)), ((u64)(0x4e994f5550c7dc97)), ((u64)(0x01dac74463a989f6)), ((u64)(0xf11fd195527ce9de)), ((u64)(0x0128bc8abe49f639)), ((u64)(0x6d67c5faa71c2456)), ((u64)(0x0172ebad6ddc73c8)), ((u64)(0x88c1b77950e32d6c)), ((u64)(0x01cfa698c95390ba)), ((u64)(0x957912abd28dfc63)), ((u64)(0x0121c81f7dd43a74)), ((u64)(0xbad75756c7317b7c)), ((u64)(0x016a3a275d494911)), ((u64)(0x298d2d2c78fdda5b)), ((u64)(0x01c4c8b1349b9b56)), ((u64)(0xd9f83c3bcb9ea879)), ((u64)(0x011afd6ec0e14115)), ((u64)(0x50764b4abe865297)), ((u64)(0x0161bcca7119915b)), ((u64)(0x2493de1d6e27e73d)), ((u64)(0x01ba2bfd0d5ff5b2)), ((u64)(0x56dc6ad264d8f086)), ((u64)(0x01145b7e285bf98f)), ((u64)(0x2c938586fe0f2ca8)), ((u64)(0x0159725db272f7f3)), ((u64)(0xf7b866e8bd92f7d2)), ((u64)(0x01afcef51f0fb5ef)), ((u64)(0xfad34051767bdae3)), ((u64)(0x010de1593369d1b5)), ((u64)(0x79881065d41ad19c)), ((u64)(0x015159af80444623)), ((u64)(0x57ea147f49218603)), ((u64)(0x01a5b01b605557ac)), ((u64)(0xb6f24ccf8db4f3c1)), ((u64)(0x01078e111c3556cb)), ((u64)(0xa4aee003712230b2)), ((u64)(0x014971956342ac7e)), ((u64)(0x4dda98044d6abcdf)), ((u64)(0x019bcdfabc13579e)), ((u64)(0xf0a89f02b062b60b)), ((u64)(0x010160bcb58c16c2)), ((u64)(0xacd2c6c35c7b638e)), ((u64)(0x0141b8ebe2ef1c73)), ((u64)(0x98077874339a3c71)), ((u64)(0x01922726dbaae390)), ((u64)(0xbe0956914080cb8e)), ((u64)(0x01f6b0f092959c74)), ((u64)(0xf6c5d61ac8507f38)), ((u64)(0x013a2e965b9d81c8)), ((u64)(0x34774ba17a649f07)), ((u64)(0x0188ba3bf284e23b)), ((u64)(0x01951e89d8fdc6c8)), ((u64)(0x01eae8caef261aca)), ((u64)(0x40fd3316279e9c3d)), ((u64)(0x0132d17ed577d0be)), ((u64)(0xd13c7fdbb186434c)), ((u64)(0x017f85de8ad5c4ed)), ((u64)(0x458b9fd29de7d420)), ((u64)(0x01df67562d8b3629)), ((u64)(0xcb7743e3a2b0e494)), ((u64)(0x012ba095dc7701d9)), ((u64)(0x3e5514dc8b5d1db9)), ((u64)(0x017688bb5394c250)), ((u64)(0x4dea5a13ae346527)), ((u64)(0x01d42aea2879f2e4)), ((u64)(0xb0b2784c4ce0bf38)), ((u64)(0x01249ad2594c37ce)), ((u64)(0x5cdf165f6018ef06)), ((u64)(0x016dc186ef9f45c2)), ((u64)(0xf416dbf7381f2ac8)), ((u64)(0x01c931e8ab871732)), ((u64)(0xd88e497a83137abd)), ((u64)(0x011dbf316b346e7f)), ((u64)(0xceb1dbd923d8596c)), ((u64)(0x01652efdc6018a1f)), ((u64)(0xc25e52cf6cce6fc7)), ((u64)(0x01be7abd3781eca7)), ((u64)(0xd97af3c1a40105dc)), ((u64)(0x01170cb642b133e8)), ((u64)(0x0fd9b0b20d014754)), ((u64)(0x015ccfe3d35d80e3)), ((u64)(0xd3d01cde90419929)), ((u64)(0x01b403dcc834e11b)), ((u64)(0x6462120b1a28ffb9)), ((u64)(0x01108269fd210cb1)), ((u64)(0xbd7a968de0b33fa8)), ((u64)(0x0154a3047c694fdd)), ((u64)(0x2cd93c3158e00f92)), ((u64)(0x01a9cbc59b83a3d5)), ((u64)(0x3c07c59ed78c09bb)), ((u64)(0x010a1f5b81324665)), ((u64)(0x8b09b7068d6f0c2a)), ((u64)(0x014ca732617ed7fe)), ((u64)(0x2dcc24c830cacf34)), ((u64)(0x019fd0fef9de8dfe)), ((u64)(0xdc9f96fd1e7ec180)), ((u64)(0x0103e29f5c2b18be)), ((u64)(0x93c77cbc661e71e1)), ((u64)(0x0144db473335deee)), ((u64)(0x38b95beb7fa60e59)), ((u64)(0x01961219000356aa)), ((u64)(0xc6e7b2e65f8f91ef)), ((u64)(0x01fb969f40042c54)), ((u64)(0xfc50cfcffbb9bb35)), ((u64)(0x013d3e2388029bb4)), ((u64)(0x3b6503c3faa82a03)), ((u64)(0x018c8dac6a0342a2)), ((u64)(0xca3e44b4f9523484)), ((u64)(0x01efb1178484134a)), ((u64)(0xbe66eaf11bd360d2)), ((u64)(0x0135ceaeb2d28c0e)), ((u64)(0x6e00a5ad62c83907)), ((u64)(0x0183425a5f872f12)), ((u64)(0x0980cf18bb7a4749)), ((u64)(0x01e412f0f768fad7)), ((u64)(0x65f0816f752c6c8d)), ((u64)(0x012e8bd69aa19cc6)), ((u64)(0xff6ca1cb527787b1)), ((u64)(0x017a2ecc414a03f7)), ((u64)(0xff47ca3e2715699d)), ((u64)(0x01d8ba7f519c84f5)), ((u64)(0xbf8cde66d86d6202)), ((u64)(0x0127748f9301d319)), ((u64)(0x2f7016008e88ba83)), ((u64)(0x017151b377c247e0)), ((u64)(0x3b4c1b80b22ae923)), ((u64)(0x01cda62055b2d9d8)), ((u64)(0x250f91306f5ad1b6)), ((u64)(0x012087d4358fc827)), ((u64)(0xee53757c8b318623)), ((u64)(0x0168a9c942f3ba30)), ((u64)(0x29e852dbadfde7ac)), ((u64)(0x01c2d43b93b0a8bd)), ((u64)(0x3a3133c94cbeb0cc)), ((u64)(0x0119c4a53c4e6976)), ((u64)(0xc8bd80bb9fee5cff)), ((u64)(0x016035ce8b6203d3)), ((u64)(0xbaece0ea87e9f43e)), ((u64)(0x01b843422e3a84c8)), ((u64)(0x74d40c9294f238a7)), ((u64)(0x01132a095ce492fd)), ((u64)(0xd2090fb73a2ec6d1)), ((u64)(0x0157f48bb41db7bc)), ((u64)(0x068b53a508ba7885)), ((u64)(0x01adf1aea12525ac)), ((u64)(0x8417144725748b53)), ((u64)(0x010cb70d24b7378b)), ((u64)(0x651cd958eed1ae28)), ((u64)(0x014fe4d06de5056e)), ((u64)(0xfe640faf2a8619b2)), ((u64)(0x01a3de04895e46c9)), ((u64)(0x3efe89cd7a93d00f)), ((u64)(0x01066ac2d5daec3e)), ((u64)(0xcebe2c40d938c413)), ((u64)(0x014805738b51a74d)), ((u64)(0x426db7510f86f518)), ((u64)(0x019a06d06e261121)), ((u64)(0xc9849292a9b4592f)), ((u64)(0x0100444244d7cab4)), ((u64)(0xfbe5b73754216f7a)), ((u64)(0x01405552d60dbd61)), ((u64)(0x7adf25052929cb59)), ((u64)(0x01906aa78b912cba)), ((u64)(0x1996ee4673743e2f)), ((u64)(0x01f485516e7577e9)), ((u64)(0xaffe54ec0828a6dd)), ((u64)(0x0138d352e5096af1)), ((u64)(0x1bfdea270a32d095)), ((u64)(0x018708279e4bc5ae)), ((u64)(0xa2fd64b0ccbf84ba)), ((u64)(0x01e8ca3185deb719)), ((u64)(0x05de5eee7ff7b2f4)), ((u64)(0x01317e5ef3ab3270)), ((u64)(0x0755f6aa1ff59fb1)), ((u64)(0x017dddf6b095ff0c)), ((u64)(0x092b7454a7f3079e)), ((u64)(0x01dd55745cbb7ecf)), ((u64)(0x65bb28b4e8f7e4c3)), ((u64)(0x012a5568b9f52f41)), ((u64)(0xbf29f2e22335ddf3)), ((u64)(0x0174eac2e8727b11)), ((u64)(0x2ef46f9aac035570)), ((u64)(0x01d22573a28f19d6)), ((u64)(0xdd58c5c0ab821566)), ((u64)(0x0123576845997025)), ((u64)(0x54aef730d6629ac0)), ((u64)(0x016c2d4256ffcc2f)), ((u64)(0x29dab4fd0bfb4170)), ((u64)(0x01c73892ecbfbf3b)), ((u64)(0xfa28b11e277d08e6)), ((u64)(0x011c835bd3f7d784)), ((u64)(0x38b2dd65b15c4b1f)), ((u64)(0x0163a432c8f5cd66)), ((u64)(0xc6df94bf1db35de7)), ((u64)(0x01bc8d3f7b3340bf)), ((u64)(0xdc4bbcf772901ab0)), ((u64)(0x0115d847ad000877)), ((u64)(0xd35eac354f34215c)), ((u64)(0x015b4e5998400a95)), ((u64)(0x48365742a30129b4)), ((u64)(0x01b221effe500d3b)), ((u64)(0x0d21f689a5e0ba10)), ((u64)(0x010f5535fef20845)), ((u64)(0x506a742c0f58e894)), ((u64)(0x01532a837eae8a56)), ((u64)(0xe4851137132f22b9)), ((u64)(0x01a7f5245e5a2ceb)), ((u64)(0x6ed32ac26bfd75b4)), ((u64)(0x0108f936baf85c13)), ((u64)(0x4a87f57306fcd321)), ((u64)(0x014b378469b67318)), ((u64)(0x5d29f2cfc8bc07e9)), ((u64)(0x019e056584240fde)), ((u64)(0xfa3a37c1dd7584f1)), ((u64)(0x0102c35f729689ea)), ((u64)(0xb8c8c5b254d2e62e)), ((u64)(0x014374374f3c2c65)), ((u64)(0x26faf71eea079fb9)), ((u64)(0x01945145230b377f)), ((u64)(0xf0b9b4e6a48987a8)), ((u64)(0x01f965966bce055e)), ((u64)(0x5674111026d5f4c9)), ((u64)(0x013bdf7e0360c35b)), ((u64)(0x2c111554308b71fb)), ((u64)(0x018ad75d8438f432)), ((u64)(0xb7155aa93cae4e7a)), ((u64)(0x01ed8d34e547313e)), ((u64)(0x326d58a9c5ecf10c)), ((u64)(0x013478410f4c7ec7)), ((u64)(0xff08aed437682d4f)), ((u64)(0x01819651531f9e78)), ((u64)(0x3ecada89454238a3)), ((u64)(0x01e1fbe5a7e78617)), ((u64)(0x873ec895cb496366)), ((u64)(0x012d3d6f88f0b3ce)), ((u64)(0x290e7abb3e1bbc3f)), ((u64)(0x01788ccb6b2ce0c2)), ((u64)(0xb352196a0da2ab4f)), ((u64)(0x01d6affe45f818f2)), ((u64)(0xb0134fe24885ab11)), ((u64)(0x01262dfeebbb0f97)), ((u64)(0x9c1823dadaa715d6)), ((u64)(0x016fb97ea6a9d37d)), ((u64)(0x031e2cd19150db4b)), ((u64)(0x01cba7de5054485d)), ((u64)(0x21f2dc02fad2890f)), ((u64)(0x011f48eaf234ad3a)), ((u64)(0xaa6f9303b9872b53)), ((u64)(0x01671b25aec1d888)), ((u64)(0xd50b77c4a7e8f628)), ((u64)(0x01c0e1ef1a724eaa)), ((u64)(0xc5272adae8f199d9)), ((u64)(0x01188d357087712a)), ((u64)(0x7670f591a32e004f)), ((u64)(0x015eb082cca94d75)), ((u64)(0xd40d32f60bf98063)), ((u64)(0x01b65ca37fd3a0d2)), ((u64)(0xc4883fd9c77bf03e)), ((u64)(0x0111f9e62fe44483)), ((u64)(0xb5aa4fd0395aec4d)), ((u64)(0x0156785fbbdd55a4)), ((u64)(0xe314e3c447b1a760)), ((u64)(0x01ac1677aad4ab0d)), ((u64)(0xaded0e5aaccf089c)), ((u64)(0x010b8e0acac4eae8)), ((u64)(0xd96851f15802cac3)), ((u64)(0x014e718d7d7625a2)), ((u64)(0x8fc2666dae037d74)), ((u64)(0x01a20df0dcd3af0b)), ((u64)(0x39d980048cc22e68)), ((u64)(0x010548b68a044d67)), ((u64)(0x084fe005aff2ba03)), ((u64)(0x01469ae42c8560c1)), ((u64)(0x4a63d8071bef6883)), ((u64)(0x0198419d37a6b8f1)), ((u64)(0x9cfcce08e2eb42a4)), ((u64)(0x01fe52048590672d)), ((u64)(0x821e00c58dd309a7)), ((u64)(0x013ef342d37a407c)), ((u64)(0xa2a580f6f147cc10)), ((u64)(0x018eb0138858d09b)), ((u64)(0x8b4ee134ad99bf15)), ((u64)(0x01f25c186a6f04c2)), ((u64)(0x97114cc0ec80176d)), ((u64)(0x0137798f428562f9)), ((u64)(0xfcd59ff127a01d48)), ((u64)(0x018557f31326bbb7)), ((u64)(0xfc0b07ed7188249a)), ((u64)(0x01e6adefd7f06aa5)), ((u64)(0xbd86e4f466f516e0)), ((u64)(0x01302cb5e6f642a7)), ((u64)(0xace89e3180b25c98)), ((u64)(0x017c37e360b3d351)), ((u64)(0x1822c5bde0def3be)), ((u64)(0x01db45dc38e0c826)), ((u64)(0xcf15bb96ac8b5857)), ((u64)(0x01290ba9a38c7d17)), ((u64)(0xc2db2a7c57ae2e6d)), ((u64)(0x01734e940c6f9c5d)), ((u64)(0x3391f51b6d99ba08)), ((u64)(0x01d022390f8b8375)), ((u64)(0x403b393124801445)), ((u64)(0x01221563a9b73229)), ((u64)(0x904a077d6da01956)), ((u64)(0x016a9abc9424feb3)), ((u64)(0x745c895cc9081fac)), ((u64)(0x01c5416bb92e3e60)), ((u64)(0x48b9d5d9fda513cb)), ((u64)(0x011b48e353bce6fc)), ((u64)(0x5ae84b507d0e58be)), ((u64)(0x01621b1c28ac20bb)), ((u64)(0x31a25e249c51eeee)), ((u64)(0x01baa1e332d728ea)), ((u64)(0x5f057ad6e1b33554)), ((u64)(0x0114a52dffc67992)), ((u64)(0xf6c6d98c9a2002aa)), ((u64)(0x0159ce797fb817f6)), ((u64)(0xb4788fefc0a80354)), ((u64)(0x01b04217dfa61df4)), ((u64)(0xf0cb59f5d8690214)), ((u64)(0x010e294eebc7d2b8)), ((u64)(0x2cfe30734e83429a)), ((u64)(0x0151b3a2a6b9c767)), ((u64)(0xf83dbc9022241340)), ((u64)(0x01a6208b50683940)), ((u64)(0x9b2695da15568c08)), ((u64)(0x0107d457124123c8)), ((u64)(0xc1f03b509aac2f0a)), ((u64)(0x0149c96cd6d16cba)), ((u64)(0x726c4a24c1573acd)), ((u64)(0x019c3bc80c85c7e9)), ((u64)(0xe783ae56f8d684c0)), ((u64)(0x0101a55d07d39cf1)), ((u64)(0x616499ecb70c25f0)), ((u64)(0x01420eb449c8842e)), ((u64)(0xf9bdc067e4cf2f6c)), ((u64)(0x019292615c3aa539)), ((u64)(0x782d3081de02fb47)), ((u64)(0x01f736f9b3494e88)), ((u64)(0x4b1c3e512ac1dd0c)), ((u64)(0x013a825c100dd115)), ((u64)(0x9de34de57572544f)), ((u64)(0x018922f31411455a)), ((u64)(0x455c215ed2cee963)), ((u64)(0x01eb6bafd91596b1)), ((u64)(0xcb5994db43c151de)), ((u64)(0x0133234de7ad7e2e)), ((u64)(0x7e2ffa1214b1a655)), ((u64)(0x017fec216198ddba)), ((u64)(0x1dbbf89699de0feb)), ((u64)(0x01dfe729b9ff1529)), ((u64)(0xb2957b5e202ac9f3)), ((u64)(0x012bf07a143f6d39)), ((u64)(0x1f3ada35a8357c6f)), ((u64)(0x0176ec98994f4888)), ((u64)(0x270990c31242db8b)), ((u64)(0x01d4a7bebfa31aaa)), ((u64)(0x5865fa79eb69c937)), ((u64)(0x0124e8d737c5f0aa)), ((u64)(0xee7f791866443b85)), ((u64)(0x016e230d05b76cd4)), ((u64)(0x2a1f575e7fd54a66)), ((u64)(0x01c9abd04725480a)), ((u64)(0x5a53969b0fe54e80)), ((u64)(0x011e0b622c774d06)), ((u64)(0xf0e87c41d3dea220)), ((u64)(0x01658e3ab7952047)), ((u64)(0xed229b5248d64aa8)), ((u64)(0x01bef1c9657a6859)), ((u64)(0x3435a1136d85eea9)), ((u64)(0x0117571ddf6c8138)), ((u64)(0x4143095848e76a53)), ((u64)(0x015d2ce55747a186)), ((u64)(0xd193cbae5b2144e8)), ((u64)(0x01b4781ead1989e7)), ((u64)(0xe2fc5f4cf8f4cb11)), ((u64)(0x0110cb132c2ff630)), ((u64)(0x1bbb77203731fdd5)), ((u64)(0x0154fdd7f73bf3bd)), ((u64)(0x62aa54e844fe7d4a)), ((u64)(0x01aa3d4df50af0ac)), ((u64)(0xbdaa75112b1f0e4e)), ((u64)(0x010a6650b926d66b)), ((u64)(0xad15125575e6d1e2)), ((u64)(0x014cffe4e7708c06)), ((u64)(0x585a56ead360865b)), ((u64)(0x01a03fde214caf08)), ((u64)(0x37387652c41c53f8)), ((u64)(0x010427ead4cfed65)), ((u64)(0x850693e7752368f7)), ((u64)(0x014531e58a03e8be)), ((u64)(0x264838e1526c4334)), ((u64)(0x01967e5eec84e2ee)), ((u64)(0xafda4719a7075402)), ((u64)(0x01fc1df6a7a61ba9)), ((u64)(0x0de86c7008649481)), ((u64)(0x013d92ba28c7d14a)), ((u64)(0x9162878c0a7db9a1)), ((u64)(0x018cf768b2f9c59c)), ((u64)(0xb5bb296f0d1d280a)), ((u64)(0x01f03542dfb83703)), ((u64)(0x5194f9e568323906)), ((u64)(0x01362149cbd32262)), ((u64)(0xe5fa385ec23ec747)), ((u64)(0x0183a99c3ec7eafa)), ((u64)(0x9f78c67672ce7919)), ((u64)(0x01e494034e79e5b9)), ((u64)(0x03ab7c0a07c10bb0)), ((u64)(0x012edc82110c2f94)), ((u64)(0x04965b0c89b14e9c)), ((u64)(0x017a93a2954f3b79)), ((u64)(0x45bbf1cfac1da243)), ((u64)(0x01d9388b3aa30a57)), ((u64)(0x8b957721cb92856a)), ((u64)(0x0127c35704a5e676)), ((u64)(0x2e7ad4ea3e7726c4)), ((u64)(0x0171b42cc5cf6014)), ((u64)(0x3a198a24ce14f075)), ((u64)(0x01ce2137f7433819)), ((u64)(0xc44ff65700cd1649)), ((u64)(0x0120d4c2fa8a030f)), ((u64)(0xb563f3ecc1005bdb)), ((u64)(0x016909f3b92c83d3)), ((u64)(0xa2bcf0e7f14072d2)), ((u64)(0x01c34c70a777a4c8)), ((u64)(0x65b61690f6c847c3)), ((u64)(0x011a0fc668aac6fd)), ((u64)(0xbf239c35347a59b4)), ((u64)(0x016093b802d578bc)), ((u64)(0xeeec83428198f021)), ((u64)(0x01b8b8a6038ad6eb)), ((u64)(0x7553d20990ff9615)), ((u64)(0x01137367c236c653)), ((u64)(0x52a8c68bf53f7b9a)), ((u64)(0x01585041b2c477e8)), ((u64)(0x6752f82ef28f5a81)), ((u64)(0x01ae64521f7595e2)), ((u64)(0x8093db1d57999890)), ((u64)(0x010cfeb353a97dad)), ((u64)(0xe0b8d1e4ad7ffeb4)), ((u64)(0x01503e602893dd18)), ((u64)(0x18e7065dd8dffe62)), ((u64)(0x01a44df832b8d45f)), ((u64)(0x6f9063faa78bfefd)), ((u64)(0x0106b0bb1fb384bb)), ((u64)(0x4b747cf9516efebc)), ((u64)(0x01485ce9e7a065ea)), ((u64)(0xde519c37a5cabe6b)), ((u64)(0x019a742461887f64)), ((u64)(0x0af301a2c79eb703)), ((u64)(0x01008896bcf54f9f)), ((u64)(0xcdafc20b798664c4)), ((u64)(0x0140aabc6c32a386)), ((u64)(0x811bb28e57e7fdf5)), ((u64)(0x0190d56b873f4c68)), ((u64)(0xa1629f31ede1fd72)), ((u64)(0x01f50ac6690f1f82)), ((u64)(0xa4dda37f34ad3e67)), ((u64)(0x013926bc01a973b1)), ((u64)(0x0e150c5f01d88e01)), ((u64)(0x0187706b0213d09e)), ((u64)(0x919a4f76c24eb181)), ((u64)(0x01e94c85c298c4c5)), ((u64)(0x7b0071aa39712ef1)), ((u64)(0x0131cfd3999f7afb)), ((u64)(0x59c08e14c7cd7aad)), ((u64)(0x017e43c8800759ba)), ((u64)(0xf030b199f9c0d958)), ((u64)(0x01ddd4baa0093028)), ((u64)(0x961e6f003c1887d7)), ((u64)(0x012aa4f4a405be19)), ((u64)(0xfba60ac04b1ea9cd)), ((u64)(0x01754e31cd072d9f)), ((u64)(0xfa8f8d705de65440)), ((u64)(0x01d2a1be4048f907)), ((u64)(0xfc99b8663aaff4a8)), ((u64)(0x0123a516e82d9ba4)), ((u64)(0x3bc0267fc95bf1d2)), ((u64)(0x016c8e5ca239028e)), ((u64)(0xcab0301fbbb2ee47)), ((u64)(0x01c7b1f3cac74331)), ((u64)(0x1eae1e13d54fd4ec)), ((u64)(0x011ccf385ebc89ff)), ((u64)(0xe659a598caa3ca27)), ((u64)(0x01640306766bac7e)), ((u64)(0x9ff00efefd4cbcb1)), ((u64)(0x01bd03c81406979e)), ((u64)(0x23f6095f5e4ff5ef)), ((u64)(0x0116225d0c841ec3)), ((u64)(0xecf38bb735e3f36a)), ((u64)(0x015baaf44fa52673)), ((u64)(0xe8306ea5035cf045)), ((u64)(0x01b295b1638e7010)), ((u64)(0x911e4527221a162b)), ((u64)(0x010f9d8ede39060a)), ((u64)(0x3565d670eaa09bb6)), ((u64)(0x015384f295c7478d)), ((u64)(0x82bf4c0d2548c2a3)), ((u64)(0x01a8662f3b391970)), ((u64)(0x51b78f88374d79a6)), ((u64)(0x01093fdd8503afe6)), ((u64)(0xe625736a4520d810)), ((u64)(0x014b8fd4e6449bdf)), ((u64)(0xdfaed044d6690e14)), ((u64)(0x019e73ca1fd5c2d7)), ((u64)(0xebcd422b0601a8cc)), ((u64)(0x0103085e53e599c6)), ((u64)(0xa6c092b5c78212ff)), ((u64)(0x0143ca75e8df0038)), ((u64)(0xd070b763396297bf)), ((u64)(0x0194bd136316c046)), ((u64)(0x848ce53c07bb3daf)), ((u64)(0x01f9ec583bdc7058)), ((u64)(0x52d80f4584d5068d)), ((u64)(0x013c33b72569c637)), ((u64)(0x278e1316e60a4831)), ((u64)(0x018b40a4eec437c5))};
const u64 strconv__pow5_inv_split_64_x[584] = {((u64)(0x0000000000000001)), ((u64)(0x0400000000000000)), ((u64)(0x3333333333333334)), ((u64)(0x0333333333333333)), ((u64)(0x28f5c28f5c28f5c3)), ((u64)(0x028f5c28f5c28f5c)), ((u64)(0xed916872b020c49c)), ((u64)(0x020c49ba5e353f7c)), ((u64)(0xaf4f0d844d013a93)), ((u64)(0x0346dc5d63886594)), ((u64)(0x8c3f3e0370cdc876)), ((u64)(0x029f16b11c6d1e10)), ((u64)(0xd698fe69270b06c5)), ((u64)(0x0218def416bdb1a6)), ((u64)(0xf0f4ca41d811a46e)), ((u64)(0x035afe535795e90a)), ((u64)(0xf3f70834acdae9f1)), ((u64)(0x02af31dc4611873b)), ((u64)(0x5cc5a02a23e254c1)), ((u64)(0x0225c17d04dad296)), ((u64)(0xfad5cd10396a2135)), ((u64)(0x036f9bfb3af7b756)), ((u64)(0xfbde3da69454e75e)), ((u64)(0x02bfaffc2f2c92ab)), ((u64)(0x2fe4fe1edd10b918)), ((u64)(0x0232f33025bd4223)), ((u64)(0x4ca19697c81ac1bf)), ((u64)(0x0384b84d092ed038)), ((u64)(0x3d4e1213067bce33)), ((u64)(0x02d09370d4257360)), ((u64)(0x643e74dc052fd829)), ((u64)(0x024075f3dceac2b3)), ((u64)(0x6d30baf9a1e626a7)), ((u64)(0x039a5652fb113785)), ((u64)(0x2426fbfae7eb5220)), ((u64)(0x02e1dea8c8da92d1)), ((u64)(0x1cebfcc8b9890e80)), ((u64)(0x024e4bba3a487574)), ((u64)(0x94acc7a78f41b0cc)), ((u64)(0x03b07929f6da5586)), ((u64)(0xaa23d2ec729af3d7)), ((u64)(0x02f394219248446b)), ((u64)(0xbb4fdbf05baf2979)), ((u64)(0x025c768141d369ef)), ((u64)(0xc54c931a2c4b758d)), ((u64)(0x03c7240202ebdcb2)), ((u64)(0x9dd6dc14f03c5e0b)), ((u64)(0x0305b66802564a28)), ((u64)(0x4b1249aa59c9e4d6)), ((u64)(0x026af8533511d4ed)), ((u64)(0x44ea0f76f60fd489)), ((u64)(0x03de5a1ebb4fbb15)), ((u64)(0x6a54d92bf80caa07)), ((u64)(0x0318481895d96277)), ((u64)(0x21dd7a89933d54d2)), ((u64)(0x0279d346de4781f9)), ((u64)(0x362f2a75b8622150)), ((u64)(0x03f61ed7ca0c0328)), ((u64)(0xf825bb91604e810d)), ((u64)(0x032b4bdfd4d668ec)), ((u64)(0xc684960de6a5340b)), ((u64)(0x0289097fdd7853f0)), ((u64)(0xd203ab3e521dc33c)), ((u64)(0x02073accb12d0ff3)), ((u64)(0xe99f7863b696052c)), ((u64)(0x033ec47ab514e652)), ((u64)(0x87b2c6b62bab3757)), ((u64)(0x02989d2ef743eb75)), ((u64)(0xd2f56bc4efbc2c45)), ((u64)(0x0213b0f25f69892a)), ((u64)(0x1e55793b192d13a2)), ((u64)(0x0352b4b6ff0f41de)), ((u64)(0x4b77942f475742e8)), ((u64)(0x02a8909265a5ce4b)), ((u64)(0xd5f9435905df68ba)), ((u64)(0x022073a8515171d5)), ((u64)(0x565b9ef4d6324129)), ((u64)(0x03671f73b54f1c89)), ((u64)(0xdeafb25d78283421)), ((u64)(0x02b8e5f62aa5b06d)), ((u64)(0x188c8eb12cecf681)), ((u64)(0x022d84c4eeeaf38b)), ((u64)(0x8dadb11b7b14bd9b)), ((u64)(0x037c07a17e44b8de)), ((u64)(0x7157c0e2c8dd647c)), ((u64)(0x02c99fb46503c718)), ((u64)(0x8ddfcd823a4ab6ca)), ((u64)(0x023ae629ea696c13)), ((u64)(0x1632e269f6ddf142)), ((u64)(0x0391704310a8acec)), ((u64)(0x44f581ee5f17f435)), ((u64)(0x02dac035a6ed5723)), ((u64)(0x372ace584c1329c4)), ((u64)(0x024899c4858aac1c)), ((u64)(0xbeaae3c079b842d3)), ((u64)(0x03a75c6da27779c6)), ((u64)(0x6555830061603576)), ((u64)(0x02ec49f14ec5fb05)), ((u64)(0xb7779c004de6912b)), ((u64)(0x0256a18dd89e626a)), ((u64)(0xf258f99a163db512)), ((u64)(0x03bdcf495a9703dd)), ((u64)(0x5b7a614811caf741)), ((u64)(0x02fe3f6de212697e)), ((u64)(0xaf951aa00e3bf901)), ((u64)(0x0264ff8b1b41edfe)), ((u64)(0x7f54f7667d2cc19b)), ((u64)(0x03d4cc11c5364997)), ((u64)(0x32aa5f8530f09ae3)), ((u64)(0x0310a3416a91d479)), ((u64)(0xf55519375a5a1582)), ((u64)(0x0273b5cdeedb1060)), ((u64)(0xbbbb5b8bc3c3559d)), ((u64)(0x03ec56164af81a34)), ((u64)(0x2fc916096969114a)), ((u64)(0x03237811d593482a)), ((u64)(0x596dab3ababa743c)), ((u64)(0x0282c674aadc39bb)), ((u64)(0x478aef622efb9030)), ((u64)(0x0202385d557cfafc)), ((u64)(0xd8de4bd04b2c19e6)), ((u64)(0x0336c0955594c4c6)), ((u64)(0xad7ea30d08f014b8)), ((u64)(0x029233aaaadd6a38)), ((u64)(0x24654f3da0c01093)), ((u64)(0x020e8fbbbbe454fa)), ((u64)(0x3a3bb1fc346680eb)), ((u64)(0x034a7f92c63a2190)), ((u64)(0x94fc8e635d1ecd89)), ((u64)(0x02a1ffa89e94e7a6)), ((u64)(0xaa63a51c4a7f0ad4)), ((u64)(0x021b32ed4baa52eb)), ((u64)(0xdd6c3b607731aaed)), ((u64)(0x035eb7e212aa1e45)), ((u64)(0x1789c919f8f488bd)), ((u64)(0x02b22cb4dbbb4b6b)), ((u64)(0xac6e3a7b2d906d64)), ((u64)(0x022823c3e2fc3c55)), ((u64)(0x13e390c515b3e23a)), ((u64)(0x03736c6c9e606089)), ((u64)(0xdcb60d6a77c31b62)), ((u64)(0x02c2bd23b1e6b3a0)), ((u64)(0x7d5e7121f968e2b5)), ((u64)(0x0235641c8e52294d)), ((u64)(0xc8971b698f0e3787)), ((u64)(0x0388a02db0837548)), ((u64)(0xa078e2bad8d82c6c)), ((u64)(0x02d3b357c0692aa0)), ((u64)(0xe6c71bc8ad79bd24)), ((u64)(0x0242f5dfcd20eee6)), ((u64)(0x0ad82c7448c2c839)), ((u64)(0x039e5632e1ce4b0b)), ((u64)(0x3be023903a356cfa)), ((u64)(0x02e511c24e3ea26f)), ((u64)(0x2fe682d9c82abd95)), ((u64)(0x0250db01d8321b8c)), ((u64)(0x4ca4048fa6aac8ee)), ((u64)(0x03b4919c8d1cf8e0)), ((u64)(0x3d5003a61eef0725)), ((u64)(0x02f6dae3a4172d80)), ((u64)(0x9773361e7f259f51)), ((u64)(0x025f1582e9ac2466)), ((u64)(0x8beb89ca6508fee8)), ((u64)(0x03cb559e42ad070a)), ((u64)(0x6fefa16eb73a6586)), ((u64)(0x0309114b688a6c08)), ((u64)(0xf3261abef8fb846b)), ((u64)(0x026da76f86d52339)), ((u64)(0x51d691318e5f3a45)), ((u64)(0x03e2a57f3e21d1f6)), ((u64)(0x0e4540f471e5c837)), ((u64)(0x031bb798fe8174c5)), ((u64)(0xd8376729f4b7d360)), ((u64)(0x027c92e0cb9ac3d0)), ((u64)(0xf38bd84321261eff)), ((u64)(0x03fa849adf5e061a)), ((u64)(0x293cad0280eb4bff)), ((u64)(0x032ed07be5e4d1af)), ((u64)(0xedca240200bc3ccc)), ((u64)(0x028bd9fcb7ea4158)), ((u64)(0xbe3b50019a3030a4)), ((u64)(0x02097b309321cde0)), ((u64)(0xc9f88002904d1a9f)), ((u64)(0x03425eb41e9c7c9a)), ((u64)(0x3b2d3335403daee6)), ((u64)(0x029b7ef67ee396e2)), ((u64)(0x95bdc291003158b8)), ((u64)(0x0215ff2b98b6124e)), ((u64)(0x892f9db4cd1bc126)), ((u64)(0x035665128df01d4a)), ((u64)(0x07594af70a7c9a85)), ((u64)(0x02ab840ed7f34aa2)), ((u64)(0x6c476f2c0863aed1)), ((u64)(0x0222d00bdff5d54e)), ((u64)(0x13a57eacda3917b4)), ((u64)(0x036ae67966562217)), ((u64)(0x0fb7988a482dac90)), ((u64)(0x02bbeb9451de81ac)), ((u64)(0xd95fad3b6cf156da)), ((u64)(0x022fefa9db1867bc)), ((u64)(0xf565e1f8ae4ef15c)), ((u64)(0x037fe5dc91c0a5fa)), ((u64)(0x911e4e608b725ab0)), ((u64)(0x02ccb7e3a7cd5195)), ((u64)(0xda7ea51a0928488d)), ((u64)(0x023d5fe9530aa7aa)), ((u64)(0xf7310829a8407415)), ((u64)(0x039566421e7772aa)), ((u64)(0x2c2739baed005cde)), ((u64)(0x02ddeb68185f8eef)), ((u64)(0xbcec2e2f24004a4b)), ((u64)(0x024b22b9ad193f25)), ((u64)(0x94ad16b1d333aa11)), ((u64)(0x03ab6ac2ae8ecb6f)), ((u64)(0xaa241227dc2954db)), ((u64)(0x02ef889bbed8a2bf)), ((u64)(0x54e9a81fe35443e2)), ((u64)(0x02593a163246e899)), ((u64)(0x2175d9cc9eed396a)), ((u64)(0x03c1f689ea0b0dc2)), ((u64)(0xe7917b0a18bdc788)), ((u64)(0x03019207ee6f3e34)), ((u64)(0xb9412f3b46fe393a)), ((u64)(0x0267a8065858fe90)), ((u64)(0xf535185ed7fd285c)), ((u64)(0x03d90cd6f3c1974d)), ((u64)(0xc42a79e57997537d)), ((u64)(0x03140a458fce12a4)), ((u64)(0x03552e512e12a931)), ((u64)(0x02766e9e0ca4dbb7)), ((u64)(0x9eeeb081e3510eb4)), ((u64)(0x03f0b0fce107c5f1)), ((u64)(0x4bf226ce4f740bc3)), ((u64)(0x0326f3fd80d304c1)), ((u64)(0xa3281f0b72c33c9c)), ((u64)(0x02858ffe00a8d09a)), ((u64)(0x1c2018d5f568fd4a)), ((u64)(0x020473319a20a6e2)), ((u64)(0xf9ccf48988a7fba9)), ((u64)(0x033a51e8f69aa49c)), ((u64)(0xfb0a5d3ad3b99621)), ((u64)(0x02950e53f87bb6e3)), ((u64)(0x2f3b7dc8a96144e7)), ((u64)(0x0210d8432d2fc583)), ((u64)(0xe52bfc7442353b0c)), ((u64)(0x034e26d1e1e608d1)), ((u64)(0xb756639034f76270)), ((u64)(0x02a4ebdb1b1e6d74)), ((u64)(0x2c451c735d92b526)), ((u64)(0x021d897c15b1f12a)), ((u64)(0x13a1c71efc1deea3)), ((u64)(0x0362759355e981dd)), ((u64)(0x761b05b2634b2550)), ((u64)(0x02b52adc44bace4a)), ((u64)(0x91af37c1e908eaa6)), ((u64)(0x022a88b036fbd83b)), ((u64)(0x82b1f2cfdb417770)), ((u64)(0x03774119f192f392)), ((u64)(0xcef4c23fe29ac5f3)), ((u64)(0x02c5cdae5adbf60e)), ((u64)(0x3f2a34ffe87bd190)), ((u64)(0x0237d7beaf165e72)), ((u64)(0x984387ffda5fb5b2)), ((u64)(0x038c8c644b56fd83)), ((u64)(0xe0360666484c915b)), ((u64)(0x02d6d6b6a2abfe02)), ((u64)(0x802b3851d3707449)), ((u64)(0x024578921bbccb35)), ((u64)(0x99dec082ebe72075)), ((u64)(0x03a25a835f947855)), ((u64)(0xae4bcd358985b391)), ((u64)(0x02e8486919439377)), ((u64)(0xbea30a913ad15c74)), ((u64)(0x02536d20e102dc5f)), ((u64)(0xfdd1aa81f7b560b9)), ((u64)(0x03b8ae9b019e2d65)), ((u64)(0x97daeece5fc44d61)), ((u64)(0x02fa2548ce182451)), ((u64)(0xdfe258a51969d781)), ((u64)(0x0261b76d71ace9da)), ((u64)(0x996a276e8f0fbf34)), ((u64)(0x03cf8be24f7b0fc4)), ((u64)(0xe121b9253f3fcc2a)), ((u64)(0x030c6fe83f95a636)), ((u64)(0xb41afa8432997022)), ((u64)(0x02705986994484f8)), ((u64)(0xecf7f739ea8f19cf)), ((u64)(0x03e6f5a4286da18d)), ((u64)(0x23f99294bba5ae40)), ((u64)(0x031f2ae9b9f14e0b)), ((u64)(0x4ffadbaa2fb7be99)), ((u64)(0x027f5587c7f43e6f)), ((u64)(0x7ff7c5dd1925fdc2)), ((u64)(0x03feef3fa6539718)), ((u64)(0xccc637e4141e649b)), ((u64)(0x033258ffb842df46)), ((u64)(0xd704f983434b83af)), ((u64)(0x028ead9960357f6b)), ((u64)(0x126a6135cf6f9c8c)), ((u64)(0x020bbe144cf79923)), ((u64)(0x83dd685618b29414)), ((u64)(0x0345fced47f28e9e)), ((u64)(0x9cb12044e08edcdd)), ((u64)(0x029e63f1065ba54b)), ((u64)(0x16f419d0b3a57d7d)), ((u64)(0x02184ff405161dd6)), ((u64)(0x8b20294dec3bfbfb)), ((u64)(0x035a19866e89c956)), ((u64)(0x3c19baa4bcfcc996)), ((u64)(0x02ae7ad1f207d445)), ((u64)(0xc9ae2eea30ca3adf)), ((u64)(0x02252f0e5b39769d)), ((u64)(0x0f7d17dd1add2afd)), ((u64)(0x036eb1b091f58a96)), ((u64)(0x3f97464a7be42264)), ((u64)(0x02bef48d41913bab)), ((u64)(0xcc790508631ce850)), ((u64)(0x02325d3dce0dc955)), ((u64)(0xe0c1a1a704fb0d4d)), ((u64)(0x0383c862e3494222)), ((u64)(0x4d67b4859d95a43e)), ((u64)(0x02cfd3824f6dce82)), ((u64)(0x711fc39e17aae9cb)), ((u64)(0x023fdc683f8b0b9b)), ((u64)(0xe832d2968c44a945)), ((u64)(0x039960a6cc11ac2b)), ((u64)(0xecf575453d03ba9e)), ((u64)(0x02e11a1f09a7bcef)), ((u64)(0x572ac4376402fbb1)), ((u64)(0x024dae7f3aec9726)), ((u64)(0x58446d256cd192b5)), ((u64)(0x03af7d985e47583d)), ((u64)(0x79d0575123dadbc4)), ((u64)(0x02f2cae04b6c4697)), ((u64)(0x94a6ac40e97be303)), ((u64)(0x025bd5803c569edf)), ((u64)(0x8771139b0f2c9e6c)), ((u64)(0x03c62266c6f0fe32)), ((u64)(0x9f8da948d8f07ebd)), ((u64)(0x0304e85238c0cb5b)), ((u64)(0xe60aedd3e0c06564)), ((u64)(0x026a5374fa33d5e2)), ((u64)(0xa344afb9679a3bd2)), ((u64)(0x03dd5254c3862304)), ((u64)(0xe903bfc78614fca8)), ((u64)(0x031775109c6b4f36)), ((u64)(0xba6966393810ca20)), ((u64)(0x02792a73b055d8f8)), ((u64)(0x2a423d2859b4769a)), ((u64)(0x03f510b91a22f4c1)), ((u64)(0xee9b642047c39215)), ((u64)(0x032a73c7481bf700)), ((u64)(0xbee2b680396941aa)), ((u64)(0x02885c9f6ce32c00)), ((u64)(0xff1bc53361210155)), ((u64)(0x0206b07f8a4f5666)), ((u64)(0x31c6085235019bbb)), ((u64)(0x033de73276e5570b)), ((u64)(0x27d1a041c4014963)), ((u64)(0x0297ec285f1ddf3c)), ((u64)(0xeca7b367d0010782)), ((u64)(0x021323537f4b18fc)), ((u64)(0xadd91f0c8001a59d)), ((u64)(0x0351d21f3211c194)), ((u64)(0xf17a7f3d3334847e)), ((u64)(0x02a7db4c280e3476)), ((u64)(0x279532975c2a0398)), ((u64)(0x021fe2a3533e905f)), ((u64)(0xd8eeb75893766c26)), ((u64)(0x0366376bb8641a31)), ((u64)(0x7a5892ad42c52352)), ((u64)(0x02b82c562d1ce1c1)), ((u64)(0xfb7a0ef102374f75)), ((u64)(0x022cf044f0e3e7cd)), ((u64)(0xc59017e8038bb254)), ((u64)(0x037b1a07e7d30c7c)), ((u64)(0x37a67986693c8eaa)), ((u64)(0x02c8e19feca8d6ca)), ((u64)(0xf951fad1edca0bbb)), ((u64)(0x023a4e198a20abd4)), ((u64)(0x28832ae97c76792b)), ((u64)(0x03907cf5a9cddfbb)), ((u64)(0x2068ef21305ec756)), ((u64)(0x02d9fd9154a4b2fc)), ((u64)(0x19ed8c1a8d189f78)), ((u64)(0x0247fe0ddd508f30)), ((u64)(0x5caf4690e1c0ff26)), ((u64)(0x03a66349621a7eb3)), ((u64)(0x4a25d20d81673285)), ((u64)(0x02eb82a11b48655c)), ((u64)(0x3b5174d79ab8f537)), ((u64)(0x0256021a7c39eab0)), ((u64)(0x921bee25c45b21f1)), ((u64)(0x03bcd02a605caab3)), ((u64)(0xdb498b5169e2818e)), ((u64)(0x02fd735519e3bbc2)), ((u64)(0x15d46f7454b53472)), ((u64)(0x02645c4414b62fcf)), ((u64)(0xefba4bed545520b6)), ((u64)(0x03d3c6d35456b2e4)), ((u64)(0xf2fb6ff110441a2b)), ((u64)(0x030fd242a9def583)), ((u64)(0x8f2f8cc0d9d014ef)), ((u64)(0x02730e9bbb18c469)), ((u64)(0xb1e5ae015c80217f)), ((u64)(0x03eb4a92c4f46d75)), ((u64)(0xc1848b344a001acc)), ((u64)(0x0322a20f03f6bdf7)), ((u64)(0xce03a2903b3348a3)), ((u64)(0x02821b3f365efe5f)), ((u64)(0xd802e873628f6d4f)), ((u64)(0x0201af65c518cb7f)), ((u64)(0x599e40b89db2487f)), ((u64)(0x0335e56fa1c14599)), ((u64)(0xe14b66fa17c1d399)), ((u64)(0x029184594e3437ad)), ((u64)(0x81091f2e7967dc7a)), ((u64)(0x020e037aa4f692f1)), ((u64)(0x9b41cb7d8f0c93f6)), ((u64)(0x03499f2aa18a84b5)), ((u64)(0xaf67d5fe0c0a0ff8)), ((u64)(0x02a14c221ad536f7)), ((u64)(0xf2b977fe70080cc7)), ((u64)(0x021aa34e7bddc592)), ((u64)(0x1df58cca4cd9ae0b)), ((u64)(0x035dd2172c9608eb)), ((u64)(0xe4c470a1d7148b3c)), ((u64)(0x02b174df56de6d88)), ((u64)(0x83d05a1b1276d5ca)), ((u64)(0x022790b2abe5246d)), ((u64)(0x9fb3c35e83f1560f)), ((u64)(0x0372811ddfd50715)), ((u64)(0xb2f635e5365aab3f)), ((u64)(0x02c200e4b310d277)), ((u64)(0xf591c4b75eaeef66)), ((u64)(0x0234cd83c273db92)), ((u64)(0xef4fa125644b18a3)), ((u64)(0x0387af39371fc5b7)), ((u64)(0x8c3fb41de9d5ad4f)), ((u64)(0x02d2f2942c196af9)), ((u64)(0x3cffc34b2177bdd9)), ((u64)(0x02425ba9bce12261)), ((u64)(0x94cc6bab68bf9628)), ((u64)(0x039d5f75fb01d09b)), ((u64)(0x10a38955ed6611b9)), ((u64)(0x02e44c5e6267da16)), ((u64)(0xda1c6dde5784dafb)), ((u64)(0x02503d184eb97b44)), ((u64)(0xf693e2fd58d49191)), ((u64)(0x03b394f3b128c53a)), ((u64)(0xc5431bfde0aa0e0e)), ((u64)(0x02f610c2f4209dc8)), ((u64)(0x6a9c1664b3bb3e72)), ((u64)(0x025e73cf29b3b16d)), ((u64)(0x10f9bd6dec5eca4f)), ((u64)(0x03ca52e50f85e8af)), ((u64)(0xda616457f04bd50c)), ((u64)(0x03084250d937ed58)), ((u64)(0xe1e783798d09773d)), ((u64)(0x026d01da475ff113)), ((u64)(0x030c058f480f252e)), ((u64)(0x03e19c9072331b53)), ((u64)(0x68d66ad906728425)), ((u64)(0x031ae3a6c1c27c42)), ((u64)(0x8711ef14052869b7)), ((u64)(0x027be952349b969b)), ((u64)(0x0b4fe4ecd50d75f2)), ((u64)(0x03f97550542c242c)), ((u64)(0xa2a650bd773df7f5)), ((u64)(0x032df7737689b689)), ((u64)(0xb551da312c31932a)), ((u64)(0x028b2c5c5ed49207)), ((u64)(0x5ddb14f4235adc22)), ((u64)(0x0208f049e576db39)), ((u64)(0x2fc4ee536bc49369)), ((u64)(0x034180763bf15ec2)), ((u64)(0xbfd0bea92303a921)), ((u64)(0x029acd2b63277f01)), ((u64)(0x9973cbba8269541a)), ((u64)(0x021570ef8285ff34)), ((u64)(0x5bec792a6a42202a)), ((u64)(0x0355817f373ccb87)), ((u64)(0xe3239421ee9b4cef)), ((u64)(0x02aacdff5f63d605)), ((u64)(0xb5b6101b25490a59)), ((u64)(0x02223e65e5e97804)), ((u64)(0x22bce691d541aa27)), ((u64)(0x0369fd6fd64259a1)), ((u64)(0xb563eba7ddce21b9)), ((u64)(0x02bb31264501e14d)), ((u64)(0xf78322ecb171b494)), ((u64)(0x022f5a850401810a)), ((u64)(0x259e9e47824f8753)), ((u64)(0x037ef73b399c01ab)), ((u64)(0x1e187e9f9b72d2a9)), ((u64)(0x02cbf8fc2e1667bc)), ((u64)(0x4b46cbb2e2c24221)), ((u64)(0x023cc73024deb963)), ((u64)(0x120adf849e039d01)), ((u64)(0x039471e6a1645bd2)), ((u64)(0xdb3be603b19c7d9a)), ((u64)(0x02dd27ebb4504974)), ((u64)(0x7c2feb3627b0647c)), ((u64)(0x024a865629d9d45d)), ((u64)(0x2d197856a5e7072c)), ((u64)(0x03aa7089dc8fba2f)), ((u64)(0x8a7ac6abb7ec05bd)), ((u64)(0x02eec06e4a0c94f2)), ((u64)(0xd52f05562cbcd164)), ((u64)(0x025899f1d4d6dd8e)), ((u64)(0x21e4d556adfae8a0)), ((u64)(0x03c0f64fbaf1627e)), ((u64)(0xe7ea444557fbed4d)), ((u64)(0x0300c50c958de864)), ((u64)(0xecbb69d1132ff10a)), ((u64)(0x0267040a113e5383)), ((u64)(0xadf8a94e851981aa)), ((u64)(0x03d8067681fd526c)), ((u64)(0x8b2d543ed0e13488)), ((u64)(0x0313385ece6441f0)), ((u64)(0xd5bddcff0d80f6d3)), ((u64)(0x0275c6b23eb69b26)), ((u64)(0x892fc7fe7c018aeb)), ((u64)(0x03efa45064575ea4)), ((u64)(0x3a8c9ffec99ad589)), ((u64)(0x03261d0d1d12b21d)), ((u64)(0xc8707fff07af113b)), ((u64)(0x0284e40a7da88e7d)), ((u64)(0x39f39998d2f2742f)), ((u64)(0x0203e9a1fe2071fe)), ((u64)(0x8fec28f484b7204b)), ((u64)(0x033975cffd00b663)), ((u64)(0xd989ba5d36f8e6a2)), ((u64)(0x02945e3ffd9a2b82)), ((u64)(0x47a161e42bfa521c)), ((u64)(0x02104b66647b5602)), ((u64)(0x0c35696d132a1cf9)), ((u64)(0x034d4570a0c5566a)), ((u64)(0x09c454574288172d)), ((u64)(0x02a4378d4d6aab88)), ((u64)(0xa169dd129ba0128b)), ((u64)(0x021cf93dd7888939)), ((u64)(0x0242fb50f9001dab)), ((u64)(0x03618ec958da7529)), ((u64)(0x9b68c90d940017bc)), ((u64)(0x02b4723aad7b90ed)), ((u64)(0x4920a0d7a999ac96)), ((u64)(0x0229f4fbbdfc73f1)), ((u64)(0x750101590f5c4757)), ((u64)(0x037654c5fcc71fe8)), ((u64)(0x2a6734473f7d05df)), ((u64)(0x02c5109e63d27fed)), ((u64)(0xeeb8f69f65fd9e4c)), ((u64)(0x0237407eb641fff0)), ((u64)(0xe45b24323cc8fd46)), ((u64)(0x038b9a6456cfffe7)), ((u64)(0xb6af502830a0ca9f)), ((u64)(0x02d6151d123fffec)), ((u64)(0xf88c402026e7087f)), ((u64)(0x0244ddb0db666656)), ((u64)(0x2746cd003e3e73fe)), ((u64)(0x03a162b4923d708b)), ((u64)(0x1f6bd73364fec332)), ((u64)(0x02e7822a0e978d3c)), ((u64)(0xe5efdf5c50cbcf5b)), ((u64)(0x0252ce880bac70fc)), ((u64)(0x3cb2fefa1adfb22b)), ((u64)(0x03b7b0d9ac471b2e)), ((u64)(0x308f3261af195b56)), ((u64)(0x02f95a47bd05af58)), ((u64)(0x5a0c284e25ade2ab)), ((u64)(0x0261150630d15913)), ((u64)(0x29ad0d49d5e30445)), ((u64)(0x03ce8809e7b55b52)), ((u64)(0x548a7107de4f369d)), ((u64)(0x030ba007ec9115db)), ((u64)(0xdd3b8d9fe50c2bb1)), ((u64)(0x026fb3398a0dab15)), ((u64)(0x952c15cca1ad12b5)), ((u64)(0x03e5eb8f434911bc)), ((u64)(0x775677d6e7bda891)), ((u64)(0x031e560c35d40e30)), ((u64)(0xc5dec645863153a7)), ((u64)(0x027eab3cf7dcd826))};
#define strconv__single_plus_zero (((u32)(0x00000000)))
#define strconv__single_minus_zero (((u32)(0x80000000)))
#define strconv__single_plus_infinity (((u32)(0x7F800000)))
#define strconv__single_minus_infinity (((u32)(0xFF800000)))
#define strconv__digits (18)
#define strconv__double_plus_zero (((u64)(0x0000000000000000)))
#define strconv__double_minus_zero (((u64)(0x8000000000000000)))
#define strconv__double_plus_infinity (((u64)(0x7FF0000000000000)))
#define strconv__double_minus_infinity (((u64)(0xFFF0000000000000)))
#define strconv__c_dpoint ('.')
#define strconv__c_plus ('+')
#define strconv__c_minus ('-')
#define strconv__c_zero ('0')
#define strconv__c_nine ('9')
#define strconv__c_ten (((u32)(10)))
const u64 strconv__pos_exp[309] = {((u64)(0x3ff0000000000000)), ((u64)(0x4024000000000000)), ((u64)(0x4059000000000000)), ((u64)(0x408f400000000000)), ((u64)(0x40c3880000000000)), ((u64)(0x40f86a0000000000)), ((u64)(0x412e848000000000)), ((u64)(0x416312d000000000)), ((u64)(0x4197d78400000000)), ((u64)(0x41cdcd6500000000)), ((u64)(0x4202a05f20000000)), ((u64)(0x42374876e8000000)), ((u64)(0x426d1a94a2000000)), ((u64)(0x42a2309ce5400000)), ((u64)(0x42d6bcc41e900000)), ((u64)(0x430c6bf526340000)), ((u64)(0x4341c37937e08000)), ((u64)(0x4376345785d8a000)), ((u64)(0x43abc16d674ec800)), ((u64)(0x43e158e460913d00)), ((u64)(0x4415af1d78b58c40)), ((u64)(0x444b1ae4d6e2ef50)), ((u64)(0x4480f0cf064dd592)), ((u64)(0x44b52d02c7e14af6)), ((u64)(0x44ea784379d99db4)), ((u64)(0x45208b2a2c280291)), ((u64)(0x4554adf4b7320335)), ((u64)(0x4589d971e4fe8402)), ((u64)(0x45c027e72f1f1281)), ((u64)(0x45f431e0fae6d721)), ((u64)(0x46293e5939a08cea)), ((u64)(0x465f8def8808b024)), ((u64)(0x4693b8b5b5056e17)), ((u64)(0x46c8a6e32246c99c)), ((u64)(0x46fed09bead87c03)), ((u64)(0x4733426172c74d82)), ((u64)(0x476812f9cf7920e3)), ((u64)(0x479e17b84357691b)), ((u64)(0x47d2ced32a16a1b1)), ((u64)(0x48078287f49c4a1d)), ((u64)(0x483d6329f1c35ca5)), ((u64)(0x48725dfa371a19e7)), ((u64)(0x48a6f578c4e0a061)), ((u64)(0x48dcb2d6f618c879)), ((u64)(0x4911efc659cf7d4c)), ((u64)(0x49466bb7f0435c9e)), ((u64)(0x497c06a5ec5433c6)), ((u64)(0x49b18427b3b4a05c)), ((u64)(0x49e5e531a0a1c873)), ((u64)(0x4a1b5e7e08ca3a8f)), ((u64)(0x4a511b0ec57e649a)), ((u64)(0x4a8561d276ddfdc0)), ((u64)(0x4ababa4714957d30)), ((u64)(0x4af0b46c6cdd6e3e)), ((u64)(0x4b24e1878814c9ce)), ((u64)(0x4b5a19e96a19fc41)), ((u64)(0x4b905031e2503da9)), ((u64)(0x4bc4643e5ae44d13)), ((u64)(0x4bf97d4df19d6057)), ((u64)(0x4c2fdca16e04b86d)), ((u64)(0x4c63e9e4e4c2f344)), ((u64)(0x4c98e45e1df3b015)), ((u64)(0x4ccf1d75a5709c1b)), ((u64)(0x4d03726987666191)), ((u64)(0x4d384f03e93ff9f5)), ((u64)(0x4d6e62c4e38ff872)), ((u64)(0x4da2fdbb0e39fb47)), ((u64)(0x4dd7bd29d1c87a19)), ((u64)(0x4e0dac74463a989f)), ((u64)(0x4e428bc8abe49f64)), ((u64)(0x4e772ebad6ddc73d)), ((u64)(0x4eacfa698c95390c)), ((u64)(0x4ee21c81f7dd43a7)), ((u64)(0x4f16a3a275d49491)), ((u64)(0x4f4c4c8b1349b9b5)), ((u64)(0x4f81afd6ec0e1411)), ((u64)(0x4fb61bcca7119916)), ((u64)(0x4feba2bfd0d5ff5b)), ((u64)(0x502145b7e285bf99)), ((u64)(0x50559725db272f7f)), ((u64)(0x508afcef51f0fb5f)), ((u64)(0x50c0de1593369d1b)), ((u64)(0x50f5159af8044462)), ((u64)(0x512a5b01b605557b)), ((u64)(0x516078e111c3556d)), ((u64)(0x5194971956342ac8)), ((u64)(0x51c9bcdfabc1357a)), ((u64)(0x5200160bcb58c16c)), ((u64)(0x52341b8ebe2ef1c7)), ((u64)(0x526922726dbaae39)), ((u64)(0x529f6b0f092959c7)), ((u64)(0x52d3a2e965b9d81d)), ((u64)(0x53088ba3bf284e24)), ((u64)(0x533eae8caef261ad)), ((u64)(0x53732d17ed577d0c)), ((u64)(0x53a7f85de8ad5c4f)), ((u64)(0x53ddf67562d8b363)), ((u64)(0x5412ba095dc7701e)), ((u64)(0x5447688bb5394c25)), ((u64)(0x547d42aea2879f2e)), ((u64)(0x54b249ad2594c37d)), ((u64)(0x54e6dc186ef9f45c)), ((u64)(0x551c931e8ab87173)), ((u64)(0x5551dbf316b346e8)), ((u64)(0x558652efdc6018a2)), ((u64)(0x55bbe7abd3781eca)), ((u64)(0x55f170cb642b133f)), ((u64)(0x5625ccfe3d35d80e)), ((u64)(0x565b403dcc834e12)), ((u64)(0x569108269fd210cb)), ((u64)(0x56c54a3047c694fe)), ((u64)(0x56fa9cbc59b83a3d)), ((u64)(0x5730a1f5b8132466)), ((u64)(0x5764ca732617ed80)), ((u64)(0x5799fd0fef9de8e0)), ((u64)(0x57d03e29f5c2b18c)), ((u64)(0x58044db473335def)), ((u64)(0x583961219000356b)), ((u64)(0x586fb969f40042c5)), ((u64)(0x58a3d3e2388029bb)), ((u64)(0x58d8c8dac6a0342a)), ((u64)(0x590efb1178484135)), ((u64)(0x59435ceaeb2d28c1)), ((u64)(0x59783425a5f872f1)), ((u64)(0x59ae412f0f768fad)), ((u64)(0x59e2e8bd69aa19cc)), ((u64)(0x5a17a2ecc414a03f)), ((u64)(0x5a4d8ba7f519c84f)), ((u64)(0x5a827748f9301d32)), ((u64)(0x5ab7151b377c247e)), ((u64)(0x5aecda62055b2d9e)), ((u64)(0x5b22087d4358fc82)), ((u64)(0x5b568a9c942f3ba3)), ((u64)(0x5b8c2d43b93b0a8c)), ((u64)(0x5bc19c4a53c4e697)), ((u64)(0x5bf6035ce8b6203d)), ((u64)(0x5c2b843422e3a84d)), ((u64)(0x5c6132a095ce4930)), ((u64)(0x5c957f48bb41db7c)), ((u64)(0x5ccadf1aea12525b)), ((u64)(0x5d00cb70d24b7379)), ((u64)(0x5d34fe4d06de5057)), ((u64)(0x5d6a3de04895e46d)), ((u64)(0x5da066ac2d5daec4)), ((u64)(0x5dd4805738b51a75)), ((u64)(0x5e09a06d06e26112)), ((u64)(0x5e400444244d7cab)), ((u64)(0x5e7405552d60dbd6)), ((u64)(0x5ea906aa78b912cc)), ((u64)(0x5edf485516e7577f)), ((u64)(0x5f138d352e5096af)), ((u64)(0x5f48708279e4bc5b)), ((u64)(0x5f7e8ca3185deb72)), ((u64)(0x5fb317e5ef3ab327)), ((u64)(0x5fe7dddf6b095ff1)), ((u64)(0x601dd55745cbb7ed)), ((u64)(0x6052a5568b9f52f4)), ((u64)(0x60874eac2e8727b1)), ((u64)(0x60bd22573a28f19d)), ((u64)(0x60f2357684599702)), ((u64)(0x6126c2d4256ffcc3)), ((u64)(0x615c73892ecbfbf4)), ((u64)(0x6191c835bd3f7d78)), ((u64)(0x61c63a432c8f5cd6)), ((u64)(0x61fbc8d3f7b3340c)), ((u64)(0x62315d847ad00087)), ((u64)(0x6265b4e5998400a9)), ((u64)(0x629b221effe500d4)), ((u64)(0x62d0f5535fef2084)), ((u64)(0x630532a837eae8a5)), ((u64)(0x633a7f5245e5a2cf)), ((u64)(0x63708f936baf85c1)), ((u64)(0x63a4b378469b6732)), ((u64)(0x63d9e056584240fe)), ((u64)(0x64102c35f729689f)), ((u64)(0x6444374374f3c2c6)), ((u64)(0x647945145230b378)), ((u64)(0x64af965966bce056)), ((u64)(0x64e3bdf7e0360c36)), ((u64)(0x6518ad75d8438f43)), ((u64)(0x654ed8d34e547314)), ((u64)(0x6583478410f4c7ec)), ((u64)(0x65b819651531f9e8)), ((u64)(0x65ee1fbe5a7e7861)), ((u64)(0x6622d3d6f88f0b3d)), ((u64)(0x665788ccb6b2ce0c)), ((u64)(0x668d6affe45f818f)), ((u64)(0x66c262dfeebbb0f9)), ((u64)(0x66f6fb97ea6a9d38)), ((u64)(0x672cba7de5054486)), ((u64)(0x6761f48eaf234ad4)), ((u64)(0x679671b25aec1d89)), ((u64)(0x67cc0e1ef1a724eb)), ((u64)(0x680188d357087713)), ((u64)(0x6835eb082cca94d7)), ((u64)(0x686b65ca37fd3a0d)), ((u64)(0x68a11f9e62fe4448)), ((u64)(0x68d56785fbbdd55a)), ((u64)(0x690ac1677aad4ab1)), ((u64)(0x6940b8e0acac4eaf)), ((u64)(0x6974e718d7d7625a)), ((u64)(0x69aa20df0dcd3af1)), ((u64)(0x69e0548b68a044d6)), ((u64)(0x6a1469ae42c8560c)), ((u64)(0x6a498419d37a6b8f)), ((u64)(0x6a7fe52048590673)), ((u64)(0x6ab3ef342d37a408)), ((u64)(0x6ae8eb0138858d0a)), ((u64)(0x6b1f25c186a6f04c)), ((u64)(0x6b537798f4285630)), ((u64)(0x6b88557f31326bbb)), ((u64)(0x6bbe6adefd7f06aa)), ((u64)(0x6bf302cb5e6f642a)), ((u64)(0x6c27c37e360b3d35)), ((u64)(0x6c5db45dc38e0c82)), ((u64)(0x6c9290ba9a38c7d1)), ((u64)(0x6cc734e940c6f9c6)), ((u64)(0x6cfd022390f8b837)), ((u64)(0x6d3221563a9b7323)), ((u64)(0x6d66a9abc9424feb)), ((u64)(0x6d9c5416bb92e3e6)), ((u64)(0x6dd1b48e353bce70)), ((u64)(0x6e0621b1c28ac20c)), ((u64)(0x6e3baa1e332d728f)), ((u64)(0x6e714a52dffc6799)), ((u64)(0x6ea59ce797fb817f)), ((u64)(0x6edb04217dfa61df)), ((u64)(0x6f10e294eebc7d2c)), ((u64)(0x6f451b3a2a6b9c76)), ((u64)(0x6f7a6208b5068394)), ((u64)(0x6fb07d457124123d)), ((u64)(0x6fe49c96cd6d16cc)), ((u64)(0x7019c3bc80c85c7f)), ((u64)(0x70501a55d07d39cf)), ((u64)(0x708420eb449c8843)), ((u64)(0x70b9292615c3aa54)), ((u64)(0x70ef736f9b3494e9)), ((u64)(0x7123a825c100dd11)), ((u64)(0x7158922f31411456)), ((u64)(0x718eb6bafd91596b)), ((u64)(0x71c33234de7ad7e3)), ((u64)(0x71f7fec216198ddc)), ((u64)(0x722dfe729b9ff153)), ((u64)(0x7262bf07a143f6d4)), ((u64)(0x72976ec98994f489)), ((u64)(0x72cd4a7bebfa31ab)), ((u64)(0x73024e8d737c5f0b)), ((u64)(0x7336e230d05b76cd)), ((u64)(0x736c9abd04725481)), ((u64)(0x73a1e0b622c774d0)), ((u64)(0x73d658e3ab795204)), ((u64)(0x740bef1c9657a686)), ((u64)(0x74417571ddf6c814)), ((u64)(0x7475d2ce55747a18)), ((u64)(0x74ab4781ead1989e)), ((u64)(0x74e10cb132c2ff63)), ((u64)(0x75154fdd7f73bf3c)), ((u64)(0x754aa3d4df50af0b)), ((u64)(0x7580a6650b926d67)), ((u64)(0x75b4cffe4e7708c0)), ((u64)(0x75ea03fde214caf1)), ((u64)(0x7620427ead4cfed6)), ((u64)(0x7654531e58a03e8c)), ((u64)(0x768967e5eec84e2f)), ((u64)(0x76bfc1df6a7a61bb)), ((u64)(0x76f3d92ba28c7d15)), ((u64)(0x7728cf768b2f9c5a)), ((u64)(0x775f03542dfb8370)), ((u64)(0x779362149cbd3226)), ((u64)(0x77c83a99c3ec7eb0)), ((u64)(0x77fe494034e79e5c)), ((u64)(0x7832edc82110c2f9)), ((u64)(0x7867a93a2954f3b8)), ((u64)(0x789d9388b3aa30a5)), ((u64)(0x78d27c35704a5e67)), ((u64)(0x79071b42cc5cf601)), ((u64)(0x793ce2137f743382)), ((u64)(0x79720d4c2fa8a031)), ((u64)(0x79a6909f3b92c83d)), ((u64)(0x79dc34c70a777a4d)), ((u64)(0x7a11a0fc668aac70)), ((u64)(0x7a46093b802d578c)), ((u64)(0x7a7b8b8a6038ad6f)), ((u64)(0x7ab137367c236c65)), ((u64)(0x7ae585041b2c477f)), ((u64)(0x7b1ae64521f7595e)), ((u64)(0x7b50cfeb353a97db)), ((u64)(0x7b8503e602893dd2)), ((u64)(0x7bba44df832b8d46)), ((u64)(0x7bf06b0bb1fb384c)), ((u64)(0x7c2485ce9e7a065f)), ((u64)(0x7c59a742461887f6)), ((u64)(0x7c9008896bcf54fa)), ((u64)(0x7cc40aabc6c32a38)), ((u64)(0x7cf90d56b873f4c7)), ((u64)(0x7d2f50ac6690f1f8)), ((u64)(0x7d63926bc01a973b)), ((u64)(0x7d987706b0213d0a)), ((u64)(0x7dce94c85c298c4c)), ((u64)(0x7e031cfd3999f7b0)), ((u64)(0x7e37e43c8800759c)), ((u64)(0x7e6ddd4baa009303)), ((u64)(0x7ea2aa4f4a405be2)), ((u64)(0x7ed754e31cd072da)), ((u64)(0x7f0d2a1be4048f90)), ((u64)(0x7f423a516e82d9ba)), ((u64)(0x7f76c8e5ca239029)), ((u64)(0x7fac7b1f3cac7433)), ((u64)(0x7fe1ccf385ebc8a0))};
const u64 strconv__neg_exp[324] = {((u64)(0x3ff0000000000000)), ((u64)(0x3fb999999999999a)), ((u64)(0x3f847ae147ae147b)), ((u64)(0x3f50624dd2f1a9fc)), ((u64)(0x3f1a36e2eb1c432d)), ((u64)(0x3ee4f8b588e368f1)), ((u64)(0x3eb0c6f7a0b5ed8d)), ((u64)(0x3e7ad7f29abcaf48)), ((u64)(0x3e45798ee2308c3a)), ((u64)(0x3e112e0be826d695)), ((u64)(0x3ddb7cdfd9d7bdbb)), ((u64)(0x3da5fd7fe1796495)), ((u64)(0x3d719799812dea11)), ((u64)(0x3d3c25c268497682)), ((u64)(0x3d06849b86a12b9b)), ((u64)(0x3cd203af9ee75616)), ((u64)(0x3c9cd2b297d889bc)), ((u64)(0x3c670ef54646d497)), ((u64)(0x3c32725dd1d243ac)), ((u64)(0x3bfd83c94fb6d2ac)), ((u64)(0x3bc79ca10c924223)), ((u64)(0x3b92e3b40a0e9b4f)), ((u64)(0x3b5e392010175ee6)), ((u64)(0x3b282db34012b251)), ((u64)(0x3af357c299a88ea7)), ((u64)(0x3abef2d0f5da7dd9)), ((u64)(0x3a88c240c4aecb14)), ((u64)(0x3a53ce9a36f23c10)), ((u64)(0x3a1fb0f6be506019)), ((u64)(0x39e95a5efea6b347)), ((u64)(0x39b4484bfeebc2a0)), ((u64)(0x398039d665896880)), ((u64)(0x3949f623d5a8a733)), ((u64)(0x3914c4e977ba1f5c)), ((u64)(0x38e09d8792fb4c49)), ((u64)(0x38aa95a5b7f87a0f)), ((u64)(0x38754484932d2e72)), ((u64)(0x3841039d428a8b8f)), ((u64)(0x380b38fb9daa78e4)), ((u64)(0x37d5c72fb1552d83)), ((u64)(0x37a16c262777579c)), ((u64)(0x376be03d0bf225c7)), ((u64)(0x37364cfda3281e39)), ((u64)(0x3701d7314f534b61)), ((u64)(0x36cc8b8218854567)), ((u64)(0x3696d601ad376ab9)), ((u64)(0x366244ce242c5561)), ((u64)(0x362d3ae36d13bbce)), ((u64)(0x35f7624f8a762fd8)), ((u64)(0x35c2b50c6ec4f313)), ((u64)(0x358dee7a4ad4b81f)), ((u64)(0x3557f1fb6f10934c)), ((u64)(0x352327fc58da0f70)), ((u64)(0x34eea6608e29b24d)), ((u64)(0x34b8851a0b548ea4)), ((u64)(0x34839dae6f76d883)), ((u64)(0x344f62b0b257c0d2)), ((u64)(0x34191bc08eac9a41)), ((u64)(0x33e41633a556e1ce)), ((u64)(0x33b011c2eaabe7d8)), ((u64)(0x3379b604aaaca626)), ((u64)(0x3344919d5556eb52)), ((u64)(0x3310747ddddf22a8)), ((u64)(0x32da53fc9631d10d)), ((u64)(0x32a50ffd44f4a73d)), ((u64)(0x3270d9976a5d5297)), ((u64)(0x323af5bf109550f2)), ((u64)(0x32059165a6ddda5b)), ((u64)(0x31d1411e1f17e1e3)), ((u64)(0x319b9b6364f30304)), ((u64)(0x316615e91d8f359d)), ((u64)(0x3131ab20e472914a)), ((u64)(0x30fc45016d841baa)), ((u64)(0x30c69d9abe034955)), ((u64)(0x309217aefe690777)), ((u64)(0x305cf2b1970e7258)), ((u64)(0x3027288e1271f513)), ((u64)(0x2ff286d80ec190dc)), ((u64)(0x2fbda48ce468e7c7)), ((u64)(0x2f87b6d71d20b96c)), ((u64)(0x2f52f8ac174d6123)), ((u64)(0x2f1e5aacf2156838)), ((u64)(0x2ee8488a5b445360)), ((u64)(0x2eb36d3b7c36a91a)), ((u64)(0x2e7f152bf9f10e90)), ((u64)(0x2e48ddbcc7f40ba6)), ((u64)(0x2e13e497065cd61f)), ((u64)(0x2ddfd424d6faf031)), ((u64)(0x2da97683df2f268d)), ((u64)(0x2d745ecfe5bf520b)), ((u64)(0x2d404bd984990e6f)), ((u64)(0x2d0a12f5a0f4e3e5)), ((u64)(0x2cd4dbf7b3f71cb7)), ((u64)(0x2ca0aff95cc5b092)), ((u64)(0x2c6ab328946f80ea)), ((u64)(0x2c355c2076bf9a55)), ((u64)(0x2c0116805effaeaa)), ((u64)(0x2bcb5733cb32b111)), ((u64)(0x2b95df5ca28ef40d)), ((u64)(0x2b617f7d4ed8c33e)), ((u64)(0x2b2bff2ee48e0530)), ((u64)(0x2af665bf1d3e6a8d)), ((u64)(0x2ac1eaff4a98553d)), ((u64)(0x2a8cab3210f3bb95)), ((u64)(0x2a56ef5b40c2fc77)), ((u64)(0x2a225915cd68c9f9)), ((u64)(0x29ed5b561574765b)), ((u64)(0x29b77c44ddf6c516)), ((u64)(0x2982c9d0b1923745)), ((u64)(0x294e0fb44f50586e)), ((u64)(0x29180c903f7379f2)), ((u64)(0x28e33d4032c2c7f5)), ((u64)(0x28aec866b79e0cba)), ((u64)(0x2878a0522c7e7095)), ((u64)(0x2843b374f06526de)), ((u64)(0x280f8587e7083e30)), ((u64)(0x27d9379fec069826)), ((u64)(0x27a42c7ff0054685)), ((u64)(0x277023998cd10537)), ((u64)(0x2739d28f47b4d525)), ((u64)(0x2704a8729fc3ddb7)), ((u64)(0x26d086c219697e2c)), ((u64)(0x269a71368f0f3047)), ((u64)(0x2665275ed8d8f36c)), ((u64)(0x2630ec4be0ad8f89)), ((u64)(0x25fb13ac9aaf4c0f)), ((u64)(0x25c5a956e225d672)), ((u64)(0x2591544581b7dec2)), ((u64)(0x255bba08cf8c979d)), ((u64)(0x25262e6d72d6dfb0)), ((u64)(0x24f1bebdf578b2f4)), ((u64)(0x24bc6463225ab7ec)), ((u64)(0x2486b6b5b5155ff0)), ((u64)(0x24522bc490dde65a)), ((u64)(0x241d12d41afca3c3)), ((u64)(0x23e7424348ca1c9c)), ((u64)(0x23b29b69070816e3)), ((u64)(0x237dc574d80cf16b)), ((u64)(0x2347d12a4670c123)), ((u64)(0x23130dbb6b8d674f)), ((u64)(0x22de7c5f127bd87e)), ((u64)(0x22a8637f41fcad32)), ((u64)(0x227382cc34ca2428)), ((u64)(0x223f37ad21436d0c)), ((u64)(0x2208f9574dcf8a70)), ((u64)(0x21d3faac3e3fa1f3)), ((u64)(0x219ff779fd329cb9)), ((u64)(0x216992c7fdc216fa)), ((u64)(0x2134756ccb01abfb)), ((u64)(0x21005df0a267bcc9)), ((u64)(0x20ca2fe76a3f9475)), ((u64)(0x2094f31f8832dd2a)), ((u64)(0x2060c27fa028b0ef)), ((u64)(0x202ad0cc33744e4b)), ((u64)(0x1ff573d68f903ea2)), ((u64)(0x1fc1297872d9cbb5)), ((u64)(0x1f8b758d848fac55)), ((u64)(0x1f55f7a46a0c89dd)), ((u64)(0x1f2192e9ee706e4b)), ((u64)(0x1eec1e43171a4a11)), ((u64)(0x1eb67e9c127b6e74)), ((u64)(0x1e81fee341fc585d)), ((u64)(0x1e4ccb0536608d61)), ((u64)(0x1e1708d0f84d3de7)), ((u64)(0x1de26d73f9d764b9)), ((u64)(0x1dad7becc2f23ac2)), ((u64)(0x1d779657025b6235)), ((u64)(0x1d42deac01e2b4f7)), ((u64)(0x1d0e3113363787f2)), ((u64)(0x1cd8274291c6065b)), ((u64)(0x1ca3529ba7d19eaf)), ((u64)(0x1c6eea92a61c3118)), ((u64)(0x1c38bba884e35a7a)), ((u64)(0x1c03c9539d82aec8)), ((u64)(0x1bcfa885c8d117a6)), ((u64)(0x1b99539e3a40dfb8)), ((u64)(0x1b6442e4fb671960)), ((u64)(0x1b303583fc527ab3)), ((u64)(0x1af9ef3993b72ab8)), ((u64)(0x1ac4bf6142f8eefa)), ((u64)(0x1a90991a9bfa58c8)), ((u64)(0x1a5a8e90f9908e0d)), ((u64)(0x1a253eda614071a4)), ((u64)(0x19f0ff151a99f483)), ((u64)(0x19bb31bb5dc320d2)), ((u64)(0x1985c162b168e70e)), ((u64)(0x1951678227871f3e)), ((u64)(0x191bd8d03f3e9864)), ((u64)(0x18e6470cff6546b6)), ((u64)(0x18b1d270cc51055f)), ((u64)(0x187c83e7ad4e6efe)), ((u64)(0x1846cfec8aa52598)), ((u64)(0x18123ff06eea847a)), ((u64)(0x17dd331a4b10d3f6)), ((u64)(0x17a75c1508da432b)), ((u64)(0x1772b010d3e1cf56)), ((u64)(0x173de6815302e556)), ((u64)(0x1707eb9aa8cf1dde)), ((u64)(0x16d322e220a5b17e)), ((u64)(0x169e9e369aa2b597)), ((u64)(0x16687e92154ef7ac)), ((u64)(0x16339874ddd8c623)), ((u64)(0x15ff5a549627a36c)), ((u64)(0x15c91510781fb5f0)), ((u64)(0x159410d9f9b2f7f3)), ((u64)(0x15600d7b2e28c65c)), ((u64)(0x1529af2b7d0e0a2d)), ((u64)(0x14f48c22ca71a1bd)), ((u64)(0x14c0701bd527b498)), ((u64)(0x148a4cf9550c5426)), ((u64)(0x14550a6110d6a9b8)), ((u64)(0x1420d51a73deee2d)), ((u64)(0x13eaee90b964b047)), ((u64)(0x13b58ba6fab6f36c)), ((u64)(0x13813c85955f2923)), ((u64)(0x134b9408eefea839)), ((u64)(0x1316100725988694)), ((u64)(0x12e1a66c1e139edd)), ((u64)(0x12ac3d79c9b8fe2e)), ((u64)(0x12769794a160cb58)), ((u64)(0x124212dd4de70913)), ((u64)(0x120ceafbafd80e85)), ((u64)(0x11d72262f3133ed1)), ((u64)(0x11a281e8c275cbda)), ((u64)(0x116d9ca79d89462a)), ((u64)(0x1137b08617a104ee)), ((u64)(0x1102f39e794d9d8b)), ((u64)(0x10ce5297287c2f45)), ((u64)(0x1098421286c9bf6b)), ((u64)(0x1063680ed23aff89)), ((u64)(0x102f0ce4839198db)), ((u64)(0x0ff8d71d360e13e2)), ((u64)(0x0fc3df4a91a4dcb5)), ((u64)(0x0f8fcbaa82a16121)), ((u64)(0x0f596fbb9bb44db4)), ((u64)(0x0f245962e2f6a490)), ((u64)(0x0ef047824f2bb6da)), ((u64)(0x0eba0c03b1df8af6)), ((u64)(0x0e84d6695b193bf8)), ((u64)(0x0e50ab877c142ffa)), ((u64)(0x0e1aac0bf9b9e65c)), ((u64)(0x0de5566ffafb1eb0)), ((u64)(0x0db111f32f2f4bc0)), ((u64)(0x0d7b4feb7eb212cd)), ((u64)(0x0d45d98932280f0a)), ((u64)(0x0d117ad428200c08)), ((u64)(0x0cdbf7b9d9cce00d)), ((u64)(0x0ca65fc7e170b33e)), ((u64)(0x0c71e6398126f5cb)), ((u64)(0x0c3ca38f350b22df)), ((u64)(0x0c06e93f5da2824c)), ((u64)(0x0bd25432b14ecea3)), ((u64)(0x0b9d53844ee47dd1)), ((u64)(0x0b677603725064a8)), ((u64)(0x0b32c4cf8ea6b6ec)), ((u64)(0x0afe07b27dd78b14)), ((u64)(0x0ac8062864ac6f43)), ((u64)(0x0a9338205089f29c)), ((u64)(0x0a5ec033b40fea93)), ((u64)(0x0a2899c2f6732210)), ((u64)(0x09f3ae3591f5b4d9)), ((u64)(0x09bf7d228322baf5)), ((u64)(0x098930e868e89591)), ((u64)(0x0954272053ed4474)), ((u64)(0x09201f4d0ff10390)), ((u64)(0x08e9cbae7fe805b3)), ((u64)(0x08b4a2f1ffecd15c)), ((u64)(0x0880825b3323dab0)), ((u64)(0x084a6a2b85062ab3)), ((u64)(0x081521bc6a6b555c)), ((u64)(0x07e0e7c9eebc444a)), ((u64)(0x07ab0c764ac6d3a9)), ((u64)(0x0775a391d56bdc87)), ((u64)(0x07414fa7ddefe3a0)), ((u64)(0x070bb2a62fe638ff)), ((u64)(0x06d62884f31e93ff)), ((u64)(0x06a1ba03f5b21000)), ((u64)(0x066c5cd322b67fff)), ((u64)(0x0636b0a8e891ffff)), ((u64)(0x060226ed86db3333)), ((u64)(0x05cd0b15a491eb84)), ((u64)(0x05973c115074bc6a)), ((u64)(0x05629674405d6388)), ((u64)(0x052dbd86cd6238d9)), ((u64)(0x04f7cad23de82d7b)), ((u64)(0x04c308a831868ac9)), ((u64)(0x048e74404f3daadb)), ((u64)(0x04585d003f6488af)), ((u64)(0x04237d99cc506d59)), ((u64)(0x03ef2f5c7a1a488e)), ((u64)(0x03b8f2b061aea072)), ((u64)(0x0383f559e7bee6c1)), ((u64)(0x034feef63f97d79c)), ((u64)(0x03198bf832dfdfb0)), ((u64)(0x02e46ff9c24cb2f3)), ((u64)(0x02b059949b708f29)), ((u64)(0x027a28edc580e50e)), ((u64)(0x0244ed8b04671da5)), ((u64)(0x0210be08d0527e1d)), ((u64)(0x01dac9a7b3b7302f)), ((u64)(0x01a56e1fc2f8f359)), ((u64)(0x017124e63593f5e1)), ((u64)(0x013b6e3d22865634)), ((u64)(0x0105f1ca820511c3)), ((u64)(0x00d18e3b9b374169)), ((u64)(0x009c16c5c5253575)), ((u64)(0x0066789e3750f791)), ((u64)(0x0031fa182c40c60d)), ((u64)(0x000730d67819e8d2)), ((u64)(0x0000b8157268fdaf)), ((u64)(0x000012688b70e62b)), ((u64)(0x000001d74124e3d1)), ((u64)(0x0000002f201d49fb)), ((u64)(0x00000004b6695433)), ((u64)(0x0000000078a42205)), ((u64)(0x000000000c1069cd)), ((u64)(0x000000000134d761)), ((u64)(0x00000000001ee257)), ((u64)(0x00000000000316a2)), ((u64)(0x0000000000004f10)), ((u64)(0x00000000000007e8)), ((u64)(0x00000000000000ca)), ((u64)(0x0000000000000014)), ((u64)(0x0000000000000002))};
const u32 strconv__ten_pow_table_32[10] = {((u32)(1)), ((u32)(10)), ((u32)(100)), ((u32)(1000)), ((u32)(10000)), ((u32)(100000)), ((u32)(1000000)), ((u32)(10000000)), ((u32)(100000000)), ((u32)(1000000000))};
#define strconv__mantbits32 (((u32)(23)))
#define strconv__expbits32 (((u32)(8)))
#define strconv__bias32 (127)
#define strconv__maxexp32 (255)
#define strconv__max_size_f64_char (512)
string strconv__digit_pairs = (string){"00102030405060708090011121314151617181910212223242526272829203132333435363738393041424344454647484940515253545556575859506162636465666768696071727374757677787970818283848586878889809192939495969798999", 200, 1};
string strconv__base_digits = (string){"0123456789abcdefghijklmnopqrstuvwxyz", 36, 1};
#define builtin__autostr_type_stack_max_depth (64)
MessageError builtin__error_sentinel__object = {.msg = {"error", 5, 1}};
IError builtin__error_sentinel = {._typ = 71273906, ._object = &builtin__error_sentinel__object};
IError builtin__none__;
string builtin__grapheme_control_ranges = (string){"00000000090000000b0000000c0000000e0000001f0000007f0000009f000000ad000000ad0000001c0600001c0600000e1800000e1800000b2000000b2000000e2000000f200000282000002820000029200000292000002a2000002e20000060200000642000006520000065200000662000006f200000fffe0000fffe0000f0ff0000f8ff0000f9ff0000fbff00003034010038340100a0bc0100a3bc010073d101007ad1010000000e0000000e0001000e0001000e0002000e001f000e0080000e00ff000e00f0010e00ff0f0e00", 416, 1};
string builtin__grapheme_extend_ranges = (string){"000300006f0300008304000087040000880400008904000091050000bd050000bf050000bf050000c1050000c2050000c4050000c5050000c7050000c7050000100600001a0600004b0600005f0600007006000070060000d6060000dc060000df060000e4060000e7060000e8060000ea060000ed0600001107000011070000300700004a070000a6070000b0070000eb070000f3070000fd070000fd07000016080000190800001b080000230800002508000027080000290800002d080000590800005b080000d3080000e1080000e3080000020900003a0900003a0900003c0900003c09000041090000480900004d0900004d090000510900005709000062090000630900008109000081090000bc090000bc090000be090000be090000c1090000c4090000cd090000cd090000d7090000d7090000e2090000e3090000fe090000fe090000010a0000020a00003c0a00003c0a0000410a0000420a0000470a0000480a00004b0a00004d0a0000510a0000510a0000700a0000710a0000750a0000750a0000810a0000820a0000bc0a0000bc0a0000c10a0000c50a0000c70a0000c80a0000cd0a0000cd0a0000e20a0000e30a0000fa0a0000ff0a0000010b0000010b00003c0b00003c0b00003e0b00003e0b00003f0b00003f0b0000410b0000440b00004d0b00004d0b0000550b0000560b0000570b0000570b0000620b0000630b0000820b0000820b0000be0b0000be0b0000c00b0000c00b0000cd0b0000cd0b0000d70b0000d70b0000000c0000000c0000040c0000040c00003e0c0000400c0000460c0000480c00004a0c00004d0c0000550c0000560c0000620c0000630c0000810c0000810c0000bc0c0000bc0c0000bf0c0000bf0c0000c20c0000c20c0000c60c0000c60c0000cc0c0000cd0c0000d50c0000d60c0000e20c0000e30c0000000d0000010d00003b0d00003c0d00003e0d00003e0d0000410d0000440d00004d0d00004d0d0000570d0000570d0000620d0000630d0000810d0000810d0000ca0d0000ca0d0000cf0d0000cf0d0000d20d0000d40d0000d60d0000d60d0000df0d0000df0d0000310e0000310e0000340e00003a0e0000470e00004e0e0000b10e0000b10e0000b40e0000bc0e0000c80e0000cd0e0000180f0000190f0000350f0000350f0000370f0000370f0000390f0000390f0000710f00007e0f0000800f0000840f0000860f0000870f00008d0f0000970f0000990f0000bc0f0000c60f0000c60f00002d100000301000003210000037100000391000003a1000003d1000003e10000058100000591000005e100000601000007110000074100000821000008210000085100000861000008d1000008d1000009d1000009d1000005d1300005f1300001217000014170000321700003417000052170000531700007217000073170000b4170000b5170000b7170000bd170000c6170000c6170000c9170000d3170000dd170000dd1700000b1800000d1800008518000086180000a9180000a9180000201900002219000027190000281900003219000032190000391900003b190000171a0000181a00001b1a00001b1a0000561a0000561a0000581a00005e1a0000601a0000601a0000621a0000621a0000651a00006c1a0000731a00007c1a00007f1a00007f1a0000b01a0000bd1a0000be1a0000be1a0000bf1a0000c01a0000001b0000031b0000341b0000341b0000351b0000351b0000361b00003a1b00003c1b00003c1b0000421b0000421b00006b1b0000731b0000801b0000811b0000a21b0000a51b0000a81b0000a91b0000ab1b0000ad1b0000e61b0000e61b0000e81b0000e91b0000ed1b0000ed1b0000ef1b0000f11b00002c1c0000331c0000361c0000371c0000d01c0000d21c0000d41c0000e01c0000e21c0000e81c0000ed1c0000ed1c0000f41c0000f41c0000f81c0000f91c0000c01d0000f91d0000fb1d0000ff1d00000c2000000c200000d0200000dc200000dd200000e0200000e1200000e1200000e2200000e4200000e5200000f0200000ef2c0000f12c00007f2d00007f2d0000e02d0000ff2d00002a3000002d3000002e3000002f300000993000009a3000006fa600006fa6000070a6000072a6000074a600007da600009ea600009fa60000f0a60000f1a6000002a8000002a8000006a8000006a800000ba800000ba8000025a8000026a800002ca800002ca80000c4a80000c5a80000e0a80000f1a80000ffa80000ffa8000026a900002da9000047a9000051a9000080a9000082a90000b3a90000b3a90000b6a90000b9a90000bca90000bda90000e5a90000e5a9000029aa00002eaa000031aa000032aa000035aa000036aa000043aa000043aa00004caa00004caa00007caa00007caa0000b0aa0000b0aa0000b2aa0000b4aa0000b7aa0000b8aa0000beaa0000bfaa0000c1aa0000c1aa0000ecaa0000edaa0000f6aa0000f6aa0000e5ab0000e5ab0000e8ab0000e8ab0000edab0000edab00001efb00001efb000000fe00000ffe000020fe00002ffe00009eff00009fff0000fd010100fd010100e0020100e0020100760301007a030100010a0100030a0100050a0100060a01000c0a01000f0a0100380a01003a0a01003f0a01003f0a0100e50a0100e60a0100240d0100270d0100ab0e0100ac0e0100460f0100500f0100011001000110010038100100461001007f10010081100100b3100100b6100100b9100100ba1001000011010002110100271101002b1101002d1101003411010073110100731101008011010081110100b6110100be110100c9110100cc110100cf110100cf1101002f12010031120100341201003412010036120100371201003e1201003e120100df120100df120100e3120100ea12010000130100011301003b1301003c1301003e1301003e13010040130100401301005713010057130100661301006c1301007013010074130100381401003f140100421401004414010046140100461401005e1401005e140100b0140100b0140100b3140100b8140100ba140100ba140100bd140100bd140100bf140100c0140100c2140100c3140100af150100af150100b2150100b5150100bc150100bd150100bf150100c0150100dc150100dd150100331601003a1601003d1601003d1601003f16010040160100ab160100ab160100ad160100ad160100b0160100b5160100b7160100b71601001d1701001f1701002217010025170100271701002b1701002f18010037180100391801003a18010030190100301901003b1901003c1901003e1901003e1901004319010043190100d4190100d7190100da190100db190100e0190100e0190100011a01000a1a0100331a0100381a01003b1a01003e1a0100471a0100471a0100511a0100561a0100591a01005b1a01008a1a0100961a0100981a0100991a0100301c0100361c0100381c01003d1c01003f1c01003f1c0100921c0100a71c0100aa1c0100b01c0100b21c0100b31c0100b51c0100b61c0100311d0100361d01003a1d01003a1d01003c1d01003d1d01003f1d0100451d0100471d0100471d0100901d0100911d0100951d0100951d0100971d0100971d0100f31e0100f41e0100f06a0100f46a0100306b0100366b01004f6f01004f6f01008f6f0100926f0100e46f0100e46f01009dbc01009ebc010065d1010065d1010067d1010069d101006ed1010072d101007bd1010082d1010085d101008bd10100aad10100add1010042d2010044d2010000da010036da01003bda01006cda010075da010075da010084da010084da01009bda01009fda0100a1da0100afda010000e0010006e0010008e0010018e001001be0010021e0010023e0010024e0010026e001002ae0010030e1010036e10100ece20100efe20100d0e80100d6e8010044e901004ae90100fbf30100fff3010020000e007f000e0000010e00ef010e00", 5728, 1};
string builtin__grapheme_spacing_mark_ranges = (string){"03090000030900003b0900003b0900003e09000040090000490900004c0900004e0900004f0900008209000083090000bf090000c0090000c7090000c8090000cb090000cc090000030a0000030a00003e0a0000400a0000830a0000830a0000be0a0000c00a0000c90a0000c90a0000cb0a0000cc0a0000020b0000030b0000400b0000400b0000470b0000480b00004b0b00004c0b0000bf0b0000bf0b0000c10b0000c20b0000c60b0000c80b0000ca0b0000cc0b0000010c0000030c0000410c0000440c0000820c0000830c0000be0c0000be0c0000c00c0000c10c0000c30c0000c40c0000c70c0000c80c0000ca0c0000cb0c0000020d0000030d00003f0d0000400d0000460d0000480d00004a0d00004c0d0000820d0000830d0000d00d0000d10d0000d80d0000de0d0000f20d0000f30d0000330e0000330e0000b30e0000b30e00003e0f00003f0f00007f0f00007f0f000031100000311000003b1000003c10000056100000571000008410000084100000b6170000b6170000be170000c5170000c7170000c81700002319000026190000291900002b19000030190000311900003319000038190000191a00001a1a0000551a0000551a0000571a0000571a00006d1a0000721a0000041b0000041b00003b1b00003b1b00003d1b0000411b0000431b0000441b0000821b0000821b0000a11b0000a11b0000a61b0000a71b0000aa1b0000aa1b0000e71b0000e71b0000ea1b0000ec1b0000ee1b0000ee1b0000f21b0000f31b0000241c00002b1c0000341c0000351c0000e11c0000e11c0000f71c0000f71c000023a8000024a8000027a8000027a8000080a8000081a80000b4a80000c3a8000052a9000053a9000083a9000083a90000b4a90000b5a90000baa90000bba90000bea90000c0a900002faa000030aa000033aa000034aa00004daa00004daa0000ebaa0000ebaa0000eeaa0000efaa0000f5aa0000f5aa0000e3ab0000e4ab0000e6ab0000e7ab0000e9ab0000eaab0000ecab0000ecab0000001001000010010002100100021001008210010082100100b0100100b2100100b7100100b81001002c1101002c11010045110100461101008211010082110100b3110100b5110100bf110100c0110100ce110100ce1101002c1201002e12010032120100331201003512010035120100e0120100e212010002130100031301003f1301003f130100411301004413010047130100481301004b1301004d1301006213010063130100351401003714010040140100411401004514010045140100b1140100b2140100b9140100b9140100bb140100bc140100be140100be140100c1140100c1140100b0150100b1150100b8150100bb150100be150100be15010030160100321601003b1601003c1601003e1601003e160100ac160100ac160100ae160100af160100b6160100b6160100201701002117010026170100261701002c1801002e1801003818010038180100311901003519010037190100381901003d1901003d19010040190100401901004219010042190100d1190100d3190100dc190100df190100e4190100e4190100391a0100391a0100571a0100581a0100971a0100971a01002f1c01002f1c01003e1c01003e1c0100a91c0100a91c0100b11c0100b11c0100b41c0100b41c01008a1d01008e1d0100931d0100941d0100961d0100961d0100f51e0100f61e0100516f0100876f0100f06f0100f16f010066d1010066d101006dd101006dd10100", 2544, 1};
string builtin__grapheme_prepend_ranges = (string){"0006000005060000dd060000dd0600000f0700000f070000e2080000e20800004e0d00004e0d0000bd100100bd100100cd100100cd100100c2110100c31101003f1901003f19010041190100411901003a1a01003a1a0100841a0100891a0100461d0100461d0100", 208, 1};
string builtin__grapheme_extended_pictographic_ranges = (string){"a9000000a9000000ae000000ae0000003c2000003c2000004920000049200000222100002221000039210000392100009421000099210000a9210000aa2100001a2300001b23000028230000282300008823000088230000cf230000cf230000e9230000ec230000ed230000ee230000ef230000ef230000f0230000f0230000f1230000f2230000f3230000f3230000f8230000fa230000c2240000c2240000aa250000ab250000b6250000b6250000c0250000c0250000fb250000fe2500000026000001260000022600000326000004260000042600000526000005260000072600000d2600000e2600000e2600000f2600001026000011260000112600001226000012260000142600001526000016260000172600001826000018260000192600001c2600001d2600001d2600001e2600001f2600002026000020260000212600002126000022260000232600002426000025260000262600002626000027260000292600002a2600002a2600002b2600002d2600002e2600002e2600002f2600002f260000302600003726000038260000392600003a2600003a2600003b2600003f26000040260000402600004126000041260000422600004226000043260000472600004826000053260000542600005e2600005f2600005f2600006026000060260000612600006226000063260000632600006426000064260000652600006626000067260000672600006826000068260000692600007a2600007b2600007b2600007c2600007d2600007e2600007e2600007f2600007f2600008026000085260000902600009126000092260000922600009326000093260000942600009426000095260000952600009626000097260000982600009826000099260000992600009a2600009a2600009b2600009c2600009d2600009f260000a0260000a1260000a2260000a6260000a7260000a7260000a8260000a9260000aa260000ab260000ac260000af260000b0260000b1260000b2260000bc260000bd260000be260000bf260000c3260000c4260000c5260000c6260000c7260000c8260000c8260000c9260000cd260000ce260000ce260000cf260000cf260000d0260000d0260000d1260000d1260000d2260000d2260000d3260000d3260000d4260000d4260000d5260000e8260000e9260000e9260000ea260000ea260000eb260000ef260000f0260000f1260000f2260000f3260000f4260000f4260000f5260000f5260000f6260000f6260000f7260000f9260000fa260000fa260000fb260000fc260000fd260000fd260000fe26000001270000022700000227000003270000042700000527000005270000082700000c2700000d2700000d2700000e2700000e2700000f2700000f27000010270000112700001227000012270000142700001427000016270000162700001d2700001d270000212700002127000028270000282700003327000034270000442700004427000047270000472700004c2700004c2700004e2700004e270000532700005527000057270000572700006327000063270000642700006427000065270000672700009527000097270000a1270000a1270000b0270000b0270000bf270000bf2700003429000035290000052b0000072b00001b2b00001c2b0000502b0000502b0000552b0000552b000030300000303000003d3000003d3000009732000097320000993200009932000000f0010003f0010004f0010004f0010005f00100cef00100cff00100cff00100d0f00100fff001000df101000ff101002ff101002ff101006cf101006ff1010070f1010071f101007ef101007ff101008ef101008ef1010091f101009af10100adf10100e5f1010001f2010002f2010003f201000ff201001af201001af201002ff201002ff2010032f201003af201003cf201003ff2010049f201004ff2010050f2010051f2010052f20100fff2010000f301000cf301000df301000ef301000ff301000ff3010010f3010010f3010011f3010011f3010012f3010012f3010013f3010015f3010016f3010018f3010019f3010019f301001af301001af301001bf301001bf301001cf301001cf301001df301001ef301001ff3010020f3010021f3010021f3010022f3010023f3010024f301002cf301002df301002ff3010030f3010031f3010032f3010033f3010034f3010035f3010036f3010036f3010037f301004af301004bf301004bf301004cf301004ff3010050f3010050f3010051f301007bf301007cf301007cf301007df301007df301007ef301007ff3010080f3010093f3010094f3010095f3010096f3010097f3010098f3010098f3010099f301009bf301009cf301009df301009ef301009ff30100a0f30100c4f30100c5f30100c5f30100c6f30100c6f30100c7f30100c7f30100c8f30100c8f30100c9f30100c9f30100caf30100caf30100cbf30100cef30100cff30100d3f30100d4f30100dff30100e0f30100e3f30100e4f30100e4f30100e5f30100f0f30100f1f30100f2f30100f3f30100f3f30100f4f30100f4f30100f5f30100f5f30100f6f30100f6f30100f7f30100f7f30100f8f30100faf3010000f4010007f4010008f4010008f4010009f401000bf401000cf401000ef401000ff4010010f4010011f4010012f4010013f4010013f4010014f4010014f4010015f4010015f4010016f4010016f4010017f4010029f401002af401002af401002bf401003ef401003ff401003ff4010040f4010040f4010041f4010041f4010042f4010064f4010065f4010065f4010066f401006bf401006cf401006df401006ef40100acf40100adf40100adf40100aef40100b5f40100b6f40100b7f40100b8f40100ebf40100ecf40100edf40100eef40100eef40100eff40100eff40100f0f40100f4f40100f5f40100f5f40100f6f40100f7f40100f8f40100f8f40100f9f40100fcf40100fdf40100fdf40100fef40100fef40100fff4010002f5010003f5010003f5010004f5010007f5010008f5010008f5010009f5010009f501000af5010014f5010015f5010015f5010016f501002bf501002cf501002df501002ef501003df5010046f5010048f5010049f501004af501004bf501004ef501004ff501004ff5010050f501005bf501005cf5010067f5010068f501006ef501006ff5010070f5010071f5010072f5010073f5010079f501007af501007af501007bf5010086f5010087f5010087f5010088f5010089f501008af501008df501008ef501008ff5010090f5010090f5010091f5010094f5010095f5010096f5010097f50100a3f50100a4f50100a4f50100a5f50100a5f50100a6f50100a7f50100a8f50100a8f50100a9f50100b0f50100b1f50100b2f50100b3f50100bbf50100bcf50100bcf50100bdf50100c1f50100c2f50100c4f50100c5f50100d0f50100d1f50100d3f50100d4f50100dbf50100dcf50100def50100dff50100e0f50100e1f50100e1f50100e2f50100e2f50100e3f50100e3f50100e4f50100e7f50100e8f50100e8f50100e9f50100eef50100eff50100eff50100f0f50100f2f50100f3f50100f3f50100f4f50100f9f50100faf50100faf50100fbf50100fff5010000f6010000f6010001f6010006f6010007f6010008f6010009f601000df601000ef601000ef601000ff601000ff6010010f6010010f6010011f6010011f6010012f6010014f6010015f6010015f6010016f6010016f6010017f6010017f6010018f6010018f6010019f6010019f601001af601001af601001bf601001bf601001cf601001ef601001ff601001ff6010020f6010025f6010026f6010027f6010028f601002bf601002cf601002cf601002df601002df601002ef601002ff6010030f6010033f6010034f6010034f6010035f6010035f6010036f6010036f6010037f6010040f6010041f6010044f6010045f601004ff6010080f6010080f6010081f6010082f6010083f6010085f6010086f6010086f6010087f6010087f6010088f6010088f6010089f6010089f601008af601008bf601008cf601008cf601008df601008df601008ef601008ef601008ff601008ff6010090f6010090f6010091f6010093f6010094f6010094f6010095f6010095f6010096f6010096f6010097f6010097f6010098f6010098f6010099f601009af601009bf60100a1f60100a2f60100a2f60100a3f60100a3f60100a4f60100a5f60100a6f60100a6f60100a7f60100adf60100aef60100b1f60100b2f60100b2f60100b3f60100b5f60100b6f60100b6f60100b7f60100b8f60100b9f60100bef60100bff60100bff60100c0f60100c0f60100c1f60100c5f60100c6f60100caf60100cbf60100cbf60100ccf60100ccf60100cdf60100cff60100d0f60100d0f60100d1f60100d2f60100d3f60100d4f60100d5f60100d5f60100d6f60100d7f60100d8f60100dff60100e0f60100e5f60100e6f60100e8f60100e9f60100e9f60100eaf60100eaf60100ebf60100ecf60100edf60100eff60100f0f60100f0f60100f1f60100f2f60100f3f60100f3f60100f4f60100f6f60100f7f60100f8f60100f9f60100f9f60100faf60100faf60100fbf60100fcf60100fdf60100fff6010074f701007ff70100d5f70100dff70100e0f70100ebf70100ecf70100fff701000cf801000ff8010048f801004ff801005af801005ff8010088f801008ff80100aef80100fff801000cf901000cf901000df901000ff9010010f9010018f9010019f901001ef901001ff901001ff9010020f9010027f9010028f901002ff9010030f9010030f9010031f9010032f9010033f901003af901003cf901003ef901003ff901003ff9010040f9010045f9010047f901004bf901004cf901004cf901004df901004ff9010050f901005ef901005ff901006bf901006cf9010070f9010071f9010071f9010072f9010072f9010073f9010076f9010077f9010078f9010079f9010079f901007af901007af901007bf901007bf901007cf901007ff9010080f9010084f9010085f9010091f9010092f9010097f9010098f90100a2f90100a3f90100a4f90100a5f90100aaf90100abf90100adf90100aef90100aff90100b0f90100b9f90100baf90100bff90100c0f90100c0f90100c1f90100c2f90100c3f90100caf90100cbf90100cbf90100ccf90100ccf90100cdf90100cff90100d0f90100e6f90100e7f90100fff9010000fa01006ffa010070fa010073fa010074fa010074fa010075fa010077fa010078fa01007afa01007bfa01007ffa010080fa010082fa010083fa010086fa010087fa01008ffa010090fa010095fa010096fa0100a8fa0100a9fa0100affa0100b0fa0100b6fa0100b7fa0100bffa0100c0fa0100c2fa0100c3fa0100cffa0100d0fa0100d6fa0100d7fa0100fffa010000fc0100fdff0100", 7856, 1};
string builtin__digit_pairs = (string){"00102030405060708090011121314151617181910212223242526272829203132333435363738393041424344454647484940515253545556575859506162636465666768696071727374757677787970818283848586878889809192939495969798999", 200, 1};
#define builtin__min_i8 (((i8)(-(128))))
#define builtin__max_i8 (((i8)(127)))
#define builtin__min_i16 (((i16)(-(32768))))
#define builtin__max_i16 (((i16)(32767)))
#define builtin__min_i32 (((i32)(-(2147483648))))
#define builtin__max_i32 (((i32)(2147483647)))
#define builtin__min_i64 (((i64)((-(9223372036854775807)) - (1))))
#define builtin__max_i64 (((i64)(9223372036854775807)))
#define builtin__min_int (((i64)(((i64)((-(9223372036854775807)) - (1))))))
#define builtin__max_int (((i64)(((i64)(9223372036854775807)))))
static const u8 builtin__min_u8 = ((u8)(0));
static const u8 builtin__max_u8 = ((u8)(255));
#define builtin__min_u16 (((u16)(0)))
#define builtin__max_u16 (((u16)(65535)))
#define builtin__min_u32 (((u32)(0)))
#define builtin__max_u32 (((u32)(4294967295)))
#define builtin__min_u64 (((u64)(0)))
#define builtin__max_u64 (((u64)(18446744073709551615)))
#define builtin__hashbits (24)
#define builtin__max_cached_hashbits (16)
#define builtin__init_log_capicity (5)
#define builtin__init_capicity ((1) << (5))
#define builtin__max_load_factor (0.8)
#define builtin__init_even_index (((1) << (5)) - (2))
#define builtin__extra_metas_inc (4)
#define builtin__hash_mask (((u32)(0x00FFFFFF)))
#define builtin__probe_inc (((u32)(0x01000000)))
#define builtin__rune_maps_columns_in_row (4)
#define builtin__rune_maps_ul (-(3))
#define builtin__rune_maps_utl (-(2))
const i32 builtin__rune_maps[1264] = {((i32)(0xB5)), 0xB5, 743, 0, 0xC0, 0xD6, 0, 32, 0xD8, 0xDE, 0, 32, 0xE0, 0xF6, -(32), 0, 0xF8, 0xFE, -(32), 0, 0xFF, 0xFF, 121, 0, 0x100, 0x12F, -(3), -(3), 0x130, 0x130, 0, -(199), 0x131, 0x131, -(232), 0, 0x132, 0x137, -(3), -(3), 0x139, 0x148, -(3), -(3), 0x14A, 0x177, -(3), -(3), 0x178, 0x178, 0, -(121), 0x179, 0x17E, -(3), -(3), 0x17F, 0x17F, -(300), 0, 0x180, 0x180, 195, 0, 0x181, 0x181, 0, 210, 0x182, 0x185, -(3), -(3), 0x186, 0x186, 0, 206, 0x187, 0x188, -(3), -(3), 0x189, 0x18A, 0, 205, 0x18B, 0x18C, -(3), -(3), 0x18E, 0x18E, 0, 79, 0x18F, 0x18F, 0, 202, 0x190, 0x190, 0, 203, 0x191, 0x192, -(3), -(3), 0x193, 0x193, 0, 205, 0x194, 0x194, 0, 207, 0x195, 0x195, 97, 0, 0x196, 0x196, 0, 211, 0x197, 0x197, 0, 209, 0x198, 0x199, -(3), -(3), 0x19A, 0x19A, 163, 0, 0x19C, 0x19C, 0, 211, 0x19D, 0x19D, 0, 213, 0x19E, 0x19E, 130, 0, 0x19F, 0x19F, 0, 214, 0x1A0, 0x1A5, -(3), -(3), 0x1A6, 0x1A6, 0, 218, 0x1A7, 0x1A8, -(3), -(3), 0x1A9, 0x1A9, 0, 218, 0x1AC, 0x1AD, -(3), -(3), 0x1AE, 0x1AE, 0, 218, 0x1AF, 0x1B0, -(3), -(3), 0x1B1, 0x1B2, 0, 217, 0x1B3, 0x1B6, -(3), -(3), 0x1B7, 0x1B7, 0, 219, 0x1B8, 0x1B9, -(3), -(3), 0x1BC, 0x1BD, -(3), -(3), 0x1BF, 0x1BF, 56, 0, 0x1C4, 0x1CC, -(2), -(2), 0x1CD, 0x1DC, -(3), -(3), 0x1DD, 0x1DD, -(79), 0, 0x1DE, 0x1EF, -(3), -(3), 0x1F1, 0x1F3, -(2), -(2), 0x1F4, 0x1F5, -(3), -(3), 0x1F6, 0x1F6, 0, -(97), 0x1F7, 0x1F7, 0, -(56), 0x1F8, 0x21F, -(3), -(3), 0x220, 0x220, 0, -(130), 0x222, 0x233, -(3), -(3), 0x23A, 0x23A, 0, 10795, 0x23B, 0x23C, -(3), -(3), 0x23D, 0x23D, 0, -(163), 0x23E, 0x23E, 0, 10792, 0x23F, 0x240, 10815, 0, 0x241, 0x242, -(3), -(3), 0x243, 0x243, 0, -(195), 0x244, 0x244, 0, 69, 0x245, 0x245, 0, 71, 0x246, 0x24F, -(3), -(3), 0x250, 0x250, 10783, 0, 0x251, 0x251, 10780, 0, 0x252, 0x252, 10782, 0, 0x253, 0x253, -(210), 0, 0x254, 0x254, -(206), 0, 0x256, 0x257, -(205), 0, 0x259, 0x259, -(202), 0, 0x25B, 0x25B, -(203), 0, 0x25C, 0x25C, 42319, 0, 0x260, 0x260, -(205), 0, 0x261, 0x261, 42315, 0, 0x263, 0x263, -(207), 0, 0x265, 0x265, 42280, 0, 0x266, 0x266, 42308, 0, 0x268, 0x268, -(209), 0, 0x269, 0x269, -(211), 0, 0x26A, 0x26A, 42308, 0, 0x26B, 0x26B, 10743, 0, 0x26C, 0x26C, 42305, 0, 0x26F, 0x26F, -(211), 0, 0x271, 0x271, 10749, 0, 0x272, 0x272, -(213), 0, 0x275, 0x275, -(214), 0, 0x27D, 0x27D, 10727, 0, 0x280, 0x280, -(218), 0, 0x282, 0x282, 42307, 0, 0x283, 0x283, -(218), 0, 0x287, 0x287, 42282, 0, 0x288, 0x288, -(218), 0, 0x289, 0x289, -(69), 0, 0x28A, 0x28B, -(217), 0, 0x28C, 0x28C, -(71), 0, 0x292, 0x292, -(219), 0, 0x29D, 0x29D, 42261, 0, 0x29E, 0x29E, 42258, 0, 0x345, 0x345, 84, 0, 0x370, 0x373, -(3), -(3), 0x376, 0x377, -(3), -(3), 0x37B, 0x37D, 130, 0, 0x37F, 0x37F, 0, 116, 0x386, 0x386, 0, 38, 0x388, 0x38A, 0, 37, 0x38C, 0x38C, 0, 64, 0x38E, 0x38F, 0, 63, 0x391, 0x3A1, 0, 32, 0x3A3, 0x3AB, 0, 32, 0x3AC, 0x3AC, -(38), 0, 0x3AD, 0x3AF, -(37), 0, 0x3B1, 0x3C1, -(32), 0, 0x3C2, 0x3C2, -(31), 0, 0x3C3, 0x3CB, -(32), 0, 0x3CC, 0x3CC, -(64), 0, 0x3CD, 0x3CE, -(63), 0, 0x3CF, 0x3CF, 0, 8, 0x3D0, 0x3D0, -(62), 0, 0x3D1, 0x3D1, -(57), 0, 0x3D5, 0x3D5, -(47), 0, 0x3D6, 0x3D6, -(54), 0, 0x3D7, 0x3D7, -(8), 0, 0x3D8, 0x3EF, -(3), -(3), 0x3F0, 0x3F0, -(86), 0, 0x3F1, 0x3F1, -(80), 0, 0x3F2, 0x3F2, 7, 0, 0x3F3, 0x3F3, -(116), 0, 0x3F4, 0x3F4, 0, -(60), 0x3F5, 0x3F5, -(96), 0, 0x3F7, 0x3F8, -(3), -(3), 0x3F9, 0x3F9, 0, -(7), 0x3FA, 0x3FB, -(3), -(3), 0x3FD, 0x3FF, 0, -(130), 0x400, 0x40F, 0, 80, 0x410, 0x42F, 0, 32, 0x430, 0x44F, -(32), 0, 0x450, 0x45F, -(80), 0, 0x460, 0x481, -(3), -(3), 0x48A, 0x4BF, -(3), -(3), 0x4C0, 0x4C0, 0, 15, 0x4C1, 0x4CE, -(3), -(3), 0x4CF, 0x4CF, -(15), 0, 0x4D0, 0x52F, -(3), -(3), 0x531, 0x556, 0, 48, 0x561, 0x586, -(48), 0, 0x10A0, 0x10C5, 0, 7264, 0x10C7, 0x10C7, 0, 7264, 0x10CD, 0x10CD, 0, 7264, 0x10D0, 0x10FA, 3008, 0, 0x10FD, 0x10FF, 3008, 0, 0x13A0, 0x13EF, 0, 38864, 0x13F0, 0x13F5, 0, 8, 0x13F8, 0x13FD, -(8), 0, 0x1C80, 0x1C80, -(6254), 0, 0x1C81, 0x1C81, -(6253), 0, 0x1C82, 0x1C82, -(6244), 0, 0x1C83, 0x1C84, -(6242), 0, 0x1C85, 0x1C85, -(6243), 0, 0x1C86, 0x1C86, -(6236), 0, 0x1C87, 0x1C87, -(6181), 0, 0x1C88, 0x1C88, 35266, 0, 0x1C90, 0x1CBA, 0, -(3008), 0x1CBD, 0x1CBF, 0, -(3008), 0x1D79, 0x1D79, 35332, 0, 0x1D7D, 0x1D7D, 3814, 0, 0x1D8E, 0x1D8E, 35384, 0, 0x1E00, 0x1E95, -(3), -(3), 0x1E9B, 0x1E9B, -(59), 0, 0x1E9E, 0x1E9E, 0, -(7615), 0x1EA0, 0x1EFF, -(3), -(3), 0x1F00, 0x1F07, 8, 0, 0x1F08, 0x1F0F, 0, -(8), 0x1F10, 0x1F15, 8, 0, 0x1F18, 0x1F1D, 0, -(8), 0x1F20, 0x1F27, 8, 0, 0x1F28, 0x1F2F, 0, -(8), 0x1F30, 0x1F37, 8, 0, 0x1F38, 0x1F3F, 0, -(8), 0x1F40, 0x1F45, 8, 0, 0x1F48, 0x1F4D, 0, -(8), 0x1F51, 0x1F51, 8, 0, 0x1F53, 0x1F53, 8, 0, 0x1F55, 0x1F55, 8, 0, 0x1F57, 0x1F57, 8, 0, 0x1F59, 0x1F59, 0, -(8), 0x1F5B, 0x1F5B, 0, -(8), 0x1F5D, 0x1F5D, 0, -(8), 0x1F5F, 0x1F5F, 0, -(8), 0x1F60, 0x1F67, 8, 0, 0x1F68, 0x1F6F, 0, -(8), 0x1F70, 0x1F71, 74, 0, 0x1F72, 0x1F75, 86, 0, 0x1F76, 0x1F77, 100, 0, 0x1F78, 0x1F79, 128, 0, 0x1F7A, 0x1F7B, 112, 0, 0x1F7C, 0x1F7D, 126, 0, 0x1F80, 0x1F87, 8, 0, 0x1F88, 0x1F8F, 0, -(8), 0x1F90, 0x1F97, 8, 0, 0x1F98, 0x1F9F, 0, -(8), 0x1FA0, 0x1FA7, 8, 0, 0x1FA8, 0x1FAF, 0, -(8), 0x1FB0, 0x1FB1, 8, 0, 0x1FB3, 0x1FB3, 9, 0, 0x1FB8, 0x1FB9, 0, -(8), 0x1FBA, 0x1FBB, 0, -(74), 0x1FBC, 0x1FBC, 0, -(9), 0x1FBE, 0x1FBE, -(7205), 0, 0x1FC3, 0x1FC3, 9, 0, 0x1FC8, 0x1FCB, 0, -(86), 0x1FCC, 0x1FCC, 0, -(9), 0x1FD0, 0x1FD1, 8, 0, 0x1FD8, 0x1FD9, 0, -(8), 0x1FDA, 0x1FDB, 0, -(100), 0x1FE0, 0x1FE1, 8, 0, 0x1FE5, 0x1FE5, 7, 0, 0x1FE8, 0x1FE9, 0, -(8), 0x1FEA, 0x1FEB, 0, -(112), 0x1FEC, 0x1FEC, 0, -(7), 0x1FF3, 0x1FF3, 9, 0, 0x1FF8, 0x1FF9, 0, -(128), 0x1FFA, 0x1FFB, 0, -(126), 0x1FFC, 0x1FFC, 0, -(9), 0x2126, 0x2126, 0, -(7517), 0x212A, 0x212A, 0, -(8383), 0x212B, 0x212B, 0, -(8262), 0x2132, 0x2132, 0, 28, 0x214E, 0x214E, -(28), 0, 0x2160, 0x216F, 0, 16, 0x2170, 0x217F, -(16), 0, 0x2183, 0x2184, -(3), -(3), 0x24B6, 0x24CF, 0, 26, 0x24D0, 0x24E9, -(26), 0, 0x2C00, 0x2C2F, 0, 48, 0x2C30, 0x2C5F, -(48), 0, 0x2C60, 0x2C61, -(3), -(3), 0x2C62, 0x2C62, 0, -(10743), 0x2C63, 0x2C63, 0, -(3814), 0x2C64, 0x2C64, 0, -(10727), 0x2C65, 0x2C65, -(10795), 0, 0x2C66, 0x2C66, -(10792), 0, 0x2C67, 0x2C6C, -(3), -(3), 0x2C6D, 0x2C6D, 0, -(10780), 0x2C6E, 0x2C6E, 0, -(10749), 0x2C6F, 0x2C6F, 0, -(10783), 0x2C70, 0x2C70, 0, -(10782), 0x2C72, 0x2C73, -(3), -(3), 0x2C75, 0x2C76, -(3), -(3), 0x2C7E, 0x2C7F, 0, -(10815), 0x2C80, 0x2CE3, -(3), -(3), 0x2CEB, 0x2CEE, -(3), -(3), 0x2CF2, 0x2CF3, -(3), -(3), 0x2D00, 0x2D25, -(7264), 0, 0x2D27, 0x2D27, -(7264), 0, 0x2D2D, 0x2D2D, -(7264), 0, 0xA640, 0xA66D, -(3), -(3), 0xA680, 0xA69B, -(3), -(3), 0xA722, 0xA72F, -(3), -(3), 0xA732, 0xA76F, -(3), -(3), 0xA779, 0xA77C, -(3), -(3), 0xA77D, 0xA77D, 0, -(35332), 0xA77E, 0xA787, -(3), -(3), 0xA78B, 0xA78C, -(3), -(3), 0xA78D, 0xA78D, 0, -(42280), 0xA790, 0xA793, -(3), -(3), 0xA794, 0xA794, 48, 0, 0xA796, 0xA7A9, -(3), -(3), 0xA7AA, 0xA7AA, 0, -(42308), 0xA7AB, 0xA7AB, 0, -(42319), 0xA7AC, 0xA7AC, 0, -(42315), 0xA7AD, 0xA7AD, 0, -(42305), 0xA7AE, 0xA7AE, 0, -(42308), 0xA7B0, 0xA7B0, 0, -(42258), 0xA7B1, 0xA7B1, 0, -(42282), 0xA7B2, 0xA7B2, 0, -(42261), 0xA7B3, 0xA7B3, 0, 928, 0xA7B4, 0xA7C3, -(3), -(3), 0xA7C4, 0xA7C4, 0, -(48), 0xA7C5, 0xA7C5, 0, -(42307), 0xA7C6, 0xA7C6, 0, -(35384), 0xA7C7, 0xA7CA, -(3), -(3), 0xA7D0, 0xA7D1, -(3), -(3), 0xA7D6, 0xA7D9, -(3), -(3), 0xA7F5, 0xA7F6, -(3), -(3), 0xAB53, 0xAB53, -(928), 0, 0xAB70, 0xABBF, -(38864), 0, 0xFF21, 0xFF3A, 0, 32, 0xFF41, 0xFF5A, -(32), 0, 0x10400, 0x10427, 0, 40, 0x10428, 0x1044F, -(40), 0, 0x104B0, 0x104D3, 0, 40, 0x104D8, 0x104FB, -(40), 0, 0x10570, 0x1057A, 0, 39, 0x1057C, 0x1058A, 0, 39, 0x1058C, 0x10592, 0, 39, 0x10594, 0x10595, 0, 39, 0x10597, 0x105A1, -(39), 0, 0x105A3, 0x105B1, -(39), 0, 0x105B3, 0x105B9, -(39), 0, 0x105BB, 0x105BC, -(39), 0, 0x10C80, 0x10CB2, 0, 64, 0x10CC0, 0x10CF2, -(64), 0, 0x118A0, 0x118BF, 0, 32, 0x118C0, 0x118DF, -(32), 0, 0x16E40, 0x16E5F, 0, 32, 0x16E60, 0x16E7F, -(32), 0, 0x1E900, 0x1E921, 0, 34, 0x1E922, 0x1E943, -(34), 0};
#define builtin__degree (6)
#define builtin__mid_index ((6) - (1))
#define builtin__max_len (((2) * (6)) - (1))
#define builtin__children_bytes ((sizeof(void*)) * (((((2) * (6)) - (1)) + (1))))
#define builtin__replace_stack_buffer_size (10)
#define builtin__max_direct_index_needle_len (16)
#define builtin__kmp_stack_buffer_size (20)
static const u8 builtin__str_intp_has_dynamic_width = ((u8)(1));
static const u8 builtin__str_intp_has_dynamic_precision = ((u8)((1) << (1)));
string builtin__si_s_code = (string){"0xfe10", 6, 1};
string builtin__si_g32_code = (string){"0xfe0e", 6, 1};
string builtin__si_g64_code = (string){"0xfe0f", 6, 1};
#define builtin__utf8_replacement_rune (((u32)(0xfffd)))
#define builtin__prealloc_block_size (((16) * (1024)) * (1024))
#define builtin__prealloc_scope_block_size ((256) * (1024))
#define builtin__prealloc_recycle_cache_slots (8)
#define builtin__prealloc_default_align ((sizeof(void*)) * (2))
#define builtin__cp_acp (0)
#define builtin__cp_utf8 (65001)

void _vinit() {
	builtin__none__ = (IError){._typ = 2065246729, ._object = (None__*)memdup(&(None__){E_STRUCT}, sizeof(None__)), ._object_is_boxed = true};
	memmove(g_autostr_type_stack, (i64[64]){0}, sizeof(g_autostr_type_stack));
	g_autostr_addr_state = (AutostrAddrStackState){0};
	as_cast_type_indexes = array_new(sizeof(VCastTypeIndexName), 0, 0);
	map_empty_data = (VMapData){.metas = NULL, .key_values = (DenseArray){.all_deleted = NULL, .keys = NULL, .values = NULL}};
	g_panic_state = (PanicState){.top = NULL, .records = NULL};
	builtin_init();
}

string Array_rune__string(Array ra) {
	Array __esc_0 = strings__new_builder(ra.len);
	Array* sb = (Array*)(memdup(&__esc_0, sizeof(Array)));
	strings__Builder__write_runes(sb, ra);
	string res = strings__Builder__str(sb);
	{
		strings__Builder__free(sb);
	}
	return res;
}

string Array_string__join(Array a, string sep) {
	if (a.len == 0) {
		return _str_30;
	}
	i64 len = 0;
	{
		i64 __for_idx_0 = 0;
		for (; __for_idx_0 < a.len; __for_idx_0++) {
			string val = *(string*)(array_get(a, __for_idx_0));
			len += val.len + sep.len;
		}
	}
	len -= sep.len;
	string res = (string){.str = malloc_noscan(len + 1), .len = len};
	i64 idx = 0;
	{
		i64 i = 0;
		for (; i < a.len; i++) {
			string val = *(string*)(array_get(a, i));
			{
				vmemcpy((void*)(res.str + idx), (void*)(val.str), val.len);
				idx += val.len;
			}
			if (i != (a.len - 1)) {
				{
					vmemcpy((void*)(res.str + idx), (void*)(sep.str), sep.len);
					idx += sep.len;
				}
			}
		}
	}
	{
		(res.str)[res.len] = 0;
	}
	return res;
}

string Array_u8__bytestr(Array b) {
	{
		u8* buf = malloc_noscan(b.len + 1);
		vmemcpy((void*)(buf), b.data, b.len);
		(buf)[b.len] = 0;
		return tos(buf, b.len);
	}
}

string Array_u8__hex(Array b) {
	if (b.len == 0) {
		return _str_30;
	}
	return data_to_hex_string(b.data, b.len);
}

DenseArray DenseArray__clone(DenseArray* d) {
	DenseArray res = (DenseArray){.key_bytes = d->key_bytes, .value_bytes = d->value_bytes, .cap = d->cap, .len = d->len, .deletes = d->deletes, .all_deleted = NULL, .values = NULL, .keys = NULL};
	{
		if (d->deletes != 0) {
			res.all_deleted = (u8*)(memdup((void*)(d->all_deleted), d->cap));
		}
		res.keys = (u8*)(memdup((void*)(d->keys), d->cap * d->key_bytes));
		res.values = (u8*)(memdup((void*)(d->values), d->cap * d->value_bytes));
	}
	return res;
}

inline void DenseArray__delete(DenseArray* d, i64 i) {
	if (i == (d->len - 1)) {
		d->len--;
		DenseArray__trim_deleted_tail(d);
		return;
	}
	if (d->deletes == 0) {
		d->all_deleted = vcalloc(d->cap);
	}
	d->deletes++;
	{
		(d->all_deleted)[i] = 1;
	}
}

inline i64 DenseArray__expand(DenseArray* d) {
	i64 old_cap = d->cap;
	i64 old_key_size = d->key_bytes * old_cap;
	i64 old_value_size = d->value_bytes * old_cap;
	if (d->cap == d->len) {
		{
			d->cap += (i64)(((i64)(			d->cap)) >> (3));
		}
		{
			d->keys = realloc_data(d->keys, old_key_size, d->key_bytes * d->cap);
			d->values = realloc_data(d->values, old_value_size, d->value_bytes * d->cap);
			if (d->deletes != 0) {
				d->all_deleted = realloc_data(d->all_deleted, old_cap, d->cap);
				vmemset((void*)(d->all_deleted + d->len), 0, d->cap - d->len);
			}
		}
	}
	i64 push_index = d->len;
	{
		if (d->deletes != 0) {
			(d->all_deleted)[push_index] = 0;
		}
	}
	d->len++;
	return push_index;
}

inline bool DenseArray__has_index(DenseArray* d, i64 i) {
	return (d->deletes == 0) || ((d->all_deleted)[i] == 0);
}

inline void* DenseArray__key(DenseArray* d, i64 i) {
	return (void*)(d->keys + (i * d->key_bytes));
}

void DenseArray__reserve(DenseArray* d, i64 n) {
	if (n <= d->cap) {
		return;
	}
	i64 old_cap = d->cap;
	i64 old_key_size = d->key_bytes * old_cap;
	i64 old_value_size = d->value_bytes * old_cap;
	d->cap = n;
	{
		d->keys = realloc_data(d->keys, old_key_size, d->key_bytes * d->cap);
		d->values = realloc_data(d->values, old_value_size, d->value_bytes * d->cap);
		if (d->deletes != 0) {
			d->all_deleted = realloc_data(d->all_deleted, old_cap, d->cap);
			vmemset((void*)(d->all_deleted + d->len), 0, d->cap - d->len);
		}
	}
}

inline void DenseArray__trim_deleted_tail(DenseArray* d) {
	if (d->deletes == 0) {
		return;
	}
	while ((d->len > 0) && ((d->all_deleted)[d->len - 1] != 0)) {
		{
			(d->all_deleted)[d->len - 1] = 0;
		}
		d->deletes--;
		d->len--;
	}
	if (d->deletes == 0) {
		{
			v_free(d->all_deleted);
			d->all_deleted = NULL;
		}
	}
}

inline void* DenseArray__value(DenseArray* d, i64 i) {
	return (void*)(d->values + (i * d->value_bytes));
}

void DenseArray__zeros_to_end(DenseArray* d) {
	u8* tmp_value = v_malloc(d->value_bytes);
	u8* tmp_key = v_malloc(d->key_bytes);
	i64 count = 0;
	{
		i64 i = 0;
		for (; i < d->len; i++) {
			if (DenseArray__has_index(d, i)) {
				{
					if (count != i) {
						memcpy(tmp_key, DenseArray__key(d, count), d->key_bytes);
						memcpy(DenseArray__key(d, count), DenseArray__key(d, i), d->key_bytes);
						memcpy(DenseArray__key(d, i), tmp_key, d->key_bytes);
						memcpy(tmp_value, DenseArray__value(d, count), d->value_bytes);
						memcpy(DenseArray__value(d, count), DenseArray__value(d, i), d->value_bytes);
						memcpy(DenseArray__value(d, i), tmp_value, d->value_bytes);
					}
				}
				count++;
			}
		}
	}
	{
		v_free(tmp_value);
		v_free(tmp_key);
		d->deletes = 0;
		v_free(d->all_deleted);
		d->all_deleted = NULL;
	}
	d->len = count;
	i64 old_cap = d->cap;
	if (count < 8) {
		d->cap = 8;
	} else {
		d->cap = count;
	}
	{
		d->values = realloc_data(d->values, d->value_bytes * old_cap, d->value_bytes * d->cap);
		d->keys = realloc_data(d->keys, d->key_bytes * old_cap, d->key_bytes * d->cap);
	}
}

i64 Error__code(Error err) {
	return 0;
}

string Error__msg(Error err) {
	return _str_30;
}

string IError__str(IError err) {
	if (err._typ == 2065246729) {
		return _str_42;
	}
	if ((err._typ == 0) || (err._typ == 2065246729)) {
		return _str_43;
	}
	i64 c = IError__code(&(err));
	if (c > 0) {
		return ({ string __v3_internal_symbol_join_0[3]; __v3_internal_symbol_join_0[0] = IError__msg(&(err)); __v3_internal_symbol_join_0[1] = _str_44; __v3_internal_symbol_join_0[2] = int__str(c); string_plus_many(3, __v3_internal_symbol_join_0); });
	}
	return IError__msg(&(err));
}

i64 MessageError__code(MessageError err) {
	return err.code;
}

string MessageError__msg(MessageError err) {
	return err.msg;
}

string MessageError__str(MessageError err) {
	if (err.code > 0) {
		return ({ string __v3_internal_symbol_join_0[3]; __v3_internal_symbol_join_0[0] = err.msg; __v3_internal_symbol_join_0[1] = _str_44; __v3_internal_symbol_join_0[2] = int__str(err.code); string_plus_many(3, __v3_internal_symbol_join_0); });
	}
	return err.msg;
}

string None____str(None__ _0) {
	return _str_42;
}

__v_option_u32 RunesIterator__next(RunesIterator* ri) {
	if (ri->i >= ri->s.len) {
		return (__v_option_u32){.ok = false};
	}
	multi_return_u32_i64 __multi_ret_0 = utf8_decode_rune(&(ri->s.str)[ri->i], ri->s.len - ri->i);
	u32 r = __multi_ret_0.arg0;
	i64 char_len = __multi_ret_0.arg1;
	i64 __if_val_1 = {0};
	if (char_len > 0) {
		__if_val_1 = char_len;
	} else {
		__if_val_1 = 1;
	}
	ri->i += __if_val_1;
	return (__v_option_u32){.ok = true, .value = r};
	return (__v_option_u32){.ok = true};
}

void VMapData__cached_rehash(VMapData* m, u32 old_cap) {
	u32* old_metas = m->metas;
	i64 metasize = (i64)(sizeof(u32) * ((m->even_index + 2) + m->extra_metas));
	m->metas = (u32*)(vcalloc(metasize));
	u32 old_extra_metas = m->extra_metas;
	{
		u32 i = (u32)(0);
		for (; i <= (old_cap + old_extra_metas); i += 2) {
			if ((old_metas)[i] == 0) {
				continue;
			}
			u32 old_meta = (old_metas)[i];
			u32 old_probe_count = (u32)(((u32)(			(((u32)(((u32)(			old_meta)) >> (builtin__hashbits))) - 1))) << (1));
			u32 old_index = (i - old_probe_count) & ((u32)(((u32)(			m->even_index)) >> (1)));
			u32 v_index = (old_index | (({ u32 _t1 = (u32)(			old_meta); u64 _t2 = (u64)(m->shift); _t2 >= 32 ? (u32)0 : (u32)(_t1 << _t2); }))) & m->even_index;
			u32 meta = (old_meta & builtin__hash_mask) | builtin__probe_inc;
			u32 kv_index = (old_metas)[i + 1];
			multi_return_u32_u32 __multi_ret_0 = VMapData__meta_less(m, v_index, meta);
			v_index = __multi_ret_0.arg0;
			meta = __multi_ret_0.arg1;
			VMapData__meta_greater(m, v_index, meta, kv_index);
		}
	}
	{
		v_free(old_metas);
	}
}

void VMapData__clear(VMapData* m) {
	if (m->metas == NULL) {
		return;
	}
	{
		if (m->key_values.all_deleted != 0) {
			v_free(m->key_values.all_deleted);
			m->key_values.all_deleted = NULL;
		}
		vmemset((void*)(m->key_values.keys), 0, m->key_values.key_bytes * m->key_values.cap);
		vmemset((void*)(m->metas), 0, sizeof(u32) * ((m->even_index + 2) + m->extra_metas));
	}
	m->key_values.len = 0;
	m->key_values.deletes = 0;
	m->even_index = builtin__init_even_index;
	m->cached_hashbits = builtin__max_cached_hashbits;
	m->shift = builtin__init_log_capicity;
	m->count = 0;
}

VMapData* VMapData__clone(VMapData* m) {
	if (m->metas == NULL) {
		return new_map_data(m->key_bytes, m->value_bytes, m->hash_fn, m->key_eq_fn, m->clone_fn, m->free_fn);
	}
	i64 metasize = (i64)(sizeof(u32) * ((m->even_index + 2) + m->extra_metas));
	VMapData* res = (VMapData*)memdup(&(VMapData){.key_bytes = m->key_bytes, .value_bytes = m->value_bytes, .even_index = m->even_index, .cached_hashbits = m->cached_hashbits, .shift = m->shift, .key_values = DenseArray__clone(&m->key_values), .metas = (u32*)(malloc_noscan(metasize)), .extra_metas = m->extra_metas, .count = m->count, .has_string_keys = m->has_string_keys, .hash_fn = m->hash_fn, .key_eq_fn = m->key_eq_fn, .clone_fn = m->clone_fn, .free_fn = m->free_fn}, sizeof(VMapData));
	{
		vmemcpy((void*)(res->metas), (void*)(m->metas), metasize);
	}
	if (!m->has_string_keys) {
		return res;
	}
	{
		i64 i = 0;
		for (; i < m->key_values.len; i++) {
			if (!DenseArray__has_index(&m->key_values, i)) {
				continue;
			}
			m->clone_fn(DenseArray__key(&res->key_values, i), DenseArray__key(&m->key_values, i));
		}
	}
	return res;
}

void VMapData__delete(VMapData* m, void* key) {
	if (m->count == 0) {
		return;
	}
	multi_return_u32_u32 __multi_ret_0 = VMapData__key_to_index(m, key);
	u32 v_index = __multi_ret_0.arg0;
	u32 meta = __multi_ret_0.arg1;
	multi_return_u32_u32 __multi_ret_1 = VMapData__meta_less(m, v_index, meta);
	v_index = __multi_ret_1.arg0;
	meta = __multi_ret_1.arg1;
	while (meta == (m->metas)[v_index]) {
		i64 kv_index = (i64)((m->metas)[v_index + 1]);
		void* pkey = DenseArray__key(&m->key_values, kv_index);
		if (m->key_eq_fn(key, pkey)) {
			while (((u32)(((u32)(			(m->metas)[v_index + 2])) >> (builtin__hashbits))) > 1) {
				{
					(m->metas)[v_index] = (m->metas)[v_index + 2] - builtin__probe_inc;
					(m->metas)[v_index + 1] = (m->metas)[v_index + 3];
				}
				v_index += 2;
			}
			m->count--;
			DenseArray__delete(&m->key_values, kv_index);
			{
				(m->metas)[v_index] = 0;
				m->free_fn(pkey);
				vmemset(pkey, 0, m->key_bytes);
			}
			if (m->key_values.len <= 32) {
				return;
			}
			if (({ u32 _t1 = (u32)(m->key_values.deletes); i64 _t2 = (i64)(((i64)(((i64)(			m->key_values.len)) >> (1)))); _t2 < 0 ? 1 : ((u64)(_t1) >= (u64)(_t2)); })) {
				DenseArray__zeros_to_end(&m->key_values);
				VMapData__rehash(m);
			}
			return;
		}
		v_index += 2;
		meta += builtin__probe_inc;
	}
}

inline void VMapData__ensure_extra_metas(VMapData* m, u32 probe_count) {
	if (((u32)(((u32)(	probe_count)) << (1))) == m->extra_metas) {
		u32 size_of_u32 = sizeof(u32);
		u32 old_mem_size = ((m->even_index + 2) + m->extra_metas);
		m->extra_metas += builtin__extra_metas_inc;
		u32 mem_size = ((m->even_index + 2) + m->extra_metas);
		{
			u8* x = realloc_data((u8*)((u8*)(m->metas)), (i64)(size_of_u32 * old_mem_size), (i64)(size_of_u32 * mem_size));
			m->metas = (u32*)(x);
			vmemset((u8*)(m->metas) + ((mem_size - builtin__extra_metas_inc) * size_of_u32), 0, (i64)(sizeof(u32) * builtin__extra_metas_inc));
		}
		if (probe_count == 252) {
			v_panic(_str_89);
		}
	}
}

void VMapData__ensure_extra_metas_grow(VMapData* m) {
	u32 size_of_u32 = sizeof(u32);
	u32 old_mem_size = ((m->even_index + 2) + m->extra_metas);
	m->extra_metas += builtin__extra_metas_inc;
	u32 mem_size = ((m->even_index + 2) + m->extra_metas);
	{
		u8* x = realloc_data((u8*)((u8*)(m->metas)), (i64)(size_of_u32 * old_mem_size), (i64)(size_of_u32 * mem_size));
		m->metas = (u32*)(x);
		vmemset((u8*)(m->metas) + ((mem_size - builtin__extra_metas_inc) * size_of_u32), 0, (i64)(sizeof(u32) * builtin__extra_metas_inc));
	}
}

bool VMapData__exists(VMapData* m, void* key) {
	if (m->count == 0) {
		return false;
	}
	multi_return_u32_u32 __multi_ret_0 = VMapData__key_to_index(m, key);
	u32 v_index = __multi_ret_0.arg0;
	u32 meta = __multi_ret_0.arg1;
	for (;;) {
		if (meta == (m->metas)[v_index]) {
			i64 kv_index = (i64)((m->metas)[v_index + 1]);
			void* pkey = DenseArray__key(&m->key_values, kv_index);
			if (m->key_eq_fn(key, pkey)) {
				return true;
			}
		}
		v_index += 2;
		meta += builtin__probe_inc;
		if (meta > (m->metas)[v_index]) {
			break;
		}
	}
	return false;
}

void VMapData__expand(VMapData* m) {
	u32 old_cap = m->even_index;
	m->even_index = ((u32)(((u32)(	(m->even_index + 2))) << (1))) - 2;
	if (m->cached_hashbits == 0) {
		m->shift += builtin__max_cached_hashbits;
		m->cached_hashbits = builtin__max_cached_hashbits;
		VMapData__rehash(m);
	} else {
		VMapData__cached_rehash(m, old_cap);
		m->cached_hashbits--;
	}
}

void VMapData__free(VMapData* m) {
	{
		v_free(m->metas);
	}
	{
		m->metas = NULL;
	}
	if (m->key_values.deletes == 0) {
		{
			i64 i = 0;
			for (; i < m->key_values.len; i++) {
				{
					void* pkey = DenseArray__key(&m->key_values, i);
					m->free_fn(pkey);
					vmemset(pkey, 0, m->key_bytes);
				}
			}
		}
	} else {
		{
			i64 i = 0;
			for (; i < m->key_values.len; i++) {
				if (!DenseArray__has_index(&m->key_values, i)) {
					continue;
				}
				{
					void* pkey = DenseArray__key(&m->key_values, i);
					m->free_fn(pkey);
					vmemset(pkey, 0, m->key_bytes);
				}
			}
		}
	}
	{
		if (m->key_values.all_deleted != NULL) {
			v_free(m->key_values.all_deleted);
			m->key_values.all_deleted = NULL;
		}
		if (m->key_values.keys != NULL) {
			v_free(m->key_values.keys);
			m->key_values.keys = NULL;
		}
		if (m->key_values.values != NULL) {
			v_free(m->key_values.values);
			m->key_values.values = NULL;
		}
		m->hash_fn = NULL;
		m->key_eq_fn = NULL;
		m->clone_fn = NULL;
		m->free_fn = NULL;
		m->key_values.cap = 0;
		m->key_values.len = 0;
		m->key_values.deletes = 0;
		m->even_index = 0;
		m->cached_hashbits = 0;
		m->shift = 0;
		m->extra_metas = 0;
		m->has_string_keys = false;
		m->count = 0;
	}
}

void* VMapData__get(VMapData* m, void* key, void* zero) {
	if (m->count == 0) {
		return zero;
	}
	multi_return_u32_u32 __multi_ret_0 = VMapData__key_to_index(m, key);
	u32 v_index = __multi_ret_0.arg0;
	u32 meta = __multi_ret_0.arg1;
	for (;;) {
		if (meta == (m->metas)[v_index]) {
			i64 kv_index = (i64)((m->metas)[v_index + 1]);
			void* pkey = DenseArray__key(&m->key_values, kv_index);
			if (m->key_eq_fn(key, pkey)) {
				void* pval = DenseArray__value(&m->key_values, kv_index);
				return (void*)((u8*)(pval));
			}
		}
		v_index += 2;
		meta += builtin__probe_inc;
		if (meta > (m->metas)[v_index]) {
			break;
		}
	}
	return zero;
}

void* VMapData__get_and_set(VMapData* m, void* key, void* zero) {
	if (m->metas == NULL) {
		VMapData__set(m, key, zero);
	}
	for (;;) {
		multi_return_u32_u32 __multi_ret_0 = VMapData__key_to_index(m, key);
		u32 v_index = __multi_ret_0.arg0;
		u32 meta = __multi_ret_0.arg1;
		for (;;) {
			if (meta == (m->metas)[v_index]) {
				i64 kv_index = (i64)((m->metas)[v_index + 1]);
				void* pkey = DenseArray__key(&m->key_values, kv_index);
				if (m->key_eq_fn(key, pkey)) {
					void* pval = DenseArray__value(&m->key_values, kv_index);
					return (void*)((u8*)(pval));
				}
			}
			v_index += 2;
			meta += builtin__probe_inc;
			if (meta > (m->metas)[v_index]) {
				break;
			}
		}
		VMapData__set(m, key, zero);
	}
	return NULL;
}

void* VMapData__get_check(VMapData* m, void* key) {
	if (m->count == 0) {
		return 0;
	}
	multi_return_u32_u32 __multi_ret_0 = VMapData__key_to_index(m, key);
	u32 v_index = __multi_ret_0.arg0;
	u32 meta = __multi_ret_0.arg1;
	for (;;) {
		if (meta == (m->metas)[v_index]) {
			i64 kv_index = (i64)((m->metas)[v_index + 1]);
			void* pkey = DenseArray__key(&m->key_values, kv_index);
			if (m->key_eq_fn(key, pkey)) {
				void* pval = DenseArray__value(&m->key_values, kv_index);
				return (void*)((u8*)(pval));
			}
		}
		v_index += 2;
		meta += builtin__probe_inc;
		if (meta > (m->metas)[v_index]) {
			break;
		}
	}
	return 0;
}

inline multi_return_u32_u32 VMapData__key_to_index(VMapData* m, void* pkey) {
	if ((void*)(m->hash_fn) == NULL) {
		VMapData__panic_nil_map_hash_fn(m);
	}
	u64 hash = m->hash_fn(pkey);
	u64 v_index = hash & m->even_index;
	u64 meta = ((({ u64 _t1 = (u64)(	hash); u64 _t2 = (u64)(m->shift); _t2 >= 64 ? (u64)0 : (u64)(_t1 >> _t2); })) & builtin__hash_mask) | builtin__probe_inc;
	return (multi_return_u32_u32){(u32)(v_index), (u32)(meta)};
}

array VMapData__keys(VMapData* m) {
	array keys = __new_array(m->count, 0, m->key_bytes);
	u8* item = (u8*)(keys.data);
	if (m->key_values.deletes == 0) {
		{
			i64 i = 0;
			for (; i < m->key_values.len; i++) {
				{
					void* pkey = DenseArray__key(&m->key_values, i);
					m->clone_fn(item, pkey);
					item = item + m->key_bytes;
				}
			}
		}
		return keys;
	}
	{
		i64 i = 0;
		for (; i < m->key_values.len; i++) {
			if (!DenseArray__has_index(&m->key_values, i)) {
				continue;
			}
			{
				void* pkey = DenseArray__key(&m->key_values, i);
				m->clone_fn(item, pkey);
				item = item + m->key_bytes;
			}
		}
	}
	return keys;
}

inline void VMapData__meta_greater(VMapData* m, u32 _index, u32 _metas, u32 kvi) {
	u32 meta = _metas;
	u32 v_index = _index;
	u32 kv_index = kvi;
	while ((m->metas)[v_index] != 0) {
		if (meta > (m->metas)[v_index]) {
			{
				u32 tmp_meta = (m->metas)[v_index];
				(m->metas)[v_index] = meta;
				meta = tmp_meta;
				u32 tmp_index = (m->metas)[v_index + 1];
				(m->metas)[v_index + 1] = kv_index;
				kv_index = tmp_index;
			}
		}
		v_index += 2;
		meta += builtin__probe_inc;
		if ((v_index + 2) >= ((m->even_index + 2) + m->extra_metas)) {
			VMapData__ensure_extra_metas_grow(m);
		}
	}
	{
		(m->metas)[v_index] = meta;
		(m->metas)[v_index + 1] = kv_index;
	}
	u32 probe_count = ((u32)(((u32)(	meta)) >> (builtin__hashbits))) - 1;
	VMapData__ensure_extra_metas(m, probe_count);
}

inline multi_return_u32_u32 VMapData__meta_less(VMapData* m, u32 _index, u32 _metas) {
	u32 v_index = _index;
	u32 meta = _metas;
	while (meta < (m->metas)[v_index]) {
		v_index += 2;
		meta += builtin__probe_inc;
	}
	return (multi_return_u32_u32){v_index, meta};
}

__attribute__((noinline)) void VMapData__panic_nil_map_hash_fn(VMapData* m) {
	{
		u64* p = (u64*)(m);
		u64 prev2 = (((u64*)((size_t)(m) - (size_t)(16))))[0];
		u64 prev1 = (((u64*)((size_t)(m) - (size_t)(8))))[0];
		v_panic(({ string __v3_internal_symbol_join_0[34]; __v3_internal_symbol_join_0[0] = _str_72; __v3_internal_symbol_join_0[1] = strconv__format_uint((size_t)((size_t)(m)), 10); __v3_internal_symbol_join_0[2] = _str_73; __v3_internal_symbol_join_0[3] = int__str(m->key_bytes); __v3_internal_symbol_join_0[4] = _str_74; __v3_internal_symbol_join_0[5] = int__str(m->value_bytes); __v3_internal_symbol_join_0[6] = _str_75; __v3_internal_symbol_join_0[7] = strconv__format_uint((u32)(m->even_index), 10); __v3_internal_symbol_join_0[8] = _str_76; __v3_internal_symbol_join_0[9] = strconv__format_uint((u8)(m->shift), 10); __v3_internal_symbol_join_0[10] = _str_77; __v3_internal_symbol_join_0[11] = strconv__format_uint((size_t)((size_t)(m->metas)), 10); __v3_internal_symbol_join_0[12] = _str_78; __v3_internal_symbol_join_0[13] = u64__str(prev2); __v3_internal_symbol_join_0[14] = _str_79; __v3_internal_symbol_join_0[15] = u64__str(prev1); __v3_internal_symbol_join_0[16] = _str_80; __v3_internal_symbol_join_0[17] = u64__str((p)[0]); __v3_internal_symbol_join_0[18] = _str_81; __v3_internal_symbol_join_0[19] = u64__str((p)[1]); __v3_internal_symbol_join_0[20] = _str_82; __v3_internal_symbol_join_0[21] = u64__str((p)[2]); __v3_internal_symbol_join_0[22] = _str_83; __v3_internal_symbol_join_0[23] = u64__str((p)[3]); __v3_internal_symbol_join_0[24] = _str_84; __v3_internal_symbol_join_0[25] = u64__str((p)[4]); __v3_internal_symbol_join_0[26] = _str_85; __v3_internal_symbol_join_0[27] = u64__str((p)[5]); __v3_internal_symbol_join_0[28] = _str_86; __v3_internal_symbol_join_0[29] = u64__str((p)[6]); __v3_internal_symbol_join_0[30] = _str_87; __v3_internal_symbol_join_0[31] = u64__str((p)[7]); __v3_internal_symbol_join_0[32] = _str_88; __v3_internal_symbol_join_0[33] = strconv__format_uint((size_t)((size_t)((void*)(m->hash_fn))), 10); string_plus_many(34, __v3_internal_symbol_join_0); }));
	}
}

void VMapData__rehash(VMapData* m) {
	u32 meta_bytes = sizeof(u32) * ((m->even_index + 2) + m->extra_metas);
	VMapData__reserve_metas(m, meta_bytes);
}

void VMapData__reserve(VMapData* m, u32 n) {
	if (m->count == 0) {
		u32 old_index = m->even_index;
		while (((u64)(n) * 5) > ((u64)(m->even_index) * 2)) {
			m->even_index = ((u32)(((u32)(			(m->even_index + 2))) << (1))) - 2;
			if (m->cached_hashbits == 0) {
				m->shift += builtin__max_cached_hashbits;
				m->cached_hashbits = builtin__max_cached_hashbits;
			} else {
				m->cached_hashbits--;
			}
		}
		if ((m->even_index != old_index) || ((n > 0) && (m->metas == NULL))) {
			u32 meta_bytes = sizeof(u32) * ((m->even_index + 2) + m->extra_metas);
			{
				v_free(m->metas);
				m->metas = (u32*)(vcalloc_noscan(meta_bytes));
			}
		}
	} else {
		while (((u64)(n) * 5) > ((u64)(m->even_index) * 2)) {
			VMapData__expand(m);
		}
	}
	u64 dense_cap = (u64)(n) + (u64)(m->key_values.deletes);
	if (dense_cap > (u64)(builtin__max_int)) {
		v_panic(_str_90);
	}
	if ((dense_cap > 0) && (dense_cap < 8)) {
		DenseArray__reserve(&m->key_values, 8);
	} else {
		DenseArray__reserve(&m->key_values, (i64)(dense_cap));
	}
}

void VMapData__reserve_metas(VMapData* m, u32 meta_bytes) {
	{
		u8* x = v_realloc((u8*)((u8*)(m->metas)), (i64)(meta_bytes));
		m->metas = (u32*)(x);
		vmemset((void*)(m->metas), 0, (i64)(meta_bytes));
	}
	{
		i64 i = 0;
		for (; i < m->key_values.len; i++) {
			if (!DenseArray__has_index(&m->key_values, i)) {
				continue;
			}
			void* pkey = DenseArray__key(&m->key_values, i);
			multi_return_u32_u32 __multi_ret_0 = VMapData__key_to_index(m, pkey);
			u32 v_index = __multi_ret_0.arg0;
			u32 meta = __multi_ret_0.arg1;
			multi_return_u32_u32 __multi_ret_1 = VMapData__meta_less(m, v_index, meta);
			v_index = __multi_ret_1.arg0;
			meta = __multi_ret_1.arg1;
			VMapData__meta_greater(m, v_index, meta, (u32)(i));
		}
	}
}

void VMapData__set(VMapData* m, void* key, void* value) {
	if (m->metas == NULL) {
		m->key_values = new_dense_array(m->key_bytes, m->value_bytes);
		m->metas = (u32*)(vcalloc_noscan(sizeof(u32) * ((m->even_index + 2) + m->extra_metas)));
	}
	if (((u32)(5) * (u32)(m->count)) > ((u32)(2) * m->even_index)) {
		VMapData__expand(m);
	}
	multi_return_u32_u32 __multi_ret_0 = VMapData__key_to_index(m, key);
	u32 v_index = __multi_ret_0.arg0;
	u32 meta = __multi_ret_0.arg1;
	multi_return_u32_u32 __multi_ret_1 = VMapData__meta_less(m, v_index, meta);
	v_index = __multi_ret_1.arg0;
	meta = __multi_ret_1.arg1;
	while (meta == (m->metas)[v_index]) {
		i64 kv_index = (i64)((m->metas)[v_index + 1]);
		void* pkey = DenseArray__key(&m->key_values, kv_index);
		if (m->key_eq_fn(key, pkey)) {
			{
				void* pval = DenseArray__value(&m->key_values, kv_index);
				vmemcpy(pval, value, m->value_bytes);
			}
			return;
		}
		v_index += 2;
		meta += builtin__probe_inc;
	}
	i64 kv_index = DenseArray__expand(&m->key_values);
	{
		void* pkey = DenseArray__key(&m->key_values, kv_index);
		void* pvalue = DenseArray__value(&m->key_values, kv_index);
		m->clone_fn(pkey, key);
		vmemcpy(pvalue, value, m->value_bytes);
	}
	VMapData__meta_greater(m, v_index, meta, (u32)(kv_index));
	m->count++;
}

array VMapData__values(VMapData* m) {
	array values = __new_array(m->count, 0, m->value_bytes);
	if (m->count == 0) {
		return values;
	}
	u8* item = (u8*)(values.data);
	if (m->key_values.deletes == 0) {
		{
			vmemcpy((void*)(item), (void*)(m->key_values.values), m->value_bytes * m->key_values.len);
		}
		return values;
	}
	{
		i64 i = 0;
		for (; i < m->key_values.len; i++) {
			if (!DenseArray__has_index(&m->key_values, i)) {
				continue;
			}
			{
				void* pvalue = DenseArray__value(&m->key_values, i);
				vmemcpy((void*)(item), pvalue, m->value_bytes);
				item = item + m->value_bytes;
			}
		}
	}
	return values;
}

void* __as_cast(void* obj, i64 obj_type, i64 expected_type, string obj_name, string expected_name) {
	if (obj_type != expected_type) {
		v_panic(({ string __v3_internal_symbol_join_0[5]; __v3_internal_symbol_join_0[0] = _str_39; __v3_internal_symbol_join_0[1] = obj_name; __v3_internal_symbol_join_0[2] = _str_40; __v3_internal_symbol_join_0[3] = expected_name; __v3_internal_symbol_join_0[4] = _str_41; string_plus_many(5, __v3_internal_symbol_join_0); }));
	}
	return obj;
}

inline u64 __at_least_one(u64 how_many) {
	if (how_many == 0) {
		return 1;
	}
	return how_many;
}

array __new_array(i64 mylen, i64 cap, i64 elm_size) {
	panic_on_negative_len(mylen);
	panic_on_negative_cap(cap);
	i64 __if_val_0 = {0};
	if (cap < mylen) {
		__if_val_0 = mylen;
	} else {
		__if_val_0 = cap;
	}
	i64 cap_ = __if_val_0;
	u64 total_size = (u64)(cap_) * (u64)(elm_size);
	void* data = NULL;
	if ((cap_ > 0) && (mylen == 0)) {
		data = alloc_array_data_uninit(total_size);
	} else if (cap_ > 0) {
		data = alloc_array_data(total_size);
	}
	array arr = (array){.element_size = elm_size, .data = data, .len = mylen, .cap = cap_, .flags = 16};
	return arr;
}

array __new_array_noscan(i64 mylen, i64 cap, i64 elm_size) {
	return __new_array(mylen, cap, elm_size);
}

void _ht_alloc(u8* p, ptrdiff_t n) {
}

void _ht_free(void* p) {
}

VNORETURN void _memory_panic(string fname, ptrdiff_t size) {
	v_memory_panic = true;
	eprint(fname);
	eprint(_str_159);
	{
		fprintf(stderr, "%p", (void*)(size));
	}
	if (size < 0) {
		eprint(_str_160);
	}
	eprintln(_str_23);
	v_panic(_str_161);
}

void _write_buf_to_fd(i64 fd, u8* buf, i64 buf_len) {
	if (buf_len <= 0) {
		return;
	}
	{
		u8* ptr = buf;
		ptrdiff_t remaining_bytes = (ptrdiff_t)(buf_len);
		ptrdiff_t x = (ptrdiff_t)(0);
		{
			void* stream = (void*)(stdout);
			if (fd == 2) {
				stream = (void*)(stderr);
			}
			{
				while (remaining_bytes > 0) {
					x = (ptrdiff_t)(fwrite(ptr, 1, remaining_bytes, (FILE*)(stream)));
					if (x <= 0) {
						break;
					}
					ptr += x;
					remaining_bytes -= x;
				}
			}
		}
	}
}

void _writeln_to_fd(i64 fd, string s) {
	{
		u8 lf = (u8)('\n');
		_write_buf_to_fd(fd, s.str, s.len);
		_write_buf_to_fd(fd, &lf, 1);
	}
}

inline void* alloc_array_data(u64 total_size) {
	u8* raw = vcalloc(array_data_allocation_size(total_size));
	return init_array_data((void*)(raw));
}

inline void* alloc_array_data_uninit(u64 total_size) {
	u8* raw = malloc_uninit(array_data_allocation_size(total_size));
	return init_array_data((void*)(raw));
}

inline void* array__alloc_array_data_like(array a, u64 total_size) {
	return alloc_array_data(total_size);
}

inline void* array__alloc_array_data_like_uninit(array a, u64 total_size) {
	return alloc_array_data_uninit(total_size);
}

inline bool array__buffer_has_slices(array a) {
	if (!((a.flags & 16) != 0) || (a.data == NULL)) {
		return false;
	}
	ArrayDataHeader* header = array__data_header(a);
	if (header == NULL) {
		return false;
	}
	return header->has_slices;
}

void array__clear(array* a) {
	if (array__needs_unique_shrink(*a)) {
		{
			a->flags &= ~((16 | 32) | 64);
		}
		a->data = NULL;
		a->offset = 0;
		a->cap = 0;
	}
	a->len = 0;
}

array array__clone(array* a) {
	return array__clone_to_depth(a, 0);
}

inline void array__clone_shallow_to_cap(array* a, i64 new_cap) {
	if (new_cap <= 0) {
		{
			a->flags &= ~((16 | 32) | 64);
		}
		a->data = NULL;
		a->offset = 0;
		a->cap = 0;
		return;
	}
	bool use_noscan_data = array__uses_noscan_data(*a);
	u64 total_size = (u64)(new_cap) * (u64)(a->element_size);
	void* new_data = array__alloc_array_data_like_uninit(*a, total_size);
	u64 copy_size = (u64)(a->len) * (u64)(a->element_size);
	if ((a->data != NULL) && (copy_size > 0)) {
		{
			vmemcpy(new_data, a->data, copy_size);
		}
	}
	a->data = new_data;
	a->offset = 0;
	a->cap = new_cap;
	{
		if (use_noscan_data) {
			a->flags |= 32;
		} else {
			a->flags &= ~32;
		}
	}
	array__set_managed_flags(a, false);
}

array array__clone_to_depth(array* a, i64 depth) {
	u64 source_capacity_in_bytes = (u64)(a->cap) * (u64)(a->element_size);
	bool use_noscan_data = (depth == 0) && array__uses_noscan_data(*a);
	bool clones_elements = (depth > 0) && (a->len >= 0) && (a->cap >= a->len) && ((({ i64 _t1 = (i64)(a->element_size); u32 _t2 = (u32)(sizeof(Array)); _t1 < 0 ? 0 : ((u64)(_t1) == (u64)(_t2)); })) || (({ i64 _t3 = (i64)(a->element_size); u32 _t4 = (u32)(sizeof(string)); _t3 < 0 ? 0 : ((u64)(_t3) == (u64)(_t4)); })));
	bool copies_capacity = !clones_elements && (a->data != 0) && (source_capacity_in_bytes > 0);
	void* data = NULL;
	if (a->cap > 0) {
		if (use_noscan_data) {
			if (copies_capacity) {
				data = array__alloc_array_data_like_uninit(*a, source_capacity_in_bytes);
			} else {
				data = array__alloc_array_data_like(*a, source_capacity_in_bytes);
			}
		} else if (copies_capacity) {
			data = alloc_array_data_uninit(source_capacity_in_bytes);
		} else {
			data = alloc_array_data(source_capacity_in_bytes);
		}
	}
	i64 __struct_field_0 = a->element_size;
	void* __struct_field_1 = data;
	i64 __struct_field_2 = a->len;
	i64 __struct_field_3 = a->cap;
	int __if_val_4 = {0};
	if (use_noscan_data) {
		__if_val_4 = 16 | 32;
	} else {
		__if_val_4 = 16;
	}
	array arr = (array){.element_size = __struct_field_0, .data = __struct_field_1, .len = __struct_field_2, .cap = __struct_field_3, .flags = __if_val_4};
	if ((depth > 0) && (({ i64 _t5 = (i64)(a->element_size); u32 _t6 = (u32)(sizeof(Array)); _t5 < 0 ? 0 : ((u64)(_t5) == (u64)(_t6)); })) && (a->len >= 0) && (a->cap >= a->len)) {
		array ar = (array){.flags = 0};
		i64 asize = (i64)(sizeof(Array));
		{
			i64 i = 0;
			for (; i < a->len; i++) {
				{
					vmemcpy((void*)(&ar), array__get_unsafe(*a, i), asize);
				}
				array ar_clone = array__clone_to_depth(&ar, depth - 1);
				{
					array__set_unsafe(&arr, i, (void*)(&ar_clone));
				}
			}
		}
		return arr;
	} else if ((depth > 0) && (({ i64 _t7 = (i64)(a->element_size); u32 _t8 = (u32)(sizeof(string)); _t7 < 0 ? 0 : ((u64)(_t7) == (u64)(_t8)); })) && (a->len >= 0) && (a->cap >= a->len)) {
		{
			i64 i = 0;
			for (; i < a->len; i++) {
				string* str_ptr = (string*)(array__get_unsafe(*a, i));
				string str_clone = string__clone((*str_ptr));
				{
					array__set_unsafe(&arr, i, (void*)(&str_clone));
				}
			}
		}
		return arr;
	}
	if ((a->data != 0) && (source_capacity_in_bytes > 0)) {
		{
			vmemcpy(arr.data, a->data, source_capacity_in_bytes);
		}
	}
	return arr;
}

inline ArrayDataHeader* array__data_header(array a) {
	if (!((a.flags & 16) != 0) || (a.data == NULL)) {
		return NULL;
	}
	u8* base_data = (u8*)(a.data) - (u64)(a.offset);
	return (ArrayDataHeader*)(base_data - array_data_header_size());
}

void array__delete(array* a, i64 i) {
	if ((i < 0) || (i >= a->len)) {
		panic_n2(_str_10, i, a->len);
	}
	if ((i == (a->len - 1)) && !array__needs_unique_shrink(*a)) {
		a->len--;
		{
			vmemset((void*)((u8*)(a->data) + ((u64)(a->len) * (u64)(a->element_size))), 0, (u64)(a->element_size));
		}
		return;
	}
	array__delete_many(a, i, 1);
}

void array__delete_last(array* a) {
	if (a->len == 0) {
		v_panic(_str_19);
	}
	if (array__needs_unique_shrink(*a)) {
		array__delete_many(a, a->len - 1, 1);
		return;
	}
	a->len--;
	{
		vmemset((void*)((u8*)(a->data) + ((u64)(a->len) * (u64)(a->element_size))), 0, (u64)(a->element_size));
	}
}

void array__delete_many(array* a, i64 i, i64 size) {
	if ((i < 0) || (((i64)(i) + (i64)(size)) > (i64)(a->len))) {
		if (size > 1) {
			panic_n3(_str_11, i, i + size, a->len);
		} else {
			panic_n2(_str_10, i, a->len);
		}
	}
	if (size == 0) {
		if (array__needs_unique_shrink(*a)) {
			array__clone_shallow_to_cap(a, a->len);
		}
		return;
	}
	if (!array__needs_unique_shrink(*a)) {
		i64 new_len = a->len - size;
		{
			vmemmove((void*)((u8*)(a->data) + ((u64)(i) * (u64)(a->element_size))), (void*)((u8*)(a->data) + ((u64)(i + size) * (u64)(a->element_size))), (u64)((a->len - i) - size) * (u64)(a->element_size));
			vmemset((void*)((u8*)(a->data) + ((u64)(new_len) * (u64)(a->element_size))), 0, (u64)(size) * (u64)(a->element_size));
		}
		a->len = new_len;
		return;
	}
	void* old_data = a->data;
	i64 new_size = a->len - size;
	if (new_size == 0) {
		{
			a->flags &= ~((16 | 32) | 64);
		}
		a->data = NULL;
		a->offset = 0;
		a->len = 0;
		a->cap = 0;
		return;
	}
	i64 new_cap = new_size;
	bool use_noscan_data = array__uses_noscan_data(*a);
	a->data = array__alloc_array_data_like(*a, (u64)(new_cap) * (u64)(a->element_size));
	{
		vmemcpy(a->data, old_data, (u64)(i) * (u64)(a->element_size));
	}
	{
		vmemcpy((void*)((u8*)(a->data) + ((u64)(i) * (u64)(a->element_size))), (void*)((u8*)(old_data) + ((u64)(i + size) * (u64)(a->element_size))), (u64)((a->len - i) - size) * (u64)(a->element_size));
	}
	if (((a->flags & 1) != 0) && !((a->flags & 16) != 0)) {
		{
			v_free(old_data);
		}
	}
	a->len = new_size;
	a->cap = new_cap;
	a->offset = 0;
	{
		if (use_noscan_data) {
			a->flags |= 32;
		} else {
			a->flags &= ~32;
		}
	}
	array__set_managed_flags(a, false);
}

void array__ensure_cap(array* a, i64 required) {
	if (required <= a->cap) {
		return;
	}
	if ((a->flags & 4) != 0) {
		panic_n(_str_3, required);
	}
	i64 __if_val_0 = {0};
	if (a->cap > 0) {
		__if_val_0 = (i64)(a->cap);
	} else {
		__if_val_0 = (i64)(2);
	}
	i64 cap = __if_val_0;
	while (required > cap) {
		cap *= 2;
	}
	if (cap > builtin__max_int) {
		if (a->cap < builtin__max_int) {
			cap = builtin__max_int;
		} else {
			panic_n(_str_4, cap);
		}
	}
	u64 new_size = (u64)(cap) * (u64)(a->element_size);
	bool use_noscan_data = array__uses_noscan_data(*a);
	void* new_data = array__alloc_array_data_like_uninit(*a, new_size);
	if (a->data != NULL) {
		{
			vmemcpy(new_data, a->data, (u64)(a->len) * (u64)(a->element_size));
		}
		if (((a->flags & 1) != 0) && !((a->flags & 64) != 0) && !array__buffer_has_slices(*a)) {
			{
				if ((a->flags & 16) != 0) {
					v_free((array__data_header(*a))->allocation);
				} else {
					v_free(a->data);
				}
			}
		}
	}
	a->data = new_data;
	a->offset = 0;
	a->cap = (i64)(cap);
	{
		if (use_noscan_data) {
			a->flags |= 32;
		} else {
			a->flags &= ~32;
		}
	}
	array__set_managed_flags(a, false);
}

void array__free(array* a) {
	if ((a->flags & 64) != 0) {
		return;
	}
	if ((a->flags & 8) != 0) {
		return;
	}
	u8* mblock_ptr = (u8*)((u64)(a->data) - (u64)(a->offset));
	if (mblock_ptr != NULL) {
		{
			if ((a->flags & 16) != 0) {
				v_free((array__data_header(*a))->allocation);
			} else {
				v_free(mblock_ptr);
			}
		}
	}
	{
		a->data = NULL;
		a->offset = 0;
		a->len = 0;
		a->cap = 0;
	}
}

void* array__get(array a, i64 i) {
	{
		if ((i < 0) || (i >= a.len)) {
			panic_n2(_str_12, i, a.len);
		}
	}
	{
		return (void*)((u8*)(a.data) + ((u64)(i) * (u64)(a.element_size)));
	}
}

void* array__get_i64(array a, i64 i) {
	{
		if ((i < 0) || (i >= (i64)(a.len))) {
			panic_n2(_str_12, i, a.len);
		}
	}
	{
		return (void*)((u8*)(a.data) + ((u64)(i) * (u64)(a.element_size)));
	}
}

void* array__get_ni(array a, i64 i) {
	return array__get(a, v_ni_index(i, a.len));
}

void* array__get_u64(array a, u64 i) {
	{
		if (i >= (u64)(a.len)) {
			v_panic(({ string __v3_internal_symbol_join_0[4]; __v3_internal_symbol_join_0[0] = _str_13; __v3_internal_symbol_join_0[1] = u64__str(i); __v3_internal_symbol_join_0[2] = _str_14; __v3_internal_symbol_join_0[3] = impl_i64_to_string(a.len); string_plus_many(4, __v3_internal_symbol_join_0); }));
		}
	}
	{
		return (void*)((u8*)(a.data) + (i * (u64)(a.element_size)));
	}
}

inline void* array__get_unsafe(array a, i64 i) {
	{
		return (void*)((u8*)(a.data) + ((u64)(i) * (u64)(a.element_size)));
	}
}

void* array__get_with_check(array a, i64 i) {
	if ((i < 0) || (i >= a.len)) {
		return 0;
	}
	{
		return (void*)((u8*)(a.data) + ((u64)(i) * (u64)(a.element_size)));
	}
}

void* array__get_with_check_i64(array a, i64 i) {
	if ((i < 0) || (i >= (i64)(a.len))) {
		return 0;
	}
	{
		return (void*)((u8*)(a.data) + ((u64)(i) * (u64)(a.element_size)));
	}
}

void* array__get_with_check_ni(array a, i64 i) {
	return array__get_with_check(a, v_ni_index(i, a.len));
}

void* array__get_with_check_u64(array a, u64 i) {
	if (i >= (u64)(a.len)) {
		return 0;
	}
	{
		return (void*)((u8*)(a.data) + (i * (u64)(a.element_size)));
	}
}

void array__insert(array* a, i64 i, void* val) {
	if ((i < 0) || (i > a->len)) {
		panic_n2(_str_6, i, a->len);
	}
	if (a->len == builtin__max_int) {
		v_panic(_str_7);
	}
	i64 required = a->len + 1;
	if (array__needs_unique_shift(*a, required)) {
		array__clone_shallow_to_cap(a, a->cap);
	} else if (required > a->cap) {
		array__ensure_cap(a, required);
	}
	{
		vmemmove(array__get_unsafe(*a, i + 1), array__get_unsafe(*a, i), (u64)((a->len - i)) * (u64)(a->element_size));
		array__set_unsafe(a, i, val);
	}
	a->len++;
}

void array__insert_many(array* a, i64 i, void* val, i64 size) {
	if ((i < 0) || (i > a->len)) {
		panic_n2(_str_8, i, a->len);
	}
	i64 new_len = (i64)(a->len) + (i64)(size);
	if (new_len > builtin__max_int) {
		panic_n(_str_9, new_len);
	}
	if (array__needs_unique_shift(*a, (i64)(new_len))) {
		array__clone_shallow_to_cap(a, a->cap);
	} else if ((i64)(new_len) > a->cap) {
		array__ensure_cap(a, (i64)(new_len));
	}
	i64 elem_size = a->element_size;
	{
		void* iptr = array__get_unsafe(*a, i);
		vmemmove(array__get_unsafe(*a, i + size), iptr, (u64)(a->len - i) * (u64)(elem_size));
		vmemcpy(iptr, val, (u64)(size) * (u64)(elem_size));
	}
	a->len = (i64)(new_len);
}

inline void array__mark_buffer_has_slices(array* a) {
	if (!((a->flags & 16) != 0) || (a->data == NULL)) {
		return;
	}
	{
		u8* base_data = (u8*)(a->data) - (u64)(a->offset);
		ArrayDataHeader* header = (ArrayDataHeader*)(base_data - array_data_header_size());
		if (!header->has_slices) {
			header->has_slices = true;
		}
	}
}

inline bool array__needs_unique_append(array a, i64 required) {
	return (required <= a.cap) && ((a.flags & 64) != 0);
}

inline bool array__needs_unique_shift(array a, i64 required) {
	return (required <= a.cap) && (((a.flags & 64) != 0) || array__buffer_has_slices(a));
}

inline bool array__needs_unique_shrink(array a) {
	return ((a.flags & 64) != 0) || array__buffer_has_slices(a);
}

void* array__pop_left(array* a) {
	if (a->len == 0) {
		v_panic(_str_17);
	}
	void* first_elem = a->data;
	{
		a->data = (void*)((u8*)(a->data) + (u64)(a->element_size));
	}
	a->offset += a->element_size;
	a->len--;
	a->cap--;
	return first_elem;
}

void array__prepend(array* a, void* val) {
	array__insert(a, 0, val);
}

void array__push(array* a, void* val) {
	{
		if (a->len < 0) {
			v_panic(_str_27);
		}
	}
	if (a->len >= builtin__max_int) {
		v_panic(_str_28);
	}
	i64 required = a->len + 1;
	if (required > a->cap) {
		array__ensure_cap(a, required);
	} else if ((a->flags & 64) != 0) {
		array__clone_shallow_to_cap(a, a->cap);
	}
	{
		copy_element_to((void*)((u8*)(a->data) + ((u64)(a->element_size) * (u64)(a->len))), val, a->element_size);
	}
	a->len++;
}

void array__push_many(array* a, void* val, i64 size) {
	if ((size <= 0) || (val == NULL)) {
		return;
	}
	i64 new_len = (i64)(a->len) + (i64)(size);
	if (new_len > builtin__max_int) {
		v_panic(_str_29);
	}
	if (array__needs_unique_append(*a, (i64)(new_len))) {
		array__clone_shallow_to_cap(a, a->cap);
	}
	bool is_self_append = (a->data == val) && (a->data != 0);
	if ((i64)(new_len) > a->cap) {
		array__ensure_cap(a, (i64)(new_len));
	}
	if (is_self_append) {
		array cloned = array__clone(a);
		{
			vmemcpy((void*)((u8*)(a->data) + ((u64)(a->element_size) * (u64)(a->len))), cloned.data, (u64)(a->element_size) * (u64)(size));
		}
	} else {
		if ((a->data != 0) && (val != 0)) {
			{
				vmemcpy((void*)((u8*)(a->data) + ((u64)(a->element_size) * (u64)(a->len))), val, (u64)(a->element_size) * (u64)(size));
			}
		}
	}
	a->len = (i64)(new_len);
}

array array__reverse(array a) {
	if (a.len < 2) {
		return a;
	}
	bool use_noscan_data = array__uses_noscan_data(a);
	i64 __struct_field_0 = a.element_size;
	void* __struct_field_1 = array__alloc_array_data_like(a, (u64)(a.cap) * (u64)(a.element_size));
	i64 __struct_field_2 = a.len;
	i64 __struct_field_3 = a.cap;
	int __if_val_4 = {0};
	if (use_noscan_data) {
		__if_val_4 = 16 | 32;
	} else {
		__if_val_4 = 16;
	}
	array arr = (array){.element_size = __struct_field_0, .data = __struct_field_1, .len = __struct_field_2, .cap = __struct_field_3, .flags = __if_val_4};
	{
		i64 i = 0;
		for (; i < a.len; i++) {
			{
				array__set_unsafe(&arr, i, array__get_unsafe(a, (a.len - 1) - i));
			}
		}
	}
	return arr;
}

void array__set(array* a, i64 i, void* val) {
	{
		if ((i < 0) || (i >= a->len)) {
			panic_n2(_str_25, i, a->len);
		}
	}
	{
		vmemcpy((void*)((u8*)(a->data) + ((u64)(a->element_size) * (u64)(i))), val, a->element_size);
	}
}

void array__set_i64(array* a, i64 i, void* val) {
	{
		if ((i < 0) || (i >= (i64)(a->len))) {
			panic_n2(_str_25, i, a->len);
		}
	}
	{
		vmemcpy((void*)((u8*)(a->data) + ((u64)(a->element_size) * (u64)(i))), val, a->element_size);
	}
}

inline void array__set_managed_flags(array* a, bool is_slice) {
	{
		a->flags |= 16;
		if (is_slice) {
			a->flags |= 64;
		} else {
			a->flags &= ~64;
		}
	}
}

void array__set_ni(array* a, i64 i, void* val) {
	array__set(a, v_ni_index(i, a->len), val);
}

void array__set_u64(array* a, u64 i, void* val) {
	{
		if (i >= (u64)(a->len)) {
			v_panic(({ string __v3_internal_symbol_join_0[4]; __v3_internal_symbol_join_0[0] = _str_26; __v3_internal_symbol_join_0[1] = u64__str(i); __v3_internal_symbol_join_0[2] = _str_14; __v3_internal_symbol_join_0[3] = impl_i64_to_string(a->len); string_plus_many(4, __v3_internal_symbol_join_0); }));
		}
	}
	{
		vmemcpy((void*)((u8*)(a->data) + ((u64)(a->element_size) * i)), val, a->element_size);
	}
}

inline void array__set_unsafe(array* a, i64 i, void* val) {
	{
		vmemcpy((void*)((u8*)(a->data) + ((u64)(a->element_size) * (u64)(i))), val, a->element_size);
	}
}

array array__slice(array a, i64 start, i64 _end) {
	i64 __if_val_0 = {0};
	if ((_end == builtin__max_i64) || (_end == builtin__max_i32)) {
		__if_val_0 = a.len;
	} else {
		__if_val_0 = _end;
	}
	i64 end = __if_val_0;
	{
		if (start > end) {
			v_panic(({ string __v3_internal_symbol_join_0[4]; __v3_internal_symbol_join_0[0] = _str_20; __v3_internal_symbol_join_0[1] = impl_i64_to_string((i64)(start)); __v3_internal_symbol_join_0[2] = _str_14; __v3_internal_symbol_join_0[3] = impl_i64_to_string(end); string_plus_many(4, __v3_internal_symbol_join_0); }));
		}
		if (end > a.len) {
			v_panic(({ string __v3_internal_symbol_join_1[5]; __v3_internal_symbol_join_1[0] = _str_21; __v3_internal_symbol_join_1[1] = impl_i64_to_string(end); __v3_internal_symbol_join_1[2] = _str_22; __v3_internal_symbol_join_1[3] = impl_i64_to_string(a.len); __v3_internal_symbol_join_1[4] = _str_23; string_plus_many(5, __v3_internal_symbol_join_1); }));
		}
		if (start < 0) {
			v_panic(string__plus(_str_24, impl_i64_to_string(start)));
		}
	}
	{
		array__mark_buffer_has_slices(&a);
	}
	u64 offset = (u64)(start) * (u64)(a.element_size);
	u8* data = (u8*)(a.data) + offset;
	i64 l = end - start;
	int flags = 64;
	if (array__uses_noscan_data(a)) {
		{
			flags |= 32;
		}
	}
	array res = (array){.element_size = a.element_size, .data = (void*)(data), .offset = a.offset + (i64)(offset), .len = l, .cap = l, .flags = flags};
	return res;
}

array array__slice_ni(array a, i64 _start, i64 _end) {
	{
		array__mark_buffer_has_slices(&a);
	}
	int flags = 64;
	if (array__uses_noscan_data(a)) {
		{
			flags |= 32;
		}
	}
	i64 __if_val_0 = {0};
	if ((_end == builtin__max_i64) || (_end == builtin__max_i32)) {
		__if_val_0 = a.len;
	} else {
		__if_val_0 = _end;
	}
	i64 end = __if_val_0;
	i64 start = _start;
	if (start < 0) {
		start = a.len + start;
		if (start < 0) {
			start = 0;
		}
	}
	if (end < 0) {
		end = a.len + end;
		if (end < 0) {
			end = 0;
		}
	}
	if (end >= a.len) {
		end = a.len;
	}
	if ((start >= a.len) || (start > end)) {
		array res = (array){.element_size = a.element_size, .data = a.data, .offset = 0, .len = 0, .cap = 0, .flags = flags};
		return res;
	}
	u64 offset = (u64)(start) * (u64)(a.element_size);
	u8* data = (u8*)(a.data) + offset;
	i64 l = end - start;
	array res = (array){.element_size = a.element_size, .data = (void*)(data), .offset = a.offset + (i64)(offset), .len = l, .cap = l, .flags = flags};
	return res;
}

inline bool array__uses_noscan_data(array a) {
	return (a.flags & 32) != 0;
}

inline u64 array_data_allocation_size(u64 total_size) {
	return ((u64)(array_data_header_size()) + 15) + __at_least_one(total_size);
}

inline i64 array_data_header_size(void) {
	return 16;
}

inline void array_sort_move(void* dst, i64 di, void* src, i64 si, i64 count, size_t element_size) {
	vmemcpy((void*)((u8*)(dst) + ((size_t)(di) * element_size)), (void*)((u8*)(src) + ((size_t)(si) * element_size)), (ptrdiff_t)((size_t)(count) * element_size));
}

bool autostr_addr_in_stack(void* addr) {
	if (g_autostr_addr_state.len >= builtin__autostr_type_stack_max_depth) {
		return true;
	}
	{
		i64 i = 0;
		for (; i < g_autostr_addr_state.len; i++) {
			if (g_autostr_addr_state.addrs[v_fixed_index(i, 64)] == addr) {
				return true;
			}
		}
	}
	return false;
}

void autostr_addr_pop(void) {
	if (g_autostr_addr_state.overflow_depth > 0) {
		g_autostr_addr_state.overflow_depth--;
	} else if (g_autostr_addr_state.len > 0) {
		g_autostr_addr_state.len--;
	}
}

void autostr_addr_push(void* addr) {
	if (g_autostr_addr_state.len >= builtin__autostr_type_stack_max_depth) {
		g_autostr_addr_state.overflow_depth++;
		return;
	}
	g_autostr_addr_state.addrs[v_fixed_index(g_autostr_addr_state.len, 64)] = addr;
	g_autostr_addr_state.types[v_fixed_index(g_autostr_addr_state.len, 64)] = 0;
	g_autostr_addr_state.len++;
}

bool autostr_addr_type_in_stack(void* addr, i64 typ) {
	if (g_autostr_addr_state.len >= builtin__autostr_type_stack_max_depth) {
		return true;
	}
	{
		i64 i = 0;
		for (; i < g_autostr_addr_state.len; i++) {
			if ((g_autostr_addr_state.addrs[v_fixed_index(i, 64)] == addr) && (g_autostr_addr_state.types[v_fixed_index(i, 64)] == typ)) {
				return true;
			}
		}
	}
	return false;
}

void autostr_addr_type_push(void* addr, i64 typ) {
	if (g_autostr_addr_state.len >= builtin__autostr_type_stack_max_depth) {
		g_autostr_addr_state.overflow_depth++;
		return;
	}
	g_autostr_addr_state.addrs[v_fixed_index(g_autostr_addr_state.len, 64)] = addr;
	g_autostr_addr_state.types[v_fixed_index(g_autostr_addr_state.len, 64)] = typ;
	g_autostr_addr_state.len++;
}

string autostr_array_circular(i64 len) {
	if (len <= 0) {
		return _str_35;
	}
	Array __esc_0 = strings__new_builder(2 + (len * 12));
	Array* sb = (Array*)(memdup(&__esc_0, sizeof(Array)));
	strings__Builder__write_string(sb, _str_36);
	{
		i64 i = 0;
		for (; i < len; i++) {
			if (i > 0) {
				strings__Builder__write_string(sb, _str_14);
			}
			strings__Builder__write_string(sb, _str_37);
		}
	}
	strings__Builder__write_string(sb, _str_38);
	string res = strings__Builder__str(sb);
	{
		strings__Builder__free(sb);
	}
	return res;
}

bool autostr_type_in_stack(i64 typ) {
	{
		i64 i = 0;
		for (; i < g_autostr_type_stack_len; i++) {
			if (g_autostr_type_stack[v_fixed_index(i, 64)] == typ) {
				return true;
			}
		}
	}
	return false;
}

void autostr_type_pop(void) {
	if (g_autostr_type_stack_len > 0) {
		g_autostr_type_stack_len--;
	}
}

void autostr_type_push(i64 typ) {
	if (g_autostr_type_stack_len >= builtin__autostr_type_stack_max_depth) {
		return;
	}
	g_autostr_type_stack[v_fixed_index(g_autostr_type_stack_len, 64)] = typ;
	g_autostr_type_stack_len++;
}

inline multi_return_u64_u64 bits__mul_64(u64 x, u64 y) {
	u64 hi = (u64)(0);
	u64 lo = (u64)(0);
	{
		__asm__ (
			"mulq %%rdx\n\t"
			: [lo] "=a" (lo),
			[hi] "=d" (hi)
			: [x] "a" (x),
			[y] "d" (y)
			: "cc"
		);
		return (multi_return_u64_u64){hi, lo};
	}
	return bits__mul_64_default(x, y);
}

multi_return_u64_u64 bits__mul_64_default(u64 x, u64 y) {
	u64 x0 = x & bits__mask32;
	u64 x1 = (u64)(((u64)(	x)) >> (32));
	u64 v_y0 = y & bits__mask32;
	u64 v_y1 = (u64)(((u64)(	y)) >> (32));
	u64 w0 = x0 * v_y0;
	u64 t = (x1 * v_y0) + ((u64)(((u64)(	w0)) >> (32)));
	u64 w1 = t & bits__mask32;
	u64 w2 = (u64)(((u64)(	t)) >> (32));
	w1 += x0 * v_y1;
	u64 hi = ((x1 * v_y1) + w2) + ((u64)(((u64)(	w1)) >> (32)));
	u64 lo = x * y;
	return (multi_return_u64_u64){hi, lo};
}

inline i64 bits__trailing_zeros_32(u32 x) {
	if (x == 0) {
		return 32;
	}
	{
		return __builtin_ctz(x);
	}
	return bits__trailing_zeros_32_default(x);
}

inline i64 bits__trailing_zeros_32_default(u32 x) {
	if (x == 0) {
		return 32;
	}
	return (i64)(bits__de_bruijn32tab[(u32)(((u32)(	(x & -x) * bits__de_bruijn32)) >> ((32 - 5)))]);
}

inline i64 bits__trailing_zeros_64(u64 x) {
	if (x == 0) {
		return 64;
	}
	{
		return __builtin_ctzll(x);
	}
	return bits__trailing_zeros_64_default(x);
}

inline i64 bits__trailing_zeros_64_default(u64 x) {
	if (x == 0) {
		return 64;
	}
	return (i64)(bits__de_bruijn64tab[(i64)((u64)(((u64)(	(x & -x) * bits__de_bruijn64)) >> ((64 - 6))))]);
}

string bool__str(bool b) {
	if (b) {
		return _str_58;
	}
	return _str_59;
}

void builtin_init(void) {
	{
		unbuffer_stdout();
	}
}

Array byteptr__vbytes(u8* data, i64 len) {
	return voidptr__vbytes((void*)(data), len);
}

string byteptr__vstring(u8* bp) {
	return (string){.str = bp, .len = vstrlen(bp)};
}

string byteptr__vstring_with_len(u8* bp, i64 len) {
	return (string){.str = bp, .len = len, .is_lit = 0};
}

string charptr__vstring(char* cp) {
	return (string){.str = (u8*)((u8*)(cp)), .len = vstrlen_char(cp), .is_lit = 0};
}

string charptr__vstring_with_len(char* cp, i64 len) {
	return (string){.str = (u8*)((u8*)(cp)), .len = len, .is_lit = 0};
}

inline void copy_element_to(void* dest, void* src, i64 element_size) {
	{
		if (element_size == 1) {
			vmemcpy(dest, src, 1);
		} else if (element_size == 2) {
			vmemcpy(dest, src, 2);
		} else if (element_size == 4) {
			vmemcpy(dest, src, 4);
		} else if (element_size == 8) {
			vmemcpy(dest, src, 8);
		} else if (element_size == 16) {
			vmemcpy(dest, src, 16);
		} else {
			vmemcpy(dest, src, element_size);
		}
	}
}

string data_to_hex_string(u8* data, i64 len) {
	u8* hex = malloc_noscan(((u64)(len) * 2) + 1);
	i64 dst = 0;
	{
		i64 c = 0;
		for (; c < len; c++) {
			u8 b = (data)[c];
			u8 n0 = (u8)(((u8)(			b)) >> (4));
			u8 n1 = b & 0xF;
			u8 __if_val_0 = {0};
			if (n0 < 10) {
				__if_val_0 = n0 + '0';
			} else {
				__if_val_0 = n0 + 'W';
			}
			(hex)[dst] = __if_val_0;
			u8 __if_val_1 = {0};
			if (n1 < 10) {
				__if_val_1 = n1 + '0';
			} else {
				__if_val_1 = n1 + 'W';
			}
			(hex)[dst + 1] = __if_val_1;
			dst += 2;
		}
	}
	(hex)[dst] = 0;
	return tos(hex, dst);
}

void eprint(string s) {
	{
		flush_stdout();
		flush_stderr();
		_write_buf_to_fd(2, s.str, s.len);
		flush_stderr();
	}
}

void eprintln(string s) {
	{
		flush_stdout();
		flush_stderr();
		_writeln_to_fd(2, s);
		flush_stderr();
	}
}

inline IError error(string message) {
	return (IError){._typ = 71273906, ._object = 	(MessageError*)memdup(&(MessageError){.msg = message}, sizeof(MessageError)), ._object_is_boxed = true};
}

inline IError error_with_code(string message, i64 code) {
	return (IError){._typ = 71273906, ._object = 	(MessageError*)memdup(&(MessageError){.msg = message, .code = code}, sizeof(MessageError)), ._object_is_boxed = true};
}

inline bool f32__eq_epsilon(float a, float b) {
	float hi = f32_max(f32_abs(a), f32_abs(b));
	float delta = f32_abs(a - b);
	if (hi > (float)(1.0)) {
		return delta <= (hi * (4 * (float)((float)(FLT_EPSILON))));
	} else {
		return ((1 / (4 * (float)((float)(FLT_EPSILON)))) * delta) <= hi;
	}
}

inline string f32__str(float x) {
	{
		strconv__Float32u f = (strconv__Float32u){.f = x};
		if (f.u == strconv__single_minus_zero) {
			return _str_191;
		}
		if (f.u == strconv__single_plus_zero) {
			return _str_192;
		}
	}
	float abs_x = f32_abs(x);
	if ((abs_x >= (float)(0.0001)) && (abs_x < (float)(1.0e6))) {
		return strconv__f32_to_str_l(x);
	} else {
		return strconv__ftoa_32(x);
	}
}

inline float f32_abs(float a) {
	if (a < 0) {
		return -a;
	}
	return a;
}

inline float f32_max(float a, float b) {
	if (a > b) {
		return a;
	}
	return b;
}

inline string f64__str(double x) {
	{
		strconv__Float64u f = (strconv__Float64u){.f = x};
		if (f.u == strconv__double_minus_zero) {
			return _str_191;
		}
		if (f.u == strconv__double_plus_zero) {
			return _str_192;
		}
	}
	double abs_x = f64_abs(x);
	if ((abs_x >= 0.0001) && (abs_x < 1.0e6)) {
		return strconv__f64_to_str_l(x);
	} else {
		return strconv__ftoa_64(x);
	}
}

inline double f64_abs(double a) {
	if (a < 0) {
		return -a;
	}
	return a;
}

inline bool fast_string_eq(string a, string b) {
	if (a.len != b.len) {
		return false;
	}
	{
		return memcmp(a.str, b.str, b.len) == 0;
	}
}

void flush_stderr(void) {
	{
		fflush(stderr);
	}
}

void flush_stdout(void) {
	{
		fflush(stdout);
	}
}

inline void gc_runtime_init(void) {
}

string i16__str(i16 n) {
	return int__str_l((i64)(n), 6);
}

string i32__str(i32 n) {
	return int__str_l((i64)(n), 11);
}

inline string i64__str(i64 nn) {
	return impl_i64_to_string(nn);
}

string i8__str(i8 n) {
	return int__str_l((i64)(n), 4);
}

string impl_i64_to_string(i64 nn) {
	{
		i64 n = nn;
		i64 d = (i64)(0);
		if (n == 0) {
			return _str_56;
		} else if (n == builtin__min_i64) {
			return _str_57;
		}
		i64 max = 20;
		u8* buf = malloc_noscan(max + 1);
		bool is_neg = false;
		if (n < 0) {
			n = -n;
			is_neg = true;
		}
		i64 v_index = max;
		(buf)[v_index] = 0;
		v_index--;
		while (n > 0) {
			i64 n1 = ({ i64 _t1 = (i64)(n); i64 _t2 = (i64)((i64)(100)); if (_t2 == 0) v_panic(_S("division by zero")); (i64)(_t1 / _t2); });
			d = (({ u32 _t3 = (u32)(			(u32)(n - (n1 * (i64)(100)))); u64 _t4 = (u64)((i64)(1)); _t4 >= 32 ? (u32)0 : (u32)(_t3 << _t4); }));
			n = n1;
			(buf)[v_index] = (builtin__digit_pairs).str[(i64)(d)];
			v_index--;
			d++;
			(buf)[v_index] = (builtin__digit_pairs).str[(i64)(d)];
			v_index--;
		}
		v_index++;
		if (d < (i64)(20)) {
			v_index++;
		}
		if (is_neg) {
			v_index--;
			(buf)[v_index] = '-';
		}
		i64 diff = max - v_index;
		vmemmove((void*)(buf), (void*)(buf + v_index), diff + 1);
		return tos(buf, diff);
	}
}

inline void* init_array_data(void* raw) {
	size_t padding = ({ size_t _t1 = (size_t)((16 - (({ size_t _t3 = (size_t)(((size_t)(raw) + (size_t)(array_data_header_size()))); size_t _t4 = (size_t)(16); if (_t4 == 0) v_panic(_S("modulo by zero")); (size_t)(_t3 % _t4); })))); size_t _t2 = (size_t)(16); if (_t2 == 0) v_panic(_S("modulo by zero")); (size_t)(_t1 % _t2); });
	{
		u8* data = ((u8*)(raw) + array_data_header_size()) + padding;
		ArrayDataHeader* header = (ArrayDataHeader*)(data - array_data_header_size());
		header->allocation = raw;
		header->has_slices = false;
		return (void*)(data);
	}
}

string int__str(i64 n) {
	{
		return impl_i64_to_string(n);
	}
}

inline string int__str_l(i64 nn, i64 max) {
	{
		i64 n = (i64)(nn);
		i64 d = 0;
		if (n == 0) {
			return _str_56;
		}
		{
			if (n == builtin__min_i64) {
				return _str_57;
			}
		}
		bool is_neg = false;
		if (n < 0) {
			n = -n;
			is_neg = true;
		}
		i64 v_index = max;
		u8* buf = malloc_noscan(max + 1);
		(buf)[v_index] = 0;
		v_index--;
		while (n > 0) {
			i64 n1 = (i64)(({ i64 _t1 = (i64)(n); i64 _t2 = (i64)(100); if (_t2 == 0) v_panic(_S("division by zero")); (i64)(_t1 / _t2); }));
			d = (i64)((u32)(((u32)(			(u32)((i64)(n) - (n1 * 100)))) << (1)));
			n = n1;
			(buf)[v_index] = (builtin__digit_pairs.str)[d];
			v_index--;
			d++;
			(buf)[v_index] = (builtin__digit_pairs.str)[d];
			v_index--;
		}
		v_index++;
		if (d < 20) {
			v_index++;
		}
		if (is_neg) {
			v_index--;
			(buf)[v_index] = '-';
		}
		i64 diff = max - v_index;
		vmemmove((void*)(buf), (void*)(buf + v_index), diff + 1);
		return tos(buf, diff);
	}
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

int main(int argc, char** argv) {
	g_main_argc = argc;
	g_main_argv = argv;
	if (getenv("VEXE") == NULL || getenv("VEXE")[0] == 0) {
		const char* v3_vexe = "/Users/alex/code/v/v";
		if (v3_vexe[0] != 0) {
#ifdef _WIN32
			_putenv_s("VEXE", v3_vexe);
#else
			setenv("VEXE", v3_vexe, 1);
#endif
		}
	}
	_vinit();
	u16 narrow = (u16)(0x55aa);
	u16 small = katomic__load_T_u16(&narrow);
	main__Probe storage = (main__Probe){.value = 0x123456789abcdef0};
	main__Probe* slot = &storage;
	main__Probe* loaded = katomic__load_T_ptr_Probe(&slot);
	vinix_consume(small, (void*)(loaded));
	return 0;
}

u8* malloc_noscan(ptrdiff_t n) {
	if (n < 0) {
		_memory_panic(_str_163, n);
	}
	u8* res = (u8*)(NULL);
	{
		{
			res = (u8*)(malloc(n));
		}
	}
	if (res == 0) {
		_memory_panic(_str_163, n);
	}
	return res;
}

u8* malloc_uninit(ptrdiff_t n) {
	if (n < 0) {
		_memory_panic(_str_164, n);
	} else if (n == 0) {
		return (u8*)(NULL);
	}
	return v_malloc(n);
}

void map__clear(map* m) {
	VMapData__clear(m->data);
}

map map__clone(map* m) {
	if ((m->data == NULL) || (m->data == &map_empty_data)) {
		return (map){.data = &map_empty_data};
	}
	return (map){.data = VMapData__clone(m->data)};
}

void map__delete(map* m, void* key) {
	{
		VMapData__delete(m->data, key);
	}
}

bool map__exists(map* m, void* key) {
	return VMapData__exists(m->data, key);
}

void map__free(map* m) {
	if ((m->data == NULL) || (m->data == &map_empty_data)) {
		return;
	}
	VMapData* data = m->data;
	map* target = (map*)(m);
	target->data = &map_empty_data;
	{
		VMapData__free(data);
		v_free(data);
	}
}

void* map__get(map* m, void* key, void* zero) {
	return VMapData__get(m->data, key, zero);
}

void* map__get_and_set(map* m, void* key, void* zero) {
	return VMapData__get_and_set(m->data, key, zero);
}

void* map__get_check(map* m, void* key) {
	return VMapData__get_check(m->data, key);
}

array map__keys(map* m) {
	return VMapData__keys(m->data);
}

void map__reserve(map* m, u32 n) {
	VMapData__reserve(m->data, n);
}

void map__set(map* m, void* key, void* value) {
	VMapData__set(m->data, key, value);
}

array map__values(map* m) {
	return VMapData__values(m->data);
}

inline void map_clone_int_1(void* dest, void* pkey) {
	{
		*(u8*)(dest) = *(u8*)(pkey);
	}
}

inline void map_clone_int_16(void* dest, void* pkey) {
	{
		vmemcpy(dest, pkey, 16);
	}
}

inline void map_clone_int_2(void* dest, void* pkey) {
	{
		*(u16*)(dest) = *(u16*)(pkey);
	}
}

inline void map_clone_int_4(void* dest, void* pkey) {
	{
		*(u32*)(dest) = *(u32*)(pkey);
	}
}

inline void map_clone_int_8(void* dest, void* pkey) {
	{
		*(u64*)(dest) = *(u64*)(pkey);
	}
}

inline void map_clone_string(void* dest, void* pkey) {
	{
		string s = *(string*)(pkey);
		string cloned = string__clone(s);
		vmemcpy(dest, (void*)(&cloned), sizeof(string));
	}
}

inline bool map_eq_int_1(void* a, void* b) {
	return *(u8*)(a) == *(u8*)(b);
}

inline bool map_eq_int_16(void* a, void* b) {
	return vmemcmp(a, b, 16) == 0;
}

inline bool map_eq_int_2(void* a, void* b) {
	return *(u16*)(a) == *(u16*)(b);
}

inline bool map_eq_int_4(void* a, void* b) {
	return *(u32*)(a) == *(u32*)(b);
}

inline bool map_eq_int_8(void* a, void* b) {
	return *(u64*)(a) == *(u64*)(b);
}

inline bool map_eq_string(void* a, void* b) {
	return fast_string_eq(*(string*)(a), *(string*)(b));
}

inline void map_free_nop(void* _0) {
}

inline void map_free_string(void* pkey) {
	{
		string__free(((string*)(pkey)));
	}
}

u64 map_hash_int_1(void* pkey) {
	return wyhash64(*(u8*)(pkey), 0);
}

u64 map_hash_int_16(void* pkey) {
	u64 halves[2];
	memmove(halves, (u64[2]){0}, sizeof(halves));
	{
		memcpy(&halves[0], pkey, 16);
	}
	return wyhash64(halves[0], halves[1]);
}

u64 map_hash_int_2(void* pkey) {
	return wyhash64(*(u16*)(pkey), 0);
}

u64 map_hash_int_4(void* pkey) {
	return wyhash64(*(u32*)(pkey), 0);
}

u64 map_hash_int_8(void* pkey) {
	return wyhash64(*(u64*)(pkey), 0);
}

u64 map_hash_string(void* pkey) {
	string* key = (string*)(pkey);
	return wyhash(key->str, (u64)(key->len), 0, (u64*)((void*)(_wyp)));
}

bool map_map_eq(map a, map b) {
	if (a.data->count != b.data->count) {
		return false;
	}
	{
		i64 i = 0;
		for (; i < a.data->key_values.len; i++) {
			if (!DenseArray__has_index(&a.data->key_values, i)) {
				continue;
			}
			void* k = DenseArray__key(&a.data->key_values, i);
			if (!VMapData__exists(b.data, k)) {
				return false;
			}
			void* va = DenseArray__value(&a.data->key_values, i);
			void* vb = VMapData__get(b.data, k, va);
			if (vmemcmp(va, vb, a.data->value_bytes) != 0) {
				return false;
			}
		}
	}
	return true;
}

void* memdup(void* src, ptrdiff_t sz) {
	if (sz == 0) {
		return (void*)(vcalloc(1));
	}
	{
		u8* mem = v_malloc(sz);
		return memcpy(mem, src, sz);
	}
}

void* memdup_align(void* src, ptrdiff_t sz, ptrdiff_t align) {
	if (sz == 0) {
		return (void*)(vcalloc(1));
	}
	ptrdiff_t n = sz;
	if (n < 0) {
		_memory_panic(_str_170, n);
	}
	u8* res = (u8*)(NULL);
	{
		{
			res = (u8*)(aligned_alloc(align, n));
		}
	}
	if (res == 0) {
		_memory_panic(_str_170, n);
	}
	return memcpy(res, src, sz);
}

void* memdup_noscan(void* src, ptrdiff_t sz) {
	if (sz == 0) {
		return (void*)(vcalloc_noscan(1));
	}
	{
		u8* mem = malloc_noscan(sz);
		return memcpy(mem, src, sz);
	}
}

array new_array_from_c_array(i64 len, i64 cap, i64 elm_size, void* c_array) {
	panic_on_negative_len(len);
	panic_on_negative_cap(cap);
	i64 cap_ = cap;
	if (cap < len) {
		cap_ = len;
	}
	array arr = (array){.element_size = elm_size, .data = alloc_array_data((u64)(cap_) * (u64)(elm_size)), .len = len, .cap = cap_, .flags = 16};
	{
		vmemcpy(arr.data, c_array, (u64)(len) * (u64)(elm_size));
	}
	return arr;
}

array new_array_from_c_array_noscan(i64 len, i64 cap, i64 elm_size, void* c_array) {
	return new_array_from_c_array(len, cap, elm_size, c_array);
}

inline DenseArray new_dense_array(i64 key_bytes, i64 value_bytes) {
	i64 cap = 8;
	return (DenseArray){.key_bytes = key_bytes, .value_bytes = value_bytes, .cap = cap, .len = 0, .deletes = 0, .all_deleted = NULL, .keys = v_malloc(__at_least_one((u64)(cap) * (u64)(key_bytes))), .values = v_malloc(__at_least_one((u64)(cap) * (u64)(value_bytes)))};
}

map new_map(i64 key_bytes, i64 value_bytes, _fn_ptr_1e8d64a3d95a0da1 hash_fn, _fn_ptr_c95f092653bee64 key_eq_fn, _fn_ptr_1a3da2026b1489ea clone_fn, _fn_ptr_5373f7edc7b60e26 free_fn) {
	return (map){.data = new_map_data(key_bytes, value_bytes, hash_fn, key_eq_fn, clone_fn, free_fn)};
}

VMapData* new_map_data(i64 key_bytes, i64 value_bytes, _fn_ptr_1e8d64a3d95a0da1 hash_fn, _fn_ptr_c95f092653bee64 key_eq_fn, _fn_ptr_1a3da2026b1489ea clone_fn, _fn_ptr_5373f7edc7b60e26 free_fn) {
	bool has_string_keys = key_bytes > (i64)(sizeof(void*));
	u32 initial_extra_metas = (u32)(builtin__extra_metas_inc);
	return (VMapData*)memdup(&(VMapData){.key_bytes = key_bytes, .value_bytes = value_bytes, .even_index = builtin__init_even_index, .cached_hashbits = builtin__max_cached_hashbits, .shift = builtin__init_log_capicity, .key_values = (DenseArray){.key_bytes = key_bytes, .value_bytes = value_bytes, .all_deleted = NULL, .keys = NULL, .values = NULL}, .metas = NULL, .extra_metas = initial_extra_metas, .count = 0, .has_string_keys = has_string_keys, .hash_fn = hash_fn, .key_eq_fn = key_eq_fn, .clone_fn = clone_fn, .free_fn = free_fn}, sizeof(VMapData));
}

VNORETURN void panic_debug(i64 line_no, string file, string mod, string fn_name, string s) {
	if ((g_panic_state.top != NULL) || (g_panic_state.len > 0)) {
		panic_unwind(s, (PanicDebugInfo){.line_no = line_no, .file = file, .mod = mod, .fn_name = fn_name});
	}
	{
		flush_stdout();
		eprintln(_str_195);
		eprint(_str_196);
		eprintln(mod);
		eprint(_str_197);
		eprint(fn_name);
		eprintln(_str_198);
		eprint(_str_199);
		eprintln(s);
		eprint(_str_200);
		eprint(file);
		eprint(_str_91);
		fprintf(stderr, "%d\n", (int)(line_no));
		eprint(_str_201);
		eprintln(vcurrent_hash());
		{
			eprint(_str_202);
			fprintf(stderr, "%p\n", (void*)(v_getpid()));
			eprint(_str_203);
			fprintf(stderr, "%p\n", (void*)(v_gettid()));
		}
		eprintln(_str_204);
		flush_stdout();
		{
			{
				print_backtrace_skipping_top_frames(1);
			}
			exit(1);
		}
	}
	exit(1);
	for (;;) {
	}
}

VNORETURN void panic_fatal(void) {
	string msg = _str_30;
	{
		i64 i = 0;
		for (; i < g_panic_state.len; i++) {
			PanicRecord* rec = panic_record(i);
			if (i > 0) {
				msg = string__plus(msg, _str_211);
			}
			msg = string__plus(msg, string__clone(rec->msg));
			if (rec->recovered) {
				msg = string__plus(msg, _str_212);
			}
		}
	}
	PanicDebugInfo debug = (panic_record(g_panic_state.len - 1))->debug;
	panic_frames_reset();
	{
		if (debug.file.len > 0) {
			panic_debug(debug.line_no, debug.file, debug.mod, debug.fn_name, msg);
		}
	}
	v_panic(msg);
}

void panic_frame_done(void* frame) {
	PanicFrame* f = (PanicFrame*)(frame);
	PanicRecord* rec = panic_record(g_panic_state.len - 1);
	if (!rec->recovered) {
		panic_jump_next();
	}
	PanicFrame* next = g_panic_state.top;
	if ((next != NULL) && (next->owner == f->owner)) {
		g_panic_state.top = next->prev;
		rec->frame = next;
		rec->resume = next->prev;
		next->jump((void*)(next));
	}
	panic_record_drop();
	while ((g_panic_state.len > 0) && (panic_record(g_panic_state.len - 1))->aborted) {
		panic_record_drop();
	}
}

void panic_frame_pop(void* frame) {
	PanicFrame* f = (PanicFrame*)(frame);
	bool __ptr_eq_0 = (void*)(g_panic_state.top) == (void*)(f);
	if (!__ptr_eq_0 && ((void*)(g_panic_state.top) != NULL) && ((void*)(f) != NULL)) {
		PanicFrame __eq_lhs_1 = *g_panic_state.top;
		PanicFrame __eq_rhs_2 = *f;
		__ptr_eq_0 = (__eq_lhs_1.prev == __eq_rhs_2.prev) && (__eq_lhs_1.owner == __eq_rhs_2.owner) && (__eq_lhs_1.jump == __eq_rhs_2.jump);
	}
	if (__ptr_eq_0) {
		g_panic_state.top = f->prev;
		return;
	}
	PanicFrame* cur = g_panic_state.top;
	while (cur != NULL) {
		bool __ptr_eq_3 = (void*)(cur->prev) == (void*)(f);
		if (!__ptr_eq_3 && ((void*)(cur->prev) != NULL) && ((void*)(f) != NULL)) {
			PanicFrame __eq_lhs_4 = *cur->prev;
			PanicFrame __eq_rhs_5 = *f;
			__ptr_eq_3 = (__eq_lhs_4.prev == __eq_rhs_5.prev) && (__eq_lhs_4.owner == __eq_rhs_5.owner) && (__eq_lhs_4.jump == __eq_rhs_5.jump);
		}
		if (__ptr_eq_3) {
			cur->prev = f->prev;
			return;
		}
		cur = cur->prev;
	}
}

void panic_frame_push(void* frame) {
	PanicFrame* f = (PanicFrame*)(frame);
	f->prev = g_panic_state.top;
	g_panic_state.top = f;
}

void panic_frame_relink(void* frame) {
	panic_frame_push(frame);
	if (g_panic_state.len > 0) {
		PanicRecord* rec = panic_record(g_panic_state.len - 1);
		if ((void*)(rec->frame) == frame) {
			rec->resume = (PanicFrame*)(frame);
		}
	}
}

void panic_frames_reset(void) {
	g_panic_state.top = NULL;
	while (g_panic_state.len > 0) {
		panic_record_drop();
	}
}

VNORETURN void panic_jump_next(void) {
	PanicFrame* frame = g_panic_state.top;
	i64 i = g_panic_state.len - 2;
	while ((i >= 0) && ({PanicFrame* __ptr_eq_lhs_0 = (panic_record(i))->resume;
	bool __ptr_eq_1 = (void*)(__ptr_eq_lhs_0) == (void*)(frame);
	if (!__ptr_eq_1 && ((void*)(__ptr_eq_lhs_0) != NULL) && ((void*)(frame) != NULL)) {
		PanicFrame __eq_lhs_2 = *__ptr_eq_lhs_0;
		PanicFrame __eq_rhs_3 = *frame;
		__ptr_eq_1 = (__eq_lhs_2.prev == __eq_rhs_3.prev) && (__eq_lhs_2.owner == __eq_rhs_3.owner) && (__eq_lhs_2.jump == __eq_rhs_3.jump);
	}
	__ptr_eq_1;})) {
		(panic_record(i))->aborted = true;
		i--;
	}
	if (frame == NULL) {
		panic_fatal();
	}
	g_panic_state.top = frame->prev;
	PanicRecord* rec = panic_record(g_panic_state.len - 1);
	rec->frame = frame;
	rec->resume = frame->prev;
	frame->jump((void*)(frame));
	for (;;) {
	}
}

VNORETURN void panic_n(string s, i64 number1) {
	v_panic(string__plus(s, impl_i64_to_string(number1)));
}

VNORETURN void panic_n2(string s, i64 number1, i64 number2) {
	v_panic(({ string __v3_internal_symbol_join_0[4]; __v3_internal_symbol_join_0[0] = s; __v3_internal_symbol_join_0[1] = impl_i64_to_string(number1); __v3_internal_symbol_join_0[2] = _str_14; __v3_internal_symbol_join_0[3] = impl_i64_to_string(number2); string_plus_many(4, __v3_internal_symbol_join_0); }));
}

VNORETURN void panic_n3(string s, i64 number1, i64 number2, i64 number3) {
	v_panic(({ string __v3_internal_symbol_join_0[6]; __v3_internal_symbol_join_0[0] = s; __v3_internal_symbol_join_0[1] = impl_i64_to_string(number1); __v3_internal_symbol_join_0[2] = _str_14; __v3_internal_symbol_join_0[3] = impl_i64_to_string(number2); __v3_internal_symbol_join_0[4] = _str_14; __v3_internal_symbol_join_0[5] = impl_i64_to_string(number3); string_plus_many(6, __v3_internal_symbol_join_0); }));
}

void panic_on_negative_cap(i64 cap) {
	if (cap < 0) {
		panic_n(_str_34, cap);
	}
}

void panic_on_negative_len(i64 len) {
	if (len < 0) {
		panic_n(_str_33, len);
	}
}

inline PanicRecord* panic_record(i64 i) {
	return &(g_panic_state.records)[i];
}

void panic_record_drop(void) {
	g_panic_state.len--;
	PanicRecord* rec = panic_record(g_panic_state.len);
	{
		free(rec->msg.str);
		*rec = (PanicRecord){.frame = NULL, .resume = NULL, .msg = _str_30, .debug = (PanicDebugInfo){.file = _str_30, .mod = _str_30, .fn_name = _str_30}};
	}
	if (g_panic_state.len == 0) {
		{
			free(g_panic_state.records);
		}
		g_panic_state.records = NULL;
		g_panic_state.cap = 0;
	}
}

__v_option_string panic_recover_frame(void* frame) {
	if (g_panic_state.len == 0) {
		return (__v_option_string){.ok = false};
	}
	PanicRecord* rec = panic_record(g_panic_state.len - 1);
	if (rec->recovered || rec->aborted || ((void*)(rec->frame) != frame)) {
		return (__v_option_string){.ok = false};
	}
	rec->recovered = true;
	return (__v_option_string){.ok = true, .value = string__clone(rec->msg)};
	return (__v_option_string){.ok = true};
}

VNORETURN void panic_unwind(string msg, PanicDebugInfo debug) {
	if (g_panic_state.len == g_panic_state.cap) {
		i64 __if_val_0 = {0};
		if (g_panic_state.cap == 0) {
			__if_val_0 = 4;
		} else {
			__if_val_0 = g_panic_state.cap * 2;
		}
		i64 new_cap = __if_val_0;
		PanicRecord* records = (PanicRecord*)(realloc(g_panic_state.records, (size_t)(new_cap) * (size_t)(sizeof(PanicRecord))));
		if (records == NULL) {
			panic_frames_reset();
			v_panic(msg);
		}
		g_panic_state.records = records;
		g_panic_state.cap = new_cap;
	}
	u8* msg_copy = (u8*)(malloc((size_t)(msg.len + 1)));
	if (msg_copy == NULL) {
		panic_frames_reset();
		v_panic(msg);
	}
	{
		memcpy(msg_copy, msg.str, (size_t)(msg.len));
		(msg_copy)[msg.len] = 0;
	}
	PanicRecord* rec = panic_record(g_panic_state.len);
	{
		*rec = (PanicRecord){.msg = (string){.str = msg_copy, .len = msg.len, .is_lit = 1}, .debug = debug, .frame = NULL, .resume = NULL};
	}
	g_panic_state.len++;
	panic_jump_next();
}

bool print_backtrace_skipping_top_frames(i64 xskipframes) {
	{
		i64 skipframes = xskipframes + 2;
		{
			return print_backtrace_skipping_top_frames_linux(skipframes);
		}
	}
	return false;
}

bool print_backtrace_skipping_top_frames_linux(i64 skipframes) {
	{
		{
			{
				{
					eprintln(_str_183);
					eprintln(_str_184);
				}
				return false;
			}
		}
	}
	return true;
}

string ptr_str(void* ptr) {
	string buf1 = u64_to_hex_no_leading_zeros((u64)(ptr), 16);
	return buf1;
}

void race_stdio_write(void) {
}

u8* realloc_data(u8* old_data, i64 old_size, i64 new_size) {
	u8* nptr = (u8*)(NULL);
	{
		{
			nptr = (u8*)(realloc(old_data, new_size));
		}
	}
	if (nptr == 0) {
		_memory_panic(_str_168, (ptrdiff_t)(new_size));
	}
	if (old_data != NULL) {
	}
	return nptr;
}

Array rune__bytes(u32 c) {
	Array res = __new_array_noscan(0, 5, sizeof(u8));
	u8* buf = (u8*)(res.data);
	res.len = utf32_decode_to_buffer((u32)(c), &buf);
	return res;
}

u32 rune__map_to(u32 c, int mode) {
	i64 start = 0;
	i64 end = ({ i64 _t1 = (i64)(1264); i64 _t2 = (i64)(builtin__rune_maps_columns_in_row); if (_t2 == 0) v_panic(_S("division by zero")); (i64)(_t1 / _t2); });
	while (start < end) {
		i64 middle = ({ i64 _t3 = (i64)((start + end)); i64 _t4 = (i64)(2); if (_t4 == 0) v_panic(_S("division by zero")); (i64)(_t3 / _t4); });
		i32* cur_map = &builtin__rune_maps[middle * builtin__rune_maps_columns_in_row];
		if ((c >= (u32)(*cur_map)) && (c <= (u32)(*(cur_map + 1)))) {
			i32 __if_val_0 = {0};
			if ((mode == MapMode__to_upper) || (mode == MapMode__to_title)) {
				__if_val_0 = *(cur_map + 2);
			} else {
				__if_val_0 = *(cur_map + 3);
			}
			i32 offset = __if_val_0;
			if (offset == builtin__rune_maps_ul) {
				u32 cnt = ({ u32 _t5 = (u32)((c - *cur_map)); u32 _t6 = (u32)(2); if (_t6 == 0) v_panic(_S("modulo by zero")); (u32)(_t5 % _t6); });
				if (mode == MapMode__to_lower) {
					return (c + 1) - cnt;
				}
				return c - cnt;
			} else if (offset == builtin__rune_maps_utl) {
				u32 cnt = ({ u32 _t7 = (u32)((c - *cur_map)); u32 _t8 = (u32)(3); if (_t8 == 0) v_panic(_S("modulo by zero")); (u32)(_t7 % _t8); });
				if (mode == MapMode__to_upper) {
					return c - cnt;
				} else if (mode == MapMode__to_lower) {
					return (c + 2) - cnt;
				}
				return (c + 1) - cnt;
			}
			return c + offset;
		}
		if (c < (u32)(*cur_map)) {
			end = middle;
		} else {
			start = middle + 1;
		}
	}
	return c;
}

string rune__str(u32 c) {
	return utf32_to_str((u32)(c));
}

u32 rune__to_lower(u32 c) {
	if (c < 0x80) {
		if ((c >= 'A') && (c <= 'Z')) {
			return c + 32;
		}
		return c;
	}
	return rune__map_to(c, MapMode__to_lower);
}

u32 rune__to_upper(u32 c) {
	if (c < 0x80) {
		if ((c >= 'a') && (c <= 'z')) {
			return c - 32;
		}
		return c;
	}
	return rune__map_to(c, MapMode__to_upper);
}

void set_stream_unbuffered(FILE* stream) {
	setvbuf(stream, (char*)(NULL), _IONBF, (size_t)(0));
}

string strconv__Dec32__get_string_32(strconv__Dec32 d, bool neg, i64 i_n_digit, i64 i_pad_digit) {
	i64 n_digit = i_n_digit + 1;
	i64 pad_digit = i_pad_digit + 1;
	u32 out = d.m;
	i64 out_len = strconv__dec_digits(out);
	i64 out_len_original = out_len;
	i64 fw_zeros = 0;
	if (pad_digit > out_len) {
		fw_zeros = pad_digit - out_len;
	}
	Array buf = __new_array_noscan((i64)(((out_len + 5) + 1) + 1), 0, sizeof(u8));
	i64 i = 0;
	if (neg) {
		if (buf.data != 0) {
			{ Array* _a0 = &buf; int _i0 = i; array__set(_a0, _i0, &(u8[]){'-'}); }
		}
		i++;
	}
	i64 disp = 0;
	if (out_len <= 1) {
		disp = 1;
	}
	if (n_digit < out_len) {
		out += strconv__ten_pow_table_32[(out_len - n_digit) - 1] * 5;
		out /= strconv__ten_pow_table_32[out_len - n_digit];
		out_len = n_digit;
	}
	i64 y = i + out_len;
	i64 x = 0;
	while (x < ((out_len - disp) - 1)) {
		{ Array* _a1 = &buf; int _i1 = y - x; array__set(_a1, _i1, &(u8[]){'0' + (u8)(({ u32 _t3 = (u32)(out); u32 _t4 = (u32)(10); if (_t4 == 0) v_panic(_S("modulo by zero")); (u32)(_t3 % _t4); }))}); }
		out /= 10;
		i++;
		x++;
	}
	if (i_n_digit == 0) {
		{
			{ Array* _a4 = &buf; int _i4 = i; array__set(_a4, _i4, &(u8[]){0}); }
			return tos((u8*)(memdup((void*)(&(*((u8*)((buf).data) + (0)))), i + 1)), i);
		}
	}
	if ((out_len > 1) || (fw_zeros > 0)) {
		{ Array* _a5 = &buf; int _i5 = y - x; array__set(_a5, _i5, &(u8[]){'.'}); }
		i++;
	}
	x++;
	if ((y - x) >= 0) {
		{ Array* _a6 = &buf; int _i6 = y - x; array__set(_a6, _i6, &(u8[]){'0' + (u8)(({ u32 _t8 = (u32)(out); u32 _t9 = (u32)(10); if (_t9 == 0) v_panic(_S("modulo by zero")); (u32)(_t8 % _t9); }))}); }
		i++;
	}
	while (fw_zeros > 0) {
		{ Array* _a9 = &buf; int _i9 = i; array__set(_a9, _i9, &(u8[]){'0'}); }
		i++;
		fw_zeros--;
	}
	{ Array* _a10 = &buf; int _i10 = i; array__set(_a10, _i10, &(u8[]){'e'}); }
	i++;
	i64 exp = (d.e + out_len_original) - 1;
	if (exp < 0) {
		{ Array* _a11 = &buf; int _i11 = i; array__set(_a11, _i11, &(u8[]){'-'}); }
		i++;
		exp = -exp;
	} else {
		{ Array* _a12 = &buf; int _i12 = i; array__set(_a12, _i12, &(u8[]){'+'}); }
		i++;
	}
	i64 d1 = ({ i64 _t14 = (i64)(exp); i64 _t15 = (i64)(10); if (_t15 == 0) v_panic(_S("modulo by zero")); (i64)(_t14 % _t15); });
	i64 d0 = ({ i64 _t16 = (i64)(exp); i64 _t17 = (i64)(10); if (_t17 == 0) v_panic(_S("division by zero")); (i64)(_t16 / _t17); });
	{ Array* _a17 = &buf; int _i17 = i; array__set(_a17, _i17, &(u8[]){'0' + (u8)(d0)}); }
	i++;
	{ Array* _a18 = &buf; int _i18 = i; array__set(_a18, _i18, &(u8[]){'0' + (u8)(d1)}); }
	i++;
	{ Array* _a19 = &buf; int _i19 = i; array__set(_a19, _i19, &(u8[]){0}); }
	return tos((u8*)(memdup((void*)(&(*((u8*)((buf).data) + (0)))), i + 1)), i);
}

string strconv__Dec64__get_string_64(strconv__Dec64 d, bool neg, i64 i_n_digit, i64 i_pad_digit) {
	i64 __if_val_0 = {0};
	if (i_n_digit < 1) {
		__if_val_0 = 1;
	} else {
		__if_val_0 = i_n_digit + 1;
	}
	i64 n_digit = __if_val_0;
	i64 pad_digit = i_pad_digit + 1;
	u64 out = d.m;
	i64 d_exp = d.e;
	i64 out_len = strconv__dec_digits(out);
	i64 out_len_original = out_len;
	i64 fw_zeros = 0;
	if (pad_digit > out_len) {
		fw_zeros = pad_digit - out_len;
	}
	Array buf = __new_array_noscan(((((out_len + 6) + 1) + 1) + fw_zeros), 0, sizeof(u8));
	i64 i = 0;
	if (neg) {
		{ Array* _a0 = &buf; int _i0 = i; array__set(_a0, _i0, &(u8[]){'-'}); }
		i++;
	}
	i64 disp = 0;
	if (out_len <= 1) {
		disp = 1;
	}
	if (n_digit < out_len) {
		out += strconv__ten_pow_table_64[(out_len - n_digit) - 1] * 5;
		out /= strconv__ten_pow_table_64[out_len - n_digit];
		u64 out_div = ({ u64 _t2 = (u64)(d.m); u64 _t3 = (u64)(strconv__ten_pow_table_64[out_len - n_digit]); if (_t3 == 0) v_panic(_S("division by zero")); (u64)(_t2 / _t3); });
		if ((out_div < out) && (strconv__dec_digits(out_div) < strconv__dec_digits(out))) {
			d_exp++;
			n_digit++;
		}
		out_len = n_digit;
	}
	i64 y = i + out_len;
	i64 x = 0;
	while (x < ((out_len - disp) - 1)) {
		{ Array* _a3 = &buf; int _i3 = y - x; array__set(_a3, _i3, &(u8[]){'0' + (u8)(({ u64 _t5 = (u64)(out); u64 _t6 = (u64)(10); if (_t6 == 0) v_panic(_S("modulo by zero")); (u64)(_t5 % _t6); }))}); }
		out /= 10;
		i++;
		x++;
	}
	if ((out_len > 1) || (fw_zeros > 0)) {
		{ Array* _a6 = &buf; int _i6 = y - x; array__set(_a6, _i6, &(u8[]){'.'}); }
		i++;
	}
	x++;
	if ((y - x) >= 0) {
		{ Array* _a7 = &buf; int _i7 = y - x; array__set(_a7, _i7, &(u8[]){'0' + (u8)(({ u64 _t9 = (u64)(out); u64 _t10 = (u64)(10); if (_t10 == 0) v_panic(_S("modulo by zero")); (u64)(_t9 % _t10); }))}); }
		i++;
	}
	while (fw_zeros > 0) {
		{ Array* _a10 = &buf; int _i10 = i; array__set(_a10, _i10, &(u8[]){'0'}); }
		i++;
		fw_zeros--;
	}
	{ Array* _a11 = &buf; int _i11 = i; array__set(_a11, _i11, &(u8[]){'e'}); }
	i++;
	i64 exp = (d_exp + out_len_original) - 1;
	if (exp < 0) {
		{ Array* _a12 = &buf; int _i12 = i; array__set(_a12, _i12, &(u8[]){'-'}); }
		i++;
		exp = -exp;
	} else {
		{ Array* _a13 = &buf; int _i13 = i; array__set(_a13, _i13, &(u8[]){'+'}); }
		i++;
	}
	i64 d2 = ({ i64 _t15 = (i64)(exp); i64 _t16 = (i64)(10); if (_t16 == 0) v_panic(_S("modulo by zero")); (i64)(_t15 % _t16); });
	exp /= 10;
	i64 d1 = ({ i64 _t17 = (i64)(exp); i64 _t18 = (i64)(10); if (_t18 == 0) v_panic(_S("modulo by zero")); (i64)(_t17 % _t18); });
	i64 d0 = ({ i64 _t19 = (i64)(exp); i64 _t20 = (i64)(10); if (_t20 == 0) v_panic(_S("division by zero")); (i64)(_t19 / _t20); });
	if (d0 > 0) {
		{ Array* _a20 = &buf; int _i20 = i; array__set(_a20, _i20, &(u8[]){'0' + (u8)(d0)}); }
		i++;
	}
	{ Array* _a21 = &buf; int _i21 = i; array__set(_a21, _i21, &(u8[]){'0' + (u8)(d1)}); }
	i++;
	{ Array* _a22 = &buf; int _i22 = i; array__set(_a22, _i22, &(u8[]){'0' + (u8)(d2)}); }
	i++;
	{ Array* _a23 = &buf; int _i23 = i; array__set(_a23, _i23, &(u8[]){0}); }
	return tos((u8*)(memdup((void*)(&(*((u8*)((buf).data) + (0)))), i + 1)), i);
}

void strconv__assert1(bool t, string msg) {
}

inline u32 strconv__bool_to_u32(bool b) {
	if (b) {
		return (u32)(1);
	}
	return (u32)(0);
}

inline u64 strconv__bool_to_u64(bool b) {
	if (b) {
		return (u64)(1);
	}
	return (u64)(0);
}

i64 strconv__dec_digits(u64 n) {
	if (n <= 9999999999) {
		if (n <= 99999) {
			if (n <= 99) {
				if (n <= 9) {
					return 1;
				} else {
					return 2;
				}
			} else {
				if (n <= 999) {
					return 3;
				} else {
					if (n <= 9999) {
						return 4;
					} else {
						return 5;
					}
				}
			}
		} else {
			if (n <= 9999999) {
				if (n <= 999999) {
					return 6;
				} else {
					return 7;
				}
			} else {
				if (n <= 99999999) {
					return 8;
				} else {
					if (n <= 999999999) {
						return 9;
					}
					return 10;
				}
			}
		}
	} else {
		if (n <= 999999999999999) {
			if (n <= 999999999999) {
				if (n <= 99999999999) {
					return 11;
				} else {
					return 12;
				}
			} else {
				if (n <= 9999999999999) {
					return 13;
				} else {
					if (n <= 99999999999999) {
						return 14;
					} else {
						return 15;
					}
				}
			}
		} else {
			if (n <= 99999999999999999) {
				if (n <= 9999999999999999) {
					return 16;
				} else {
					return 17;
				}
			} else {
				if (n <= 999999999999999999) {
					return 18;
				} else {
					if (n <= 9999999999999999999) {
						return 19;
					}
					return 20;
				}
			}
		}
	}
}

strconv__Dec32 strconv__f32_to_decimal(u32 mant, u32 exp) {
	i64 e2 = 0;
	u32 m2 = (u32)(0);
	if (exp == 0) {
		e2 = ((1 - strconv__bias32) - (i64)(strconv__mantbits32)) - 2;
		m2 = mant;
	} else {
		e2 = (((i64)(exp) - strconv__bias32) - (i64)(strconv__mantbits32)) - 2;
		m2 = ((u32)(((u32)(		(u32)(1))) << (strconv__mantbits32))) | mant;
	}
	bool even = (m2 & 1) == 0;
	bool accept_bounds = even;
	u32 mv = (u32)(4 * m2);
	u32 mp = (u32)((4 * m2) + 2);
	u32 mm_shift = strconv__bool_to_u32((mant != 0) || (exp <= 1));
	u32 mm = (u32)(((4 * m2) - 1) - mm_shift);
	u32 vr = (u32)(0);
	u32 vp = (u32)(0);
	u32 vm = (u32)(0);
	i64 e10 = 0;
	bool vm_is_trailing_zeros = false;
	bool vr_is_trailing_zeros = false;
	u8 last_removed_digit = (u8)(0);
	if (e2 >= 0) {
		u32 q = strconv__log10_pow2(e2);
		e10 = (i64)(q);
		i64 k = (strconv__pow5_inv_num_bits_32 + strconv__pow5_bits((i64)(q))) - 1;
		i64 i = (-e2 + (i64)(q)) + k;
		vr = strconv__mul_pow5_invdiv_pow2(mv, q, i);
		vp = strconv__mul_pow5_invdiv_pow2(mp, q, i);
		vm = strconv__mul_pow5_invdiv_pow2(mm, q, i);
		if ((q != 0) && ((({ u32 _t1 = (u32)((vp - 1)); u32 _t2 = (u32)(10); if (_t2 == 0) v_panic(_S("division by zero")); (u32)(_t1 / _t2); })) <= (({ u32 _t3 = (u32)(vm); u32 _t4 = (u32)(10); if (_t4 == 0) v_panic(_S("division by zero")); (u32)(_t3 / _t4); })))) {
			i64 l = (strconv__pow5_inv_num_bits_32 + strconv__pow5_bits((i64)(q - 1))) - 1;
			last_removed_digit = (u8)(({ u32 _t5 = (u32)(strconv__mul_pow5_invdiv_pow2(mv, q - 1, (-e2 + (i64)(q - 1)) + l)); u32 _t6 = (u32)(10); if (_t6 == 0) v_panic(_S("modulo by zero")); (u32)(_t5 % _t6); }));
		}
		if (q <= 9) {
			if ((({ u32 _t7 = (u32)(mv); u32 _t8 = (u32)(5); if (_t8 == 0) v_panic(_S("modulo by zero")); (u32)(_t7 % _t8); })) == 0) {
				vr_is_trailing_zeros = strconv__multiple_of_power_of_five_32(mv, q);
			} else if (accept_bounds) {
				vm_is_trailing_zeros = strconv__multiple_of_power_of_five_32(mm, q);
			} else if (strconv__multiple_of_power_of_five_32(mp, q)) {
				vp--;
			}
		}
	} else {
		u32 q = strconv__log10_pow5(-e2);
		e10 = (i64)(q) + e2;
		i64 i = -e2 - (i64)(q);
		i64 k = strconv__pow5_bits(i) - strconv__pow5_num_bits_32;
		i64 j = (i64)(q) - k;
		vr = strconv__mul_pow5_div_pow2(mv, (u32)(i), j);
		vp = strconv__mul_pow5_div_pow2(mp, (u32)(i), j);
		vm = strconv__mul_pow5_div_pow2(mm, (u32)(i), j);
		if ((q != 0) && ((({ u32 _t9 = (u32)((vp - 1)); u32 _t10 = (u32)(10); if (_t10 == 0) v_panic(_S("division by zero")); (u32)(_t9 / _t10); })) <= (({ u32 _t11 = (u32)(vm); u32 _t12 = (u32)(10); if (_t12 == 0) v_panic(_S("division by zero")); (u32)(_t11 / _t12); })))) {
			j = ((i64)(q) - 1) - (strconv__pow5_bits(i + 1) - strconv__pow5_num_bits_32);
			last_removed_digit = (u8)(({ u32 _t13 = (u32)(strconv__mul_pow5_div_pow2(mv, (u32)(i + 1), j)); u32 _t14 = (u32)(10); if (_t14 == 0) v_panic(_S("modulo by zero")); (u32)(_t13 % _t14); }));
		}
		if (q <= 1) {
			vr_is_trailing_zeros = true;
			if (accept_bounds) {
				vm_is_trailing_zeros = mm_shift == 1;
			} else {
				vp--;
			}
		} else if (q < 31) {
			vr_is_trailing_zeros = strconv__multiple_of_power_of_two_32(mv, q - 1);
		}
	}
	i64 removed = 0;
	u32 out = (u32)(0);
	if (vm_is_trailing_zeros || vr_is_trailing_zeros) {
		while ((({ u32 _t15 = (u32)(vp); u32 _t16 = (u32)(10); if (_t16 == 0) v_panic(_S("division by zero")); (u32)(_t15 / _t16); })) > (({ u32 _t17 = (u32)(vm); u32 _t18 = (u32)(10); if (_t18 == 0) v_panic(_S("division by zero")); (u32)(_t17 / _t18); }))) {
			vm_is_trailing_zeros = vm_is_trailing_zeros && ((({ u32 _t19 = (u32)(vm); u32 _t20 = (u32)(10); if (_t20 == 0) v_panic(_S("modulo by zero")); (u32)(_t19 % _t20); })) == 0);
			vr_is_trailing_zeros = vr_is_trailing_zeros && (last_removed_digit == 0);
			last_removed_digit = (u8)(({ u32 _t21 = (u32)(vr); u32 _t22 = (u32)(10); if (_t22 == 0) v_panic(_S("modulo by zero")); (u32)(_t21 % _t22); }));
			vr /= 10;
			vp /= 10;
			vm /= 10;
			removed++;
		}
		if (vm_is_trailing_zeros) {
			while ((({ u32 _t23 = (u32)(vm); u32 _t24 = (u32)(10); if (_t24 == 0) v_panic(_S("modulo by zero")); (u32)(_t23 % _t24); })) == 0) {
				vr_is_trailing_zeros = vr_is_trailing_zeros && (last_removed_digit == 0);
				last_removed_digit = (u8)(({ u32 _t25 = (u32)(vr); u32 _t26 = (u32)(10); if (_t26 == 0) v_panic(_S("modulo by zero")); (u32)(_t25 % _t26); }));
				vr /= 10;
				vp /= 10;
				vm /= 10;
				removed++;
			}
		}
		if (vr_is_trailing_zeros && (last_removed_digit == 5) && ((({ u32 _t27 = (u32)(vr); u32 _t28 = (u32)(2); if (_t28 == 0) v_panic(_S("modulo by zero")); (u32)(_t27 % _t28); })) == 0)) {
			last_removed_digit = 4;
		}
		out = vr;
		if (((vr == vm) && (!accept_bounds || !vm_is_trailing_zeros)) || (last_removed_digit >= 5)) {
			out++;
		}
	} else {
		while ((({ u32 _t29 = (u32)(vp); u32 _t30 = (u32)(10); if (_t30 == 0) v_panic(_S("division by zero")); (u32)(_t29 / _t30); })) > (({ u32 _t31 = (u32)(vm); u32 _t32 = (u32)(10); if (_t32 == 0) v_panic(_S("division by zero")); (u32)(_t31 / _t32); }))) {
			last_removed_digit = (u8)(({ u32 _t33 = (u32)(vr); u32 _t34 = (u32)(10); if (_t34 == 0) v_panic(_S("modulo by zero")); (u32)(_t33 % _t34); }));
			vr /= 10;
			vp /= 10;
			vm /= 10;
			removed++;
		}
		out = vr + strconv__bool_to_u32((vr == vm) || (last_removed_digit >= 5));
	}
	return (strconv__Dec32){.m = out, .e = e10 + removed};
}

multi_return_strconv__Dec32_bool strconv__f32_to_decimal_exact_int(u32 i_mant, u32 exp) {
	strconv__Dec32 d = (strconv__Dec32){0};
	u32 e = exp - strconv__bias32;
	if (e > strconv__mantbits32) {
		return (multi_return_strconv__Dec32_bool){d, false};
	}
	u32 shift = strconv__mantbits32 - e;
	u32 mant = i_mant | 0x00800000;
	d.m = ({ u32 _t1 = (u32)(	mant); u64 _t2 = (u64)(shift); _t2 >= 32 ? (u32)0 : (u32)(_t1 >> _t2); });
	if ((({ u32 _t3 = (u32)(	d.m); u64 _t4 = (u64)(shift); _t4 >= 32 ? (u32)0 : (u32)(_t3 << _t4); })) != mant) {
		return (multi_return_strconv__Dec32_bool){d, false};
	}
	while ((({ u32 _t5 = (u32)(d.m); u32 _t6 = (u32)(10); if (_t6 == 0) v_panic(_S("modulo by zero")); (u32)(_t5 % _t6); })) == 0) {
		d.m /= 10;
		d.e++;
	}
	return (multi_return_strconv__Dec32_bool){d, true};
}

string strconv__f32_to_str(float f, i64 n_digit) {
	strconv__Uf32 u1 = (strconv__Uf32){0};
	u1.f = f;
	u32 u = u1.u;
	bool neg = ((u32)(((u32)(	u)) >> ((strconv__mantbits32 + strconv__expbits32)))) != 0;
	u32 mant = u & (((u32)(((u32)(	(u32)(1))) << (strconv__mantbits32))) - (u32)(1));
	u32 exp = ((u32)(((u32)(	u)) >> (strconv__mantbits32))) & (((u32)(((u32)(	(u32)(1))) << (strconv__expbits32))) - (u32)(1));
	if ((({ u32 _t1 = (u32)(exp); i64 _t2 = (i64)(strconv__maxexp32); _t2 < 0 ? 0 : ((u64)(_t1) == (u64)(_t2)); })) || ((exp == 0) && (mant == 0))) {
		return strconv__get_string_special(neg, exp == 0, mant == 0);
	}
	multi_return_strconv__Dec32_bool __multi_ret_0 = strconv__f32_to_decimal_exact_int(mant, exp);
	strconv__Dec32 d = __multi_ret_0.arg0;
	bool ok = __multi_ret_0.arg1;
	if (!ok) {
		d = strconv__f32_to_decimal(mant, exp);
	}
	return strconv__Dec32__get_string_32(d, neg, n_digit, 0);
}

string strconv__f32_to_str_l(float f) {
	string s = strconv__f32_to_str(f, 8);
	string res = strconv__fxx_to_str_l_parse(s);
	{
		string__free(&s);
	}
	return res;
}

strconv__Dec64 strconv__f64_to_decimal(u64 mant, u64 exp) {
	i64 e2 = 0;
	u64 m2 = (u64)(0);
	if (exp == 0) {
		e2 = ((1 - strconv__bias64) - (i64)(strconv__mantbits64)) - 2;
		m2 = mant;
	} else {
		e2 = (((i64)(exp) - strconv__bias64) - (i64)(strconv__mantbits64)) - 2;
		m2 = ((u64)(((u64)(		(u64)(1))) << (strconv__mantbits64))) | mant;
	}
	bool even = (m2 & 1) == 0;
	bool accept_bounds = even;
	u64 mv = (u64)(4 * m2);
	u64 mm_shift = strconv__bool_to_u64((mant != 0) || (exp <= 1));
	u64 vr = (u64)(0);
	u64 vp = (u64)(0);
	u64 vm = (u64)(0);
	i64 e10 = 0;
	bool vm_is_trailing_zeros = false;
	bool vr_is_trailing_zeros = false;
	if (e2 >= 0) {
		u32 q = strconv__log10_pow2(e2) - strconv__bool_to_u32(e2 > 3);
		e10 = (i64)(q);
		i64 k = (strconv__pow5_inv_num_bits_64 + strconv__pow5_bits((i64)(q))) - 1;
		i64 i = (-e2 + (i64)(q)) + k;
		strconv__Uint128 mul = *((strconv__Uint128*)(&strconv__pow5_inv_split_64_x[q * 2]));
		vr = strconv__mul_shift_64((u64)(4) * m2, mul, i);
		vp = strconv__mul_shift_64(((u64)(4) * m2) + (u64)(2), mul, i);
		vm = strconv__mul_shift_64((((u64)(4) * m2) - (u64)(1)) - mm_shift, mul, i);
		if (q <= 21) {
			if ((({ u64 _t1 = (u64)(mv); u64 _t2 = (u64)(5); if (_t2 == 0) v_panic(_S("modulo by zero")); (u64)(_t1 % _t2); })) == 0) {
				vr_is_trailing_zeros = strconv__multiple_of_power_of_five_64(mv, q);
			} else if (accept_bounds) {
				vm_is_trailing_zeros = strconv__multiple_of_power_of_five_64((mv - 1) - mm_shift, q);
			} else if (strconv__multiple_of_power_of_five_64(mv + 2, q)) {
				vp--;
			}
		}
	} else {
		u32 q = strconv__log10_pow5(-e2) - strconv__bool_to_u32(-e2 > 1);
		e10 = (i64)(q) + e2;
		i64 i = -e2 - (i64)(q);
		i64 k = strconv__pow5_bits(i) - strconv__pow5_num_bits_64;
		i64 j = (i64)(q) - k;
		strconv__Uint128 mul = *((strconv__Uint128*)(&strconv__pow5_split_64_x[i * 2]));
		vr = strconv__mul_shift_64((u64)(4) * m2, mul, j);
		vp = strconv__mul_shift_64(((u64)(4) * m2) + (u64)(2), mul, j);
		vm = strconv__mul_shift_64((((u64)(4) * m2) - (u64)(1)) - mm_shift, mul, j);
		if (q <= 1) {
			vr_is_trailing_zeros = true;
			if (accept_bounds) {
				vm_is_trailing_zeros = (mm_shift == 1);
			} else {
				vp--;
			}
		} else if (q < 63) {
			vr_is_trailing_zeros = strconv__multiple_of_power_of_two_64(mv, q - 1);
		}
	}
	i64 removed = 0;
	u8 last_removed_digit = (u8)(0);
	u64 out = (u64)(0);
	if (vm_is_trailing_zeros || vr_is_trailing_zeros) {
		for (;;) {
			u64 vp_div_10 = ({ u64 _t3 = (u64)(vp); u64 _t4 = (u64)(10); if (_t4 == 0) v_panic(_S("division by zero")); (u64)(_t3 / _t4); });
			u64 vm_div_10 = ({ u64 _t5 = (u64)(vm); u64 _t6 = (u64)(10); if (_t6 == 0) v_panic(_S("division by zero")); (u64)(_t5 / _t6); });
			if (vp_div_10 <= vm_div_10) {
				break;
			}
			u64 vm_mod_10 = ({ u64 _t7 = (u64)(vm); u64 _t8 = (u64)(10); if (_t8 == 0) v_panic(_S("modulo by zero")); (u64)(_t7 % _t8); });
			u64 vr_div_10 = ({ u64 _t9 = (u64)(vr); u64 _t10 = (u64)(10); if (_t10 == 0) v_panic(_S("division by zero")); (u64)(_t9 / _t10); });
			u64 vr_mod_10 = ({ u64 _t11 = (u64)(vr); u64 _t12 = (u64)(10); if (_t12 == 0) v_panic(_S("modulo by zero")); (u64)(_t11 % _t12); });
			vm_is_trailing_zeros = vm_is_trailing_zeros && (vm_mod_10 == 0);
			vr_is_trailing_zeros = vr_is_trailing_zeros && (last_removed_digit == 0);
			last_removed_digit = (u8)(vr_mod_10);
			vr = vr_div_10;
			vp = vp_div_10;
			vm = vm_div_10;
			removed++;
		}
		if (vm_is_trailing_zeros) {
			for (;;) {
				u64 vm_div_10 = ({ u64 _t13 = (u64)(vm); u64 _t14 = (u64)(10); if (_t14 == 0) v_panic(_S("division by zero")); (u64)(_t13 / _t14); });
				u64 vm_mod_10 = ({ u64 _t15 = (u64)(vm); u64 _t16 = (u64)(10); if (_t16 == 0) v_panic(_S("modulo by zero")); (u64)(_t15 % _t16); });
				if (vm_mod_10 != 0) {
					break;
				}
				u64 vp_div_10 = ({ u64 _t17 = (u64)(vp); u64 _t18 = (u64)(10); if (_t18 == 0) v_panic(_S("division by zero")); (u64)(_t17 / _t18); });
				u64 vr_div_10 = ({ u64 _t19 = (u64)(vr); u64 _t20 = (u64)(10); if (_t20 == 0) v_panic(_S("division by zero")); (u64)(_t19 / _t20); });
				u64 vr_mod_10 = ({ u64 _t21 = (u64)(vr); u64 _t22 = (u64)(10); if (_t22 == 0) v_panic(_S("modulo by zero")); (u64)(_t21 % _t22); });
				vr_is_trailing_zeros = vr_is_trailing_zeros && (last_removed_digit == 0);
				last_removed_digit = (u8)(vr_mod_10);
				vr = vr_div_10;
				vp = vp_div_10;
				vm = vm_div_10;
				removed++;
			}
		}
		if (vr_is_trailing_zeros && (last_removed_digit == 5) && ((({ u64 _t23 = (u64)(vr); u64 _t24 = (u64)(2); if (_t24 == 0) v_panic(_S("modulo by zero")); (u64)(_t23 % _t24); })) == 0)) {
			last_removed_digit = 4;
		}
		out = vr;
		if (((vr == vm) && (!accept_bounds || !vm_is_trailing_zeros)) || (last_removed_digit >= 5)) {
			out++;
		}
	} else {
		bool round_up = false;
		while ((({ u64 _t25 = (u64)(vp); u64 _t26 = (u64)(100); if (_t26 == 0) v_panic(_S("division by zero")); (u64)(_t25 / _t26); })) > (({ u64 _t27 = (u64)(vm); u64 _t28 = (u64)(100); if (_t28 == 0) v_panic(_S("division by zero")); (u64)(_t27 / _t28); }))) {
			round_up = (({ u64 _t29 = (u64)(vr); u64 _t30 = (u64)(100); if (_t30 == 0) v_panic(_S("modulo by zero")); (u64)(_t29 % _t30); })) >= 50;
			vr /= 100;
			vp /= 100;
			vm /= 100;
			removed += 2;
		}
		while ((({ u64 _t31 = (u64)(vp); u64 _t32 = (u64)(10); if (_t32 == 0) v_panic(_S("division by zero")); (u64)(_t31 / _t32); })) > (({ u64 _t33 = (u64)(vm); u64 _t34 = (u64)(10); if (_t34 == 0) v_panic(_S("division by zero")); (u64)(_t33 / _t34); }))) {
			round_up = (({ u64 _t35 = (u64)(vr); u64 _t36 = (u64)(10); if (_t36 == 0) v_panic(_S("modulo by zero")); (u64)(_t35 % _t36); })) >= 5;
			vr /= 10;
			vp /= 10;
			vm /= 10;
			removed++;
		}
		out = vr + strconv__bool_to_u64((vr == vm) || round_up);
	}
	return (strconv__Dec64){.m = out, .e = e10 + removed};
}

multi_return_strconv__Dec64_bool strconv__f64_to_decimal_exact_int(u64 i_mant, u64 exp) {
	strconv__Dec64 d = (strconv__Dec64){0};
	u64 e = exp - strconv__bias64;
	if (e > strconv__mantbits64) {
		return (multi_return_strconv__Dec64_bool){d, false};
	}
	u64 shift = strconv__mantbits64 - e;
	u64 mant = i_mant | (u64)(0x0010000000000000);
	d.m = ({ u64 _t1 = (u64)(	mant); u64 _t2 = (u64)(shift); _t2 >= 64 ? (u64)0 : (u64)(_t1 >> _t2); });
	if ((({ u64 _t3 = (u64)(	d.m); u64 _t4 = (u64)(shift); _t4 >= 64 ? (u64)0 : (u64)(_t3 << _t4); })) != mant) {
		return (multi_return_strconv__Dec64_bool){d, false};
	}
	while ((({ u64 _t5 = (u64)(d.m); u64 _t6 = (u64)(10); if (_t6 == 0) v_panic(_S("modulo by zero")); (u64)(_t5 % _t6); })) == 0) {
		d.m /= 10;
		d.e++;
	}
	return (multi_return_strconv__Dec64_bool){d, true};
}

string strconv__f64_to_str(double f, i64 n_digit) {
	strconv__Uf64 u1 = (strconv__Uf64){0};
	u1.f = f;
	u64 u = u1.u;
	bool neg = ((u64)(((u64)(	u)) >> ((strconv__mantbits64 + strconv__expbits64)))) != 0;
	u64 mant = u & (((u64)(((u64)(	(u64)(1))) << (strconv__mantbits64))) - (u64)(1));
	u64 exp = ((u64)(((u64)(	u)) >> (strconv__mantbits64))) & (((u64)(((u64)(	(u64)(1))) << (strconv__expbits64))) - (u64)(1));
	if ((exp == strconv__maxexp64) || ((exp == 0) && (mant == 0))) {
		return strconv__get_string_special(neg, exp == 0, mant == 0);
	}
	multi_return_strconv__Dec64_bool __multi_ret_0 = strconv__f64_to_decimal_exact_int(mant, exp);
	strconv__Dec64 d = __multi_ret_0.arg0;
	bool ok = __multi_ret_0.arg1;
	if (!ok) {
		d = strconv__f64_to_decimal(mant, exp);
	}
	return strconv__Dec64__get_string_64(d, neg, n_digit, 0);
}

string strconv__f64_to_str_l(double f) {
	string s = strconv__f64_to_str(f, 18);
	string res = strconv__fxx_to_str_l_parse(s);
	{
		string__free(&s);
	}
	return res;
}

string strconv__format_int(i64 n, i64 radix) {
	{
		if ((radix < 2) || (radix > 36)) {
			panic_n(_str_252, radix);
		}
		if (n == 0) {
			return _str_56;
		}
		i64 n_copy = n;
		bool have_minus = false;
		if (n < 0) {
			have_minus = true;
			n_copy = -n_copy;
		}
		string res = _str_30;
		while (n_copy != 0) {
			string tmp_0 = res;
			i64 bdx = (i64)(({ i64 _t1 = (i64)(n_copy); i64 _t2 = (i64)(radix); if (_t2 == 0) v_panic(_S("modulo by zero")); (i64)(_t1 % _t2); }));
			string tmp_1 = u8__ascii_str((strconv__base_digits).str[bdx]);
			res = string__plus(tmp_1, res);
			string__free(&tmp_0);
			string__free(&tmp_1);
			n_copy /= radix;
		}
		if (have_minus) {
			string final_res = string__plus(_str_71, res);
			string__free(&res);
			return final_res;
		}
		return res;
	}
}

string strconv__format_uint(u64 n, i64 radix) {
	{
		if ((radix < 2) || (radix > 36)) {
			panic_n(_str_252, radix);
		}
		if (n == 0) {
			return _str_56;
		}
		u64 n_copy = n;
		string res = _str_30;
		u64 uradix = (u64)(radix);
		while (n_copy != 0) {
			string tmp_0 = res;
			string tmp_1 = u8__ascii_str((strconv__base_digits).str[(i64)(({ u64 _t1 = (u64)(n_copy); u64 _t2 = (u64)(uradix); if (_t2 == 0) v_panic(_S("modulo by zero")); (u64)(_t1 % _t2); }))]);
			res = string__plus(tmp_1, res);
			string__free(&tmp_0);
			string__free(&tmp_1);
			n_copy /= uradix;
		}
		return res;
	}
}

inline string strconv__ftoa_32(float f) {
	return strconv__f32_to_str(f, 8);
}

inline string strconv__ftoa_64(double f) {
	return strconv__f64_to_str(f, 17);
}

string strconv__fxx_to_str_l_parse(string s) {
	if ((s.len > 2) && (((s).str[0] == 'n') || ((s).str[1] == 'i'))) {
		return string__clone(s);
	}
	bool m_sgn_flag = false;
	i64 sgn = 1;
	u8 b[26];
	memmove(b, (u8[26]){0}, sizeof(b));
	i64 d_pos = 1;
	i64 i = 0;
	i64 i1 = 0;
	i64 exp = 0;
	i64 exp_sgn = 1;
	{
		i64 __for_idx_0 = 0;
		for (; __for_idx_0 < s.len; __for_idx_0++) {
			u8 c = (s).str[__for_idx_0];
			if (c == '-') {
				sgn = -1;
				i++;
			} else if (c == '+') {
				sgn = 1;
				i++;
			} else if ((c >= '0') && (c <= '9')) {
				b[i1] = c;
				i1++;
				i++;
			} else if (c == '.') {
				if (sgn > 0) {
					d_pos = i;
				} else {
					d_pos = i - 1;
				}
				i++;
			} else if (c == 'e') {
				i++;
				break;
			} else {
				return _str_253;
			}
		}
	}
	b[i1] = 0;
	if ((s).str[i] == '-') {
		exp_sgn = -1;
		i++;
	} else if ((s).str[i] == '+') {
		exp_sgn = 1;
		i++;
	}
	i64 c = i;
	while (c < s.len) {
		exp = (exp * 10) + (i64)((s).str[c] - '0');
		c++;
	}
	Array __arr_init_1 = __new_array_noscan(exp + 32, 0, sizeof(u8));
	{
		i64 __arr_idx_2 = 0;
		for (; __arr_idx_2 < __arr_init_1.len; __arr_idx_2++) {
			i64 v_index = __arr_idx_2;
			{ Array* _a0 = &__arr_init_1; int _i0 = __arr_idx_2; array__set(_a0, _i0, &(u8[]){0}); }
		}
	}
	Array res = __arr_init_1;
	i64 r_i = 0;
	if (sgn == 1) {
		if (m_sgn_flag) {
			{ Array* _a1 = &res; int _i1 = r_i; array__set(_a1, _i1, &(u8[]){'+'}); }
			r_i++;
		}
	} else {
		{ Array* _a2 = &res; int _i2 = r_i; array__set(_a2, _i2, &(u8[]){'-'}); }
		r_i++;
	}
	i = 0;
	if (exp_sgn >= 0) {
		while (b[i] != 0) {
			{ Array* _a3 = &res; int _i3 = r_i; array__set(_a3, _i3, &(u8[]){b[i]}); }
			r_i++;
			i++;
			if ((i >= d_pos) && (exp >= 0)) {
				if (exp == 0) {
					{ Array* _a4 = &res; int _i4 = r_i; array__set(_a4, _i4, &(u8[]){'.'}); }
					r_i++;
				}
				exp--;
			}
		}
		while (exp >= 0) {
			{ Array* _a5 = &res; int _i5 = r_i; array__set(_a5, _i5, &(u8[]){'0'}); }
			r_i++;
			exp--;
		}
	} else {
		bool dot_p = true;
		while (exp > 0) {
			{ Array* _a6 = &res; int _i6 = r_i; array__set(_a6, _i6, &(u8[]){'0'}); }
			r_i++;
			exp--;
			if (dot_p) {
				{ Array* _a7 = &res; int _i7 = r_i; array__set(_a7, _i7, &(u8[]){'.'}); }
				r_i++;
				dot_p = false;
			}
		}
		while (b[i] != 0) {
			{ Array* _a8 = &res; int _i8 = r_i; array__set(_a8, _i8, &(u8[]){b[i]}); }
			r_i++;
			i++;
		}
	}
	if ((r_i > 1) && ((*((u8*)((res).data) + (r_i - 1))) == '.')) {
		{ Array* _a9 = &res; int _i9 = r_i; array__set(_a9, _i9, &(u8[]){'0'}); }
		r_i++;
	} else {
		bool __contains_3 = false;
		{
			i64 __contains_idx_4 = 0;
			for (; __contains_idx_4 < res.len; __contains_idx_4++) {
				if (*(u8*)(array_get(res, __contains_idx_4)) == '.') {
					__contains_3 = true;
				}
			}
		}
		if (!__contains_3) {
			{ Array* _a10 = &res; int _i10 = r_i; array__set(_a10, _i10, &(u8[]){'.'}); }
			r_i++;
			{ Array* _a11 = &res; int _i11 = r_i; array__set(_a11, _i11, &(u8[]){'0'}); }
			r_i++;
		}
	}
	{ Array* _a12 = &res; int _i12 = r_i; array__set(_a12, _i12, &(u8[]){0}); }
	string tmp_res = string__clone(tos(res.data, r_i));
	{
		array__free(&res);
	}
	return tmp_res;
}

string strconv__get_string_special(bool neg, bool expZero, bool mantZero) {
	if (!mantZero) {
		return _str_236;
	}
	if (!expZero) {
		if (neg) {
			return _str_136;
		} else {
			return _str_134;
		}
	}
	if (neg) {
		return _str_237;
	}
	return _str_238;
}

u32 strconv__log10_pow2(i64 e) {
	return (u32)(((u32)(	((u32)(e) * 78913))) >> (18));
}

u32 strconv__log10_pow5(i64 e) {
	return (u32)(((u32)(	((u32)(e) * 732923))) >> (20));
}

inline u32 strconv__mul_pow5_div_pow2(u32 m, u32 i, i64 j) {
	return strconv__mul_shift_32(m, strconv__pow5_split_32[i], j);
}

inline u32 strconv__mul_pow5_invdiv_pow2(u32 m, u32 q, i64 j) {
	return strconv__mul_shift_32(m, strconv__pow5_inv_split_32[q], j);
}

u32 strconv__mul_shift_32(u32 m, u64 mul, i64 ishift) {
	multi_return_u64_u64 __multi_ret_0 = bits__mul_64((u64)(m), mul);
	u64 hi = __multi_ret_0.arg0;
	u64 lo = __multi_ret_0.arg1;
	u64 shifted_sum = (({ u64 _t1 = (u64)(	lo); u64 _t2 = (u64)((u64)(ishift)); _t2 >= 64 ? (u64)0 : (u64)(_t1 >> _t2); })) + (({ u64 _t3 = (u64)(	hi); u64 _t4 = (u64)((u64)(64 - ishift)); _t4 >= 64 ? (u64)0 : (u64)(_t3 << _t4); }));
	return (u32)(shifted_sum);
}

u64 strconv__mul_shift_64(u64 m, strconv__Uint128 mul, i64 shift) {
	multi_return_u64_u64 __multi_ret_0 = bits__mul_64(m, mul.hi);
	u64 hihi = __multi_ret_0.arg0;
	u64 hilo = __multi_ret_0.arg1;
	multi_return_u64_u64 __multi_ret_1 = bits__mul_64(m, mul.lo);
	u64 lohi = __multi_ret_1.arg0;
	strconv__Uint128 sum = (strconv__Uint128){.lo = lohi + hilo, .hi = hihi};
	if (sum.lo < lohi) {
		sum.hi++;
	}
	return strconv__shift_right_128(sum, shift - 64);
}

bool strconv__multiple_of_power_of_five_32(u32 v, u32 p) {
	return strconv__pow5_factor_32(v) >= p;
}

bool strconv__multiple_of_power_of_five_64(u64 v, u32 p) {
	return strconv__pow5_factor_64(v) >= p;
}

bool strconv__multiple_of_power_of_two_32(u32 v, u32 p) {
	return (u32)(bits__trailing_zeros_32(v)) >= p;
}

bool strconv__multiple_of_power_of_two_64(u64 v, u32 p) {
	return (u32)(bits__trailing_zeros_64(v)) >= p;
}

i64 strconv__pow5_bits(i64 e) {
	return (i64)(((u32)(((u32)(	((u32)(e) * 1217359))) >> (19))) + 1);
}

u32 strconv__pow5_factor_32(u32 i_v) {
	u32 v = i_v;
	{
		u32 n = (u32)(0);
		for (; true; n++) {
			u32 q = ({ u32 _t1 = (u32)(v); u32 _t2 = (u32)(5); if (_t2 == 0) v_panic(_S("division by zero")); (u32)(_t1 / _t2); });
			u32 r = ({ u32 _t3 = (u32)(v); u32 _t4 = (u32)(5); if (_t4 == 0) v_panic(_S("modulo by zero")); (u32)(_t3 % _t4); });
			if (r != 0) {
				return n;
			}
			v = q;
		}
	}
	return v;
}

u32 strconv__pow5_factor_64(u64 v_i) {
	u64 v = v_i;
	{
		u32 n = (u32)(0);
		for (; true; n++) {
			u64 q = ({ u64 _t1 = (u64)(v); u64 _t2 = (u64)(5); if (_t2 == 0) v_panic(_S("division by zero")); (u64)(_t1 / _t2); });
			u64 r = ({ u64 _t3 = (u64)(v); u64 _t4 = (u64)(5); if (_t4 == 0) v_panic(_S("modulo by zero")); (u64)(_t3 % _t4); });
			if (r != 0) {
				return n;
			}
			v = q;
		}
	}
	return (u32)(0);
}

u64 strconv__shift_right_128(strconv__Uint128 v, i64 shift) {
	return (({ u64 _t1 = (u64)(	v.hi); u64 _t2 = (u64)((u64)(64 - shift)); _t2 >= 64 ? (u64)0 : (u64)(_t1 << _t2); })) | (({ u64 _t3 = (u64)(	v.lo); u64 _t4 = (u64)((u32)(shift)); _t4 >= 64 ? (u64)0 : (u64)(_t3 >> _t4); }));
}

string string__all_after(string s, string sub) {
	i64 pos = string__index_(s, sub);
	if (pos == -1) {
		return string__clone(s);
	}
	return string__substr(	s, 	pos + sub.len, (	s).len);
}

string string__all_after_last(string s, string sub) {
	i64 pos = string__index_last_(s, sub);
	if (pos == -1) {
		return string__clone(s);
	}
	return string__substr(	s, 	pos + sub.len, (	s).len);
}

string string__all_before(string s, string sub) {
	i64 pos = string__index_(s, sub);
	if (pos == -1) {
		return string__clone(s);
	}
	return string__substr(	s, 0, 	pos);
}

string string__all_before_last(string s, string sub) {
	i64 pos = string__index_last_(s, sub);
	if (pos == -1) {
		return string__clone(s);
	}
	return string__substr(	s, 0, 	pos);
}

u8 string__at(string s, i64 idx) {
	{
		if ((idx < 0) || (idx >= s.len)) {
			panic_n2(_str_113, idx, s.len);
		}
	}
	return (s.str)[idx];
}

u8 string__at_i64(string s, i64 idx) {
	{
		if ((idx < 0) || (idx >= (i64)(s.len))) {
			panic_n2(_str_113, idx, s.len);
		}
	}
	return (s.str)[(i64)(idx)];
}

u8 string__at_ni(string s, i64 idx) {
	return string__at(s, v_ni_index(idx, s.len));
}

u8 string__at_u64(string s, u64 idx) {
	{
		if (idx >= (u64)(s.len)) {
			v_panic(({ string __v3_internal_symbol_join_0[4]; __v3_internal_symbol_join_0[0] = _str_114; __v3_internal_symbol_join_0[1] = u64__str(idx); __v3_internal_symbol_join_0[2] = _str_14; __v3_internal_symbol_join_0[3] = impl_i64_to_string(s.len); string_plus_many(4, __v3_internal_symbol_join_0); }));
		}
	}
	return (s.str)[(i64)(idx)];
}

__v_option_u8 string__at_with_check(string s, i64 idx) {
	if ((idx < 0) || (idx >= s.len)) {
		return (__v_option_u8){.ok = false};
	}
	{
		return (__v_option_u8){.ok = true, .value = (s.str)[idx]};
	}
	return (__v_option_u8){.ok = true};
}

__v_option_u8 string__at_with_check_i64(string s, i64 idx) {
	if ((idx < 0) || (idx >= (i64)(s.len))) {
		return (__v_option_u8){.ok = false};
	}
	{
		return (__v_option_u8){.ok = true, .value = (s.str)[(i64)(idx)]};
	}
	return (__v_option_u8){.ok = true};
}

__v_option_u8 string__at_with_check_ni(string s, i64 idx) {
	return string__at_with_check(s, v_ni_index(idx, s.len));
	return (__v_option_u8){.ok = true};
}

__v_option_u8 string__at_with_check_u64(string s, u64 idx) {
	if (idx >= (u64)(s.len)) {
		return (__v_option_u8){.ok = false};
	}
	{
		return (__v_option_u8){.ok = true, .value = (s.str)[(i64)(idx)]};
	}
	return (__v_option_u8){.ok = true};
}

string string__clone(string a) {
	if (a.len <= 0) {
		return _str_30;
	}
	string b = (string){.str = malloc_noscan(a.len + 1), .len = a.len};
	{
		vmemcpy((void*)(b.str), (void*)(a.str), a.len);
		(b.str)[a.len] = 0;
	}
	return b;
}

bool string__contains(string s, string substr) {
	if (substr.len == 0) {
		return true;
	}
	if (substr.len == 1) {
		return string__contains_u8(s, (substr.str)[0]);
	}
	return string__index_(s, substr) != -1;
}

bool string__contains_u8(string s, u8 x) {
	{
		i64 __for_idx_0 = 0;
		for (; __for_idx_0 < s.len; __for_idx_0++) {
			u8 c = (s).str[__for_idx_0];
			if (x == c) {
				return true;
			}
		}
	}
	return false;
}

bool string__eq(string s, string a) {
	if (s.str == 0) {
		return (a.str == 0) || (a.len == 0);
	}
	if (s.len != a.len) {
		return false;
	}
	{
		return vmemcmp((void*)(s.str), (void*)(a.str), a.len) == 0;
	}
}

void string__free(string* s) {
	if (s->is_lit == -98761234) {
		u8* double_free_msg = (u8*)("double string.free() detected\n");
		i64 double_free_msg_len = vstrlen(double_free_msg);
		{
			_write_buf_to_fd(1, double_free_msg, double_free_msg_len);
		}
		return;
	}
	if ((s->is_lit == 1) || (s->str == 0)) {
		return;
	}
	{
		v_free(s->str);
		s->str = NULL;
	}
	s->len = 0;
	s->is_lit = -98761234;
}

i64 string__index_(string s, string p) {
	if ((p.len > s.len) || (p.len == 0) || ((u64)(s.str) <= 0xFFFF) || ((u64)(p.str) <= 0xFFFF)) {
		return -1;
	}
	if (p.len > builtin__max_direct_index_needle_len) {
		return string__index_kmp(s, p);
	}
	u8 first = (p.str)[0];
	i64 last_start = s.len - p.len;
	{
		i64 i = 0;
		for (; i <= last_start; i++) {
			if ((s.str)[i] != first) {
				continue;
			}
			i64 j = 1;
			while ((j < p.len) && (s.str)[i + j] == (p.str)[j]) {
				j++;
			}
			if (j == p.len) {
				return i;
			}
		}
	}
	return -1;
}

i64 string__index_kmp(string s, string p) {
	if (p.len > s.len) {
		return -1;
	}
	i64 stack_prefixes[20];
	memmove(stack_prefixes, (i64[20]){0}, sizeof(stack_prefixes));
	i64* p_prefixes = &stack_prefixes[0];
	if (p.len > builtin__kmp_stack_buffer_size) {
		p_prefixes = (i64*)(vcalloc(p.len * (i64)(sizeof(i64))));
	}
	i64 j = 0;
	{
		i64 i = 1;
		for (; i < p.len; i++) {
			while ((p.str)[j] != (p.str)[i] && (j > 0)) {
				j = (p_prefixes)[j - 1];
			}
			if ((p.str)[j] == (p.str)[i]) {
				j++;
			}
			{
				(p_prefixes)[i] = j;
			}
		}
	}
	j = 0;
	{
		i64 i = 0;
		for (; i < s.len; i++) {
			while ((p.str)[j] != (s.str)[i] && (j > 0)) {
				j = (p_prefixes)[j - 1];
			}
			if ((p.str)[j] == (s.str)[i]) {
				j++;
			}
			if (j == p.len) {
				i64 _t1 = 				(i - p.len) + 1;
				{
					if (p.len > builtin__kmp_stack_buffer_size) {
						{
							v_free(p_prefixes);
						}
					}
				}
				return _t1;
			}
		}
	}
	i64 _t2 = 	-1;
	{
		if (p.len > builtin__kmp_stack_buffer_size) {
			{
				v_free(p_prefixes);
			}
		}
	}
	return _t2;
	{
		if (p.len > builtin__kmp_stack_buffer_size) {
			{
				v_free(p_prefixes);
			}
		}
	}
}

i64 string__index_last_(string s, string p) {
	if ((p.len > s.len) || (p.len == 0)) {
		return -1;
	}
	i64 i = s.len - p.len;
	while (i >= 0) {
		i64 j = 0;
		while ((j < p.len) && (s.str)[i + j] == (p.str)[j]) {
			j++;
		}
		if (j == p.len) {
			return i;
		}
		i--;
	}
	return -1;
}

bool string__is_capital(string s) {
	if ((s.len == 0) || !(((s).str[0] >= 'A') && ((s).str[0] <= 'Z'))) {
		return false;
	}
	{
		i64 i = 1;
		for (; i < s.len; i++) {
			if (((s).str[i] >= 'A') && ((s).str[i] <= 'Z')) {
				return false;
			}
		}
	}
	return true;
}

bool string__is_pure_ascii(string s) {
	{
		i64 i = 0;
		for (; i < s.len; i++) {
			if ((s).str[i] >= 0x80) {
				return false;
			}
		}
	}
	return true;
}

bool string__lt(string s, string a) {
	i64 __if_val_0 = {0};
	if (s.len < a.len) {
		__if_val_0 = s.len;
	} else {
		__if_val_0 = a.len;
	}
	i64 min_len = __if_val_0;
	if (min_len > 0) {
		i64 cmp = vmemcmp((void*)(s.str), (void*)(a.str), min_len);
		if (cmp != 0) {
			return cmp < 0;
		}
	}
	return s.len < a.len;
}

string string__plus(string s, string a) {
	i64 __if_val_0 = {0};
	if (s.len > 0) {
		__if_val_0 = s.len;
	} else {
		__if_val_0 = 0;
	}
	i64 slen = __if_val_0;
	i64 __if_val_1 = {0};
	if (a.len > 0) {
		__if_val_1 = a.len;
	} else {
		__if_val_1 = 0;
	}
	i64 alen = __if_val_1;
	i64 new_len = alen + slen;
	string res = (string){.str = malloc_noscan(new_len + 1), .len = new_len};
	{
		if (slen > 0) {
			vmemcpy((void*)(res.str), (void*)(s.str), slen);
		}
		if (alen > 0) {
			vmemcpy((void*)(res.str + slen), (void*)(a.str), alen);
		}
		(res.str)[new_len] = 0;
	}
	return res;
}

Array string__runes(string s) {
	Array runes = __new_array_noscan(0, s.len, sizeof(u32));
	{
		i64 i = 0;
		for (; i < s.len; i++) {
			multi_return_u32_i64 __multi_ret_0 = utf8_decode_rune(&(s.str)[i], s.len - i);
			u32 r = __multi_ret_0.arg0;
			i64 char_len = __multi_ret_0.arg1;
			u32 __arr_val_1 = r;
			array_push(&runes, &__arr_val_1);
			if (char_len > 1) {
				i += char_len - 1;
			}
		}
	}
	return runes;
}

string string__substr(string s, i64 start, i64 _end) {
	i64 __if_val_0 = {0};
	if ((_end == builtin__max_i64) || (_end == builtin__max_i32)) {
		__if_val_0 = s.len;
	} else {
		__if_val_0 = _end;
	}
	i64 end = __if_val_0;
	{
		if ((start > end) || (start > s.len) || (end > s.len) || (start < 0) || (end < 0)) {
			v_panic(({ string __v3_internal_symbol_join_0[8]; __v3_internal_symbol_join_0[0] = _str_110; __v3_internal_symbol_join_0[1] = impl_i64_to_string(start); __v3_internal_symbol_join_0[2] = _str_14; __v3_internal_symbol_join_0[3] = impl_i64_to_string(end); __v3_internal_symbol_join_0[4] = _str_111; __v3_internal_symbol_join_0[5] = impl_i64_to_string(s.len); __v3_internal_symbol_join_0[6] = _str_112; __v3_internal_symbol_join_0[7] = s; string_plus_many(8, __v3_internal_symbol_join_0); }));
		}
	}
	i64 len = end - start;
	if (len == s.len) {
		return string__clone(s);
	}
	string res = (string){.str = malloc_noscan(len + 1), .len = len};
	{
		vmemcpy((void*)(res.str), (void*)(s.str + start), len);
		(res.str)[len] = 0;
	}
	return res;
}

string string__substr_ni(string s, i64 _start, i64 _end) {
	i64 start = _start;
	i64 __if_val_0 = {0};
	if ((_end == builtin__max_i64) || (_end == builtin__max_i32)) {
		__if_val_0 = s.len;
	} else {
		__if_val_0 = _end;
	}
	i64 end = __if_val_0;
	if (start < 0) {
		start = s.len + start;
		if (start < 0) {
			start = 0;
		}
	}
	if (end < 0) {
		end = s.len + end;
		if (end < 0) {
			end = 0;
		}
	}
	if (end >= s.len) {
		end = s.len;
	}
	if ((start > s.len) || (end < start)) {
		return _str_30;
	}
	i64 len = end - start;
	string res = (string){.str = malloc_noscan(len + 1), .len = len};
	{
		vmemcpy((void*)(res.str), (void*)(s.str + start), len);
		(res.str)[len] = 0;
	}
	return res;
}

string string__to_lower(string s) {
	if (string__is_pure_ascii(s)) {
		return string__to_lower_ascii(s);
	}
	Array runes = string__runes(s);
	{
		i64 i = 0;
		for (; i < runes.len; i++) {
			{ Array* _a0 = &runes; int _i0 = i; array__set(_a0, _i0, &(u32[]){rune__to_lower((*((u32*)((runes).data) + (i))))}); }
		}
	}
	return Array_rune__string(runes);
}

string string__to_lower_ascii(string s) {
	{
		u8* b = malloc_noscan(s.len + 1);
		{
			i64 i = 0;
			for (; i < s.len; i++) {
				if (((s.str)[i] >= 'A') && ((s.str)[i] <= 'Z')) {
					(b)[i] = (s.str)[i] + 32;
				} else {
					(b)[i] = (s.str)[i];
				}
			}
		}
		(b)[s.len] = 0;
		return tos(b, s.len);
	}
}

string string__to_upper(string s) {
	if (string__is_pure_ascii(s)) {
		return string__to_upper_ascii(s);
	}
	Array runes = string__runes(s);
	{
		i64 i = 0;
		for (; i < runes.len; i++) {
			{ Array* _a0 = &runes; int _i0 = i; array__set(_a0, _i0, &(u32[]){rune__to_upper((*((u32*)((runes).data) + (i))))}); }
		}
	}
	return Array_rune__string(runes);
}

string string__to_upper_ascii(string s) {
	{
		u8* b = malloc_noscan(s.len + 1);
		{
			i64 i = 0;
			for (; i < s.len; i++) {
				if (((s.str)[i] >= 'a') && ((s.str)[i] <= 'z')) {
					(b)[i] = (s.str)[i] - 32;
				} else {
					(b)[i] = (s.str)[i];
				}
			}
		}
		(b)[s.len] = 0;
		return tos(b, s.len);
	}
}

string string_plus_many(i64 data_len, string* input_base) {
	i64 new_len = 0;
	{
		i64 i = 0;
		for (; i < data_len; i++) {
			string part = (input_base)[i];
			i64 __if_val_0 = {0};
			if (part.len > 0) {
				__if_val_0 = part.len;
			} else {
				__if_val_0 = 0;
			}
			new_len += __if_val_0;
		}
	}
	string res = (string){.str = malloc_noscan(new_len + 1), .len = new_len};
	i64 offset = 0;
	{
		{
			i64 i = 0;
			for (; i < data_len; i++) {
				string part = (input_base)[i];
				i64 __if_val_1 = {0};
				if (part.len > 0) {
					__if_val_1 = part.len;
				} else {
					__if_val_1 = 0;
				}
				i64 part_len = __if_val_1;
				if (part_len > 0) {
					vmemcpy((void*)(res.str + offset), (void*)(part.str), part_len);
					offset += part_len;
				}
			}
		}
		(res.str)[new_len] = 0;
	}
	return res;
}

void strings__Builder__free(Array* b) {
	if (b->data != 0) {
		Array* arr = (Array*)(b);
		{
			array__free(arr);
		}
	}
}

string strings__Builder__str(Array* b) {
	u8 __arr_val_0 = (u8)(0);
	array_push(b, &__arr_val_0);
	u8* bcopy = (u8*)(memdup_noscan(b->data, b->len));
	string s = u8__vstring_with_len(bcopy, b->len - 1);
	array__clear(b);
	return s;
}

void strings__Builder__write_ptr(Array* b, u8* ptr, i64 len) {
	if (len == 0) {
		return;
	}
	{
		array_push_many_ptr(b, ptr, len);
	}
}

void strings__Builder__write_runes(Array* b, Array runes) {
	u8 buffer[5];
	memmove(buffer, (u8[5]){0}, sizeof(buffer));
	{
		i64 __for_idx_0 = 0;
		for (; __for_idx_0 < runes.len; __for_idx_0++) {
			u32 r = *(u32*)(array_get(runes, __for_idx_0));
			string res = utf32_to_str_no_malloc((u32)(r), &((u8*[]){&buffer[0]})[0]);
			if (res.len == 0) {
				continue;
			}
			{
				array_push_many_ptr(b, res.str, res.len);
			}
		}
	}
}

inline void strings__Builder__write_string(Array* b, string s) {
	if (s.len == 0) {
		return;
	}
	{
		array_push_many_ptr(b, s.str, s.len);
	}
}

Array strings__new_builder(i64 initial_size) {
	Array res = (Array)(__new_array_noscan(0, initial_size, sizeof(u8)));
	{
		res.flags |= 1;
	}
	return res;
}

string tos(u8* s, i64 len) {
	if (s == 0) {
		v_panic(_str_99);
	}
	return (string){.str = s, .len = len};
}

void trace_error(string x) {
}

inline string u64__str(u64 nn) {
	{
		u64 n = nn;
		u64 d = (u64)(0);
		if (n == 0) {
			return _str_56;
		}
		i64 max = 20;
		u8* buf = malloc_noscan(max + 1);
		i64 v_index = max;
		(buf)[v_index] = 0;
		v_index--;
		while (n > 0) {
			u64 n1 = ({ u64 _t1 = (u64)(n); u64 _t2 = (u64)(100); if (_t2 == 0) v_panic(_S("division by zero")); (u64)(_t1 / _t2); });
			d = ((u64)(((u64)(			(n - (n1 * 100)))) << (1)));
			n = n1;
			(buf)[v_index] = (builtin__digit_pairs).str[(i64)(d)];
			v_index--;
			d++;
			(buf)[v_index] = (builtin__digit_pairs).str[(i64)(d)];
			v_index--;
		}
		v_index++;
		if (d < 20) {
			v_index++;
		}
		i64 diff = max - v_index;
		vmemmove((void*)(buf), (void*)(buf + v_index), diff + 1);
		return tos(buf, diff);
	}
}

inline string u64_to_hex_no_leading_zeros(u64 nn, u8 len) {
	u64 n = nn;
	u8 buf[17];
	memmove(buf, (u8[17]){0}, sizeof(buf));
	buf[len] = 0;
	i64 i = 0;
	{
		i = len - 1;
		for (; i >= 0; i--) {
			u8 d = (u8)(n & 0xF);
			u8 __if_val_0 = {0};
			if (d < 10) {
				__if_val_0 = d + '0';
			} else {
				__if_val_0 = d + 87;
			}
			buf[i] = __if_val_0;
			n = (u64)(((u64)(			n)) >> (4));
			if (n == 0) {
				break;
			}
		}
	}
	i64 res_len = len - i;
	return tos((u8*)(memdup((void*)(&buf[i]), res_len + 1)), res_len);
}

string u8__ascii_str(u8 b) {
	string str = (string){.str = malloc_noscan(2), .len = 1};
	{
		(str.str)[0] = b;
		(str.str)[1] = 0;
	}
	return str;
}

inline bool u8__is_capital(u8 c) {
	return (c >= 'A') && (c <= 'Z');
}

inline bool u8__is_letter(u8 c) {
	return ((c >= 'a') && (c <= 'z')) || ((c >= 'A') && (c <= 'Z'));
}

string u8__vstring(u8* bp) {
	return (string){.str = bp, .len = vstrlen(bp)};
}

string u8__vstring_with_len(u8* bp, i64 len) {
	return (string){.str = bp, .len = len, .is_lit = 0};
}

void unbuffer_stdout(void) {
	{
		{
			set_stream_unbuffered(stdout);
		}
	}
}

i64 utf32_decode_to_buffer(u32 code, u8** buf) {
	{
		i64 icode = (i64)(code);
		u8* buffer = (u8*)(*buf);
		if (icode <= 127) {
			(buffer)[0] = (u8)(icode);
			return 1;
		} else if (icode <= 2047) {
			(buffer)[0] = 192 | (u8)((i64)(((i64)(			icode)) >> (6)));
			(buffer)[1] = 128 | (u8)(icode & 63);
			return 2;
		} else if (icode <= 65535) {
			(buffer)[0] = 224 | (u8)((i64)(((i64)(			icode)) >> (12)));
			(buffer)[1] = 128 | ((u8)((i64)(((i64)(			icode)) >> (6))) & 63);
			(buffer)[2] = 128 | (u8)(icode & 63);
			return 3;
		} else if (icode <= 1114111) {
			(buffer)[0] = 240 | (u8)((i64)(((i64)(			icode)) >> (18)));
			(buffer)[1] = 128 | ((u8)((i64)(((i64)(			icode)) >> (12))) & 63);
			(buffer)[2] = 128 | ((u8)((i64)(((i64)(			icode)) >> (6))) & 63);
			(buffer)[3] = 128 | (u8)(icode & 63);
			return 4;
		}
	}
	return 0;
}

string utf32_to_str(u32 code) {
	{
		u8* buffer = malloc_noscan(5);
		string res = utf32_to_str_no_malloc(code, &buffer);
		if (res.len == 0) {
			v_free(buffer);
		}
		return res;
	}
}

string utf32_to_str_no_malloc(u32 code, u8** buf) {
	{
		i64 len = utf32_decode_to_buffer(code, buf);
		if (len == 0) {
			return _str_30;
		}
		((*buf))[len] = 0;
		return tos((*buf), len);
	}
}

multi_return_u32_i64 utf8_decode_rune(u8* _bytes, i64 available_len) {
	if (available_len <= 0) {
		return (multi_return_u32_i64){0, 0};
	}
	u8 b0 = (_bytes)[0];
	if (b0 < 0x80) {
		return (multi_return_u32_i64){(u32)(b0), 1};
	}
	if (b0 < 0xc2) {
		return (multi_return_u32_i64){builtin__utf8_replacement_rune, 1};
	}
	i64 __if_val_0 = {0};
	if (b0 < 0xe0) {
		__if_val_0 = 2;
	} else {
		if (b0 < 0xf0) {
			__if_val_0 = 3;
		} else {
			if (b0 < 0xf5) {
				__if_val_0 = 4;
			} else {
				return (multi_return_u32_i64){builtin__utf8_replacement_rune, 1};
			}
		}
	}
	i64 char_len = __if_val_0;
	if (available_len < char_len) {
		return (multi_return_u32_i64){builtin__utf8_replacement_rune, 1};
	}
	u8 b1 = (_bytes)[1];
	if (!utf8_is_continuation(b1)) {
		return (multi_return_u32_i64){builtin__utf8_replacement_rune, 1};
	}
	if (char_len == 2) {
		return (multi_return_u32_i64){((u32)(((u32)(		((u32)(b0) & 0x1f))) << (6))) | ((u32)(b1) & 0x3f), 2};
	}
	if ((b0 == 0xe0) && (b1 < 0xa0)) {
		return (multi_return_u32_i64){builtin__utf8_replacement_rune, 1};
	}
	if ((b0 == 0xed) && (b1 >= 0xa0)) {
		return (multi_return_u32_i64){builtin__utf8_replacement_rune, 1};
	}
	u8 b2 = (_bytes)[2];
	if (!utf8_is_continuation(b2)) {
		return (multi_return_u32_i64){builtin__utf8_replacement_rune, 1};
	}
	if (char_len == 3) {
		return (multi_return_u32_i64){(((u32)(((u32)(		((u32)(b0) & 0x0f))) << (12))) | ((u32)(((u32)(		((u32)(b1) & 0x3f))) << (6)))) | ((u32)(b2) & 0x3f), 3};
	}
	if ((b0 == 0xf0) && (b1 < 0x90)) {
		return (multi_return_u32_i64){builtin__utf8_replacement_rune, 1};
	}
	if ((b0 == 0xf4) && (b1 > 0x8f)) {
		return (multi_return_u32_i64){builtin__utf8_replacement_rune, 1};
	}
	u8 b3 = (_bytes)[3];
	if (!utf8_is_continuation(b3)) {
		return (multi_return_u32_i64){builtin__utf8_replacement_rune, 1};
	}
	return (multi_return_u32_i64){((((u32)(((u32)(	((u32)(b0) & 0x07))) << (18))) | ((u32)(((u32)(	((u32)(b1) & 0x3f))) << (12)))) | ((u32)(((u32)(	((u32)(b2) & 0x3f))) << (6)))) | ((u32)(b3) & 0x3f), 4};
}

inline bool utf8_is_continuation(u8 b) {
	return (b & 0xc0) == 0x80;
}

VNORETURN void v_exit(i64 code) {
	exit(code);
	for (;;) {
	}
}

inline i64 v_fixed_index(i64 i, i64 len) {
	{
		if ((i < 0) || (i >= len)) {
			v_panic(({ string __v3_internal_symbol_join_0[5]; __v3_internal_symbol_join_0[0] = _str_186; __v3_internal_symbol_join_0[1] = i64__str((i64)(i)); __v3_internal_symbol_join_0[2] = _str_187; __v3_internal_symbol_join_0[3] = i64__str((i64)(len)); __v3_internal_symbol_join_0[4] = _str_23; string_plus_many(5, __v3_internal_symbol_join_0); }));
		}
	}
	return i;
}

inline i64 v_fixed_index_i64(i64 i, i64 len) {
	{
		if ((i < 0) || (i >= (i64)(len))) {
			v_panic(({ string __v3_internal_symbol_join_0[5]; __v3_internal_symbol_join_0[0] = _str_186; __v3_internal_symbol_join_0[1] = i64__str(i); __v3_internal_symbol_join_0[2] = _str_187; __v3_internal_symbol_join_0[3] = i64__str((i64)(len)); __v3_internal_symbol_join_0[4] = _str_23; string_plus_many(5, __v3_internal_symbol_join_0); }));
		}
	}
	return (i64)(i);
}

inline i64 v_fixed_index_ni(i64 i, i64 len) {
	return v_fixed_index(v_ni_index(i, len), len);
}

inline i64 v_fixed_index_u64(u64 i, i64 len) {
	{
		if (i >= (u64)(len)) {
			v_panic(({ string __v3_internal_symbol_join_0[5]; __v3_internal_symbol_join_0[0] = _str_186; __v3_internal_symbol_join_0[1] = u64__str(i); __v3_internal_symbol_join_0[2] = _str_187; __v3_internal_symbol_join_0[3] = i64__str((i64)(len)); __v3_internal_symbol_join_0[4] = _str_23; string_plus_many(5, __v3_internal_symbol_join_0); }));
		}
	}
	return (i64)(i);
}

void v_free(void* ptr) {
	if (ptr == 0) {
		return;
	}
	IError* none_err = (IError*)(&builtin__none__);
	if (ptr == none_err->_object) {
		return;
	}
	IError* sentinel_err = (IError*)(&builtin__error_sentinel);
	if (ptr == sentinel_err->_object) {
		return;
	}
	{
		{
			free(ptr);
		}
	}
}

u64 v_getpid(void) {
	{
		return (u64)(getpid());
	}
}

u64 v_gettid(void) {
	{
		return (u64)(v3_gettid());
	}
}

u8* v_malloc(ptrdiff_t n) {
	if (n < 0) {
		_memory_panic(_str_162, n);
	} else if (n == 0) {
		return (u8*)(NULL);
	}
	u8* res = (u8*)(NULL);
	{
		{
			res = (u8*)(malloc(n));
		}
	}
	if (res == 0) {
		_memory_panic(_str_162, n);
	}
	return res;
}

inline i64 v_ni_index(i64 i, i64 len) {
	if (i < 0) {
		return len + i;
	} else {
		return i;
	}
}

VNORETURN void v_panic(string s) {
	if ((g_panic_state.top != NULL) || (g_panic_state.len > 0)) {
		panic_unwind(s, (PanicDebugInfo){.file = _str_30, .mod = _str_30, .fn_name = _str_30});
	}
	{
		flush_stdout();
		eprint(_str_207);
		eprintln(s);
		eprint(_str_208);
		eprintln(vcurrent_hash());
		{
			eprint(_str_209);
			fprintf(stderr, "%p\n", (void*)(v_getpid()));
			eprint(_str_210);
			fprintf(stderr, "%p\n", (void*)(v_gettid()));
		}
		flush_stdout();
		{
			{
				print_backtrace_skipping_top_frames(1);
			}
			exit(1);
		}
	}
	exit(1);
	for (;;) {
	}
}

u8* v_realloc(u8* b, ptrdiff_t n) {
	u8* new_ptr = (u8*)(NULL);
	{
		{
			new_ptr = (u8*)(realloc(b, n));
		}
	}
	if (new_ptr == 0) {
		_memory_panic(_str_167, n);
	}
	if (b != NULL) {
	}
	return new_ptr;
}

inline i64 v_slice_index_i64(i64 i) {
	if ((i < (i64)(builtin__min_int)) || (i > (i64)(builtin__max_int))) {
		v_panic(string__plus(_str_188, i64__str(i)));
	}
	return (i64)(i);
}

inline i64 v_slice_index_u64(u64 i) {
	if (i > (u64)(builtin__max_int)) {
		v_panic(string__plus(_str_188, u64__str(i)));
	}
	return (i64)(i);
}

u8* vcalloc(ptrdiff_t n) {
	if (n < 0) {
		_memory_panic(_str_169, n);
	} else if (n == 0) {
		return (u8*)(NULL);
	}
	{
		{
			void* r = calloc(1, n);
			return (u8*)(r);
		}
	}
	return (u8*)(NULL);
}

u8* vcalloc_noscan(ptrdiff_t n) {
	{
		return vcalloc(n);
	}
	return (u8*)(NULL);
}

string vcurrent_hash(void) {
	return _str_189;
}

inline i64 vmemcmp(void* const_s1, void* const_s2, ptrdiff_t n) {
	if ((n == 0) || ((u64)(const_s1) <= 0xFFFF) || ((u64)(const_s2) <= 0xFFFF)) {
		return 0;
	}
	{
		return memcmp(const_s1, const_s2, n);
	}
}

inline void* vmemcpy(void* dest, void* const_src, ptrdiff_t n) {
	if ((n == 0) || ((u64)(dest) <= 0xFFFF) || ((u64)(const_src) <= 0xFFFF)) {
		return dest;
	}
	{
		return memcpy(dest, const_src, n);
	}
}

inline void* vmemmove(void* dest, void* const_src, ptrdiff_t n) {
	if ((n == 0) || ((u64)(dest) <= 0xFFFF) || ((u64)(const_src) <= 0xFFFF)) {
		return dest;
	}
	{
		return memmove(dest, const_src, n);
	}
}

inline void* vmemset(void* s, i64 c, ptrdiff_t n) {
	if ((n == 0) || ((u64)(s) <= 0xFFFF)) {
		return s;
	}
	{
		return memset(s, c, n);
	}
}

Array voidptr__vbytes(void* data, i64 len) {
	array res = (array){.element_size = 1, .data = data, .len = len, .cap = len, .flags = 0};
	return res;
}

inline i64 vstrlen(u8* s) {
	return (i64)(strlen((char*)(s)));
}

inline i64 vstrlen_char(char* s) {
	return (i64)(strlen(s));
}

// THE END.
