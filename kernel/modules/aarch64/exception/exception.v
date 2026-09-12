@[has_globals]
module exception

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import aarch64.uart
import lib
import memory
import memory.mmap
import proc
import term
import userland

fn C.exception_vectors()
fn C.sc_dump_ring()

// Dedicated stack for exceptions taken while early boot runs on SP_EL0. When a
// fault is taken to EL1 the CPU switches to SP_EL1; Limine never set it, so it
// would be garbage. 32 KiB is enough for the deep fault dump.
__global (
	exception_stack [32768]u8
	// Static line buffer for the fatal report. The report must not allocate:
	// a fault inside the allocator (or on memory it relies on) would otherwise
	// re-fault while being reported, recursing into silence. That is exactly
	// what happened on the M1 when the PMM bitmap was left unmapped.
	fatal_line     [256]u8
	fatal_line_len = int(0)
)

fn fatal_put_str(s string) {
	for i := 0; i < s.len; i++ {
		if fatal_line_len < 255 {
			fatal_line[fatal_line_len] = s[i]
			fatal_line_len++
		}
	}
}

fn fatal_put_hex(v u64) {
	digits := '0123456789abcdef'
	if v == 0 {
		fatal_put_str('0')
		return
	}
	mut tmp := [16]u8{}
	mut i := 16
	mut x := v
	for x > 0 && i > 0 {
		i--
		tmp[i] = digits[x & 0xf]
		x >>= 4
	}
	for j := i; j < 16; j++ {
		if fatal_line_len < 255 {
			fatal_line[fatal_line_len] = tmp[j]
			fatal_line_len++
		}
	}
}

// Framebuffer-visible fatal report built in a static buffer, no heap.
fn emit_fatal_line(ec u64, esr u64, far u64, gpr_state &cpulocal.GPRState) {
	fatal_line_len = 0
	fatal_put_str('\n*** FATAL EXCEPTION ec=0x')
	fatal_put_hex(ec)
	fatal_put_str(' esr=0x')
	fatal_put_hex(esr)
	fatal_put_str(' far=0x')
	fatal_put_hex(far)
	fatal_put_str(' pc=0x')
	fatal_put_hex(gpr_state.pc)
	fatal_put_str(' lr=0x')
	fatal_put_hex(gpr_state.x30)
	fatal_put_str(' sp=0x')
	fatal_put_hex(gpr_state.sp)
	fatal_put_str(' pstate=0x')
	fatal_put_hex(gpr_state.pstate)
	fatal_put_str(' el=0x')
	fatal_put_hex(cpu.read_currentel())
	fatal_put_str(' ***\n')
	term.print(voidptr(&fatal_line[0]), u64(fatal_line_len))
}

pub fn initialise() {
	irq_dispatch_fn = default_irq_dispatch
	cpu.write_vbar_el1(u64(voidptr(C.exception_vectors)))
	cpu.isb()

	// Give SP_EL1 a real stack so a Current-EL/SP_EL0 fault (anything before the
	// scheduler, which runs at EL1t) reaches the handler instead of faulting
	// again on an uninitialised stack. 16-byte aligned per the ABI.
	mut sp_top := u64(voidptr(&exception_stack[0])) + u64(sizeof(exception_stack))
	sp_top &= ~u64(0xf)
	cpu.set_sp_el1(sp_top)
	cpu.isb()
}

