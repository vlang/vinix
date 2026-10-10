// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
//
// How the bytes of a key are read: floats, fixed point, byte order, names.
module core

import math

fn float_bits(value f32) u32 {
	return math.f32_bits(value)
}

const most = i64(0x7fffffffffffffff)

fn test_a_float_is_cut_off_towards_zero_at_the_scale_asked_for() {
	assert flt_scaled(float_bits(0.0), 1000) == 0
	assert flt_scaled(float_bits(38.5), 1000) == 38500
	assert flt_scaled(float_bits(-12.25), 1000) == -12250
	assert flt_scaled(float_bits(3456.0), 1) == 3456
	assert flt_scaled(float_bits(0.999), 1) == 0
	assert flt_scaled(float_bits(-0.999), 1) == 0
	assert flt_scaled(float_bits(1350.0), 1) == 1350
	// The constants the simulated SMC is given are what they are called.
	assert sim_flt_38_5 == float_bits(38.5)
	assert sim_flt_31_25 == float_bits(31.25)
	assert sim_flt_47 == float_bits(47.0)
	assert sim_flt_2400 == float_bits(2400.0)
	assert sim_flt_1350 == float_bits(1350.0)
	assert sim_flt_5349 == float_bits(5349.0)
}

// Values read from a real SMC (a Mac17,6), bytes as it gave them.
fn test_floats_read_from_a_real_machine() {
	// TB0T cc cc 0a 42: 34.699997 degrees.
	battery := [u8(0xcc), 0xcc, 0x0a, 0x42]!
	assert flt_scaled(u32(little_endian(&battery[0], 4)), 1000) == 34699
	// F0Ac 00 00 58 45: 3456 revolutions a minute.
	fan := [u8(0x00), 0x00, 0x58, 0x45]!
	assert flt_scaled(u32(little_endian(&fan[0], 4)), 1) == 3456
	// F0Mn 00 c0 a8 44: 1350.
	slowest := [u8(0x00), 0xc0, 0xa8, 0x44]!
	assert flt_scaled(u32(little_endian(&slowest[0], 4)), 1) == 1350
}

fn test_a_float_too_big_for_the_integer_is_held_at_its_end() {
	assert flt_scaled(float_bits(1.0e30), 1000) == most
	assert flt_scaled(float_bits(-1.0e30), 1000) == -most - 1
	assert flt_scaled(float_bits(1.0e-30), 1000) == 0
	// The smallest denormal, and the largest finite float.
	assert flt_scaled(1, 1000) == 0
	assert flt_scaled(0x7f7fffff, 1) == most
}

fn test_what_is_not_a_number_is_told_apart() {
	assert flt_is_number(float_bits(38.5))
	assert flt_is_number(0)
	assert flt_is_number(0x80000000)
	assert !flt_is_number(0x7f800000)
	assert !flt_is_number(0xff800000)
	assert !flt_is_number(0x7fc00000)
	assert !flt_is_number(0xffffffff)
}

fn test_fixed_point_is_48_16() {
	assert ioft_scaled(u64(44) << 16, 1000) == 44000
	assert ioft_scaled(0, 1000) == 0
	assert ioft_scaled(0x8000, 1000) == 500
	assert ioft_scaled(0xffff, 1000) == 999
	// TG0B from a real SMC: 33 b3 22 00 00 00 00 00 is 34.70 degrees.
	graphics := [u8(0x33), 0xb3, 0x22, 0, 0, 0, 0, 0]!
	assert ioft_scaled(little_endian(&graphics[0], 8), 1000) == 34699
	// All ones does not wrap into something small.
	assert ioft_scaled(~u64(0), 1000) == ((u64(1) << 48) - 1) * 1000 + 999
	assert ioft_scaled(~u64(0), 1) == (u64(1) << 48) - 1
	assert ioft_scaled(~u64(0), ~u64(0)) == ~u64(0)
}

fn test_numbers_are_lowest_byte_first() {
	bytes := [u8(0x01), 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]!
	assert little_endian(&bytes[0], 1) == 0x01
	assert little_endian(&bytes[0], 2) == 0x0201
	assert little_endian(&bytes[0], 4) == 0x04030201
	assert little_endian(&bytes[0], 8) == 0x0807060504030201
	assert swap16(0x1f99) == 0x991f
	assert swap16(swap16(0xabcd)) == 0xabcd
}

fn test_keys_are_their_four_characters() {
	mut text := [4]u8{}
	key_text(key_b0rm, &text[0])
	assert unsafe { tos(&text[0], 4) } == 'B0RM'
	key_text(key_aci, &text[0])
	assert unsafe { tos(&text[0], 4) } == 'AC-i'
	key_text(0x00410a7f, &text[0])
	assert unsafe { tos(&text[0], 4) } == '?A??'
	assert fan_key(0, `A`, `c`) == key_f0ac
	assert fan_key(0, `M`, `n`) == key_f0mn
	assert fan_key(0, `M`, `x`) == key_f0mx
	key_text(fan_key(1, `A`, `c`), &text[0])
	assert unsafe { tos(&text[0], 4) } == 'F1Ac'
	for slot in 0 .. slot_count {
		assert slot_key(slot) != 0
	}
	assert slot_key(slot_count) == 0
	assert type_flt == 0x666c7420
	assert type_ioft == 0x696f6674
}

fn test_temperatures_have_to_be_possible() {
	assert plausible_temperature(0)
	assert plausible_temperature(38500)
	assert plausible_temperature(-40000)
	assert plausible_temperature(199999)
	assert !plausible_temperature(200000)
	assert !plausible_temperature(-273150)
	assert !plausible_temperature(most)
}
