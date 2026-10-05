// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

fn syscall_instruction_size() u64 { return 2 }
fn syscall_instruction_word() u32 { return 0x050f }
fn syscall_instruction_aligned(_ u64) bool { return true }
