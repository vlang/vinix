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

// Keep ordinary binaries on the compact contiguous allocation path. Larger
// segments are assembled from modest chunks so they do not depend on finding
// hundreds of MiB of physically contiguous RAM after initramfs extraction.
const contiguous_page_limit = u64(4096)
const allocation_chunk_pages = u64(256)

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

// architecture reports the ELF machine without mapping any part of the file.
// The ARM64 exec path uses this to hand x86-64 programs to the userspace
// translator instead of jumping directly into foreign instructions.
pub fn architecture(_res &resource.Resource) !u16 {
	mut res := unsafe { _res }
	mut header := &Header{}

	res.read(0, header, 0, sizeof(Header)) or { return error('') }
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
		base = pie_base + random_offset(image_aslr_span - pie_base, image_alignment)
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
		if phdr.p_filesz > phdr.p_memsz {
			return error('elf: LOAD segment filesz exceeds memsz')
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

		mut pf := 0
		if phdr.p_flags & pf_r != 0 { pf |= mmap.prot_read }
		if phdr.p_flags & pf_w != 0 { pf |= mmap.prot_write }
		if phdr.p_flags & pf_x != 0 { pf |= mmap.prot_exec }

		virt := lib.align_down(base + phdr.p_vaddr, page_size)
		if page_count > contiguous_page_limit {
			mut phys_pages := []u64{cap: int(page_count)}
			mut first_page := u64(0)
			file_begin := misalign
			file_end := misalign + phdr.p_filesz

			for first_page < page_count {
				remaining := page_count - first_page
				chunk_pages := if remaining > allocation_chunk_pages {
					allocation_chunk_pages
				} else {
					remaining
				}
				chunk_addr := memory.pmm_alloc_nozero(chunk_pages)
				if chunk_addr == 0 {
					unsafe { phys_pages.free() }
					return error('elf: Allocation failure')
				}

				chunk_size := chunk_pages * page_size
				unsafe { C.memset(byteptr(chunk_addr) + higher_half, 0, chunk_size) }
				for page := u64(0); page < chunk_pages; page++ {
					phys_pages << u64(chunk_addr) + page * page_size
				}

				chunk_begin := first_page * page_size
				chunk_end := chunk_begin + chunk_size
				copy_begin := if chunk_begin > file_begin { chunk_begin } else { file_begin }
				copy_end := if chunk_end < file_end { chunk_end } else { file_end }
				if copy_begin < copy_end {
					destination := unsafe {
						byteptr(chunk_addr) + higher_half + copy_begin - chunk_begin
					}
					file_offset := phdr.p_offset + copy_begin - file_begin
					res.read(0, destination, file_offset, copy_end - copy_begin) or {
						unsafe { phys_pages.free() }
						return error('')
					}
				}
				first_page += chunk_pages
			}

			mmap.map_pages(mut pagemap, virt, phys_pages, pf, mmap.map_anonymous) or {
				unsafe { phys_pages.free() }
				return error('')
			}
			unsafe { phys_pages.free() }
		} else {
			// The file data is about to overwrite most executable segments. Avoid
			// clearing that memory twice by initialising only bytes not populated
			// from the ELF image.
			addr := memory.pmm_alloc_nozero(page_count)
			if addr == 0 {
				return error('elf: Allocation failure')
			}
			allocation_size := page_count * page_size
			mmap.map_range(mut pagemap, virt, u64(addr), allocation_size, pf, mmap.map_anonymous) or {
				return error('')
			}

			buf := unsafe { byteptr(addr) + misalign + higher_half }
			res.read(0, buf, phdr.p_offset, phdr.p_filesz) or { return error('') }
			unsafe {
				if misalign != 0 {
					C.memset(byteptr(addr) + higher_half, 0, misalign)
				}
				tail := allocation_size - misalign - phdr.p_filesz
				if tail != 0 {
					C.memset(buf + phdr.p_filesz, 0, tail)
				}
			}
		}
	}

	// If no PT_PHDR segment was found, compute AT_PHDR from the first
	// LOAD segment's base (like Linux's binfmt_elf.c). This works for both
	// PIE (vaddr 0) and EXEC (vaddr 0x400000+) binaries.
	if auxval.at_phdr == 0 {
		auxval.at_phdr = load_addr + header.phoff
	}

	return auxval, ld_path
}
