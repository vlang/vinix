// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the actual pinned interpreter with independent instruction memory.
@[translated; has_globals]
module rspbudgetfixture

#include <n64-rsp-native-abi.h>

@[typedef]
struct C.n64_const_char {}
@[typedef]
struct C.RSP_INFO {
mut:
	SP_PC_REG &u32
}

@[c_extern] __global C.n64_rsp_info C.RSP_INFO
@[c_extern] __global C.n64_rsp_imem &u8
@[c_extern] __global C.n64_rsp_dmem &u8
@[c_extern] __global C.n64_rsp_cr [16]&u32
@[export: 'vinix_n64_cpu_budget'] __global cpu_budget u64
@[export: 'vinix_n64_rsp_budget'] __global rsp_budget u64
@[export: 'g_rsp_force_halt'] __global force_halt i32

__global (
	instructions [1024]u32
	data [1024]u32
	pc u32
	status u32
	exhausted u32
	unexpected_message bool
)

fn C.run_task()
fn C.puts(&char) i32
fn C.memset(voidptr, i32, usize) voidptr

@[export: 'vinix_n64_budget_exhausted']
pub fn budget_exhausted() {
	unsafe { exhausted++ }
}

// The upstream logger's leading arguments use the ordinary native ABI.
// This fixture ignores its unused variadic arguments and rejects any message.
@[export: 'vinix_n64_rsp_fixture_message']
pub fn rsp_message(level i32, message &C.n64_const_char) {
	unsafe { unexpected_message = true }
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.n64_rsp_imem = &u8(&instructions[0])
		C.n64_rsp_dmem = &u8(&data[0])
		C.n64_rsp_info.SP_PC_REG = &pc
		C.n64_rsp_cr[4] = &status
		// J 0; J 0 repeatedly enters the static-PC branch-delay path.
		// The former loop-top check sees only the first instruction.
		instructions[0] = 0x08000000
		instructions[1] = 0x08000000
		rsp_budget = 16
		C.puts(c'N64 RSP: executing a branch in a branch delay slot')
		C.run_task()
		if exhausted != 1 || rsp_budget != 0 || unexpected_message {
			C.puts(c'N64 RSP FAIL: branch-delay instructions escaped their budget')
			return 1
		}
		// An independent normal task still terminates through BREAK afterward.
		C.memset(&instructions[0], 0, sizeof(instructions))
		instructions[0] = 0x0000000d
		pc = 0
		rsp_budget = 16
		C.run_task()
		if exhausted != 1 || rsp_budget != 15 || pc != 0x04001004 || unexpected_message {
			C.puts(c'N64 RSP FAIL: interpreter did not run a normal BREAK task afterward')
			return 1
		}
		C.puts(c'N64 RSP PASS: branch-delay loop is bounded and a subsequent task runs')
		return 0
	}
}