// Called from vectors.S for synchronous exceptions
@[export: 'exception__sync_handler']
pub fn sync_handler(esr u64, far u64, gpr_state &cpulocal.GPRState) {
	ec := (esr >> 26) & 0x3f // Exception Class

	match ec {
		0x01 { // Trapped WFI/WFE from userspace
			// WFI and WFE are architectural hints at EL0. Hypervisors may trap
			// them to EL1, but userspace must be allowed to resume afterwards.
			if gpr_state.pc < higher_half {
				mut state := unsafe { &cpulocal.GPRState(gpr_state) }
				state.pc += 4
				return
			}
			fault_handler(ec, esr, far, gpr_state)
		}
		0x00, 0x07, 0x19, 0x1d { // Undefined or unavailable FP/SVE/SME instruction
			if gpr_state.pc < higher_half {
				if userland.dispatch_sync_signal(gpr_state, u8(userland.sigill)) {
					return
				}
				terminate_faulting_process(ec, esr, far, gpr_state, u8(userland.sigill))
			}
			fault_handler(ec, esr, far, gpr_state)
		}
		0x2c { // Trapped floating-point exception
			if gpr_state.pc < higher_half {
				if userland.dispatch_sync_signal(gpr_state, u8(userland.sigfpe)) {
					return
				}
				terminate_faulting_process(ec, esr, far, gpr_state, u8(userland.sigfpe))
			}
			fault_handler(ec, esr, far, gpr_state)
		}
		0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x3c {
			// Breakpoint, software step, watchpoint and the BRK instruction.
			// BRK is how __builtin_trap() and the CHECK macros of large C++
			// programs abort, so it arrives from ordinary applications rather
			// than only from a debugger.
			if gpr_state.pc < higher_half {
				if userland.dispatch_sync_signal(gpr_state, u8(userland.sigtrap)) {
					return
				}
				terminate_faulting_process(ec, esr, far, gpr_state, u8(userland.sigtrap))
			}
			fault_handler(ec, esr, far, gpr_state)
		}
		0x20, 0x21 { // Instruction Abort from lower/same EL
			mmap.pf_handler(gpr_state) or {
				if gpr_state.pc < higher_half {
					if userland.dispatch_sync_fault(gpr_state, far, esr) {
						return
					}
					terminate_faulting_process(ec, esr, far, gpr_state, u8(userland.sigsegv))
				}
				fault_handler(ec, esr, far, gpr_state)
			}
		}
		0x24, 0x25 { // Data Abort from lower/same EL
			mmap.pf_handler(gpr_state) or {
				if gpr_state.pc < higher_half {
					if userland.dispatch_sync_fault(gpr_state, far, esr) {
						return
					}
					terminate_faulting_process(ec, esr, far, gpr_state, u8(userland.sigsegv))
				}
				fault_handler(ec, esr, far, gpr_state)
			}
		}
		0x15 { // SVC from AArch64 (syscall)
			// Handled separately
		}
		else {
			fault_handler(ec, esr, far, gpr_state)
		}
	}
}

// A fault raised by a userspace instruction that no handler took over ends that
// one process, exactly as it would on Linux. Panicking the machine instead
// would let any crashing application take the system down with it, and a
// multi-process browser crashes a renderer as a matter of course.
@[noreturn]
fn terminate_faulting_process(ec u64, esr u64, far u64, gpr_state &cpulocal.GPRState, signal u8) {
	mut current_thread := proc.current_thread()
	mut name := c'?'
	mut pid := -1
	if unsafe { current_thread != 0 } {
		name = current_thread.process.name.str
		pid = current_thread.process.pid
	}
	// One line, not the full register dump: this is an application fault being
	// reported, not a kernel bug being debugged.
	C.printf(c'\n\e[31mfault\e[m: %s[%d] killed by signal %d (ec=0x%llx esr=0x%llx far=0x%llx pc=0x%llx)\n',
		name, pid, int(signal), ec, esr, far, gpr_state.pc)
	userland.exit_with_fatal_signal(signal)
}

fn dump_reg(name &u8, val u64) {
	uart.puts(name)
	uart.puts(c'=0x')
	uart_put_hex(val)
}

