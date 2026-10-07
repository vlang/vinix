// SPDX-License-Identifier: MIT
@[translated; has_globals]
module vbridge

#define VINIX_V_RUNTIME 1
#include <native-abi.h>

struct C.FILE {}
@[typedef]
struct C.ps2_const_byte {}
@[typedef]
struct C.ps2_const_char {}
struct C.ee_state {}
struct C.ee_bus {}
struct C.iop_bus {}
struct C.ps2_ipu {}
struct C.ps2_ee_timers {}
struct C.ps2_iop_timers {}
struct C.sched_state {}
struct C.ps2_ram { mut: buf &u8 }
struct C.iop_state { mut: pc u32 next_pc u32 cop0_r [16]u32 }
struct C.ps2_state {
mut:
	ee &C.ee_state
	iop &C.iop_state
	ee_bus &C.ee_bus
	iop_bus &C.iop_bus
	ipu &C.ps2_ipu
	ee_ram &C.ps2_ram
	iop_ram &C.ps2_ram
	ee_timers &C.ps2_ee_timers
	iop_timers &C.ps2_iop_timers
	sched &C.sched_state
	ee_cycles i32
	timescale i32
}
@[typedef]
struct C.Elf32_Ehdr {
mut:
	e_ident [16]u8
	e_type u16
	e_machine u16
	e_entry u32
	e_phoff u32
	e_phentsize u16
	e_phnum u16
}
@[typedef]
struct C.Elf32_Phdr {
mut:
	p_type u32
	p_offset u32
	p_vaddr u32
	p_filesz u32
	p_memsz u32
	p_flags u32
}
@[typedef]
struct C.ps2_const_elfheader { e_entry u32 e_phoff u32 e_phnum u16 }
struct C.ps2_runtime_construction { mut: storage voidptr message &C.ps2_const_char }

@[c_extern] __global C.vinix_ps2_runtime_type [1]u8
fn C.vinix_ps2_allocate_exception(usize) voidptr
fn C.vinix_ps2_free_exception(voidptr)
fn C.vinix_ps2_throw_exception(voidptr, voidptr, fn (voidptr))
fn C.vinix_ps2_runtime_ctor(voidptr, &C.ps2_const_char)
fn C.vinix_ps2_runtime_dtor(voidptr)
fn C.vinix_ps2_unwind_scope(voidptr, fn (voidptr) i32, fn (voidptr)) i32
fn C.fseek(&C.FILE, i64, i32) i32
fn C.ftell(&C.FILE) i64
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.ee_run_block(&C.ee_state, i32) i32
fn C.ee_get_pc(&C.ee_state) u32
fn C.ee_bus_init_fastmem(&C.ee_bus)
fn C.iop_bus_init_fastmem(&C.iop_bus)
fn C.sched_tick(&C.sched_state, i32) i32
fn C.ps2_ipu_run(&C.ps2_ipu)
fn C.ps2_ee_timers_tick(&C.ps2_ee_timers)
fn C.iop_cycle(&C.iop_state)
fn C.ps2_iop_timers_tick(&C.ps2_iop_timers)

fn runtime_construct(context voidptr) i32 {
	unsafe {
		mut construction := &C.ps2_runtime_construction(context)
		C.vinix_ps2_runtime_ctor(construction.storage, construction.message)
		construction.storage = nil
		return 0
	}
}

fn runtime_cleanup(context voidptr) {
	unsafe {
		mut construction := &C.ps2_runtime_construction(context)
		if construction.storage != nil {
			C.vinix_ps2_free_exception(construction.storage)
			construction.storage = nil
		}
	}
}

// The caller's stack record survives a constructor throw. The native envelope
// releases only unpublished exception storage and resumes the original unwind.
fn runtime_error(message &C.ps2_const_char) {
	unsafe {
		object := C.vinix_ps2_allocate_exception(C.VINIX_PS2_RUNTIME_ERROR_SIZE)
		mut construction := C.ps2_runtime_construction{storage: object, message: message}
		C.vinix_ps2_unwind_scope(&construction, runtime_construct, runtime_cleanup)
		C.vinix_ps2_throw_exception(object, voidptr(&C.vinix_ps2_runtime_type[0]), C.vinix_ps2_runtime_dtor)
	}
}

@[export: 'vinix_ps2_file_size']
pub fn file_size(file &C.FILE, size &usize) i32 {
	if C.fseek(file, 0, C.SEEK_END) != 0 { return 0 }
	end := C.ftell(file)
	if end < 0 || C.fseek(file, 0, C.SEEK_SET) != 0 { return 0 }
	unsafe { *size = usize(end) }
	return 1
}

