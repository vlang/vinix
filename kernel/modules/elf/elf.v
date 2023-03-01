// elf.v: ELF loader.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

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
}

pub const (
	at_entry    = 9
	at_phdr     = 3
	at_phent    = 4
	at_phnum    = 5

	pt_load     = 0x00000001
	pt_interp   = 0x00000003
	pt_phdr     = 0x00000006

	abi_sysv    = 0x00
	arch_x86_64 = 0x3e
	bits_le     = 0x01

	ei_class    = 4
	ei_data     = 5
	ei_version  = 6
	ei_osabi    = 7
)

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

pub const (
	pf_x = 1
	pf_w = 2
	pf_r = 4
)

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

pub fn load(_pagemap &memory.Pagemap, _res &resource.Resource, base u64) !(Auxval, string) {
	mut res := unsafe { _res }
	mut pagemap := unsafe { _pagemap }

	mut header := &Header{}

	res.read(0, header, 0, sizeof(Header)) or { return error('') }

	if unsafe { C.memcmp(&header.ident, c'\177ELF', 4) } != 0 {
		return error('elf: Invalid magic')
	}

	if header.ident[elf.ei_class] != 0x02 || header.ident[elf.ei_data] != elf.bits_le
		|| header.ident[elf.ei_osabi] != elf.abi_sysv || header.machine != elf.arch_x86_64 {
		return error('elf: Unsupported ELF file')
	}

	mut auxval := Auxval{
		at_entry: base + header.entry
		at_phdr: 0
		at_phent: sizeof(ProgramHdr)
		at_phnum: header.ph_num
	}

	mut ld_path := ''

	for i := u64(0); i < header.ph_num; i++ {
		mut phdr := &ProgramHdr{}

		res.read(0, phdr, header.phoff + (sizeof(ProgramHdr) * i), sizeof(ProgramHdr)) or { return error('') }

		match phdr.p_type {
			elf.pt_interp {
				mut p := memory.malloc(phdr.p_filesz + 1)
				res.read(0, p, phdr.p_offset, phdr.p_filesz) or { return error('') }
				ld_path = unsafe { cstring_to_vstring(p) }
			}
			elf.pt_phdr {
				auxval.at_phdr = base + phdr.p_vaddr
			}
			else {}
		}

		if phdr.p_type != elf.pt_load {
			continue
		}

		misalign := phdr.p_vaddr & (page_size - 1)
		page_count := lib.div_roundup(misalign + phdr.p_memsz, page_size)

		addr := memory.pmm_alloc(page_count)
		if addr == 0 {
			return error('elf: Allocation failure')
		}

		pf := mmap.prot_read | mmap.prot_exec | if phdr.p_flags & elf.pf_w != 0 {
			mmap.prot_write
		} else {
			0
		}

		virt := base + phdr.p_vaddr
		phys := u64(addr)

		mmap.map_range(pagemap, virt, phys, page_count * page_size, pf, mmap.map_anonymous) or {
			return error('')
		}

		buf := unsafe { byteptr(addr) + misalign + higher_half }

		res.read(0, buf, phdr.p_offset, phdr.p_filesz) or { return error('') }
	}

	return auxval, ld_path
}
