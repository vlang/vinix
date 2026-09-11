module elf

import lib
import memory
import memory.mmap
import resource
import krandom

pub struct Auxval {
pub mut:
	at_entry u64
	at_phdr  u64
	at_phent u64
	at_phnum u64
	at_base  u64
}

pub const et_dyn = 0x03
pub const et_exec = 0x02

pub const at_entry = 9
pub const at_phdr = 3
pub const at_phent = 4
pub const at_phnum = 5
pub const at_pagesz = 6
pub const at_uid = 11
pub const at_euid = 12
pub const at_gid = 13
pub const at_egid = 14
pub const at_base = 7
pub const at_hwcap = 16
pub const at_secure = 23
pub const at_random = 25
pub const at_hwcap2 = 26

pub const pt_load = 0x00000001
pub const pt_interp = 0x00000003
pub const pt_phdr = 0x00000006

const pie_base = u64(0x00200000)
const interpreter_base = u64(0x40000000)
const image_aslr_span = u64(0x40000000)
const image_alignment = u64(0x200000)
const stack_base = u64(0x70000000000)
const mmap_base = u64(0x80000000000)
const arena_aslr_span = u64(0x10000000)

fn random_offset(span u64, alignment u64) u64 {
	mut value := u64(0)
	if span <= alignment || !krandom.fill(&value, sizeof(value), false) {
		return 0
	}
	slots := span / alignment
	return (value % slots) * alignment
}

pub fn interpreter_load_base() u64 {
	return interpreter_base + random_offset(image_aslr_span, image_alignment)
}

pub fn initial_stack_top() u64 {
	return stack_base - random_offset(arena_aslr_span, page_size)
}

pub fn initial_mmap_base() u64 {
	return mmap_base + random_offset(arena_aslr_span, page_size)
}

pub const abi_sysv = 0x00
pub const arch_x86_64 = 0x3e
pub const arch_aarch64 = 0xb7
pub const bits_le = 0x01

pub const ei_class = 4
pub const ei_data = 5
pub const ei_version = 6
pub const ei_osabi = 7

pub struct Header {
pub mut:
	ident     [16]u8
	@type     u16
	machine   u16
	version   u32
	entry     u64
	phoff     u64
	shoff     u64
	flags     u32
	hdr_size  u16
	phdr_size u16
	ph_num    u16
	shdr_size u16
	sh_num    u16
	shstrndx  u16
}

pub const pf_x = 1
pub const pf_w = 2
pub const pf_r = 4

pub struct ProgramHdr {
pub mut:
	p_type   u32
	p_flags  u32
	p_offset u64
	p_vaddr  u64
	p_paddr  u64
	p_filesz u64
	p_memsz  u64
	p_align  u64
}

pub struct SectionHdr {
pub mut:
	sh_name       u32
	sh_type       u32
	sh_flags      u64
	sh_addr       u64
	sh_offset     u64
	sh_size       u64
	sh_link       u32
	sh_info       u32
	sh_addr_align u64
	sh_entsize    u64
}

struct LoadedRange {
	base   u64
	length u64
}

fn read_exact(mut res resource.Resource, buf voidptr, offset u64, length u64) ! {
	read := res.read(unsafe { nil }, buf, offset, length) or {
		return error('elf: read failure')
	}
	if read != i64(length) {
		return error('elf: truncated file')
	}
}

// architecture reports the ELF machine without mapping any part of the file.
// The ARM64 exec path uses this to hand x86-64 programs to the userspace
// translator instead of jumping directly into foreign instructions.
pub fn architecture(_res &resource.Resource) !u16 {
	mut res := unsafe { _res }
	mut header := &Header{}

	read_exact(mut res, header, 0, sizeof(Header))!
	if unsafe { C.memcmp(&header.ident, c'\177ELF', 4) } != 0 {
		return error('elf: Invalid magic')
	}
	if header.ident[ei_class] != 0x02 || header.ident[ei_data] != bits_le
		|| header.ident[ei_osabi] != abi_sysv {
		return error('elf: Unsupported ELF file')
	}

	return header.machine
}

