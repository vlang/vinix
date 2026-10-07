// SPDX-License-Identifier: GPL-2.0-or-later
// Independent executable text and native musl interpreter regression.
@[translated; has_globals]
module textfixture

#include <elf-text-native-abi.h>

@[typedef]
struct C.FILE {}
@[typedef]
struct C.Elf64_Ehdr {
	e_phoff     u64
	e_phentsize u16
	e_phnum     u16
}
@[typedef]
struct C.Elf64_Phdr {
mut:
	p_type   u32
	p_flags  u32
	p_offset u64
	p_vaddr  u64
	p_filesz u64
	p_memsz  u64
	p_align  u64
}
struct C.velf_dynamic_words {
	entries [4]u64
}
@[c_extern] __global C.errno i32
@[c_extern] __global C.stdout &C.FILE
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(&C.FILE) i32
fn C.sysconf(i32) i64
fn C.mprotect(voidptr, usize, i32) i32
fn C.fork() i32
fn C.execl(&char, &char, ...&char) i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.getauxval(usize) usize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.strcmp(&char, &char) i32
fn C.pause() i32
fn C.velf_text_target() i32

// File-backed initialized storage, retaining the original volatile native words.
@[cinit]
__global dynamic_fixture C.velf_dynamic_words = C.velf_dynamic_words{
	entries: [u64(30), u64(0), u64(0), u64(0)]!
}

// The native declaration supplies placement attributes for this actual C wrapper.
@[export: 'velf_text_target'; noinline]
pub fn text_target() i32 { return 73 }

@[inline]
fn check(condition bool, line i32) bool {
	unsafe {
		if !condition { C.printf(c'ELF TEXT FAIL: line=%d errno=%d\n', line, C.errno) }
	}
	return condition
}

fn check_text(mutable bool) i32 {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		address := usize(C.velf_text_target) & ~(page - 1)
		C.errno = 0
		result := C.mprotect(voidptr(address), page, C.PROT_READ | C.PROT_EXEC)
		if !check(if mutable { result == 0 } else { result == -1 && C.errno == C.EPERM }, 27) { return 1 }
		if !check(C.velf_text_target() == 73, 28) { return 1 }
		return 0
	}
}

fn run_child(path &char, mode &char) i32 {
	unsafe {
		child := C.fork()
		if !check(child >= 0, 35) { return 1 }
		if child == 0 {
			C.execl(path, path, mode, &char(nil))
			C._exit(100)
		}
		mut status := i32(0)
		if !check(C.waitpid(child, &status, 0) == child, 41) { return 1 }
		if !check(C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, 42) { return 1 }
		return 0
	}
}

fn check_interpreter() i32 {
	unsafe {
		base := C.getauxval(C.AT_BASE)
		if !check(base != 0, 49) { return 1 }
		header := &C.Elf64_Ehdr(base)
		phdrs := &C.Elf64_Phdr(base + header.e_phoff)
		page := usize(C.sysconf(C._SC_PAGESIZE))
		for index := u32(0); index < header.e_phnum; index++ {
			if phdrs[index].p_type != C.PT_LOAD || (phdrs[index].p_flags & u32(C.PF_X)) == 0 { continue }
			address := (base + phdrs[index].p_vaddr) & ~(page - 1)
			C.errno = 0
			if !check(C.mprotect(voidptr(address), page, C.PROT_READ | C.PROT_EXEC) == -1 && C.errno == C.EPERM, 57) { return 1 }
			return 0
		}
		check(false, 60)
		return 1
	}
}

fn make_fixture(path &char, tag u64, value u64) i32 {
	unsafe {
		source := C.open(c'/proc/self/exe', C.O_RDONLY)
		output := C.open(path, C.O_CREAT | C.O_TRUNC | C.O_RDWR, i32(0o700))
		if !check(source >= 0 && output >= 0, 67) { return 1 }
		mut buffer := [8192]char{}
		mut length := isize(0)
		for {
			length = C.read(source, &buffer[0], sizeof(buffer))
			if length <= 0 { break }
			if !check(C.write(output, &buffer[0], usize(length)) == length, 71) { return 1 }
		}
		if !check(length == 0 && C.close(source) == 0, 72) { return 1 }
		mut header := C.Elf64_Ehdr{}
		if !check(C.pread(output, &header, sizeof(header), 0) == isize(sizeof(header)), 74) { return 1 }
		mut offset := ~u64(0)
		mut spare := i64(-1)
		for index := u32(0); index < header.e_phnum; index++ {
			mut ph := C.Elf64_Phdr{}
			at := i64(header.e_phoff + u64(index) * header.e_phentsize)
			if !check(C.pread(output, &ph, sizeof(ph), at) == isize(sizeof(ph)), 80) { return 1 }
			address := u64(usize(&dynamic_fixture))
			if ph.p_type == C.PT_LOAD && address >= ph.p_vaddr && address - ph.p_vaddr < ph.p_filesz {
				offset = ph.p_offset + address - ph.p_vaddr
			}
			if ph.p_type == C.PT_GNU_STACK { spare = at }
		}
		if !check(offset != ~u64(0) && spare >= 0, 86) { return 1 }
		mut table := [tag, value, u64(C.DT_NULL), u64(0)]!
		if !check(C.pwrite(output, &table[0], sizeof(table), i64(offset)) == isize(sizeof(table)), 88) { return 1 }
		mut ph := C.Elf64_Phdr{
			p_type: u32(C.PT_DYNAMIC)
			p_flags: u32(C.PF_R | C.PF_W)
			p_offset: offset
			p_vaddr: u64(usize(&dynamic_fixture))
			p_filesz: sizeof(table)
			p_memsz: sizeof(table)
			p_align: 8
		}
		if !check(C.pwrite(output, &ph, sizeof(ph), spare) == isize(sizeof(ph)), 92) { return 1 }
		if !check(C.close(output) == 0, 93) { return 1 }
		return 0
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc > 1 {
			if !check(check_text(C.strcmp(argv[1], c'mutable') == 0) == 0, 100) { return 1 }
			return if C.strcmp(argv[1], c'interpreter') == 0 { check_interpreter() } else { 0 }
		}
		if !check(check_text(false) == 0, 103) { return 1 }
		if !check(make_fixture(c'/tmp/elf-ordinary', u64(C.DT_NULL), 0) == 0, 104) { return 1 }
		if !check(make_fixture(c'/tmp/elf-legacy', u64(C.DT_TEXTREL), 0) == 0, 105) { return 1 }
		if !check(make_fixture(c'/tmp/elf-flags', u64(C.DT_FLAGS), u64(C.DF_TEXTREL)) == 0, 106) { return 1 }
		if !check(run_child(c'/tmp/elf-ordinary', c'frozen') == 0, 107) { return 1 }
		if !check(run_child(c'/tmp/elf-legacy', c'mutable') == 0, 108) { return 1 }
		if !check(run_child(c'/tmp/elf-flags', c'mutable') == 0, 109) { return 1 }
		if !check(run_child(c'/elf-pie', c'interpreter') == 0, 111) { return 1 }
		C.puts(c'ELF TEXT PASS: ordinary and both textrel encodings')
		C.puts(c'ELF TEXT PASS: PIE and interpreter boot')
		C.fflush(C.stdout)
		for { C.pause() }
	}
	return 0
}
