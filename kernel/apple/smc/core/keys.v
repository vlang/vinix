// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
//
// The SMC's keys this kernel asks for, and how the bytes of a value are read.
//
// A key is four characters and so is the type GET_KEY_INFO gives for it. The
// names and what each means are Linux's: drivers/power/supply/macsmc-power.c
// for the battery and the charger, drivers/hwmon/macsmc-hwmon.c and the
// device trees beside it (arch/arm64/boot/dts/apple/hwmon-*.dtsi) for
// sensors and fans. docs/m1-battery.md says which of them were also read,
// with which type and size, from the SMC of the Mac this was written on.
//
// Numbers are little-endian in the order the SMC holds them, with one
// exception Linux found: the remaining charge, B0RM, is big-endian on
// firmware whose BCF0 is four bytes long.
//
// Like core.v this file imports nothing, allocates nothing and uses no
// floating point: a float is taken apart as the 32 bits it is.
module core

// The battery.
pub const key_b0rm = u32(0x4230524d) // B0RM  remaining charge, mAh
pub const key_b0fc = u32(0x42304643) // B0FC  charge when full, mAh
pub const key_b0dc = u32(0x42304443) // B0DC  charge when new, mAh
pub const key_b0ct = u32(0x42304354) // B0CT  charge cycles
pub const key_b0te = u32(0x42305445) // B0TE  minutes to empty, 0xffff for none
pub const key_b0tf = u32(0x42305446) // B0TF  minutes to full, 0xffff for none
pub const key_bitv = u32(0x42495456) // BITV  the voltage it must not go under, mV
pub const key_bsfc = u32(0x42534643) // BSFC  full
pub const key_bcf0 = u32(0x42434630) // BCF0  about to give out
pub const key_bmdn = u32(0x424d444e) // BMDN  what it is called
pub const key_bmsn = u32(0x424d534e) // BMSN  its serial number
// Charging.
pub const key_ch0r = u32(0x43483052) // CH0R  why the charger's power is not taken
pub const key_chce = u32(0x43484345) // CHCE  a charger is there
pub const key_chcc = u32(0x43484343) // CHCC  and it can charge
pub const key_chnc = u32(0x43484e43) // CHNC  why the battery is not being charged
pub const key_chsc = u32(0x43485343) // CHSC  charging, where CHNC is not there
pub const key_chis = u32(0x43484953) // CHIS  the charger is supplying power
pub const key_chwa = u32(0x43485741) // CHWA  stop charging at 80%
pub const key_aci = u32(0x41432d69) // AC-i  the charger's current limit, mA
// Fans. The digit is the fan's number.
pub const key_fnum = u32(0x464e756d) // FNum  how many
pub const key_f0ac = u32(0x46304163) // F0Ac  revolutions a minute, now
pub const key_f0mn = u32(0x46304d6e) // F0Mn  the slowest it runs
pub const key_f0mx = u32(0x46304d78) // F0Mx  the fastest
// Temperatures, in degrees Celsius.
pub const key_th0x = u32(0x54483078) // TH0x
pub const key_tb0t = u32(0x54423054) // TB0T
pub const key_tchp = u32(0x54434850) // TCHP
pub const key_tw0p = u32(0x54573050) // TW0P

// Types.
pub const type_flt = u32(0x666c7420) // "flt "  IEEE 754, 32 bits
pub const type_ioft = u32(0x696f6674) // "ioft"  48.16 fixed point, unsigned

// Attribute bits (include/linux/mfd/macsmc.h).
pub const flag_readable = u8(0x80)
pub const flag_writable = u8(0x40)

// The key of fan `index` whose last two characters are `a` and `b`.
pub fn fan_key(index int, a u8, b u8) u32 {
	return (u32(`F`) << 24) | (u32(`0` + u8(index)) << 16) | (u32(a) << 8) | u32(b)
}

// A key as the four characters it is, into `out`.
pub fn key_text(key u32, out &u8) {
	for i in 0 .. 4 {
		c := u8(key >> u32(24 - 8 * i))
		shown := if c >= 0x20 && c < 0x7f { c } else { `?` }
		unsafe {
			out[i] = shown
		}
	}
}

// The first `count` bytes at `bytes`, lowest first, as one number.
pub fn little_endian(bytes &u8, count int) u64 {
	mut value := u64(0)
	for i in 0 .. count {
		value |= u64(unsafe { bytes[i] }) << u32(8 * i)
	}
	return value
}

pub fn swap16(value u64) u64 {
	return ((value & 0xff) << 8) | ((value >> 8) & 0xff)
}

// Whether the 32 bits of a float are a number at all: not an infinity and
// not one of the patterns that mean "not a number".
pub fn flt_is_number(bits u32) bool {
	return (bits >> 23) & 0xff != 0xff
}

// A float's value times `scale`, as an integer cut off towards zero and held
// to what 64 bits can say. Linux's macsmc_hwmon_read_f32_scaled().
pub fn flt_scaled(bits u32, scale u64) i64 {
	mut value := u64((bits & 0x7fffff) | 0x800000) * scale
	exponent := int((bits >> 23) & 0xff) - 127 - 23
	if exponent > 63 {
		value = ~u64(0)
	} else if exponent < -63 {
		value = 0
	} else if exponent < 0 {
		value >>= u32(-exponent)
	} else if exponent != 0 && (value & ~((u64(1) << u32(64 - exponent)) - 1)) != 0 {
		// It would not fit.
		value = ~u64(0)
	} else {
		value <<= u32(exponent)
	}
	largest := u64(0x7fffffffffffffff)
	if bits & 0x80000000 != 0 {
		if value > largest {
			return -i64(largest) - 1
		}
		return -i64(value)
	}
	if value > largest {
		return i64(largest)
	}
	return i64(value)
}

// A 48.16 fixed point number times `scale`, cut off towards zero. `scale`
// is at most a million here, and the product is made in two halves so that
// it cannot overflow on the way. Linux's macsmc_hwmon_read_ioft_scaled().
pub fn ioft_scaled(value u64, scale u64) u64 {
	whole := value >> 16
	fraction := value & 0xffff
	if scale != 0 && whole > ~u64(0) / scale {
		return ~u64(0)
	}
	return whole * scale + ((fraction * scale) >> 16)
}