pub fn load(_pagemap &memory.Pagemap, _res &resource.Resource, _base u64) !(Auxval, string) {
	mut res := unsafe { _res }
	mut pagemap := unsafe { _pagemap }
	mut base := _base

	mut header := &Header{}

	read_exact(mut res, header, 0, sizeof(Header))!

	if unsafe { C.memcmp(&header.ident, c'\177ELF', 4) } != 0 {
		return error('elf: Invalid magic')
	}

	if header.ident[ei_class] != 0x02 || header.ident[ei_data] != bits_le
		|| header.ident[ei_osabi] != abi_sysv
		|| (header.machine != arch_x86_64 && header.machine != arch_aarch64)
		|| (header.@type != et_exec && header.@type != et_dyn)
		|| header.phdr_size != sizeof(ProgramHdr) {
		return error('elf: Unsupported ELF file')
	}
	program_header_bytes := u64(header.ph_num) * sizeof(ProgramHdr)
	if header.phoff > u64(res.stat.size)
		|| program_header_bytes > u64(res.stat.size) - header.phoff {
		return error('elf: truncated program header table')
	}

	// PIE/ET_DYN binaries have p_vaddr starting at 0. Loading at base=0
	// would map code at virtual address 0, breaking null pointer checks
	// in ld-musl and userspace. Apply a non-zero base for PIE binaries
	// when no explicit base is given (base=0 means "auto" for ET_DYN).
	if base == 0 && header.@type == u16(et_dyn) {
		base = pie_base + random_offset(image_aslr_span - pie_base, image_alignment)
	}
	if header.entry > u64(-1) - base {
		return error('elf: entry address overflow')
	}

	mut auxval := Auxval{
		at_entry: base + header.entry
		at_phdr: 0
		at_phent: sizeof(ProgramHdr)
		at_phnum: header.ph_num
		at_base: if base != 0 { base } else { u64(0) }
	}

	mut ld_path := ''
	mut load_addr := u64(0)
	mut load_addr_set := false
	mut loaded_ranges := []LoadedRange{}
	mut committed := false
	defer {
		if !committed {
			for i := loaded_ranges.len; i > 0; i-- {
				range := loaded_ranges[i - 1]
				mmap.munmap(mut pagemap, voidptr(range.base), range.length) or {}
			}
			if ld_path != '' {
				unsafe { ld_path.free() }
			}
		}
		unsafe { loaded_ranges.free() }
	}

	for i := u64(0); i < header.ph_num; i++ {
		mut phdr := &ProgramHdr{}

		read_exact(mut res, phdr, header.phoff + (sizeof(ProgramHdr) * i), sizeof(ProgramHdr))!

		match phdr.p_type {
			pt_interp {
				if ld_path != '' {
					return error('elf: multiple interpreters')
				}
				if phdr.p_filesz == 0 || phdr.p_filesz > 4096
					|| phdr.p_offset > u64(res.stat.size)
					|| phdr.p_filesz > u64(res.stat.size) - phdr.p_offset {
					return error('elf: invalid interpreter path')
				}
				mut p := unsafe { malloc(phdr.p_filesz + 1) }
				if p == unsafe { nil } {
					return error('elf: allocation failure')
				}
				read_exact(mut res, p, phdr.p_offset, phdr.p_filesz) or {
					unsafe { free(p) }
					return error('elf: invalid interpreter path')
				}
				unsafe { (&u8(p))[phdr.p_filesz] = 0 }
				ld_path = unsafe { cstring_to_vstring(p) }
				unsafe { free(p) }
			}
			pt_phdr {
				if phdr.p_vaddr > u64(-1) - base {
					return error('elf: PHDR address overflow')
				}
				auxval.at_phdr = base + phdr.p_vaddr
			}
			else {}
		}

		if phdr.p_type != pt_load {
			continue
		}
		if phdr.p_filesz > phdr.p_memsz {
			return error('elf: LOAD segment filesz exceeds memsz')
		}
		if phdr.p_offset > u64(res.stat.size)
			|| phdr.p_filesz > u64(res.stat.size) - phdr.p_offset {
			return error('elf: LOAD segment exceeds file')
		}
		if phdr.p_memsz == 0 {
			continue
		}
		if phdr.p_vaddr > u64(-1) - base || base + phdr.p_vaddr < phdr.p_offset {
			return error('elf: LOAD address overflow')
		}

		// Track the first LOAD segment's effective base address
		// (vaddr - file_offset), matching Linux's load_addr computation.
		// Needed for AT_PHDR fallback when no PT_PHDR segment exists.
		if !load_addr_set {
			load_addr = base + phdr.p_vaddr - phdr.p_offset
			load_addr_set = true
		}

		if phdr.p_vaddr & (page_size - 1) != phdr.p_offset & (page_size - 1) {
			return error('elf: incongruent LOAD segment')
		}
		segment_address := base + phdr.p_vaddr
		misalign := segment_address & (page_size - 1)
		if phdr.p_memsz > u64(-1) - misalign {
			return error('elf: LOAD size overflow')
		}
		mapping_length := lib.align_up(misalign + phdr.p_memsz, page_size)
		if mapping_length < misalign + phdr.p_memsz {
			return error('elf: LOAD size overflow')
		}

		mut pf := 0
		if phdr.p_flags & pf_r != 0 {
			pf |= mmap.prot_read
		}
		if phdr.p_flags & pf_w != 0 {
			pf |= mmap.prot_write
		}
		if phdr.p_flags & pf_x != 0 {
			pf |= mmap.prot_exec
		}

		virt := lib.align_down(segment_address, page_size)
		file_offset := i64(lib.align_down(phdr.p_offset, page_size))
		file_backed_length := misalign + phdr.p_filesz
		mmap.mmap_file_segment(pagemap, virt, mapping_length, pf, res, file_offset, 0, file_backed_length) or { return error('elf: unable to map LOAD segment') }
		loaded_ranges << LoadedRange{
			base: virt
			length: mapping_length
		}
	}

	// If no PT_PHDR segment was found, compute AT_PHDR from the first
	// LOAD segment's base (like Linux's binfmt_elf.c). This works for both
	// PIE (vaddr 0) and EXEC (vaddr 0x400000+) binaries.
	if !load_addr_set {
		return error('elf: no loadable segments')
	}
	if auxval.at_phdr == 0 {
		if header.phoff > u64(-1) - load_addr {
			return error('elf: PHDR address overflow')
		}
		auxval.at_phdr = load_addr + header.phoff
	}

	committed = true
	return auxval, ld_path
}
