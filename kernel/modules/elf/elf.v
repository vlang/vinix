module elf

import lib
import memory
import memory.mmap
import resource

pub struct Auxval {
pub mut:
	at_entry u64
	at_phdr  u64
	at_phent u64
	at_phnum u64
	at_base  u64
}

pub const et_dyn = 0x03

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
pub const at_secure = 23
pub const at_random = 25

pub const pt_load = 0x00000001
pub const pt_interp = 0x00000003
pub const pt_phdr = 0x00000006

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

pub fn load(_pagemap &memory.Pagemap, _res &resource.Resource, _base u64) !(Auxval, string) {
	mut res := unsafe { _res }
	mut pagemap := unsafe { _pagemap }
	mut base := _base

	mut header := &Header{}

	res.read(0, header, 0, sizeof(Header)) or { return error('') }

	if unsafe { C.memcmp(&header.ident, c'\177ELF', 4) } != 0 {
		return error('elf: Invalid magic')
	}

	if header.ident[ei_class] != 0x02 || header.ident[ei_data] != bits_le
		|| header.ident[ei_osabi] != abi_sysv
		|| (header.machine != arch_x86_64 && header.machine != arch_aarch64) {
		return error('elf: Unsupported ELF file')
	}

	// PIE/ET_DYN binaries have p_vaddr starting at 0. Loading at base=0
	// would map code at virtual address 0, breaking null pointer checks
	// in ld-musl and userspace. Apply a non-zero base for PIE binaries
	// when no explicit base is given (base=0 means "auto" for ET_DYN).
	if base == 0 && header.@type == u16(et_dyn) {
		base = 0x200000
	}

	mut auxval := Auxval{
		at_entry: base + header.entry
		at_phdr:  0
		at_phent: sizeof(ProgramHdr)
		at_phnum: header.ph_num
		at_base:  if base != 0 { base } else { u64(0) }
	}

	mut ld_path := ''
	mut load_addr := u64(0)
	mut load_addr_set := false

	for i := u64(0); i < header.ph_num; i++ {
		mut phdr := &ProgramHdr{}

		res.read(0, phdr, header.phoff + (sizeof(ProgramHdr) * i), sizeof(ProgramHdr)) or {
			return error('')
		}

		match phdr.p_type {
			pt_interp {
				mut p := unsafe { malloc(phdr.p_filesz + 1) }
				res.read(0, p, phdr.p_offset, phdr.p_filesz) or { return error('') }
				ld_path = unsafe { cstring_to_vstring(p) }
				unsafe { free(p) }
			}
			pt_phdr {
				auxval.at_phdr = base + phdr.p_vaddr
			}
			else {}
		}

		if phdr.p_type != pt_load {
			continue
		}

		// Track the first LOAD segment's effective base address
		// (vaddr - file_offset), matching Linux's load_addr computation.
		// Needed for AT_PHDR fallback when no PT_PHDR segment exists.
		if !load_addr_set {
			load_addr = base + phdr.p_vaddr - phdr.p_offset
			load_addr_set = true
		}

		misalign := phdr.p_vaddr & (page_size - 1)
		page_count := lib.div_roundup(misalign + phdr.p_memsz, page_size)

		addr := memory.pmm_alloc(page_count)
		if addr == 0 {
			return error('elf: Allocation failure')
		}

		pf := mmap.prot_read | mmap.prot_exec | if phdr.p_flags & pf_w != 0 {
			mmap.prot_write
		} else {
			0
		}

		virt := lib.align_down(base + phdr.p_vaddr, page_size)
		phys := u64(addr)

		mmap.map_range(mut pagemap, virt, phys, page_count * page_size, pf, mmap.map_anonymous) or {
			return error('')
		}

		buf := unsafe { byteptr(addr) + misalign + higher_half }

		res.read(0, buf, phdr.p_offset, phdr.p_filesz) or { return error('') }
	}

	// If no PT_PHDR segment was found, compute AT_PHDR from the first
	// LOAD segment's base (like Linux's binfmt_elf.c). This works for both
	// PIE (vaddr 0) and EXEC (vaddr 0x400000+) binaries.
	if auxval.at_phdr == 0 {
		auxval.at_phdr = load_addr + header.phoff
	}

	return auxval, ld_path
}
