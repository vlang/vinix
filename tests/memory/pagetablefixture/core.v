// SPDX-License-Identifier: BSD-2-Clause
// Independent page-table reclamation fixture; preserve native mappings/faults.
@[has_globals]
module pagetablefixture

#include <pagetable-native-abi.h>

@[typedef]
struct C.sigjmp_buf {}

@[typedef]
struct C.sigset_t {}

struct C.sigaction {
mut:
	sa_handler fn (i32)
	sa_mask    C.sigset_t
}

struct C.sysinfo {
	freeram  usize
	mem_unit u32
}

struct C.vqpt_byte {
mut:
	value u8
}

struct C.vqpt_signal {
mut:
	value i32
}

__global pt_jump C.sigjmp_buf
__global pt_fault C.vqpt_signal

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigsetjmp(C.sigjmp_buf, i32) i32
fn C.siglongjmp(C.sigjmp_buf, i32)
fn C.vqpt_fault_handler(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C._exit(i32)
fn C.sysconf(i32) i64
fn C.sysinfo(&C.sysinfo) i32
fn C.__get_cpuid_count(u32, u32, &u32, &u32, &u32, &u32) i32

@[c_extern]
__global C.errno i32

fn check(ok bool, line i32, expression &char) bool {
	if !ok {
		unsafe { C.printf(c'PAGETABLE FAIL line %d: %s (errno=%d)\n', line, expression, C.errno) }
	}
	return ok
}

@[export: 'vqpt_fault_handler']
pub fn fault_handler(signal i32) {
	unsafe {
		pt_fault.value = signal
		C.siglongjmp(pt_jump, 1)
	}
}

fn absent(address &u8) i32 {
	unsafe {
		mut action := C.sigaction{ sa_handler: C.vqpt_fault_handler }
		mut previous := C.sigaction{}
		C.sigemptyset(&action.sa_mask)
		if !check(C.sigaction(C.SIGSEGV, &action, &previous) == 0, 46, c'sigaction(SIGSEGV, &action, &previous) == 0') {
			return 1
		}
		pt_fault.value = 0
		if C.sigsetjmp(pt_jump, 1) == 0 { _ = (&C.vqpt_byte(address)).value }
		if !check(C.sigaction(C.SIGSEGV, &previous, nil) == 0, 50, c'sigaction(SIGSEGV, &previous, NULL) == 0') {
			return 1
		}
		if !check(pt_fault.value == C.SIGSEGV, 51, c'pt_fault == SIGSEGV') { return 1 }
		return 0
	}
}

fn wait_child(child i32) i32 {
	unsafe {
		mut status := i32(0)
		mut waited := i32(0)
		for {
			waited = C.waitpid(child, &status, 0)
			if !(waited < 0 && C.errno == C.EINTR) { break }
		}
		if !check(waited == child, 62, c'waited == child') { return 1 }
		if !check(C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, 63, c'WIFEXITED(status) && WEXITSTATUS(status) == 0') {
			return 1
		}
		return 0
	}
}

fn boundary(at usize, page usize, optional i32) i32 {
	unsafe {
		$if amd64 {
			if optional != 0 {
				mut eax := u32(0)
				mut ebx := u32(0)
				mut ecx := u32(0)
				mut edx := u32(0)
				if C.__get_cpuid_count(7, 0, &eax, &ebx, &ecx, &edx) == 0 || ecx & (u32(1) << 16) == 0 {
					C.printf(c'PAGETABLE SKIP: boundary=0x%lx CPU has four-level paging\n', at)
					return 0
				}
			}
		} $else {
			_ = optional
		}
		base := at - 4 * page
		length := 8 * page
		flags := i32(C.MAP_PRIVATE | C.MAP_ANONYMOUS | C.MAP_FIXED_NOREPLACE)
		mut area := &u8(C.mmap(voidptr(base), length, C.PROT_READ | C.PROT_WRITE, flags, -1, 0))
		if !check(voidptr(area) == voidptr(base), 90, c'area == (void *)base') { return 1 }
		mut i := usize(0)
		for i < 8 {
			(&C.vqpt_byte(area + i * page)).value = u8(0x30 + i)
			i++
		}
		if !check(C.munmap(voidptr(base + 6 * page), page) == 0, 97, c'munmap((void *)(base + 6 * page), page) == 0') {
			return 1
		}
		if !check((&C.vqpt_byte(area + 5 * page)).value == 0x35 && (&C.vqpt_byte(area + 7 * page)).value == 0x37, 98, c'area[5 * page] == 0x35 && area[7 * page] == 0x37') {
			return 1
		}
		if !check(C.munmap(voidptr(base + 7 * page), page) == 0, 99, c'munmap((void *)(base + 7 * page), page) == 0') {
			return 1
		}
		if !check((&C.vqpt_byte(area + 4 * page)).value == 0x34 && (&C.vqpt_byte(area + 5 * page)).value == 0x35, 100, c'area[4 * page] == 0x34 && area[5 * page] == 0x35') {
			return 1
		}
		if !check(absent(area + 6 * page) == 0, 101, c'pt_absent(area + 6 * page) == 0') {
			return 1
		}
		if !check(absent(area + 7 * page) == 0, 102, c'pt_absent(area + 7 * page) == 0') {
			return 1
		}
		mut ready := [2]i32{}
		if !check(C.pipe(&ready[0]) == 0, 107, c'pipe(ready) == 0') { return 1 }
		child := C.fork()
		if !check(child >= 0, 109, c'child >= 0') { return 1 }
		if child == 0 {
			mut token := u8(0)
			C.close(ready[1])
			if C.read(ready[0], &token, 1) != 1 { C._exit(1) }
			i = 0
			for i < 6 {
				if (&C.vqpt_byte(area + i * page)).value != u8(0x30 + i) { C._exit(2) }
				i++
			}
			(&C.vqpt_byte(area + 4 * page)).value = 0x71
			C._exit(if (&C.vqpt_byte(area + 4 * page)).value == 0x71 { 0 } else { 3 })
		}
		if !check(C.close(ready[0]) == 0, 121, c'close(ready[0]) == 0') { return 1 }
		if !check(C.munmap(voidptr(base + page), page) == 0, 124, c'munmap((void *)(base + page), page) == 0') {
			return 1
		}
		if !check((&C.vqpt_byte(area)).value == 0x30 && (&C.vqpt_byte(area + 2 * page)).value == 0x32, 125, c'area[0] == 0x30 && area[2 * page] == 0x32') {
			return 1
		}
		if !check(C.munmap(voidptr(base), page) == 0, 126, c'munmap((void *)base, page) == 0') {
			return 1
		}
		if !check(C.munmap(voidptr(base + 2 * page), 2 * page) == 0, 127, c'munmap((void *)(base + 2 * page), 2 * page) == 0') {
			return 1
		}
		if !check((&C.vqpt_byte(area + 4 * page)).value == 0x34 && (&C.vqpt_byte(area + 5 * page)).value == 0x35, 128, c'area[4 * page] == 0x34 && area[5 * page] == 0x35') {
			return 1
		}
		if !check(absent(area + 3 * page) == 0, 129, c'pt_absent(area + 3 * page) == 0') {
			return 1
		}
		replacement := C.mmap(voidptr(base), 4 * page, C.PROT_READ | C.PROT_WRITE, flags, -1, 0)
		if !check(replacement == voidptr(base), 132, c'replacement == (void *)base') { return 1 }
		i = 0
		for i < 4 {
			if !check((&C.vqpt_byte(area + i * page)).value == 0, 134, c'area[i * page] == 0') {
				return 1
			}
			(&C.vqpt_byte(area + i * page)).value = u8(0x80 + i)
			i++
		}
		if !check(C.write(ready[1], c'x', 1) == 1, 137, c'write(ready[1], "x", 1) == 1') {
			return 1
		}
		if !check(C.close(ready[1]) == 0, 138, c'close(ready[1]) == 0') { return 1 }
		if !check(wait_child(child) == 0, 139, c'pt_wait(child) == 0') { return 1 }
		if !check((&C.vqpt_byte(area + 4 * page)).value == 0x34 && (&C.vqpt_byte(area + 5 * page)).value == 0x35, 140, c'area[4 * page] == 0x34 && area[5 * page] == 0x35') {
			return 1
		}
		if !check(C.munmap(voidptr(base), length) == 0, 141, c'munmap((void *)base, length) == 0') {
			return 1
		}
		if !check(absent(area) == 0, 142, c'pt_absent(area) == 0') { return 1 }
		if !check(absent(area + 5 * page) == 0, 143, c'pt_absent(area + 5 * page) == 0') {
			return 1
		}
		for _ in 0 .. 4 {
			area = &u8(C.mmap(voidptr(base), length, C.PROT_READ | C.PROT_WRITE, flags, -1, 0))
			if !check(voidptr(area) == voidptr(base), 150, c'area == (void *)base') { return 1 }
			i = 0
			for i < 8 {
				if !check((&C.vqpt_byte(area + i * page)).value == 0, 152, c'area[i * page] == 0') {
					return 1
				}
				(&C.vqpt_byte(area + i * page)).value = u8(0xa0 + i)
				i++
			}
			if !check(C.munmap(voidptr(base), 7 * page) == 0, 155, c'munmap((void *)base, 7 * page) == 0') {
				return 1
			}
			if !check((&C.vqpt_byte(area + 7 * page)).value == 0xa7, 156, c'area[7 * page] == 0xa7') {
				return 1
			}
			if !check(C.munmap(voidptr(base + 7 * page), page) == 0, 157, c'munmap((void *)(base + 7 * page), page) == 0') {
				return 1
			}
		}
		C.printf(c'PAGETABLE PASS: boundary=0x%lx page=%zu\n', at, page)
		return 0
	}
}

@[export: 'vinix_pagetable_boundaries']
pub fn boundaries() i32 {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		if !check(page == 4096 || page == 16384, 167, c'page == 4096 || page == 16384') { return 1 }
		mut before := C.sysinfo{}
		mut after := C.sysinfo{}
		if !check(C.sysinfo(&before) == 0, 169, c'sysinfo(&before) == 0') { return 1 }
		if page == 4096 {
			if !check(boundary(usize(64) << 20, page, 0) == 0, 171, c'pt_boundary(UINT64_C(64) << 20, page, 0) == 0') {
				return 1
			}
			if !check(boundary(usize(32) << 30, page, 0) == 0, 172, c'pt_boundary(UINT64_C(32) << 30, page, 0) == 0') {
				return 1
			}
			if !check(boundary(usize(4) << 40, page, 0) == 0, 173, c'pt_boundary(UINT64_C(4) << 40, page, 0) == 0') {
				return 1
			}
			if !check(boundary(usize(1) << 48, page, 1) == 0, 174, c'pt_boundary(UINT64_C(1) << 48, page, 1) == 0') {
				return 1
			}
		} else {
			if !check(boundary(usize(128) << 20, page, 0) == 0, 177, c'pt_boundary(UINT64_C(128) << 20, page, 0) == 0') {
				return 1
			}
			if !check(boundary(usize(512) << 30, page, 0) == 0, 178, c'pt_boundary(UINT64_C(512) << 30, page, 0) == 0') {
				return 1
			}
		}
		if !check(C.sysinfo(&after) == 0, 180, c'sysinfo(&after) == 0') { return 1 }
		unit := if after.mem_unit != 0 { usize(after.mem_unit) } else { usize(1) }
		if !check(after.freeram * unit + usize(1024) * 1024 >= before.freeram * (if before.mem_unit != 0 {
			usize(before.mem_unit)
		} else {
			usize(1)
		}), 182, c'after.freeram * unit + 1024UL * 1024 >= before.freeram * (before.mem_unit ? before.mem_unit : 1)') {
			return 1
		}
		C.puts(c'PAGETABLE CHECK: PASS sparse tables, sibling survival, holes, COW and reuse')
		return 0
	}
}
