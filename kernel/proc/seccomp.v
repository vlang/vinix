// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// seccomp: a task's system calls passed through the classic BPF programs it
// has installed, as Linux's seccomp(2) passes them. Every program sees the
// call's number, the architecture, the address it was made from and its six
// arguments, laid out as struct seccomp_data, and answers with an action: let
// it run, fail it with an errno, raise SIGSYS, or kill the process. The most
// restrictive answer of all the programs wins. Docker installs its default
// profile this way in every container, a few hundred instructions that turn
// away the calls a container has no business making.
//
// Programs are checked when installed as Linux checks them, never change
// afterwards, and are inherited from the calling task at clone/fork/exec.
// TSYNC may replace siblings' heads only when each is disabled or holds an
// ancestor of the caller's chain. Identical independently installed programs
// do not constitute the same ancestor.
@[has_globals]
module proc

import errno
import katomic
import klock
import memory

// Lock order: process table -> thread list -> seccomp. Evaluation, diagnostic
// snapshots and final thread reclamation take only seccomp_lock. A bounded
// evaluator retains the lock through its immutable chain, so no reader can
// observe a reclaimed node and no per-syscall reference/allocation is needed.
__global (
	seccomp_lock klock.Lock
)

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
pub const audit_arch_x86_64 = u32(0xc000003e)

// A synchronous SIGSYS belongs to the triggering thread. It is consumed
// when that private signal is selected, before building the user frame.
pub struct SeccompSignal {
pub mut:
	pending bool
	data u32
	syscall u32
	address u64
}

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
	// Direct task heads and child filters' prev links each own one reference.
	// Protected by seccomp_lock, including the final release.
	refs u64
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
	if last != 0x06 && last != 0x16 { return false }
	return seccomp_check_scratch(instructions)
}

// Linux's classic-BPF verifier requires each scratch word to have been
// written along every incoming branch before a load. Zeroing the runtime
// scratch array cannot substitute for rejecting an invalid program.
fn seccomp_check_scratch(instructions []SockFilter) bool {
	// Forward-only jumps let one pass intersect the initialized-word masks.
	// Bound this temporary to 8 KiB of the 64 KiB kernel stack; installation
	// needs no new allocation or lifetime to manage.
	mut masks := [bpf_max_instructions]u16{}
	for i in 0 .. instructions.len { masks[i] = u16(0xffff) }
	mut initialized := u16(0)
	for pc, insn in instructions {
		initialized &= masks[pc]
		match insn.code {
			0x02, 0x03 { initialized |= u16(1) << insn.k }
			0x60, 0x61 {
				if initialized & (u16(1) << insn.k) == 0 { return false }
			}
			0x05 {
				masks[pc + 1 + int(insn.k)] &= initialized
				initialized = u16(0xffff)
			}
			0x15, 0x1d, 0x25, 0x2d, 0x35, 0x3d, 0x45, 0x4d {
				masks[pc + 1 + int(insn.jt)] &= initialized
				masks[pc + 1 + int(insn.jf)] &= initialized
				initialized = u16(0xffff)
			}
			else {}
		}
	}
	return true
}