@[export: 'vinix_ps2_check_elf']
pub fn check_elf(bytes &C.ps2_const_byte, size usize, header &C.Elf32_Ehdr) {
	unsafe {
		if size < sizeof(C.Elf32_Ehdr) { runtime_error(&C.ps2_const_char(c'Truncated PS2 ELF header')); return }
		C.memcpy(header, bytes, sizeof(C.Elf32_Ehdr))
		magic := [u8(0x7f), u8(0x45), u8(0x4c), u8(0x46)]!
		if C.memcmp(&header.e_ident[0], &magic[0], 4) != 0 || header.e_ident[4] != 1
			|| header.e_ident[5] != 1 || header.e_machine != 8 || header.e_type != 2
			|| header.e_phentsize != sizeof(C.Elf32_Phdr) || header.e_phnum == 0
			|| header.e_phnum > 128 || header.e_phoff > size
			|| usize(header.e_phnum) * sizeof(C.Elf32_Phdr) > size - header.e_phoff
			|| (header.e_entry & 3) != 0 || (header.e_entry & 0x1fffffff) >= C.RAM_SIZE_32MB {
			runtime_error(&C.ps2_const_char(c'Expected a little-endian executable PS2 MIPS ELF')); return
		}
		mut entry_loaded := false
		for i := u32(0); i < header.e_phnum; i++ {
			mut segment := C.Elf32_Phdr{}
			C.memcpy(&segment, &u8(bytes) + header.e_phoff + usize(i) * sizeof(C.Elf32_Phdr), sizeof(C.Elf32_Phdr))
			if segment.p_type != C.PT_LOAD { continue }
			address := segment.p_vaddr & 0x1fffffff
			if address >= C.RAM_SIZE_32MB || segment.p_memsz > C.RAM_SIZE_32MB - address
				|| segment.p_filesz > segment.p_memsz || segment.p_offset > size
				|| segment.p_filesz > size - segment.p_offset {
				runtime_error(&C.ps2_const_char(c'PS2 ELF segment is outside RAM or the file')); return
			}
			entry := header.e_entry & 0x1fffffff
			if (segment.p_flags & 1) != 0 && entry >= address && entry - address < segment.p_memsz { entry_loaded = true }
		}
		if !entry_loaded { runtime_error(&C.ps2_const_char(c'PS2 ELF entry is outside its executable segments')) }
	}
}

@[export: 'vinix_ps2_load_baremetal']
pub fn load_baremetal(ps2 &C.ps2_state, bytes &C.ps2_const_byte, header &C.ps2_const_elfheader) {
	unsafe {
		for i := u32(0); i < header.e_phnum; i++ {
			mut segment := C.Elf32_Phdr{}
			C.memcpy(&segment, &u8(bytes) + header.e_phoff + usize(i) * sizeof(C.Elf32_Phdr), sizeof(C.Elf32_Phdr))
			if segment.p_type != C.PT_LOAD { continue }
			dest := ps2.ee_ram.buf + (segment.p_vaddr & 0x1fffffff)
			C.memset(dest, 0, segment.p_memsz)
			C.memcpy(dest, &u8(bytes) + segment.p_offset, segment.p_filesz)
		}
		mut entry := header.e_entry
		mut next_pc := header.e_entry + 4
		mut status := u32(0x70000000)
		mut stack := u64(0x01fff000)
		C.memcpy(&u8(ps2.ee) + C.VINIX_PS2_EE_PC, &entry, sizeof(u32))
		C.memcpy(&u8(ps2.ee) + C.VINIX_PS2_EE_NEXT_PC, &next_pc, sizeof(u32))
		C.memcpy(&u8(ps2.ee) + C.VINIX_PS2_EE_STATUS, &status, sizeof(u32))
		C.memcpy(&u8(ps2.ee) + C.VINIX_PS2_EE_R29, &stack, sizeof(u64))
		idle := [u32(0x08000000), u32(0)]!
		C.memcpy(ps2.iop_ram.buf, &idle[0], sizeof(idle))
		ps2.iop.pc = 0
		ps2.iop.next_pc = 4
		ps2.iop.cop0_r[C.COP0_SR] = 0
		C.ee_bus_init_fastmem(ps2.ee_bus)
		C.iop_bus_init_fastmem(ps2.iop_bus)
	}
}

@[export: 'vinix_ps2_tick']
pub fn tick(ps2 &C.ps2_state) {
	unsafe {
		mut cycles := C.ee_run_block(ps2.ee, 128)
		if cycles == 0 { cycles = C.ee_run_block(ps2.ee, 128) }
		if cycles == 0 { return }
		if cycles < 0 || cycles > 4096 { runtime_error(&C.ps2_const_char(c'Invalid PS2 CPU cycle count')); return }
		ps2.ee_cycles += cycles
		C.sched_tick(ps2.sched, ps2.timescale * cycles)
		C.ps2_ipu_run(ps2.ipu)
		for i := i32(0); i < cycles; i++ { C.ps2_ee_timers_tick(ps2.ee_timers) }
		for ps2.ee_cycles > 8 {
			C.iop_cycle(ps2.iop)
			C.ps2_iop_timers_tick(ps2.iop_timers)
			ps2.ee_cycles -= 8
		}
	}
}

@[export: 'vinix_ps2_boot_bios']
pub fn boot_bios(ps2 &C.ps2_state, path &C.ps2_const_char, size usize) {
	unsafe {
		mut reached := false
		for i := u32(0); i < 10000000; i++ {
			if C.ee_get_pc(ps2.ee) == 0x00082000 { reached = true; break }
			tick(ps2)
		}
		if !reached { runtime_error(&C.ps2_const_char(c'PS2 BIOS did not reach its boot entry within the cycle limit')); return }
		if size >= 256 { runtime_error(&C.ps2_const_char(c'PS2 boot path is too long')); return }
		mut patched := false
		for i := u32(0); i + 256 <= C.RAM_SIZE_32MB; i += 16 {
			dest := ps2.ee_ram.buf + i
			if C.memcmp(dest, c'rom0:OSDSYS', 12) == 0 {
				C.memcpy(dest, path, size + 1)
				patched = true
			}
		}
		if !patched { runtime_error(&C.ps2_const_char(c'PS2 BIOS boot path was not found')) }
	}
}
