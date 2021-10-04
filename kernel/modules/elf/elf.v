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

pub const at_entry = 10
pub const at_phdr  = 20
pub const at_phent = 21
pub const at_phnum = 22

pub const pt_load   = 0x00000001
pub const pt_interp = 0x00000003
pub const pt_phdr   = 0x00000006

pub const abi_sysv    = 0x00
pub const arch_x86_64 = 0x3e
pub const bits_le     = 0x01

pub const ei_class   = 4
pub const ei_data    = 5
pub const ei_version = 6
pub const ei_osabi   = 7

pub struct Header {
pub mut:
	ident [16]byte
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

pub fn load(_pagemap &memory.Pagemap, _res &resource.Resource, base u64) ?(Auxval, string) {
	mut res := unsafe { _res }
	mut pagemap := unsafe { _pagemap }

	mut header := &Header{}

	res.read(0, header, 0, sizeof(Header)) ?

	if unsafe { C.memcmp(&header.ident, c'\177ELF', 4) } != 0 {
		return error('elf: Invalid magic')
	}

	if header.ident[ei_class] != 0x02
	|| header.ident[ei_data]  != bits_le
	|| header.machine != arch_x86_64 {
		return error('elf: Unsupported ELF file')
	}

	mut auxval := Auxval{at_entry: base + header.entry,
						 at_phdr: 0,
						 at_phent: sizeof(ProgramHdr),
						 at_phnum: header.ph_num}

	mut ld_path := ''

	for i := u64(0); i < header.ph_num; i++ {
		mut phdr := &ProgramHdr{}

		res.read(0, phdr, header.phoff + (sizeof(ProgramHdr) * i), sizeof(ProgramHdr)) ?

		match phdr.p_type {
			pt_interp {
				mut p := memory.malloc(phdr.p_filesz + 1)
				res.read(0, p, phdr.p_offset, phdr.p_filesz) ?
				ld_path = unsafe { cstring_to_vstring(p) }
			}
			pt_phdr {
				auxval.at_phdr = base + phdr.p_vaddr
			}
			else {}
		}

		if phdr.p_type != pt_load {
			continue
		}

		misalign := phdr.p_vaddr & (page_size - 1)
		page_count := lib.div_roundup(misalign + phdr.p_memsz, page_size)

		addr := memory.pmm_alloc(page_count)
		if addr == 0 {
			return error('elf: Allocation failure')
		}

		pf := mmap.prot_read | mmap.prot_exec
		| if phdr.p_flags & pf_w != 0 { mmap.prot_write } else { 0 }

		virt := base + phdr.p_vaddr
		phys := u64(addr)

		mmap.map_range(pagemap, virt, phys, page_count * page_size, pf,
					   mmap.map_anonymous) or {
			return none
		}

		buf := unsafe { byteptr(addr) + misalign + higher_half }

		res.read(0, buf, phdr.p_offset, phdr.p_filesz) ?
	}

	return auxval, ld_path
}