// Run a checked program over `data`, struct seccomp_data as sixteen words.
fn seccomp_run(instructions []SockFilter, data [16]u32) u32 {
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
pub fn seccomp_verdict(task &Thread, nr u64, ip u64, args [6]u64) u32 {
	seccomp_lock.acquire()
	defer { seccomp_lock.release() }
	filter := task.seccomp
	if filter == unsafe { nil } { return seccomp_ret_kill_process }
	mut data := [16]u32{}
	data[0] = u32(nr)
	data[1] = seccomp_audit_arch
	data[2] = u32(ip)
	data[3] = u32(ip >> 32)
	for i in 0 .. 6 {
		data[4 + 2 * i] = u32(args[i])
		data[5 + 2 * i] = u32(args[i] >> 32)
	}
	mut verdict := seccomp_ret_allow
	mut current := unsafe { filter }
	for current != unsafe { nil } {
		// Fixed-array value passing keeps the seccomp_data words on the stack.
		// Taking &data makes V box 64 bytes on every filtered syscall.
		answer := seccomp_run(current.instructions, data)
		if i32(answer & seccomp_ret_action_full) < i32(verdict & seccomp_ret_action_full) {
			verdict = answer
		}
		current = current.prev
	}
	return verdict
}

pub fn seccomp_mode(task &Thread) u32 {
	if task == unsafe { nil } { return 0 }
	return katomic.load(&task.seccomp_mode)
}

// Called while attaching under table/list locks, before the new task is
// published. This also refreshes NNP: TSYNC may have set it on the source
// after the scheduler constructor copied its earlier scalar state.
pub fn seccomp_inherit(mut task Thread, source &Thread) {
	seccomp_lock.acquire()
	defer { seccomp_lock.release() }
	if source == unsafe { nil } { return }
	task.seccomp_mode = source.seccomp_mode
	task.seccomp = source.seccomp
	task.no_new_privs = no_new_privs_state(source)
	if task.seccomp != unsafe { nil } { task.seccomp.refs++ }
	seccomp_record_leader(task)
}

fn seccomp_record_leader(task &Thread) {
	if task.process == unsafe { nil } || task.tid != task.process.pid { return }
	mut process := task.process
	process.leader_seccomp_mode = task.seccomp_mode
	process.leader_seccomp_filters = if task.seccomp == unsafe { nil } { 0 } else { task.seccomp.count }
}

// Scalar snapshots survive leader retirement; they own no filter reference.
// The caller pins target through the process table lock while taking this.
pub fn seccomp_status(process &Process, target &Thread) (u32, int) {
	seccomp_lock.acquire()
	defer { seccomp_lock.release() }
	if target == unsafe { nil } || voidptr(target.process) != voidptr(process) {
		return process.leader_seccomp_mode, process.leader_seccomp_filters
	}
	return target.seccomp_mode, if target.seccomp == unsafe { nil } { 0 } else { target.seccomp.count }
}

pub fn seccomp_set_strict() (u64, u64) {
	mut task := current_thread()
	seccomp_lock.acquire()
	defer { seccomp_lock.release() }
	if task.seccomp_mode != seccomp_mode_disabled && task.seccomp_mode != seccomp_mode_strict {
		return errno.err, errno.einval
	}
	katomic.store(mut &task.seccomp_mode, u32(seccomp_mode_strict))
	seccomp_record_leader(task)
	return 0, 0
}

// A node owns its predecessor. Releasing the last direct reference releases
// that link iteratively; shared branches remain alive. All readers hold the
// same lock, so no grace period or retained pointer exists after the free.
fn seccomp_put(filter &SeccompFilter) {
	mut head := unsafe { filter }
	for head != unsafe { nil } {
		head.refs--
		if head.refs != 0 { break }
		previous := head.prev
		unsafe {
			head.instructions.free()
			free(head)
		}
		head = previous
	}
}

// Scheduler final reclamation (or unpublished-constructor rollback) occurs
// after the task is off its CPU and its last Thread pin has gone.
pub fn seccomp_release(mut task Thread) {
	seccomp_lock.acquire()
	defer { seccomp_lock.release() }
	old := task.seccomp
	task.seccomp = unsafe { nil }
	katomic.store(mut &task.seccomp_mode, u32(0))
	seccomp_put(old)
}

fn seccomp_ancestor(ancestor &SeccompFilter, child &SeccompFilter) bool {
	if ancestor == unsafe { nil } { return true }
	mut head := unsafe { child }
	for head != unsafe { nil } {
		if voidptr(head) == voidptr(ancestor) { return true }
		head = head.prev
	}
	return false
}

// Takes ownership of instructions only on success. User copies/verification
// precede the locks. Publication and TSYNC validation share the thread attach
// locks, excluding concurrent clone and exec's sibling teardown.
pub fn seccomp_attach(instructions []SockFilter, sync bool, sync_esrch bool) (u64, u64) {
	mut task := current_thread()
	mut process := task.process
	// A fallible allocator may reclaim pages; do not enter it under any of
	// the publication locks. Failed validation frees only this unpublished
	// header: the syscall caller still owns and frees the instruction buffer.
	mut filter := unsafe { &SeccompFilter(memory.malloc_packed_fallible(sizeof(SeccompFilter))) } @[freed]
	if filter == unsafe { nil } { return errno.err, errno.enomem }
	mut published := false
	defer { if !published { unsafe { free(filter) } } }
	pid_lock.acquire()
	defer { pid_lock.release() }
	process.threads_lock.acquire()
	defer { process.threads_lock.release() }
	seccomp_lock.acquire()
	defer { seccomp_lock.release() }
	if task.seccomp_mode == seccomp_mode_strict { return errno.err, errno.einval }
	mut count := 1
	mut path_total := instructions.len
	if task.seccomp != unsafe { nil } {
		count += task.seccomp.count
		path_total += task.seccomp.path_total + 4
	}
	if path_total > seccomp_max_path_instructions {
		return errno.err, errno.enomem
	}
	if sync {
		for peer in process.threads {
			if voidptr(peer) == voidptr(task) || katomic.load(&peer.exit_claimed) != 0 { continue }
			if peer.seccomp_mode == seccomp_mode_disabled
				|| (peer.seccomp_mode == seccomp_mode_filter && seccomp_ancestor(peer.seccomp, task.seccomp)) { continue }
			tid := tid_in(peer, process.numbered_in)
			if sync_esrch || tid == 0 { return errno.err, errno.esrch }
			return u64(tid), 0
		}
	}
	unsafe { *filter = SeccompFilter{
		refs:         1
		instructions: instructions
		prev:         task.seccomp
		count:        count
		path_total:   path_total
	} }
	// Transfer the caller's old head reference into the new prev link.
	task.seccomp = filter
	published = true
	katomic.store(mut &task.seccomp_mode, u32(seccomp_mode_filter))
	seccomp_record_leader(task)
	if sync {
		for mut peer in process.threads {
			if voidptr(peer) == voidptr(task) || katomic.load(&peer.exit_claimed) != 0 { continue }
			filter.refs++
			old := peer.seccomp
			peer.seccomp = filter
			seccomp_put(old)
			if no_new_privs_state(task) != 0 {
				katomic.store(mut &peer.no_new_privs, u32(1))
				if peer.tid == process.pid { katomic.store(mut &process.leader_no_new_privs, u32(1)) }
			}
			katomic.store(mut &peer.seccomp_mode, u32(seccomp_mode_filter))
			seccomp_record_leader(peer)
		}
	}
	return 0, 0
}
