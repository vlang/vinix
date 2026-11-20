// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import errno

// personality(2): a task's Linux execution domain and the compatibility flags
// that go with it. Linux 6.12 accepts any value, keeps it per task, passes it
// to new threads and processes, and keeps it across exec except
// READ_IMPLIES_EXEC, which loading a 64-bit ELF clears on both architectures.
// What Vinix acts on:
// - ADDR_NO_RANDOMIZE: an exec places the program, interpreter, stack, mmap
//   area, break and signal trampoline at fixed addresses, as `setarch -R` and
//   GDB's disable-randomization expect; see Process.layout_fixed.
// - READ_IMPLIES_EXEC: mmap and mprotect add PROT_EXEC to readable memory that
//   may be executable, as Linux does; Vinix's W^X policy then judges it.
// - UNAME26 and, on x86-64, PER_LINUX32 change what uname(2) reports.
// The remaining flags are kept and reported but change nothing, as on Linux
// for 64-bit tasks, except where its limits say otherwise.
pub const per_mask = u32(0x00ff)
pub const per_linux32 = u32(0x0008)
pub const uname26 = u32(0x0020000)
pub const addr_no_randomize = u32(0x0040000)
pub const read_implies_exec = u32(0x0400000)
const personality_query = u32(0xffffffff)

// The value is an unsigned int: only the register's low 32 bits count. The
// result is the previous personality.
pub fn syscall_personality(_ voidptr, value_word u64) (u64, u64) {
	value := u32(value_word)
	mut t := current_thread()
	old := t.personality
	if value != personality_query {
		// arm64 refuses the 32-bit domain on a CPU without AArch32 at EL0,
		// which Vinix never runs.
		$if arm64 {
			if value & per_mask == per_linux32 { return errno.err, errno.einval }
		}
		t.personality = value
	}
	return u64(old), 0
}

pub fn current_personality() u32 {
	t := current_thread()
	return if t == unsafe { nil } { u32(0) } else { t.personality }
}

// What an exec by thread `old` leaves the new program with.
pub fn exec_personality(old &Thread) u32 {
	return old.personality & ~read_implies_exec
}

// Whether an exec by the calling thread randomizes the new program's layout.
pub fn exec_randomizes() bool {
	return current_personality() & addr_no_randomize == 0
}