fn fault_handler(ec u64, esr u64, far u64, gpr_state &cpulocal.GPRState) {
	// The full register dump below goes to the UART, which is dead on Apple
	// hardware. Put the essentials on the framebuffer too (the same print path
	// the boot log uses), so a kernel fault is visible on a machine with no
	// serial rather than a silent freeze.
	// A red bar at row 56, drawn without locks or allocation, marks a fault
	// even if the text path below cannot run (lock held, allocator wedged).
	term.early_stage_mark(56)
	emit_fatal_line(ec, esr, far, gpr_state)

	uart.puts(c'FATAL EXCEPTION: ec=0x')
	uart_put_hex(ec)
	uart.puts(c' esr=0x')
	uart_put_hex(esr)
	uart.puts(c' far=0x')
	uart_put_hex(far)
	uart.puts(c' pc=0x')
	uart_put_hex(gpr_state.pc)
	uart.puts(c'\n')
	// Dump ALL registers
	dump_reg(c' x0', gpr_state.x0)
	dump_reg(c'  x1', gpr_state.x1)
	dump_reg(c'  x2', gpr_state.x2)
	dump_reg(c'  x3', gpr_state.x3)
	uart.puts(c'\n')
	dump_reg(c' x4', gpr_state.x4)
	dump_reg(c'  x5', gpr_state.x5)
	dump_reg(c'  x6', gpr_state.x6)
	dump_reg(c'  x7', gpr_state.x7)
	uart.puts(c'\n')
	dump_reg(c' x8', gpr_state.x8)
	dump_reg(c'  x9', gpr_state.x9)
	dump_reg(c'  x10', gpr_state.x10)
	dump_reg(c'  x11', gpr_state.x11)
	uart.puts(c'\n')
	dump_reg(c' x12', gpr_state.x12)
	dump_reg(c'  x13', gpr_state.x13)
	dump_reg(c'  x14', gpr_state.x14)
	dump_reg(c'  x15', gpr_state.x15)
	uart.puts(c'\n')
	dump_reg(c' x16', gpr_state.x16)
	dump_reg(c'  x17', gpr_state.x17)
	dump_reg(c'  x18', gpr_state.x18)
	dump_reg(c'  x19', gpr_state.x19)
	uart.puts(c'\n')
	dump_reg(c' x20', gpr_state.x20)
	dump_reg(c'  x21', gpr_state.x21)
	dump_reg(c'  x22', gpr_state.x22)
	dump_reg(c'  x23', gpr_state.x23)
	uart.puts(c'\n')
	dump_reg(c' x24', gpr_state.x24)
	dump_reg(c'  x25', gpr_state.x25)
	dump_reg(c'  x26', gpr_state.x26)
	dump_reg(c'  x27', gpr_state.x27)
	uart.puts(c'\n')
	dump_reg(c' x28', gpr_state.x28)
	dump_reg(c'  x29', gpr_state.x29)
	dump_reg(c'  x30', gpr_state.x30)
	dump_reg(c'  sp', gpr_state.sp)
	uart.puts(c'\n')

	// Show process info
	{
		mut current_thread := proc.current_thread()
		if unsafe { current_thread != 0 } {
			uart.puts(c'PROCESS: pid=')
			uart.put_dec(u64(current_thread.process.pid))
			uart.puts(c' name=')
			uart.puts(current_thread.process.name.str)
			uart.puts(c'\n')
		}
	}

	// For UDF/uncategorized (ec=0x0) or any userspace crash, dump PTE and memory at PC
	if ec == 0x0 && gpr_state.pc < higher_half {
		mut current_thread := proc.current_thread()
		pc_page := gpr_state.pc & ~u64(0xfff)
		phys := current_thread.process.pagemap.virt2phys(pc_page) or { u64(0) }
		pte_p := current_thread.process.pagemap.virt2pte(pc_page, false) or { unsafe { &u64(0) } }
		mut pte_val := u64(0)
		if pte_p != unsafe { &u64(0) } {
			pte_val = unsafe { *pte_p }
		}
		uart.puts(c'PC PAGE: virt=0x')
		uart_put_hex(pc_page)
		uart.puts(c' phys=0x')
		uart_put_hex(phys)
		uart.puts(c' pte=0x')
		uart_put_hex(pte_val)
		uart.puts(c'\n')

		// Dump 32 bytes of instructions at PC (read via HHDM)
		if phys != 0 {
			pc_offset := gpr_state.pc & u64(0xfff)
			kernel_addr := phys + higher_half + pc_offset
			uart.puts(c'INSN AT PC (via HHDM):\n')
			for ioff := u64(0); ioff < 32; ioff += 4 {
				uart.puts(c'  0x')
				uart_put_hex(gpr_state.pc + ioff)
				uart.puts(c': 0x')
				word := unsafe { *&u32(kernel_addr + ioff) }
				uart_put_hex(u64(word))
				uart.puts(c'\n')
			}
		}

		// Dump mmap ranges covering PC
		uart.puts(c'MMAP RANGES covering PC:\n')
		for ri := u64(0); ri < current_thread.process.pagemap.mmap_ranges.len; ri++ {
			r := unsafe { &mmap.MmapRangeLocal(current_thread.process.pagemap.mmap_ranges[ri]) }
			if gpr_state.pc >= r.base && gpr_state.pc < r.base + r.length {
				uart.puts(c'  base=0x')
				uart_put_hex(r.base)
				uart.puts(c' len=0x')
				uart_put_hex(r.length)
				uart.puts(c' prot=')
				uart.put_dec(u64(u32(r.prot)))
				uart.puts(c' flags=0x')
				uart_put_hex(u64(u32(r.flags)))
				uart.puts(c'\n')
			}
		}

		// Dump user stack: 64 bytes below SP and 128 bytes above SP
		// The recently-popped frame (from ldp x29,x30,[sp],#N) is below sp
		sp_val := gpr_state.sp
		dump_start := if sp_val >= 64 { sp_val - 64 } else { u64(0) }
		uart.puts(c'USER STACK around SP=0x')
		uart_put_hex(sp_val)
		uart.puts(c':\n')
		for si := dump_start; si < sp_val + 128; si += 8 {
			si_page := si & ~u64(0xfff)
			si_phys := current_thread.process.pagemap.virt2phys(si_page) or { continue }
			si_offset := si & u64(0xfff)
			if si_offset + 8 > page_size {
				continue
			}
			si_kernel := si_phys + higher_half + si_offset
			val := unsafe { *&u64(si_kernel) }
			if si == sp_val {
				uart.puts(c'  [SP   ] 0x')
			} else if si < sp_val {
				uart.puts(c'  [sp-0x')
				uart_put_hex(sp_val - si)
				uart.puts(c'] 0x')
			} else {
				uart.puts(c'  [sp+0x')
				uart_put_hex(si - sp_val)
				uart.puts(c'] 0x')
			}
			uart_put_hex(si)
			uart.puts(c' = 0x')
			uart_put_hex(val)
			if val == u64(0x220000) {
				uart.puts(c' *** 0x220000 ***')
			}
			uart.puts(c'\n')
		}
	}

	// Dump PTE info for instruction abort or user data abort
	if ec == 0x20 || ec == 0x24 {
		mut current_thread := proc.current_thread()
		page_addr := far & ~u64(0xfff)
		phys := current_thread.process.pagemap.virt2phys(page_addr) or { u64(0) }
		pte_p := current_thread.process.pagemap.virt2pte(page_addr, false) or { unsafe { &u64(0) } }
		mut pte_val := u64(0)
		if pte_p != unsafe { &u64(0) } {
			pte_val = unsafe { *pte_p }
		}
		uart.puts(c'PTE DUMP: page=0x')
		uart_put_hex(page_addr)
		uart.puts(c' phys=0x')
		uart_put_hex(phys)
		uart.puts(c' pte=0x')
		uart_put_hex(pte_val)
		uart.puts(c'\n')
		// Also dump the ELF loader mmap ranges covering this address
		uart.puts(c'MMAP RANGES covering FAR:\n')
		for ri := u64(0); ri < current_thread.process.pagemap.mmap_ranges.len; ri++ {
			r := unsafe { &mmap.MmapRangeLocal(current_thread.process.pagemap.mmap_ranges[ri]) }
			if far >= r.base && far < r.base + r.length {
				uart.puts(c'  base=0x')
				uart_put_hex(r.base)
				uart.puts(c' len=0x')
				uart_put_hex(r.length)
				uart.puts(c' prot=')
				uart.put_dec(u64(u32(r.prot)))
				uart.puts(c' flags=0x')
				uart_put_hex(u64(u32(r.flags)))
				uart.puts(c'\n')
			}
		}
	}

	// For musl a_crash (data abort at NULL from aligned_alloc)
	if ec == 0x24 && gpr_state.pc == 0x40028d80 {
		chunk := gpr_state.x1
		if chunk != 0 {
			// Dump 256 bytes around chunk
			uart.puts(c'\n=== CHUNK MEMORY at 0x')
			uart_put_hex(chunk)
			uart.puts(c' ===\n')
			dump_base := (chunk - 64) & ~u64(7)
			for off := u64(0); off < 256; off += 8 {
				addr := dump_base + off
				uart.puts(c'  ')
				uart_put_hex(addr)
				uart.puts(c': ')
				uart_put_hex(unsafe { *&u64(addr) })
				uart.puts(c'\n')
			}

			// Check for physical page aliasing: walk TTBR0 page table to find
			// ALL virtual addresses mapped to the same physical page as chunk
			mut current_thread := proc.current_thread()
			chunk_phys := current_thread.process.pagemap.virt2phys(chunk & ~u64(0xfff)) or {
				uart.puts(c'  Chunk page not mapped!\n')
				u64(0)
			}
			if chunk_phys != 0 {
				uart.puts(c'\n=== PHYS PAGE ALIASING CHECK for phys=0x')
				uart_put_hex(chunk_phys)
				uart.puts(c' ===\n')
				hh := higher_half
				pt_top := current_thread.process.pagemap.top_level
				mut alias_count := 0
				for l0i := u64(0); l0i < 512; l0i++ {
					l0e := unsafe { *&u64(u64(pt_top) + hh + l0i * 8) }
					if l0e & 1 == 0 {
						continue
					}
					l1_base := l0e & memory.pte_flags_mask
					for l1i := u64(0); l1i < 512; l1i++ {
						l1e := unsafe { *&u64(l1_base + hh + l1i * 8) }
						if l1e & 1 == 0 {
							continue
						}
						l2_base := l1e & memory.pte_flags_mask
						for l2i := u64(0); l2i < 512; l2i++ {
							l2e := unsafe { *&u64(l2_base + hh + l2i * 8) }
							if l2e & 1 == 0 {
								continue
							}
							l3_base := l2e & memory.pte_flags_mask
							for l3i := u64(0); l3i < 512; l3i++ {
								l3e := unsafe { *&u64(l3_base + hh + l3i * 8) }
								if l3e & 1 == 0 {
									continue
								}
								phys := l3e & memory.pte_flags_mask
								if phys == chunk_phys {
									virt := (l0i << 39) | (l1i << 30) | (l2i << 21) | (l3i << 12)
									uart.puts(c'  VIRT=0x')
									uart_put_hex(virt)
									uart.puts(c' PTE=0x')
									uart_put_hex(l3e)
									if virt == (chunk & ~u64(0xfff)) {
										uart.puts(c' (expected)')
									} else {
										uart.puts(c' *** ALIAS! ***')
									}
									uart.puts(c'\n')
									alias_count++
								}
							}
						}
					}
				}
				if alias_count <= 1 {
					uart.puts(c'  No aliasing found (page mapped once)\n')
				} else {
					uart.puts(c'  WARNING: page mapped ')
					uart.put_dec(u64(alias_count))
					uart.puts(c' times!\n')
				}
			}

			// Dump mmap ranges containing this address
			uart.puts(c'\n=== MMAP RANGES for chunk ===\n')
			for ri := u64(0); ri < current_thread.process.pagemap.mmap_ranges.len; ri++ {
				r := unsafe { &mmap.MmapRangeLocal(current_thread.process.pagemap.mmap_ranges[ri]) }
				if chunk >= r.base && chunk < r.base + r.length {
					uart.puts(c'  base=0x')
					uart_put_hex(r.base)
					uart.puts(c' len=0x')
					uart_put_hex(r.length)
					uart.puts(c' prot=')
					uart.put_dec(u64(r.prot))
					uart.puts(c' flags=0x')
					uart_put_hex(u64(r.flags))
					uart.puts(c'\n')
				}
			}
		}
	}
	// Dump syscall ring buffer on any crash
	C.sc_dump_ring()
	// For user-space faults (lower EL), kill the process instead of hanging.
	// Check if PC is in user-space (below higher_half) — covers EC=0x00 (UDF/abort),
	// EC=0x20 (instruction abort from lower EL), EC=0x24 (data abort from lower EL), etc.
	if gpr_state.pc < higher_half && segfault_kill_fn != unsafe { nil } {
		mut signum := 139 // 128 + 11 (SIGSEGV) — default
		if ec == 0x0 {
			signum = 134 // 128 + 6 (SIGABRT)
		}
		uart.puts(c'Killing user process (sig=')
		uart.put_dec(u64(signum))
		uart.puts(c')\n')
		segfault_kill_fn(voidptr(gpr_state), signum)
		return
	}
	for {}
}

