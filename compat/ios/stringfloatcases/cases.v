// SPDX-License-Identifier: GPL-2.0-or-later
// Shared, bit-exact native Foundation and Vinix regression vectors.
module stringfloatcases

pub struct Case {
pub:
	input string
	bits u32
}

pub fn cases() []Case {
	inputs := ['', '0', '-0', '+0', '1.5', '-12.25tail', '  \t\n+3.25e2x', '.', '-', 'word',
		'1,5', '1e', '1e+', '1e-2', '0x1.8p2', '-0x1p-149', 'inf', '-Infinity', 'NaN',
		'nan(12)', '1e1000', '-1e1000', '3.4028234663852886e38', '3.4028236e38',
		'1e-50', '-1e-50', '1.401298464324817e-45', '1.000000059604644775390625',
		'1.000000059604644775390626', '١.٥', '１２.５', '12\x0034', '\x0012',
		'- 1.5', '+\t1.5', '+\n1.5', '-.', '-word', '-NaN', '-inf', '1.e2', '.5e2',
		'1e+ 2', '1e- 2', '1E٢', '١٢.٥e٢', '1.٢', '𝟙.𝟝', '¹.⁵', '१.५', '۱.۵',
		'1٫5', '−1.5', '＋1.5', '1d2', '1e2e3', 'x\uFEFF1.5']
	expected := [u32(0), 0, 0x80000000, 0, 0x3fc00000, 0xc1440000, 0, 0, 0, 0,
		0x3f800000, 0x3f800000, 0x3f800000, 0x3c23d70a, 0, 0x80000000, 0, 0, 0, 0,
		0x7f800000, 0xff800000, 0x7f7fffff, 0x7f800000, 0, 0x80000000, 1,
		0x3f800000, 0x3f800000, 0x3fc00000, 0x41480000, 0x41400000, 0,
		0, 0, 0, 0, 0, 0, 0, 0x42c80000, 0x42480000, 0x3f800000, 0x3f800000,
		0x42c80000, 0x449c4000, 0x3f99999a, 0, 0, 0x3fc00000, 0x3fc00000,
		0x3f800000, 0, 0, 0x3f800000, 0x42c80000, 0]
	assert inputs.len == expected.len
	mut result := []Case{}
	for i, input in inputs { result << Case{input, expected[i]} }
	for prefix in ['\t', '\n', '\v', '\f', '\r', ' ', '\u0085', '\u00a0', '\u1680',
		'\u180e', '\u2000', '\u2001', '\u2002', '\u2003', '\u2004', '\u2005', '\u2006',
		'\u2007', '\u2008', '\u2009', '\u200a', '\u200b', '\u2028', '\u2029', '\u202f',
		'\u205f', '\u2060', '\u3000', '\uFEFF'] {
		accepted := prefix !in ['\n', '\v', '\f', '\r', '\u0085', '\u180e', '\u2028', '\u2029', '\u2060', '\uFEFF']
		// initWithBytes strips a leading BOM before parsing; test it after a sign.
		if prefix != '\uFEFF' { result << Case{prefix + '1.5', if accepted { u32(0x3fc00000) } else { u32(0) }} }
		result << Case{'+' + prefix + '1.5', 0}
		result << Case{'1e' + prefix + '2', 0x3f800000}
	}
	for zero in [0x30, 0x660, 0x6f0, 0x7c0, 0x966, 0x9e6, 0xa66, 0xae6, 0xb66,
		0xbe6, 0xc66, 0xce6, 0xd66, 0xde6, 0xe50, 0xed0, 0xf20, 0x1040, 0x1090,
		0x17e0, 0x1810, 0x1946, 0x19d0, 0x1a80, 0x1a90, 0x1b50, 0x1bb0,
		0x1c40, 0x1c50, 0xa620, 0xa8d0, 0xa900, 0xa9d0, 0xa9f0, 0xaa50, 0xabf0, 0xff10] {
		for digit in 0 .. 10 {
			text := rune(zero + digit).str()
			bits := [u32(0), 0x3f800000, 0x40000000, 0x40400000, 0x40800000,
				0x40a00000, 0x40c00000, 0x40e00000, 0x41000000, 0x41100000]!
			result << Case{text, bits[digit]}
		}
		result << Case{'-' + rune(zero + 1).str() + '.' + rune(zero + 5).str(), 0xbfc00000}
		result << Case{'1e' + rune(zero + 2).str(), 0x42c80000}
		result << Case{rune(zero - 1).str() + '2', 0}
		result << Case{rune(zero + 10).str() + '2', 0}
	}
	for zero in [0x104a0, 0x10d30, 0x11066, 0x1d7ce, 0x1d7d8, 0x1e950, 0x1fbf0] {
		result << Case{rune(zero + 1).str(), 0}
		result << Case{'1e' + rune(zero + 2).str(), 0x3f800000}
	}
	return result
}
