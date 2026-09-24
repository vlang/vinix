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
pub const pt_dynamic = 0x00000002
pub const pt_interp = 0x00000003
pub const pt_phdr = 0x00000006

const dt_null = i64(0)
const dt_textrel = i64(22)
const dynamic_scan_limit = u64(64 * 1024)

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

struct DynamicEntry {
	d_tag   i64
	d_value u64
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

fn exec_trace(enabled bool, image string, stage string) {
	if enabled {
		println('exec[gpu]/elf ${image}: ${stage}')
	}
}

pub fn load(_pagemap &memory.Pagemap, _res &resource.Resource, _base u64) !(Auxval, string) {
	return load_impl(_pagemap, _res, _base, false, '')
}

// Verbose production-visible loader diagnostics for the one hardware desktop
// exec under investigation. Keeping this as a separate entry point avoids
// flooding every normal program launch.
pub fn load_traced(_pagemap &memory.Pagemap, _res &resource.Resource, _base u64, image string) !(Auxval, string) {
	return load_impl(_pagemap, _res, _base, true, image)
}

fn load_impl(_pagemap &memory.Pagemap, _res &resource.Resource, _base u64, trace bool, image string) !(Auxval, string) {
	mut res := unsafe { _res }
	mut pagemap := unsafe { _pagemap }
	mut base := _base

	mut header := &Header{}

	exec_trace(trace, image, 'reading ELF header')
	read_exact(mut res, header, 0, sizeof(Header))!
	exec_trace(trace, image, 'ELF header read')

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
	if trace {
		println('exec[gpu]/elf ${image}: header valid type=${header.@type} phnum=${header.ph_num} entry=0x${header.entry:x}')
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
		exec_trace(trace, image, 'choosing PIE load base')
		base = pie_base + random_offset(image_aslr_span - pie_base, image_alignment)
	}
	if trace {
		println('exec[gpu]/elf ${image}: effective load base=0x${base:x}')
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
	mut textrel := false
	mut committed := false
	defer {
		if !committed {
			exec_trace(trace, image, 'load failed; rolling back mapped ranges')
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

		if trace {
			println('exec[gpu]/elf ${image}: reading program header ${i + 1}/${header.ph_num}')
		}
		read_exact(mut res, phdr, header.phoff + (sizeof(ProgramHdr) * i), sizeof(ProgramHdr))!
		if trace {
			println('exec[gpu]/elf ${image}: program header ${i + 1} type=${phdr.p_type} flags=0x${phdr.p_flags:x}')
		}

		match phdr.p_type {
			pt_dynamic {
				// OpenBSD leaves text/rodata mutable when DT_TEXTREL says the
				// runtime linker must rewrite instructions. Bound the scan just as
				// OpenBSD does; an oversized table conservatively disables automatic
				// text immutability rather than risking a relocation failure.
				if phdr.p_offset > u64(res.stat.size)
					|| phdr.p_filesz > u64(res.stat.size) - phdr.p_offset {
					return error('elf: invalid DYNAMIC segment')
				}
				if phdr.p_filesz > dynamic_scan_limit {
					textrel = true
				} else {
					mut dynamic_offset := u64(0)
					for dynamic_offset + sizeof(DynamicEntry) <= phdr.p_filesz {
						mut dynamic := &DynamicEntry{}
						read_exact(mut res, dynamic, phdr.p_offset + dynamic_offset,
							sizeof(DynamicEntry))!
						if dynamic.d_tag == dt_textrel {
							textrel = true
							break
						}
						if dynamic.d_tag == dt_null {
							break
						}
						dynamic_offset += sizeof(DynamicEntry)
					}
				}
			}
			pt_interp {
				exec_trace(trace, image, 'reading interpreter path')
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
				exec_trace(trace, image, 'interpreter path read')
			}
			pt_phdr {
				if phdr.p_vaddr > u64(-1) - base {
					return error('elf: PHDR address overflow')
				}
				auxval.at_phdr = base + phdr.p_vaddr
				exec_trace(trace, image, 'recorded PT_PHDR address')
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
		if trace {
			println('exec[gpu]/elf ${image}: mapping LOAD ${i + 1} va=0x${virt:x} len=0x${mapping_length:x} file=0x${file_offset:x} prot=${pf}')
		}
		mmap.mmap_file_segment(pagemap, virt, mapping_length, pf, res, file_offset, 0, file_backed_length) or { return error('elf: unable to map LOAD segment') }
		if trace {
			println('exec[gpu]/elf ${image}: mapped LOAD ${i + 1}')
		}
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
		exec_trace(trace, image, 'deriving missing PT_PHDR address')
		if header.phoff > u64(-1) - load_addr {
			return error('elf: PHDR address overflow')
		}
		auxval.at_phdr = load_addr + header.phoff
	}

	// Freeze only final executable, non-writable mappings, after every PT_LOAD
	// replacement is complete. Page-rounded segment overlap can otherwise make
	// an earlier executable range contain pages that a later writable segment
	// replaced. DT_TEXTREL keeps the image mutable for the runtime linker.
	if !textrel {
		for range in loaded_ranges {
			mmap.mimmutable_executable(mut pagemap, range.base, range.length) or {
				return error('elf: unable to make text immutable')
			}
		}
	}

	committed = true
	if trace {
		println('exec[gpu]/elf ${image}: committed entry=0x${auxval.at_entry:x} phdr=0x${auxval.at_phdr:x}')
	}
	return auxval, ld_path
}
