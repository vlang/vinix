// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// seccomp: a process's system calls passed through the classic BPF programs it
// has installed, as Linux's seccomp(2) passes them. Every program sees the
// call's number, the architecture, the address it was made from and its six
// arguments, laid out as struct seccomp_data, and answers with an action: let
// it run, fail it with an errno, raise SIGSYS, or kill the process. The most
// restrictive answer of all the programs wins. Docker installs its default
// profile this way in every container, a few hundred instructions that turn
// away the calls a container has no business making.
//
// Programs are checked when installed as Linux checks them, never change
// afterwards, and are kept by a process's children after fork and exec.
// They belong to the process here, not to one thread, which is what
// SECCOMP_FILTER_FLAG_TSYNC asks Linux for.
module proc

pub const seccomp_mode_disabled = 0
pub const seccomp_mode_strict = 1
pub const seccomp_mode_filter = 2

pub const seccomp_ret_kill_process = u32(0x80000000)
pub const seccomp_ret_kill_thread = u32(0x00000000)
pub const seccomp_ret_trap = u32(0x00030000)
pub const seccomp_ret_errno = u32(0x00050000)
pub const seccomp_ret_user_notif = u32(0x7fc00000)
pub const seccomp_ret_trace = u32(0x7ff00000)
pub const seccomp_ret_log = u32(0x7ffc0000)
pub const seccomp_ret_allow = u32(0x7fff0000)
pub const seccomp_ret_action_full = u32(0xffff0000)
pub const seccomp_ret_data = u32(0x0000ffff)

pub const audit_arch_aarch64 = u32(0xc00000b7)

pub const bpf_max_instructions = 4096
// Linux's bound on every program a call runs through, each counted with four
// instructions more than it has.
const seccomp_max_path_instructions = 32768
const seccomp_data_size = u32(64)

// One classic BPF instruction, as struct sock_filter lays it out.
pub struct SockFilter {
pub mut:
	code u16
	jt   u8
	jf   u8
	k    u32
}

pub struct SeccompFilter {
pub mut:
	instructions []SockFilter
	// The program installed before this one, which runs too.
	prev &SeccompFilter = unsafe { nil }
	// Programs in the chain ending here, and their instructions, each
	// counted as Linux counts it.
	count      int
	path_total int
}

// Whether a program is one a filter can be: classic BPF as Linux checks it,
// narrowed to what reads struct seccomp_data. Every jump goes forward and
// stays inside, and the program ends by returning, so it always finishes.
pub fn seccomp_check(instructions []SockFilter) bool {
	if instructions.len == 0 || instructions.len > bpf_max_instructions {
		return false
	}
	for pc, insn in instructions {
		k := insn.k
		match insn.code {
			// BPF_LD|BPF_W|BPF_ABS: a 32-bit word of seccomp_data.
			0x20 {
				if k & 3 != 0 || k >= seccomp_data_size {
					return false
				}
			}
			// BPF_LD/BPF_LDX|BPF_W|BPF_LEN, BPF_LD/BPF_LDX|BPF_IMM.
			0x80, 0x81, 0x00, 0x01 {}
			// BPF_LD/BPF_LDX|BPF_MEM, BPF_ST, BPF_STX: the scratch words.
			0x60, 0x61, 0x02, 0x03 {
				if k >= 16 {
					return false
				}
			}
			// BPF_ALU: add, sub, mul, or, and, xor with K or X; div, mod, shifts
			// with X; neg.
			0x04, 0x0c, 0x14, 0x1c, 0x24, 0x2c, 0x44, 0x4c, 0x54, 0x5c, 0xa4, 0xac, 0x3c,
			0x9c, 0x6c, 0x7c, 0x84 {}
			// Division and remainder by a constant zero.
			0x34, 0x94 {
				if k == 0 {
					return false
				}
			}
			// Shifts by a constant of 32 or more.
			0x64, 0x74 {
				if k >= 32 {
					return false
				}
			}
			// BPF_JMP|BPF_JA.
			0x05 {
				if u64(pc) + 1 + u64(k) >= u64(instructions.len) {
					return false
				}
			}
			// BPF_JMP|BPF_JEQ/JGT/JGE/JSET with K or X.
			0x15, 0x1d, 0x25, 0x2d, 0x35, 0x3d, 0x45, 0x4d {
				if pc + 1 + int(insn.jt) >= instructions.len
					|| pc + 1 + int(insn.jf) >= instructions.len {
					return false
				}
			}
			// BPF_RET with K or A; BPF_MISC|BPF_TAX, BPF_TXA.
			0x06, 0x16, 0x07, 0x87 {}
			else {
				return false
			}
		}
	}
	last := instructions[instructions.len - 1].code
	return last == 0x06 || last == 0x16
}

