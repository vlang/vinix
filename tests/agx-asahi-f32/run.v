// SPDX-License-Identifier: GPL-2.0-or-later
//
// The G13 InitData float helpers against Asahi's own software F32.
//
// Vinix computes the firmware's power coefficients without an FPU, and they
// have to be the bit patterns Asahi's float.rs produces, ties and truncation
// included. This compiles the arithmetic core of the pinned float.rs,
// unmodified, as an oracle, and feeds both implementations the same inputs:
// the expressions the builders use, sweeps over their device-tree ranges and
// pseudo-random operands.
//
// v run tests/agx-asahi-f32/run.v --asahi-linux /path/to/linux-aurora
// (or AGX_ASAHI_LINUX). Needs rustc.
import os

const oracle_main = '
use float::F32;
use std::io::{self, Write};

fn main() {
    let path = std::env::args().nth(1).unwrap();
    let cases = std::fs::read_to_string(path).unwrap();
    let mut out = io::BufWriter::new(io::stdout());
    for line in cases.lines() {
        let mut fields = line.split_whitespace();
        let op = fields.next().unwrap();
        let a = u32::from_str_radix(fields.next().unwrap(), 16).unwrap();
        let b = u32::from_str_radix(fields.next().unwrap(), 16).unwrap();
        let result = match op {
            "from" => F32::from(a),
            "frac" => F32::from(a) / F32::from(b),
            "udiv" => F32::from(a) / F32::from_bits(b),
            "mul" => F32::from_bits(a) * F32::from_bits(b),
            "oneminus" => F32::from_bits(0x3f800000) - F32::from_bits(a),
            _ => panic!("unknown operation {}", op),
        };
        writeln!(out, "{:08x}", result.to_bits()).unwrap();
    }
}
'

const checker_wrapper = '

pub fn eval(op string, a u32, b u32) ?u32 {
	if op == \'from\' {
		value := firmware_u32_to_f32_bits(a) or { return none }
		return value
	}
	if op == \'frac\' {
		value := firmware_fraction_to_f32_bits(a, b) or { return none }
		return value
	}
	if op == \'udiv\' {
		value := firmware_u32_div_f32_bits(a, b) or { return none }
		return value
	}
	if op == \'mul\' {
		value := firmware_f32_multiply_bits(a, b) or { return none }
		return value
	}
	if op == \'oneminus\' {
		value := firmware_f32_one_minus_bits(a) or { return none }
		return value
	}
	return none
}
'

const checker_main = '
import asahif32
import os
import strconv

