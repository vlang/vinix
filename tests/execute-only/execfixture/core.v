// Independent execute-only oracle; native storage and syscalls retain original lifetimes.
@[translated; has_globals]
module execfixture

#include <native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.exec_volatile_byte { value u8 }
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32
__global failures i32

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setvbuf(&C.FILE, voidptr, i32, usize) i32
fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.pipe(&i32) i32
fn C.sysconf(i32) i64
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.mremap(voidptr, usize, usize, i32, ...) voidptr
fn C.munmap(voidptr, usize) i32
fn C.ftruncate(i32, i64) i32
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strstr(&char, &char) &char
fn C.strtol(&char, voidptr, i32) i64
fn C.unlink(&char) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.WIFSIGNALED(i32) bool
fn C.WTERMSIG(i32) i32
fn C._exit(i32)
fn C.pause() i32

fn native_xonly() bool {
	return C.EXEC_NATIVE_XONLY != 0
}

fn code_size() usize { $if arm64 { return 8 } return 6 }

fn check(ok bool, name &char) {
	unsafe {
		C.printf(c'EXECUTE ONLY %s: %s errno=%d\n', if ok { &char(c'PASS') } else { &char(c'FAIL') }, name, C.errno)
		if !ok { failures++ }
	}
}

fn status_of(pid i32) i32 {
	if pid <= 0 { return -1 }
	mut status := i32(-1)
	unsafe { for C.waitpid(pid, &status, 0) < 0 { if C.errno != C.EINTR { return -1 } } }
	return status
}

fn exits_ok(status i32) bool { return status >= 0 && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0 }
fn segv(status i32) bool { return status >= 0 && C.WIFSIGNALED(status) && C.WTERMSIG(status) == C.SIGSEGV }
type CodeFunction = fn () i32
fn run_code(p voidptr) i32 { return unsafe { CodeFunction(p)() } }

fn sync_code(p &u8, length usize) {
	$if arm64 {
		mut ctr := u64(0)
		asm volatile aarch64 { mrs ctr, ctr_el0 ; =r (ctr) }
		dline := usize(4) << ((ctr >> 16) & 15)
		iline := usize(4) << (ctr & 15)
		end := usize(p) + length
		for address := usize(p) & ~(dline - 1); address < end; address += dline {
			asm volatile aarch64 { dc cvau, address ; ; r (address) ; memory }
		}
		asm volatile aarch64 { dsb ish ; ; ; memory }
		for address := usize(p) & ~(iline - 1); address < end; address += iline {
			asm volatile aarch64 { ic ivau, address ; ; r (address) ; memory }
		}
		asm volatile aarch64 {
			dsb ish
			isb
			; ; ; memory
		}
	}
}

fn fill_code(p &u8, page usize, count i32) {
	unsafe {
		$if arm64 {
			code := [u8(0x40), 0x05, 0x80, 0x52, 0xc0, 0x03, 0x5f, 0xd6]!
			for i := i32(0); i < count; i++ { C.memcpy(p + usize(i) * page, &code[0], sizeof(code)) }
		} $else {
			code := [u8(0xb8), 0x2a, 0, 0, 0, 0xc3]!
			for i := i32(0); i < count; i++ { C.memcpy(p + usize(i) * page, &code[0], sizeof(code)) }
		}
		sync_code(p, page * usize(count))
	}
}

fn copy_denied(fd i32, p voidptr) bool {
	unsafe {
		C.errno = 0
		n := C.write(fd, p, code_size())
		return if native_xonly() { n == -1 && C.errno == C.EFAULT } else { n == isize(code_size()) }
	}
}

fn drain_compat(fd i32) {
	if !native_xonly() {
		mut bytes := [8]u8{}
		unsafe { C.read(fd, &bytes[0], code_size()) }
	}
}

fn slab_kb() i64 {
	unsafe {
		mut bytes := [4096]char{}
		fd := C.open(c'/proc/meminfo', C.O_RDONLY)
		if fd < 0 { return -1 }
		n := C.read(fd, &bytes[0], sizeof(bytes) - 1)
		C.close(fd)
		if n < 0 { return -1 }
		bytes[n] = 0
		p := C.strstr(&bytes[0], c'Slab:')
		return if p != nil { C.strtol(p + 5, nil, 10) } else { i64(-1) }
	}
}