fn uart_put_hex(val u64) {
	hex := c'0123456789abcdef'
	mut buf := [17]u8{}
	mut i := 16
	buf[i] = 0
	mut v := val
	if v == 0 {
		uart.putc(u8(`0`))
		return
	}
	for v > 0 && i > 0 {
		i--
		buf[i] = u8(unsafe { hex[v & 0xf] })
		v >>= 4
	}
	for i < 16 {
		uart.putc(buf[i])
		i++
	}
}

// Called from vectors.S for IRQ exceptions
@[export: 'exception__irq_handler']
pub fn irq_handler(gpr_state &cpulocal.GPRState) {
	irq_dispatch(gpr_state)
}

__global (
	irq_dispatch_fn fn (voidptr)
	segfault_kill_fn fn (voidptr, int)
)

fn default_irq_dispatch(_ voidptr) {
	C.printf(c'IRQ received but no dispatch handler registered\n')
}

pub fn irq_dispatch(gpr_state &cpulocal.GPRState) {
	irq_dispatch_fn(voidptr(gpr_state))
}

pub fn register_irq_dispatch(handler fn (voidptr)) {
	irq_dispatch_fn = handler
}

pub fn register_segfault_handler(handler fn (voidptr, int)) {
	segfault_kill_fn = handler
}
