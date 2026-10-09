module mmap

import x86.cpu
import x86.cpu.local as cpulocal
import x86.kio
import memory
import proc
import sched

// Page-fault error code bits.
const pf_write = u64(1) << 1
const pf_instruction = u64(1) << 4

const rflags_ac = u64(1) << 18
const cr4_smap = u64(1) << 21

// The kernel's image is linked into the top two gigabytes.
const kernel_image_base = u64(0xffffffff80000000)

// One line for each kernel path the audit finds, with what called it. The
// access itself is often in memcpy or strlen, which keep no frame and may use
// the frame pointer for something else, so the callers are read off the stack:
// the words on it that point into the kernel's image are, nearly all of them,
// return addresses.
fn report_direct_access(gpr_state &cpulocal.GPRState, addr u64, write bool) {
	mut frames := [5]u64{}
	mut found := 0
	if gpr_state.rsp >= higher_half && gpr_state.rsp & 7 == 0 {
		for i in 0 .. 96 {
			slot := gpr_state.rsp + u64(i) * 8
			// Not past the end of the stack's last page.
			if i != 0 && slot & 0xfff == 0 {
				break
			}
			word := unsafe { *(&u64(slot)) }
			if word >= kernel_image_base {
				frames[found] = word
				found++
				if found == frames.len {
					break
				}
			}
		}
	}
	top := frames[0]
	if !memory.user_guard_note(gpr_state.rip * 31 + top + frames[1] * 7) {
		return
	}
	current := proc.current_thread()
	name := if current != unsafe { nil } { current.process.name.str } else { c'?' }
	C.kprintf(c'user-access: %s 0x%llx at pc 0x%llx lr 0x%llx < 0x%llx 0x%llx 0x%llx 0x%llx (%s)\n',
		if write { c'wrote' } else { c'read' }, addr, gpr_state.rip, top, frames[1], frames[2],
		frames[3], frames[4], name)
	// A production kernel prints to the screen only, and an audit is read
	// from a log: the same line to COM1.
	serial_text(c'user-access: ')
	serial_text(if write { c'wrote' } else { c'read' })
	serial_hex(c' ', addr)
	serial_hex(c' at pc ', gpr_state.rip)
	serial_hex(c' lr ', top)
	serial_hex(c' < ', frames[1])
	serial_hex(c' ', frames[2])
	serial_hex(c' ', frames[3])
	serial_hex(c' ', frames[4])
	serial_text(c' (')
	serial_text(name)
	serial_text(c')\r\n')
}

const com1 = u16(0x3f8)

fn serial_text(text &u8) {
	for i := 0; unsafe { text[i] } != 0; i++ {
		// Until the transmitter is empty. No port reads as all ones.
		for kio.port_in[u8](com1 + 5) & 0x20 == 0 {}
		kio.port_out[u8](com1, unsafe { text[i] })
	}
}

fn serial_hex(before &u8, value u64) {
	mut digits := [19]u8{}
	digits[0] = `0`
	digits[1] = `x`
	for i in 0 .. 16 {
		digits[2 + i] = '0123456789abcdef'[int((value >> u64(60 - 4 * i)) & 0xf)]
	}
	serial_text(before)
	// The audit's reader takes the shortest form, as %llx prints it.
	mut start := 2
	for start < 17 && digits[start] == `0` {
		start++
	}
	digits[start - 1] = `x`
	digits[start - 2] = `0`
	serial_text(unsafe { &digits[start - 2] })
}

pub fn pf_handler(gpr_state &cpulocal.GPRState) ? {
	// CR2 is read before interrupts go back on. Once they are, the scheduler
	// can switch this thread out, and another one's page fault on this CPU
	// overwrites CR2: the handler then looked up the other thread's address in
	// this thread's page map, found nothing there, and killed it with SIGSEGV
	// for a page that was perfectly mappable.
	addr := cpu.read_cr2()
	// Also protect callers other than the top-level ISR. Userspace faults
	// keep their ordinary page-in/COW behavior.
	if gpr_state.cs & 3 == 0 && memory.fault_resolution_disabled() {
		return none
	}
	if gpr_state.err & 1 != 0 {
		// The kernel reached for a page userspace can reach, with SMAP on and
		// AC clear: a path that still follows a user pointer rather than
		// copying through usercopy. An audit names the path once and lets the
		// access through, with AC set until the thread goes back to userspace,
		// so it sees the first such access of each entry into the kernel. This
		// comes before copy-on-write, which would otherwise answer that the
		// page is writable already and retry the access for ever.
		if addr < higher_half && gpr_state.cs & 3 == 0 && gpr_state.err & pf_instruction == 0
			&& gpr_state.rflags & rflags_ac == 0 && cpu.read_cr4() & cr4_smap != 0 {
			if !memory.user_guard_auditing() {
				C.kprintf(c'user-access: the kernel %s user address 0x%llx directly, at pc 0x%llx; vinix.user_access=audit reports this and carries on\n',
					if gpr_state.err & pf_write != 0 { c'wrote' } else { c'read' }, addr,
					gpr_state.rip)
				return none
			}
			report_direct_access(gpr_state, addr, gpr_state.err & pf_write != 0)
			unsafe {
				mut state := &cpulocal.GPRState(gpr_state)
				state.rflags |= rflags_ac
			}
			return
		}
		// A write-protection fault on a fork-shared private page is the normal
		// COW path, not a process fault.
		if gpr_state.err & 2 != 0 {
			current := proc.current_thread()
			asm volatile amd64 {
				sti
			}
			resolved := current != unsafe { nil }
				&& resolve_cow_fault(current.process.pagemap, addr)
			asm volatile amd64 {
				cli
			}
			if resolved {
				return
			}
		}
		// It was a protection violation, crash
		return none
	}

	// Only user mappings can be paged in here, and during early boot there is
	// no current thread to page them in for.
	if addr >= higher_half {
		return none
	}
	mut current_thread := proc.current_thread()
	if current_thread == unsafe { nil } {
		return none
	}

	asm volatile amd64 {
		sti
	}
	defer {
		asm volatile amd64 {
			cli
		}
	}

	// A page that is mapped by the time the lock is held was paged in by
	// another thread that faulted on it too; retrying the access is all this
	// one needs.
	mut pagemap := current_thread.process.pagemap
	page_in(mut pagemap, addr, true)?
	if gpr_state.cs & 3 == 3 { sched.park_for_cgroup() }
}

// x86 keeps the instruction cache coherent with stores.
fn sync_new_code_page(_page voidptr) {}

// Small private anonymous mappings may wait until their first access.
fn demand_private_anonymous() bool {
	return true
}