fn main() {
	lines := os.read_lines(os.args[1])!
	mut out := []string{cap: lines.len}
	for line in lines {
		fields := line.split(\' \')
		a := u32(strconv.parse_uint(fields[1], 16, 32)!)
		b := u32(strconv.parse_uint(fields[2], 16, 32)!)
		if value := asahif32.eval(fields[0], a, b) {
			out << \'\${value:08x}\'
		} else {
			out << \'none\'
		}
	}
	os.write_lines(os.args[2], out)!
}
'

// The arithmetic core: F32 and F32U with their operators, without the kernel
// crate's property parsing or Zeroable marker.
fn extract_core(source string) !string {
	start := source.index('/// An IEEE754-compatible floating point number') or {
		return error('float.rs: no F32 definition')
	}
	end := source.index("impl<'a> TryFrom<of::Property<'a>> for F32") or {
		return error('float.rs: no property conversion after the arithmetic')
	}
	mut core := source[start..end]
	zeroable := '// SAFETY: F32 is a transparent repr of `u32` and therefore zeroable\nunsafe impl Zeroable for F32 {}\n'
	if !core.contains(zeroable) {
		return error('float.rs: Zeroable marker changed')
	}
	core = core.replace(zeroable, '')
	if core.contains('kernel::') || core.contains('of::') {
		return error('float.rs: the arithmetic core now depends on the kernel crate')
	}
	return '#![allow(dead_code, unused)]\nmod float {\nuse core::ops;\n${core}\n}\n'
}

struct Lcg {
mut:
	state u64 = 0x2545_f491_4f6c_dd1d
}

fn (mut g Lcg) next() u32 {
	g.state = g.state * 6364136223846793005 + 1442695040888963407
	return u32(g.state >> 32)
}

// A positive normal binary32 with an exponent in [low, high].
fn (mut g Lcg) float(low int, high int) u32 {
	exponent := u32(low + int(g.next() % u32(high - low + 1)) + 127)
	return (exponent << 23) | (g.next() & 0x7f_ffff)
}

fn cases() []string {
	mut out := []string{}
	mut g := Lcg{}
	// Integer conversions: every small value, around each power of two, and
	// values wider than the mantissa.
	for value in 0 .. 4096 {
		out << 'from ${value:x} 0'
	}
	for bit in 0 .. 32 {
		power := u64(1) << bit
		for delta in [i64(-1), 0, 1] {
			value := i64(power) + delta
			if value >= 0 && value <= 0xffff_ffff {
				out << 'from ${u32(value):x} 0'
			}
		}
	}
	for _ in 0 .. 4000 {
		out << 'from ${g.next():x} 0'
	}
	// 1 / n for every time constant up to 20000 and 1 - 1/n, as each filter
	// pair is built. 1 - 1/3 is an exact tie.
	for n in 1 .. 20001 {
		out << 'frac 1 ${n:x}'
	}
	// period_ms / 1000 and -max_ps_scaled / max_power_mw.
	for period in 1 .. 1001 {
		out << 'frac ${period:x} 3e8'
	}
	for scaled := 100; scaled <= 3000; scaled += 100 {
		for power := 1; power <= 100_000; power += 97 {
			out << 'frac ${scaled:x} ${power:x}'
		}
	}
	for _ in 0 .. 10_000 {
		out << 'frac ${g.next() % 0x100_0000 + 1:x} ${g.next() % 0x100_0000 + 1:x}'
	}
	// boost_ps_count / 0.95, and integers over other divisors.
	for count in 0 .. 4096 {
		out << 'udiv ${count:x} 3f733333'
	}
	for _ in 0 .. 5000 {
		out << 'udiv ${g.next() % 0x100_0000:x} ${g.float(-20, 20):x}'
	}
	// Device-tree gains times period_s, and random products.
	gains := [u32(0x40fca970), 0x416b53d1, 0x3ca59586, 0x40a90fdb, 0x42b70000, 0x43480000,
		0x40f00000, 0xc2480000, 0xc2c80000, 0x40400000, 0x40e00000, 0x3e7ae148]
	periods := [u32(0x3c03126f), 0x3a83126f, 0x3b03126f, 0x3c23d70a, 0x3ca3d70a, 0x3d4ccccd]
	for gain in gains {
		for period in periods {
			out << 'mul ${gain:x} ${period:x}'
		}
		for _ in 0 .. 500 {
			out << 'mul ${gain:x} ${g.float(-12, -1):x}'
		}
	}
	for _ in 0 .. 20_000 {
		sign := g.next() & 0x8000_0000
		out << 'mul ${g.float(-30, 30) | sign:x} ${g.float(-30, 30):x}'
	}
	// 1 - x for x in (0, 1], including every 1/n above and random operands.
	for value in [u32(0x3f800000), 0x3f000000, 0x3eaaaaab, 0x3e638e39, 0x3b51a2b8, 0x3e4ccccd,
		0x3a3e0a8a, 0x0, 0x80000000] {
		out << 'oneminus ${value:x} 0'
	}
	for _ in 0 .. 20_000 {
		out << 'oneminus ${g.float(-40, -1):x} 0'
	}
	return out
}

fn run(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 {
		return error('${args.join(' ')}\n${result.output}')
	}
	return result.output
}

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut asahi := os.getenv('AGX_ASAHI_LINUX')
	for index := 1; index < os.args.len; index++ {
		if os.args[index] == '--asahi-linux' && index + 1 < os.args.len {
			index++
			asahi = os.args[index]
		}
	}
	if asahi == '' {
		eprintln('usage: run.v --asahi-linux PATH (or AGX_ASAHI_LINUX)')
		exit(2)
	}
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	float_rs := os.read_file(os.join_path(asahi, 'drivers/gpu/drm/asahi/float.rs'))!
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-asahi-f32-${os.getpid()}')
	os.mkdir_all(os.join_path(scratch, 'asahif32'))!
	defer {
		os.rmdir_all(scratch) or {}
	}

	os.write_file(os.join_path(scratch, 'oracle.rs'), extract_core(float_rs)! + oracle_main)!
	run(['rustc', '--edition', '2021', '-O', '-o', os.join_path(scratch, 'oracle'),
		os.join_path(scratch, 'oracle.rs')])!

	production := os.getenv_opt('AGX_ASAHI_F32_SOURCE') or {
		os.join_path(repo, 'kernel/gpu/agx/fw/asahi_f32.v')
	}
	module_source := os.read_file(production)!.replace_once('module fw', 'module asahif32')
	os.write_file(os.join_path(scratch, 'asahif32/asahi_f32.v'), module_source + checker_wrapper)!
	os.write_file(os.join_path(scratch, 'main.v'), checker_main)!
	v := os.getenv_opt('V') or { 'v' }
	run([v, '-cc', 'cc', '-cflags', '-fsanitize=undefined -fno-sanitize-recover=undefined', '-ldflags',
		'-fsanitize=undefined', '-path', '${scratch}|@vlib|@vmodules', '-o', os.join_path(scratch, 'checker'),
		os.join_path(scratch, 'main.v')])!

	inputs := cases()
	cases_path := os.join_path(scratch, 'cases.txt')
	os.write_lines(cases_path, inputs)!
	expected := run([os.join_path(scratch, 'oracle'), cases_path])!.split_into_lines()
	run([os.join_path(scratch, 'checker'), cases_path, os.join_path(scratch, 'vinix.txt')])!
	actual := os.read_lines(os.join_path(scratch, 'vinix.txt'))!
	if expected.len != inputs.len || actual.len != inputs.len {
		eprintln('result counts differ: ${inputs.len} cases, ${expected.len} oracle, ${actual.len} Vinix')
		exit(1)
	}
	mut mismatches := 0
	mut by_operation := map[string]int{}
	for index, input in inputs {
		infinite := expected[index] in ['7f800000', 'ff800000']
		if actual[index] == expected[index] || (infinite && actual[index] == 'none') {
			continue
		}
		mismatches++
		kind := if actual[index] == 'none' { 'refused' } else { 'different value' }
		by_operation['${input.all_before(' ')} ${kind}']++
		if mismatches <= 20 {
			eprintln('${input}: Asahi ${expected[index]}, Vinix ${actual[index]}')
		}
	}
	if mismatches != 0 {
		for operation, count in by_operation {
			eprintln('  ${operation}: ${count}')
		}
		eprintln('${mismatches} of ${inputs.len} results differ from Asahi float.rs')
		exit(1)
	}
	println('Asahi F32: ${inputs.len} conversions, quotients, products and 1 - x match float.rs bit for bit')
}