// Run a checked program over `data`, struct seccomp_data as sixteen words.
fn seccomp_run(instructions []SockFilter, data &[16]u32) u32 {
	mut a := u32(0)
	mut x := u32(0)
	mut scratch := [16]u32{}
	mut pc := 0
	for pc < instructions.len {
		insn := instructions[pc]
		k := insn.k
		match insn.code {
			0x20 { a = data[k >> 2] }
			0x80 { a = seccomp_data_size }
			0x81 { x = seccomp_data_size }
			0x00 { a = k }
			0x01 { x = k }
			0x60 { a = scratch[k] }
			0x61 { x = scratch[k] }
			0x02 { scratch[k] = a }
			0x03 { scratch[k] = x }
			0x04 { a += k }
			0x0c { a += x }
			0x14 { a -= k }
			0x1c { a -= x }
			0x24 { a *= k }
			0x2c { a *= x }
			0x34 { a /= k }
			0x3c {
				// Division by zero ends the program with 0, as in Linux.
				if x == 0 {
					return 0
				}
				a /= x
			}
			0x94 { a %= k }
			0x9c {
				if x == 0 {
					return 0
				}
				a %= x
			}
			0x44 { a |= k }
			0x4c { a |= x }
			0x54 { a &= k }
			0x5c { a &= x }
			0xa4 { a ^= k }
			0xac { a ^= x }
			0x64 { a <<= k }
			0x6c { a = if x < 32 { a << x } else { u32(0) } }
			0x74 { a >>= k }
			0x7c { a = if x < 32 { a >> x } else { u32(0) } }
			0x84 { a = u32(0) - a }
			0x05 { pc += int(k) }
			0x15 { pc += if a == k { int(insn.jt) } else { int(insn.jf) } }
			0x1d { pc += if a == x { int(insn.jt) } else { int(insn.jf) } }
			0x25 { pc += if a > k { int(insn.jt) } else { int(insn.jf) } }
			0x2d { pc += if a > x { int(insn.jt) } else { int(insn.jf) } }
			0x35 { pc += if a >= k { int(insn.jt) } else { int(insn.jf) } }
			0x3d { pc += if a >= x { int(insn.jt) } else { int(insn.jf) } }
			0x45 { pc += if a & k != 0 { int(insn.jt) } else { int(insn.jf) } }
			0x4d { pc += if a & x != 0 { int(insn.jt) } else { int(insn.jf) } }
			0x06 { return k }
			0x16 { return a }
			0x07 { x = a }
			0x87 { a = x }
			else { return seccomp_ret_kill_thread }
		}
		pc++
	}
	return seccomp_ret_kill_thread
}

// What the programs ending in `filter` answer for a call: the most
// restrictive answer, compared as Linux compares them.
pub fn seccomp_verdict(filter &SeccompFilter, nr u64, ip u64, args [6]u64) u32 {
	mut data := [16]u32{}
	data[0] = u32(nr)
	data[1] = audit_arch_aarch64
	data[2] = u32(ip)
	data[3] = u32(ip >> 32)
	for i in 0 .. 6 {
		data[4 + 2 * i] = u32(args[i])
		data[5 + 2 * i] = u32(args[i] >> 32)
	}
	mut verdict := seccomp_ret_allow
	mut current := unsafe { filter }
	for current != unsafe { nil } {
		answer := seccomp_run(current.instructions, &data)
		if i32(answer & seccomp_ret_action_full) < i32(verdict & seccomp_ret_action_full) {
			verdict = answer
		}
		current = current.prev
	}
	return verdict
}

// Add a checked program to the ones `process` has. False when the chain
// would grow past what Linux lets one call run through.
pub fn seccomp_attach(mut process Process, instructions []SockFilter) bool {
	mut count := 1
	mut path_total := instructions.len + 4
	if process.seccomp != unsafe { nil } {
		count += process.seccomp.count
		path_total += process.seccomp.path_total
	}
	if path_total > seccomp_max_path_instructions {
		return false
	}
	process.seccomp = &SeccompFilter{
		instructions: instructions
		prev:         process.seccomp
		count:        count
		path_total:   path_total
	}
	process.seccomp_mode = seccomp_mode_filter
	return true
}

// How many programs a process has installed, for /proc/<pid>/status.
pub fn seccomp_filter_count(process &Process) int {
	if process.seccomp == unsafe { nil } {
		return 0
	}
	return process.seccomp.count
}