fn exercise(p &u8, page usize, ends &i32) {
	unsafe {
		mut code := [8]u8{}
		$if arm64 { code = [u8(0x40), 0x05, 0x80, 0x52, 0xc0, 0x03, 0x5f, 0xd6]! }
		$else { code = [u8(0xb8), 0x2a, 0, 0, 0, 0xc3, 0, 0]! }
		fill_code(p, page, 3)
		check(C.mprotect(p, 3 * page, C.PROT_EXEC) == 0 && run_code(p) == 42, c'explicit execute-only native instruction fetch')
		mut child := C.fork()
		if child == 0 {
			value := (&C.exec_volatile_byte(p)).value
			C._exit(if value == code[0] { 0 } else { 1 })
		}
		status := status_of(child)
		check(if native_xonly() { segv(status) } else { exits_ok(status) }, c'native data-read protection (x86 readable fallback)')
		check(copy_denied(ends[1], p), c'checked read honors native execute-only support')
		drain_compat(ends[0])
		mut input := [8]u8{}
		check(C.write(ends[1], &input[0], code_size()) == isize(code_size()), c'prepare checked output')
		C.errno = 0
		check(C.read(ends[0], p, code_size()) == -1 && C.errno == C.EFAULT, c'checked output cannot modify executable text')
		check(C.read(ends[0], &input[0], code_size()) == isize(code_size()), c'failed checked output preserves pipe bytes')
		check(C.mprotect(p, page, C.PROT_READ | C.PROT_EXEC) == 0 && C.memcmp(p, &code[0], code_size()) == 0 && run_code(p) == 42, c'read-execute transition permits data reads')
		check(C.mprotect(p, page, C.PROT_READ | C.PROT_WRITE) == 0, c'writable transition removes execute permission')
		child = C.fork()
		if child == 0 { C._exit(if run_code(p) == 42 { 0 } else { 1 }) }
		check(segv(status_of(child)), c'data-only mapping rejects instruction fetch')
		check(C.mprotect(p, page, C.PROT_EXEC) == 0 && run_code(p) == 42, c'restore execute-only permission')
		C.puts(c'EXECUTE ONLY PASS: permissions and checked copies')

		check(C.mprotect(p + page, page, C.PROT_READ | C.PROT_EXEC) == 0, c'split range retains independent protections')
		check(C.memcmp(p + page, &code[0], code_size()) == 0 && run_code(p + 2 * page) == 42, c'split center readable while outer code still executes')
		check(copy_denied(ends[1], p + 2 * page), c'split preserves outer execute-only checked-copy rule')
		drain_compat(ends[0])
		child = C.fork()
		if child == 0 {
			if run_code(p) != 42 || run_code(p + page) != 42 { C._exit(1) }
			if !copy_denied(ends[1], p) { C._exit(2) }
			C._exit(0)
		}
		check(exits_ok(status_of(child)), c'fork retains execute-only and readable split permissions')
		drain_compat(ends[0])
		child = C.fork()
		if child == 0 {
			if C.mprotect(p, page, C.PROT_READ | C.PROT_WRITE) != 0 { C._exit(1) }
			$if arm64 { p[0] = 0x60 } $else { p[1] = 43 }
			sync_code(p, page)
			if C.mprotect(p, page, C.PROT_EXEC) != 0 || run_code(p) != 43 { C._exit(2) }
			C._exit(0)
		}
		check(exits_ok(status_of(child)) && run_code(p) == 42, c"fork COW writable transition preserves parent's execute-only bytes")
		moved := &u8(C.mremap(p + 2 * page, page, 2 * page, C.MREMAP_MAYMOVE))
		check(moved != C.MAP_FAILED && run_code(moved) == 42, c'remap retains execute-only instruction bytes')
		if moved != C.MAP_FAILED {
			check(copy_denied(ends[1], moved), c'remap preserves checked-copy protection')
			drain_compat(ends[0])
			check(C.mprotect(moved, page, C.PROT_READ | C.PROT_EXEC) == 0 && C.memcmp(moved, &code[0], code_size()) == 0, c'remapped bytes survive protection change')
			C.munmap(moved, 2 * page)
		}
		fd := C.open(c'/tmp/execute-only-code', C.O_CREAT | C.O_TRUNC | C.O_RDWR, i32(0o600))
		mut file_code := &u8(C.MAP_FAILED)
		if fd >= 0 && C.ftruncate(fd, i64(page)) == 0 && C.pwrite(fd, &code[0], code_size(), 0) == isize(code_size()) {
			file_code = C.mmap(nil, page, C.PROT_EXEC, C.MAP_PRIVATE, fd, 0)
		}
		check(file_code != C.MAP_FAILED && run_code(file_code) == 42, c'demand-paged file executes without a readable data mapping')
		if file_code != C.MAP_FAILED {
			check(copy_denied(ends[1], file_code), c'file-backed checked-read rule')
			drain_compat(ends[0])
			check(C.mprotect(file_code, page, C.PROT_READ | C.PROT_EXEC) == 0 && C.memcmp(file_code, &code[0], code_size()) == 0, c'file-backed protection transition preserves code')
			C.munmap(file_code, page)
		}
		if fd >= 0 { C.close(fd) }
		C.unlink(c'/tmp/execute-only-code')
		check(C.mprotect(p, page, C.PROT_EXEC) == 0, c'prepare repeated checked denials')
		for i := i32(0); i < 100; i++ { copy_denied(ends[1], p); drain_compat(ends[0]) }
		before := slab_kb()
		mut bad := i32(0)
		for i := i32(0); i < 3000; i++ { if !copy_denied(ends[1], p) { bad++ }; drain_compat(ends[0]) }
		after := slab_kb()
		C.printf(c'EXECUTE ONLY slab: before=%ld after=%ld KiB\n', before, after)
		check(bad == 0 && before >= 0 && after >= 0 && after <= before + 16, c'repeated native checked reads have bounded retained scratch')
		C.munmap(p, 3 * page)
		C.close(ends[0]); C.close(ends[1])
		C.puts(c'EXECUTE ONLY PASS: fork split remap and demand paging')
	}
}

@[export: 'main']
pub fn entry() i32 {
	unsafe {
		console := C.open(c'/dev/com1', C.O_WRONLY | C.O_NOCTTY)
		if console >= 0 { C.dup2(console, 1); C.dup2(console, 2); C.close(console) }
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		page := usize(C.sysconf(C._SC_PAGESIZE))
		p := &u8(C.mmap(nil, 3 * page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		mut ends := [i32(-1), -1]!
		check(p != C.MAP_FAILED && C.pipe(&ends[0]) == 0, c'prepare native code and checked-copy pipe')
		if p != C.MAP_FAILED && ends[0] >= 0 { exercise(p, page, &ends[0]) }
		C.puts(if failures != 0 { &char(c'EXECUTE ONLY GUEST: FAIL') } else { &char(c'EXECUTE ONLY GUEST: PASS') })
		for { C.pause() }
		return 0
	}
}
