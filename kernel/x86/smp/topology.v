// SPDX-License-Identifier: GPL-2.0-or-later
module smp

import limine
import x86.cpu

struct SMTTopology {
	known bool
	shift u32
}

// CPUID's extended topology leaves encode SMT bits at the bottom of the
// x2APIC identifier. Removing only those bits retains package/die/core identity.
fn smt_topology() SMTTopology {
	for leaf in [u32(0x1f), u32(0xb)]! {
		for level := u32(0); level < 32; level++ {
			ok, width, count, kind, _ := cpu.cpuid(leaf, level)
			if !ok || count & 0xffff == 0 { break }
			if (kind >> 8) & 0xff != 1 { continue }
			shift := width & 0x1f
			threads := count & 0xffff
			if threads > u32(1) << shift { break }
			return SMTTopology{known: true, shift: shift}
		}
	}
	return SMTTopology{}
}

fn same_physical_core(first u32, second u32, topology SMTTopology) bool {
	return topology.known && first >> topology.shift == second >> topology.shift
}

// Exact tokens only: a prefix or suffix must not turn SMT back on. An
// unrecognized value fails closed, and a later token can replace an earlier one.
fn smt_enabled() bool {
	mut enabled := true
	file := limine.kernel_file()
	if file == unsafe { nil } || file.cmdline == unsafe { nil } { return enabled }
	text := unsafe { &u8(file.cmdline) }
	mut index := 0
	for unsafe { text[index] } != 0 {
		for is_space(unsafe { text[index] }) { index++ }
		start := index
		for unsafe { text[index] } != 0 && !is_space(unsafe { text[index] }) { index++ }
		length := index - start
		if length < 10 { continue }
		mut matched := true
		for offset, byte in 'vinix.smt=' {
			if unsafe { text[start + offset] } != byte { matched = false; break }
		}
		if matched { enabled = length == 11 && unsafe { text[start + 10] } == `1` }
	}
	return enabled
}

fn is_space(byte u8) bool {
	return byte == ` ` || byte == `\t` || byte == `\n` || byte == `\r`
}
