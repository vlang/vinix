// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

fn syscall_instruction_size() u64 { return 4 }
fn syscall_instruction_word() u32 { return 0xd4000001 }
fn syscall_instruction_aligned(address u64) bool { return address & 3 == 0 }
