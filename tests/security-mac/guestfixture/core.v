// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native mandatory-domain oracle; original conditions stay intact.
@[has_globals]
module guestfixture

#include <native-abi.h>

@[typedef]
struct C.mac_ull {}

@[typedef]
struct C.mac_ll {}

@[typedef]
struct C.pthread_t {}

@[typedef]
struct C.cpu_set_t {}

struct C.stat {}

struct C.sched_param {
mut:
	sched_priority i32
}

struct C.rlimit {
mut:
	rlim_cur u64
	rlim_max u64
}

struct C.iovec {
mut:
	iov_base voidptr
	iov_len  usize
}

struct C.cmsghdr {
mut:
	cmsg_len   u32
	cmsg_level i32
	cmsg_type  i32
}

struct C.msghdr {
mut:
	msg_name       voidptr
	msg_namelen    u32
	msg_iov        &C.iovec
	msg_iovlen     i32
	msg_control    voidptr
	msg_controllen u32
	msg_flags      i32
}

@[typedef]
struct C.mac_cmsg_storage {
mut:
	bytes [24]u8
}

struct C.mac_sched_attr {
mut:
	size     u32
	policy   u32
	flags    u64
	nice     i32
	priority u32
	runtime  u64
	deadline u64
	period   u64
}

@[typedef]
struct C.Elf64_Ehdr {
mut:
	e_ident     [16]u8
	e_type      u16
	e_machine   u16
	e_version   u32
	e_entry     u64
	e_phoff     u64
	e_shoff     u64
	e_flags     u32
	e_ehsize    u16
	e_phentsize u16
	e_phnum     u16
	e_shentsize u16
	e_shnum     u16
	e_shstrndx  u16
}

@[typedef]
struct C.Elf64_Phdr {
mut:
	p_type   u32
	p_flags  u32
	p_offset u64
	p_vaddr  u64
	p_paddr  u64
	p_filesz u64
	p_memsz  u64
	p_align  u64
}

@[c_extern]
__global C.errno i32

@[c_extern]
__global C.stdout voidptr

@[c_extern]
__global C.stderr voidptr

fn C.__builtin_alloca(usize) voidptr
fn C.prctl(i32, ...voidptr) i32
fn C.setxattr(&char, &char, voidptr, usize, i32) i32
fn C.lsetxattr(&char, &char, voidptr, usize, i32) i32
fn C.fsetxattr(i32, &char, voidptr, usize, i32) i32
fn C.getxattr(&char, &char, voidptr, usize) isize
fn C.lgetxattr(&char, &char, voidptr, usize) isize
fn C.fgetxattr(i32, &char, voidptr, usize) isize
fn C.flistxattr(i32, voidptr, usize) isize
fn C.removexattr(&char, &char) i32
fn C.open(&char, i32, ...voidptr) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.close(i32) i32
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.strtok(&char, &char) &char
fn C.strerror(i32) &char
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.sscanf(&char, &char, ...voidptr) i32
fn C.snprintf(&char, usize, &char, ...voidptr) i32
fn C.printf(&char, ...voidptr) i32
fn C.fprintf(voidptr, &char, ...voidptr) i32
fn C.puts(&char) i32
fn C.setbuf(voidptr, &char)
fn C.syscall(isize, ...voidptr) isize
fn C.fchmod(i32, u32) i32
fn C.ftruncate(i32, i64) i32
fn C.fchown(i32, u32, u32) i32
fn C.fstat(i32, &C.stat) i32
fn C.fstatat(i32, &char, &C.stat, i32) i32
fn C.stat(&char, &C.stat) i32
fn C.lseek(i32, i64, i32) i64
fn C.flock(i32, i32) i32
fn C.futimens(i32, voidptr) i32
fn C.ioctl(i32, u64, ...voidptr) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.mprotect(voidptr, usize, i32) i32
fn C.mincore(voidptr, usize, &u8) i32
fn C.dup(i32) i32
fn C.readlink(&char, &char, usize) isize
fn C.link(&char, &char) i32
fn C.unlink(&char) i32
fn C.rename(&char, &char) i32
fn C.symlink(&char, &char) i32
fn C.access(&char, i32) i32
fn C.mkdir(&char, u32) i32
fn C.mkfifo(&char, u32) i32
fn C.mknod(&char, u32, u64) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.execv(&char, &&char) i32
fn C.geteuid() u32
fn C.getppid() i32
fn C.kill(i32, i32) i32
fn C.getpgid(i32) i32
fn C.setpgid(i32, i32) i32
fn C.process_vm_readv(i32, &C.iovec, usize, &C.iovec, usize, u64) isize
fn C.sched_getaffinity(i32, usize, &C.cpu_set_t) i32
fn C.sched_setaffinity(i32, usize, &C.cpu_set_t) i32
fn C.CPU_ZERO(&C.cpu_set_t)
fn C.CPU_SET(i32, &C.cpu_set_t)
fn C.sethostname(&char, usize) i32
fn C.prlimit(i32, i32, &C.rlimit, &C.rlimit) i32
fn C.setpriority(i32, u32, i32) i32
fn C.getpriority(i32, u32) i32
fn C.inotify_init1(i32) i32
fn C.inotify_add_watch(i32, &char, u32) i32
fn C.inotify_rm_watch(i32, i32) i32
fn C.splice(i32, &i64, i32, &i64, usize, u32) isize
fn C.pipe(&i32) i32
fn C.pipe2(&i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.sendmsg(i32, &C.msghdr, i32) isize
fn C.recvmsg(i32, &C.msghdr, i32) isize
fn C.CMSG_FIRSTHDR(&C.msghdr) &C.cmsghdr
fn C.CMSG_LEN(usize) usize
fn C.CMSG_DATA(&C.cmsghdr) voidptr
fn C.unshare(i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C._exit(i32)
fn C.atoi(&char) i32
fn C.strtoull(&char, &&char, i32) u64
fn C.usleep(u32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, &voidptr) i32
fn C.vinix_mac_policy_blocked_thread(voidptr) voidptr
fn C.vinix_mac_policy_close_exec_descriptor(voidptr) voidptr

const mac_prctl = i32(0x56584d41)
const inspect = u32(1)
const read_mask = u32(2)
const write_mask = u32(4)
const execute_mask = u32(8)
const create_mask = u32(16)
const remove_mask = u32(32)
const metadata_mask = u32(64)
const ioctl_mask = u32(128)
const search = u32(256)
const all = u32(511)

fn require(condition bool, line i32, expression &char) bool {
	if !condition {
		unsafe { C.fprintf(C.stderr, c'SECURITY MAC FAIL line %d: %s (errno=%d %s)\n', line, expression, C.errno, C.strerror(C.errno)) }
	}
	return condition
}

fn control(command u32, domain u32, kind u32, mask u32) i64 {
	return i64(C.prctl(mac_prctl, usize(command), usize(domain), usize(kind), usize(mask)))
}

fn label(path &char, value &char) i32 {
	return C.setxattr(path, c'security.vinix', value, C.strlen(value), 0)
}

fn contents(path &char, value &char) i32 {
	fd := C.open(path, C.O_CREAT | C.O_RDWR | C.O_TRUNC, i32(0o755))
	if fd < 0 { return -1 }
	result := C.write(fd, value, C.strlen(value))
	saved := C.errno
	C.close(fd)
	unsafe { C.errno = saved }
	return if result == isize(C.strlen(value)) { i32(0) } else { i32(-1) }
}

fn slab_class_bytes(wanted_size u32) u64 {
	unsafe {
		text := &char(C.__builtin_alloca(4096))
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { return ~u64(0) }
		length := C.read(fd, text, 4095)
		C.close(fd)
		if length <= 0 { return ~u64(0) }
		text[length] = 0
		mut total := u64(0)
		mut line := C.strtok(text, c'\n')
		values := &C.mac_ull(C.__builtin_alloca(3 * sizeof(C.mac_ull)))
		mut words := [3]u64{}
		for line != nil {
			if C.sscanf(line, c'size-%*u %llu %llu %llu', &values[0], &values[1], &values[2]) == 3 {
				C.memcpy(&words[0], values, sizeof(words))
				if wanted_size == 0 || words[0] == wanted_size {
					total += words[0] * words[1]
				}
			}
			line = C.strtok(nil, c'\n')
		}
		return total
	}
}

fn slab_bytes() u64 { return slab_class_bytes(0) }

@[export: 'vinix_mac_policy_blocked_thread']
pub fn blocked_thread(argument voidptr) voidptr {
	unsafe {
		fd := *(&i32(argument))
		byte := &char(C.__builtin_alloca(1))
		C.read(fd, byte, 1)
		return nil
	}
}

fn prepare_interpreter_test() i32 {
	unsafe {
		mut image := [4096]u8{}
		mut header := C.Elf64_Ehdr{}
		C.memcpy(&header.e_ident[0], voidptr(C.ELFMAG), usize(C.SELFMAG))
		header.e_ident[C.EI_CLASS] = u8(C.ELFCLASS64)
		header.e_ident[C.EI_DATA] = u8(C.ELFDATA2LSB)
		header.e_ident[C.EI_VERSION] = u8(C.EV_CURRENT)
		header.e_type = u16(C.ET_EXEC)
		$if arm64 {
			header.e_machine = u16(C.EM_AARCH64)
		} $else {
			header.e_machine = u16(C.EM_X86_64)
		}
		header.e_version = u32(C.EV_CURRENT)
		header.e_entry = 0x400800
		header.e_phoff = u64(sizeof(header))
		header.e_ehsize = u16(sizeof(header))
		header.e_phentsize = u16(sizeof(C.Elf64_Phdr))
		header.e_phnum = 2
		mut program := [2]C.Elf64_Phdr{}
		mut interpreter := [u8(`/`), u8(`m`), u8(`a`), u8(`c`), u8(`-`), u8(`p`), u8(`r`), u8(`i`),
			u8(`v`), u8(`a`), u8(`t`), u8(`e`), u8(`/`), u8(`e`), u8(`x`), u8(`e`), u8(`c`), u8(`-`),
			u8(`d`), u8(`e`), u8(`n`), u8(`i`), u8(`e`), u8(`d`), u8(0)]!
		program[0].p_type = u32(C.PT_INTERP)
		program[0].p_offset = u64(sizeof(header) + sizeof(program))
		program[0].p_filesz = u64(sizeof(interpreter))
		program[1].p_type = u32(C.PT_LOAD)
		program[1].p_flags = u32(C.PF_R | C.PF_X)
		program[1].p_vaddr = 0x400000
		program[1].p_filesz = u64(sizeof(image))
		program[1].p_memsz = 16384
		program[1].p_align = 16384
		C.memcpy(&image[0], &header, sizeof(header))
		C.memcpy(&image[0] + sizeof(header), &program[0], sizeof(program))
		C.memcpy(&image[0] + program[0].p_offset, &interpreter[0], sizeof(interpreter))
		fd := C.open(c'/mac-private/dynamic', C.O_CREAT | C.O_WRONLY, i32(0o755))
		if fd < 0 { return -1 }
		result := C.write(fd, &image[0], sizeof(image))
		C.close(fd)
		return if result == isize(sizeof(image)) { i32(0) } else { i32(-1) }
	}
}

fn copy_program_to_memfd() i32 {
	unsafe {
		source := C.open(c'/sbin/init', C.O_RDONLY)
		if source < 0 { return -1 }
		target := i32(C.syscall(C.SYS_memfd_create, c'mac-program', i32(C.MFD_CLOEXEC)))
		if target < 0 {
			C.close(source)
			return -1
		}
		bytes := &char(C.__builtin_alloca(4096))
		mut length := isize(0)
		for {
			length = C.read(source, bytes, 4096)
			if length <= 0 { break }
			if C.write(target, bytes, usize(length)) != length {
				C.close(source)
				C.close(target)
				return -1
			}
		}
		C.close(source)
		if length < 0 || C.fchmod(target, 0o755) != 0 {
			C.close(target)
			return -1
		}
		return target
	}
}

@[export: 'vinix_mac_policy_close_exec_descriptor']
pub fn close_exec_descriptor(argument voidptr) voidptr {
	unsafe {
		descriptor := *(&i32(argument))
		C.usleep(50)
		C.close(descriptor)
		return nil
	}
}

// Copy into declared native scalars to preserve nominal variadic types without
// aliasing V's uint64_t/int64_t words as distinct native long-long types.
fn native_unsigned(value u64) C.mac_ull {
	unsafe {
		mut native := C.mac_ull{}
		C.memcpy(&native, &value, sizeof(native))
		return native
	}
}

fn native_signed(value i64) C.mac_ll {
	unsafe {
		mut native := C.mac_ll{}
		C.memcpy(&native, &value, sizeof(native))
		return native
	}
}

fn test_exec_descriptor_close() i32 {
	unsafe {
		mut successful := i32(0)
		status := &i32(C.__builtin_alloca(sizeof(i32)))
		for iteration := i32(0); iteration < 16; iteration++ {
			child := C.fork()
			if !require(child >= 0, 167, c'child >= 0') { return 1 }
			if child == 0 {
				mut descriptor := copy_program_to_memfd()
				if descriptor < 0 || control(3, 1, 0, 0) != 0 { C._exit(3) }
				closer := &C.pthread_t(C.__builtin_alloca(sizeof(C.pthread_t)))
				if C.pthread_create(closer, nil, C.vinix_mac_policy_close_exec_descriptor, &descriptor) != 0 {
					C._exit(4)
				}
				mut arguments := [&char(c'/sbin/init'), &char(c'exec-race'), &char(nil)]!
				C.syscall(C.SYS_execveat, descriptor, c'', &arguments[0], voidptr(nil), i32(C.AT_EMPTY_PATH))
				saved := C.errno
				if C.pthread_join(*closer, nil) != 0 { C._exit(5) }
				// The loader's looked-up image must survive closing the last descriptor.
				C._exit(if saved == C.EBADF && control(0, 0, 0, 0) == 0 { i32(2) } else { i32(6) })
			}
			if !require(C.waitpid(child, status, 0) == child && C.WIFEXITED(*status), 182, c'waitpid(child, &status, 0) == child && WIFEXITED(status)') {
				return 1
			}
			if !require(C.WEXITSTATUS(*status) == 0 || C.WEXITSTATUS(*status) == 2, 183, c'WEXITSTATUS(status) == 0 || WEXITSTATUS(status) == 2') {
				return 1
			}
			successful += i32(C.WEXITSTATUS(*status) == 0)
		}
		if !require(successful > 0, 186, c'successful > 0') { return 1 }
		C.printf(c'SECURITY MAC EXEC concurrent_close_successes=%d\n', successful)
		return 0
	}
}

fn denied_kernel_read(path &char) i32 {
	unsafe {
		fd := C.open(path, C.O_RDONLY)
		if fd < 0 { return i32(C.errno == C.EACCES || C.errno == C.EPERM) }
		bytes := C.__builtin_alloca(16)
		C.errno = 0
		denied := C.read(fd, bytes, 16) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM)
		C.close(fd)
		return i32(denied)
	}
}

fn send_fd(channel i32, descriptor i32) i32 {
	unsafe {
		mut byte := u8(`F`)
		mut vec := C.iovec{ iov_base: &byte, iov_len: 1 }
		mut raw := C.mac_cmsg_storage{}
		C.memset(&raw, 0, sizeof(raw))
		mut message := C.msghdr{}
		message.msg_iov = &vec
		message.msg_iovlen = 1
		message.msg_control = &raw.bytes[0]
		message.msg_controllen = u32(sizeof(raw.bytes))
		mut ancillary := C.CMSG_FIRSTHDR(&message)
		ancillary.cmsg_level = i32(C.SOL_SOCKET)
		ancillary.cmsg_type = i32(C.SCM_RIGHTS)
		ancillary.cmsg_len = u32(C.CMSG_LEN(sizeof(i32)))
		C.memcpy(C.CMSG_DATA(ancillary), &descriptor, sizeof(descriptor))
		return if C.sendmsg(channel, &message, 0) == 1 { i32(0) } else { i32(-1) }
	}
}

fn receive_fd(channel i32) i32 {
	unsafe {
		byte := C.__builtin_alloca(1)
		mut vec := C.iovec{ iov_base: byte, iov_len: 1 }
		mut raw := C.mac_cmsg_storage{}
		C.memset(&raw, 0, sizeof(raw))
		mut message := C.msghdr{}
		message.msg_iov = &vec
		message.msg_iovlen = 1
		message.msg_control = &raw.bytes[0]
		message.msg_controllen = u32(sizeof(raw.bytes))
		if C.recvmsg(channel, &message, 0) != 1 { return -1 }
		ancillary := C.CMSG_FIRSTHDR(&message)
		if ancillary == nil || ancillary.cmsg_type != C.SCM_RIGHTS || ancillary.cmsg_len != C.CMSG_LEN(sizeof(i32)) {
			return -1
		}
		descriptor := &i32(C.__builtin_alloca(sizeof(i32)))
		C.memcpy(descriptor, C.CMSG_DATA(ancillary), sizeof(i32))
		return *descriptor
	}
}

fn ipc_worker(source i32, sink i32) i32 {
	unsafe {
		if !require(control(0, 0, 0, 0) == 2, 250, c'control(0, 0, 0, 0) == 2') { return 1 }
		bytes := &char(C.__builtin_alloca(4))
		C.errno = 0
		if !require((C.read(source, bytes, 4)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 252, c'(read(source, bytes, sizeof(bytes))) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.write(sink, c'bad!', 4)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 253, c'(write(sink, "bad!", 4)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.syscall(C.SYS_tee, source, sink, 4, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 254, diagnostic_254()) {
			return 1
		}
		mut vector := C.iovec{ iov_base: voidptr(c'bad!'), iov_len: 4 }
		C.errno = 0
		if !require((C.syscall(C.SYS_vmsplice, sink, &vector, 1, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 256, diagnostic_256()) {
			return 1
		}
		return 0
	}
}

fn test_pipe_transfer_policy() i32 {
	unsafe {
		source := &i32(C.__builtin_alloca(2 * sizeof(i32)))
		sink := &i32(C.__builtin_alloca(2 * sizeof(i32)))
		if !require(C.pipe(source) == 0 && C.pipe2(sink, C.O_NONBLOCK) == 0, 263, c'pipe(source) == 0 && pipe2(sink, O_NONBLOCK) == 0') {
			return 1
		}
		if !require(C.write(source[1], c'data', 4) == 4, 264, c'write(source[1], "data", 4) == 4') {
			return 1
		}
		child := C.fork()
		if !require(child >= 0, 266, c'child >= 0') { return 1 }
		if child == 0 {
			input := &char(C.__builtin_alloca(32))
			output := &char(C.__builtin_alloca(32))
			C.snprintf(input, 32, c'%d', source[0])
			C.snprintf(output, 32, c'%d', sink[1])
			mut arguments := [&char(c'/sbin/init'), &char(c'ipc-worker'), input, output, &char(nil)]!
			if control(3, 2, 0, 0) != 0 { C._exit(2) }
			C.execv(c'/sbin/init', &arguments[0])
			C._exit(3)
		}
		status := &i32(C.__builtin_alloca(sizeof(i32)))
		if !require(C.waitpid(child, status, 0) == child && C.WIFEXITED(*status) && C.WEXITSTATUS(*status) == 0, 277, c'waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0') {
			return 1
		}
		bytes := &char(C.__builtin_alloca(4))
		if !require(C.read(source[0], bytes, 4) == 4 && C.memcmp(bytes, c'data', 4) == 0, 279, c'read(source[0], bytes, 4) == 4 && !memcmp(bytes, "data", 4)') {
			return 1
		}
		C.errno = 0
		if !require(C.read(sink[0], bytes, 4) == -1 && C.errno == C.EAGAIN, 280, c'read(sink[0], bytes, 4) == -1 && errno == EAGAIN') {
			return 1
		}
		C.close(source[0])
		C.close(source[1])
		C.close(sink[0])
		C.close(sink[1])
		C.puts(c'SECURITY MAC IPC pipe transfers denied')
		return 0
	}
}

fn worker(secret_fd i32, readonly_fd i32, channel i32, parent i32, address usize, repeated i32) i32 {
	unsafe {
		if !require(C.geteuid() == 0, 288, c'geteuid() == 0') { return 1 }
		if !require(control(0, 0, 0, 0) == 1, 289, c'control(0, 0, 0, 0) == 1') { return 1 }
		if !require(control(4, 0, 0, 0) == 1, 290, c'control(4, 0, 0, 0) == 1') { return 1 }
		resident := &u8(C.__builtin_alloca(1))
		C.errno = 0
		if !require(C.mincore(voidptr(usize(0x680000000000)), 16384, resident) == -1 && C.errno == C.ENOMEM, 292, c'mincore(OLD_MAP, 16384, &resident) == -1 && errno == ENOMEM') {
			return 1
		}
		C.errno = 0
		if !require((control(1, 1, 2, all)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 293, c'(control(1, 1, 2, 511U)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((control(3, 2, 0, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 294, c'(control(3, 2, 0, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((control(2, 0, 0, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 295, c'(control(2, 0, 0, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((label(c'/mac-private', c'0')) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 296, c'(label("/mac-private", "0")) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.removexattr(c'/mac-private', c'security.vinix')) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 297, c'(removexattr("/mac-private", "security.vinix")) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		buffer := &char(C.__builtin_alloca(16))
		metadata := &C.stat(C.__builtin_alloca(sizeof(C.stat)))
		C.errno = 0
		if !require((C.read(secret_fd, buffer, 16)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 301, c'(read(secret_fd, buffer, sizeof(buffer))) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.pread(secret_fd, buffer, 16, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 302, c'(pread(secret_fd, buffer, sizeof(buffer), 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.write(secret_fd, c'bad', 3)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 303, c'(write(secret_fd, "bad", 3)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.pwrite(secret_fd, c'bad', 3, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 304, c'(pwrite(secret_fd, "bad", 3, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.ftruncate(secret_fd, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 305, c'(ftruncate(secret_fd, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.fchmod(secret_fd, 0o777)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 306, c'(fchmod(secret_fd, 0777)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.fchown(secret_fd, 0, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 307, c'(fchown(secret_fd, 0, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.fstat(secret_fd, metadata)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 308, c'(fstat(secret_fd, &metadata)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.fstatat(secret_fd, c'', metadata, C.AT_EMPTY_PATH)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 309, c'(fstatat(secret_fd, "", &metadata, 0x1000)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.lseek(secret_fd, 0, C.SEEK_END)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 310, c'(lseek(secret_fd, 0, 2)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.flock(secret_fd, C.LOCK_EX | C.LOCK_NB)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 311, c'(flock(secret_fd, 2 | 4)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.fgetxattr(secret_fd, c'security.vinix', buffer, 16)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 312, c'(fgetxattr(secret_fd, "security.vinix", buffer, sizeof(buffer))) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.flistxattr(secret_fd, buffer, 16)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 313, c'(flistxattr(secret_fd, buffer, sizeof(buffer))) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.fsetxattr(secret_fd, c'user.x', c'x', 1, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 314, c'(fsetxattr(secret_fd, "user.x", "x", 1, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.futimens(secret_fd, nil)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 315, c'(futimens(secret_fd, ((void*)0))) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		mut flags := i32(0)
		C.errno = 0
		if !require((C.ioctl(secret_fd, u64(0x80086601), &flags)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 317, c'(ioctl(secret_fd, 0x80086601UL, &flags)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require(C.mmap(nil, 16384, C.PROT_NONE, C.MAP_PRIVATE, secret_fd, 0) == voidptr(C.MAP_FAILED) && C.errno == C.EACCES, 319, c'mmap(NULL, 16384, PROT_NONE, MAP_PRIVATE, secret_fd, 0) == MAP_FAILED && errno == EACCES') {
			return 1
		}
		duplicate := C.dup(secret_fd)
		if !require(duplicate >= 0, 321, c'duplicate >= 0') { return 1 }
		C.errno = 0
		if !require((C.read(duplicate, buffer, 1)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 322, c'(read(duplicate, buffer, 1)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.close(duplicate)
		C.errno = 0
		if !require((C.open(c'/mac-private/secret-alias', C.O_RDONLY)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 324, c'(open("/mac-private/secret-alias", 00)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.open(c'/mac-bind/secret', C.O_RDONLY)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 325, c'(open("/mac-bind/secret", 00)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.open(c'/mac-private/secret-symlink', C.O_RDONLY)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 326, c'(open("/mac-private/secret-symlink", 00)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.open(c'/mac-private/denied-link', C.O_RDONLY)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 327, c'(open("/mac-private/denied-link", 00)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.readlink(c'/mac-private/denied-link', buffer, 16)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 328, c'(readlink("/mac-private/denied-link", buffer, sizeof(buffer))) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.open(c'/mac-private/denied-directory/public', C.O_RDONLY)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 329, c'(open("/mac-private/denied-directory/public", 00)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.link(c'/mac-private/secret-alias', c'/mac-private/linked')) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 330, c'(link("/mac-private/secret-alias", "/mac-private/linked")) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.unlink(c'/mac-private/secret-alias')) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 331, c'(unlink("/mac-private/secret-alias")) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.rename(c'/mac-private/secret-alias', c'/mac-private/moved')) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 332, c'(rename("/mac-private/secret-alias", "/mac-private/moved")) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.rename(c'/mac-private/replace', c'/mac-private/secret-alias')) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 333, c'(rename("/mac-private/replace", "/mac-private/secret-alias")) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.access(c'/mac-private/secret-alias', C.R_OK)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 334, c'(access("/mac-private/secret-alias", 4)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.open(c'/mac-secret/new', C.O_CREAT | C.O_WRONLY, 0o600)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 335, c'(open("/mac-secret/new", 0100 | 01, 0600)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}

		if !require(C.pread(readonly_fd, buffer, 6, 0) == 6 && C.memcmp(buffer, c'public', 6) == 0, 337, c'pread(readonly_fd, buffer, 6, 0) == 6 && memcmp(buffer, "public", 6) == 0') {
			return 1
		}
		if !require(C.fstat(readonly_fd, metadata) == 0, 338, c'fstat(readonly_fd, &metadata) == 0') {
			return 1
		}
		C.errno = 0
		if !require((C.write(readonly_fd, c'bad', 3)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 339, c'(write(readonly_fd, "bad", 3)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.pwrite(readonly_fd, c'bad', 3, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 340, c'(pwrite(readonly_fd, "bad", 3, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.ftruncate(readonly_fd, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 341, c'(ftruncate(readonly_fd, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.fchmod(readonly_fd, 0o777)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 342, c'(fchmod(readonly_fd, 0777)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.open(c'/mac-readonly/public', C.O_TRUNC | C.O_WRONLY)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 343, c'(open("/mac-readonly/public", 01000 | 01)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.unlink(c'/mac-readonly/public')) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 344, c'(unlink("/mac-readonly/public")) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.link(c'/mac-readonly/public', c'/mac-private/ro-linked')) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 345, c'(link("/mac-readonly/public", "/mac-private/ro-linked")) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		mut mapped := C.mmap(nil, 16384, C.PROT_READ, C.MAP_SHARED, readonly_fd, 0)
		if !require(mapped != voidptr(C.MAP_FAILED), 347, c'mapped != MAP_FAILED') { return 1 }
		C.errno = 0
		if !require((C.mprotect(mapped, 16384, C.PROT_READ | C.PROT_WRITE)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 348, c'(mprotect(mapped, 16384, 1 | 2)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.mprotect(mapped, 16384, C.PROT_READ | C.PROT_EXEC)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 349, c'(mprotect(mapped, 16384, 1 | 4)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		if !require(C.munmap(mapped, 16384) == 0, 350, c'munmap(mapped, 16384) == 0') { return 1 }
		mapped = C.mmap(nil, 16384, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE, readonly_fd, 0)
		if !require(mapped != voidptr(C.MAP_FAILED), 352, c'mapped != MAP_FAILED') { return 1 }
		if !require(C.munmap(mapped, 16384) == 0, 353, c'munmap(mapped, 16384) == 0') { return 1 }
		output := C.open(c'/mac-private/output', C.O_CREAT | C.O_RDWR | C.O_TRUNC, i32(0o600))
		if !require(output >= 0, 356, c'output >= 0') { return 1 }
		if !require(C.write(output, c'owned', 5) == 5, 357, c'write(output, "owned", 5) == 5') {
			return 1
		}
		if !require(C.getxattr(c'/mac-private/output', c'security.vinix', buffer, 16) == 1 && buffer[0] == char(`1`), 358, c'getxattr("/mac-private/output", "security.vinix", buffer, sizeof(buffer)) == 1 && buffer[0] == \'1\'') {
			return 1
		}
		if !require(C.mkdir(c'/mac-private/created', 0o700) == 0 || C.errno == C.EEXIST, 359, c'mkdir("/mac-private/created", 0700) == 0 || errno == EEXIST') {
			return 1
		}
		if !require(C.getxattr(c'/mac-private/created', c'security.vinix', buffer, 16) == 1 && buffer[0] == char(`1`), 360, c'getxattr("/mac-private/created", "security.vinix", buffer, sizeof(buffer)) == 1 && buffer[0] == \'1\'') {
			return 1
		}
		if !require(C.link(c'/mac-private/output', c'/mac-private/outlink') == 0 || C.errno == C.EEXIST, 361, c'link("/mac-private/output", "/mac-private/outlink") == 0 || errno == EEXIST') {
			return 1
		}
		if !require(C.rename(c'/mac-private/outlink', c'/mac-private/movedlink') == 0, 362, c'rename("/mac-private/outlink", "/mac-private/movedlink") == 0') {
			return 1
		}
		if !require(C.unlink(c'/mac-private/movedlink') == 0, 363, c'unlink("/mac-private/movedlink") == 0') {
			return 1
		}
		if !require(C.symlink(c'output', c'/mac-private/symlink') == 0 || C.errno == C.EEXIST, 364, c'symlink("output", "/mac-private/symlink") == 0 || errno == EEXIST') {
			return 1
		}
		if !require(C.lgetxattr(c'/mac-private/symlink', c'security.vinix', buffer, 16) == 1 && buffer[0] == char(`1`), 365, c'lgetxattr("/mac-private/symlink", "security.vinix", buffer, sizeof(buffer)) == 1 && buffer[0] == \'1\'') {
			return 1
		}

		overlay := C.open(c'/mac-overlay/owned', C.O_RDWR)
		if !require(overlay >= 0 && C.write(overlay, c'up', 2) == 2, 368, c'overlay >= 0 && write(overlay, "up", 2) == 2') {
			return 1
		}
		if !require(C.fgetxattr(overlay, c'security.vinix', buffer, 16) == 1 && buffer[0] == char(`1`), 369, c'fgetxattr(overlay, "security.vinix", buffer, sizeof(buffer)) == 1 && buffer[0] == \'1\'') {
			return 1
		}
		C.close(overlay)
		C.errno = 0
		if !require((C.open(c'/mac-overlay/secret', C.O_RDWR)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 371, c'(open("/mac-overlay/secret", 02)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require(C.open(c'/mac-upper/secret', C.O_RDONLY) == -1 && C.errno == C.ENOENT, 372, c'open("/mac-upper/secret", O_RDONLY) == -1 && errno == ENOENT') {
			return 1
		}
		mut from := i64(0)
		mut to := i64(0)
		C.errno = 0
		if !require((C.syscall(C.SYS_copy_file_range, secret_fd, &from, output, &to, 3, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 375, diagnostic_375()) {
			return 1
		}
		from = 0
		to = 0
		C.errno = 0
		if !require((C.syscall(C.SYS_copy_file_range, readonly_fd, &from, secret_fd, &to, 3, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 377, diagnostic_377()) {
			return 1
		}
		pipes := &i32(C.__builtin_alloca(2 * sizeof(i32)))
		if !require(C.pipe(pipes) == 0, 379, c'pipe(pipes) == 0') { return 1 }
		C.errno = 0
		if !require((C.fstat(pipes[0], metadata)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 380, c'(fstat(pipes[0], &metadata)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		anonymous_path := &char(C.__builtin_alloca(64))
		C.snprintf(anonymous_path, 64, c'/proc/self/fd/%d', pipes[0])
		C.errno = 0
		if !require((C.stat(anonymous_path, metadata)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 383, c'(stat(anonymous_path, &metadata)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		from = 0
		C.errno = 0
		if !require((C.splice(secret_fd, &from, pipes[1], nil, 3, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 385, c'(splice(secret_fd, &from, pipes[1], ((void*)0), 3, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		if !require(C.write(pipes[1], c'bad', 3) == 3, 386, c'write(pipes[1], "bad", 3) == 3') {
			return 1
		}
		to = 0
		C.errno = 0
		if !require((C.splice(pipes[0], nil, readonly_fd, &to, 3, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 388, c'(splice(pipes[0], ((void*)0), readonly_fd, &to, 3, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.close(pipes[0])
		C.close(pipes[1])
		C.close(output)
		if !require(C.kill(parent, 0) == -1 && C.errno == C.EPERM, 391, c'kill(parent, 0) == -1 && errno == EPERM') {
			return 1
		}
		proc_path := &char(C.__builtin_alloca(64))
		C.snprintf(proc_path, 64, c'/proc/%d/maps', parent)
		proc_fd := C.open(proc_path, C.O_RDONLY)
		if proc_fd >= 0 {
			C.errno = 0
			if !require((C.read(proc_fd, buffer, 16)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 395, c'(read(proc_fd, buffer, sizeof(buffer))) == -1 && (errno == EACCES || errno == EPERM)') {
				return 1
			}
			C.close(proc_fd)
		} else {
			if !require(C.errno == C.EACCES || C.errno == C.EPERM, 396, c'errno == EACCES || errno == EPERM') {
				return 1
			}
		}
		mut local := C.iovec{ iov_base: buffer, iov_len: 1 }
		mut remote := C.iovec{ iov_base: voidptr(address), iov_len: 1 }
		C.errno = 0
		if !require((C.process_vm_readv(parent, &local, 1, &remote, 1, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 398, c'(process_vm_readv(parent, &local, 1, &remote, 1, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.mount(c'tmpfs', c'/mac-private', c'tmpfs', 0, nil)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 399, c'(mount("tmpfs", "/mac-private", "tmpfs", 0, ((void*)0))) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.mknod(c'/mac-private/device', C.S_IFBLK | 0o600, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 400, c'(mknod("/mac-private/device", 0060000 | 0600, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.open(c'/mac-private/raw', C.O_RDONLY)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 401, c'(open("/mac-private/raw", 00)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		mut bad_argv := [&char(c'/mac-private/exec-denied'), &char(nil)]!
		C.errno = 0
		if !require((C.execv(c'/mac-private/exec-denied', &bad_argv[0])) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 403, c'(execv("/mac-private/exec-denied", bad_argv)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.execv(c'/mac-private/shebang', &bad_argv[0])) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 404, c'(execv("/mac-private/shebang", bad_argv)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.execv(c'/mac-private/dynamic', &bad_argv[0])) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 405, c'(execv("/mac-private/dynamic", bad_argv)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.execv(c'/mac-private/denied-executable', &bad_argv[0])) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 406, c'(execv("/mac-private/denied-executable", bad_argv)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.sethostname(c'confined', 8)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 407, c'(sethostname("confined", 8)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		if !require(denied_kernel_read(c'/proc/security_audit') != 0, 408, c'denied_kernel_read("/proc/security_audit")') {
			return 1
		}
		mut limit := C.rlimit{ rlim_cur: 128, rlim_max: 128 }
		old_limit := &C.rlimit(C.__builtin_alloca(sizeof(C.rlimit)))
		C.errno = 0
		if !require((C.prlimit(parent, C.RLIMIT_NOFILE, nil, old_limit)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 410, c'(prlimit(parent, 7, ((void*)0), &old_limit)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.prlimit(parent, C.RLIMIT_NOFILE, &limit, nil)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 411, c'(prlimit(parent, 7, &limit, ((void*)0))) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.setpriority(C.PRIO_PROCESS, u32(parent), 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 412, c'(setpriority(0, (id_t)parent, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.getpriority(C.PRIO_PROCESS, u32(parent))) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 413, c'(getpriority(0, (id_t)parent)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		if !require(C.prlimit(0, C.RLIMIT_NOFILE, nil, old_limit) == 0, 414, c'prlimit(0, RLIMIT_NOFILE, NULL, &old_limit) == 0') {
			return 1
		}
		C.errno = 0
		if !require(C.getpriority(C.PRIO_PROCESS, 0) == 0 && C.errno == 0, 415, c'getpriority(PRIO_PROCESS, 0) == 0 && errno == 0') {
			return 1
		}
		if !require(C.setpriority(C.PRIO_PROCESS, 0, 0) == 0, 416, c'setpriority(PRIO_PROCESS, 0, 0) == 0') {
			return 1
		}
		mut parameters := C.sched_param{}
		C.errno = 0
		if !require((C.syscall(C.SYS_sched_getscheduler, parent)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 418, diagnostic_418()) {
			return 1
		}
		C.errno = 0
		if !require((C.syscall(C.SYS_sched_getparam, parent, &parameters)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 419, diagnostic_419()) {
			return 1
		}
		C.errno = 0
		if !require((C.syscall(C.SYS_sched_setscheduler, parent, C.SCHED_OTHER, &parameters)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 420, diagnostic_420()) {
			return 1
		}
		C.errno = 0
		if !require((C.syscall(C.SYS_sched_setparam, parent, &parameters)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 421, diagnostic_421()) {
			return 1
		}
		if !require(C.syscall(C.SYS_sched_getscheduler, 0) == C.SCHED_OTHER, 422, c'syscall(SYS_sched_getscheduler, 0) == SCHED_OTHER') {
			return 1
		}
		if !require(C.syscall(C.SYS_sched_getparam, 0, &parameters) == 0, 423, c'syscall(SYS_sched_getparam, 0, &parameters) == 0') {
			return 1
		}
		if !require(C.syscall(C.SYS_sched_setscheduler, 0, C.SCHED_OTHER, &parameters) == 0, 424, c'syscall(SYS_sched_setscheduler, 0, SCHED_OTHER, &parameters) == 0') {
			return 1
		}
		mut scheduling := C.mac_sched_attr{ size: u32(sizeof(C.mac_sched_attr)) }
		C.errno = 0
		if !require((C.syscall(C.SYS_sched_getattr, parent, &scheduling, sizeof(C.mac_sched_attr), 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 426, diagnostic_426()) {
			return 1
		}
		C.errno = 0
		if !require((C.syscall(C.SYS_sched_setattr, parent, &scheduling, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 427, diagnostic_427()) {
			return 1
		}
		scheduling.policy = 6
		scheduling.runtime = 1000
		scheduling.deadline = 1000000
		scheduling.period = 1000000
		C.errno = 0
		if !require((C.syscall(C.SYS_sched_setattr, parent, &scheduling, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 429, diagnostic_429()) {
			return 1
		}
		affinity := &C.cpu_set_t(C.__builtin_alloca(sizeof(C.cpu_set_t)))
		C.CPU_ZERO(affinity)
		C.CPU_SET(0, affinity)
		C.errno = 0
		if !require((C.sched_getaffinity(parent, sizeof(C.cpu_set_t), affinity)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 432, c'(sched_getaffinity(parent, sizeof(affinity), &affinity)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.sched_setaffinity(parent, sizeof(C.cpu_set_t), affinity)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 433, c'(sched_setaffinity(parent, sizeof(affinity), &affinity)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		if !require(C.sched_getaffinity(0, sizeof(C.cpu_set_t), affinity) == 0, 434, c'sched_getaffinity(0, sizeof(affinity), &affinity) == 0') {
			return 1
		}
		if !require(C.sched_setaffinity(0, sizeof(C.cpu_set_t), affinity) == 0, 435, c'sched_setaffinity(0, sizeof(affinity), &affinity) == 0') {
			return 1
		}
		robust_head := &voidptr(C.__builtin_alloca(sizeof(voidptr)))
		robust_length := &usize(C.__builtin_alloca(sizeof(usize)))
		C.errno = 0
		if !require((C.syscall(C.SYS_get_robust_list, parent, robust_head, robust_length)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 438, diagnostic_438()) {
			return 1
		}
		if !require(C.syscall(C.SYS_get_robust_list, 0, robust_head, robust_length) == 0, 439, c'syscall(SYS_get_robust_list, 0, &robust_head, &robust_length) == 0') {
			return 1
		}
		C.errno = 0
		if !require((C.getpgid(parent)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 440, c'(getpgid(parent)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.setpgid(parent, parent)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 441, c'(setpgid(parent, parent)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		if !require(C.getpgid(0) >= 0, 442, c'getpgid(0) >= 0') { return 1 }
		if repeated == 0 {
			mut passed := receive_fd(channel)
			if !require(passed >= 0, 446, c'passed >= 0') { return 1 }
			C.errno = 0
			if !require((C.read(passed, buffer, 1)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 447, c'(read(passed, buffer, 1)) == -1 && (errno == EACCES || errno == EPERM)') {
				return 1
			}
			C.close(passed)
			passed = receive_fd(channel)
			if !require(passed >= 0, 450, c'passed >= 0') { return 1 }
			C.errno = 0
			if !require((C.read(passed, buffer, 16)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 451, c'(read(passed, buffer, sizeof(buffer))) == -1 && (errno == EACCES || errno == EPERM)') {
				return 1
			}
			C.errno = 0
			if !require((C.inotify_rm_watch(passed, 1)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 452, c'(inotify_rm_watch(passed, 1)) == -1 && (errno == EACCES || errno == EPERM)') {
				return 1
			}
			C.errno = 0
			if !require((C.inotify_add_watch(passed, c'/mac-private', C.IN_CREATE)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 453, c'(inotify_add_watch(passed, "/mac-private", 0x00000100)) == -1 && (errno == EACCES || errno == EPERM)') {
				return 1
			}
			C.close(passed)
			passed = receive_fd(channel)
			if !require(passed >= 0, 456, c'passed >= 0') { return 1 }
			mut memfd_arguments := [&char(c'mac-denied'), &char(nil)]!
			C.errno = 0
			if !require((C.syscall(C.SYS_execveat, passed, c'', &memfd_arguments[0], nil, C.AT_EMPTY_PATH)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 458, diagnostic_458()) {
				return 1
			}
			C.close(passed)
			passed = receive_fd(channel)
			if !require(passed >= 0 && C.lseek(passed, 0, C.SEEK_SET) == 0, 461, c'passed >= 0 && lseek(passed, 0, SEEK_SET) == 0') {
				return 1
			}
			C.errno = 0
			if !require((C.read(passed, buffer, 16)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 462, c'(read(passed, buffer, sizeof(buffer))) == -1 && (errno == EACCES || errno == EPERM)') {
				return 1
			}
			C.close(passed)
			for i := i32(0); i < 20; i++ {
				if !require(slab_bytes() != ~u64(0), 464, c'slab_bytes() != ~0ULL') { return 1 }
			}
			mut before := slab_bytes()
			for i := i32(0); i < 1000; i++ {
				repeated_fd := C.open(c'/mac-private/output', C.O_RDONLY)
				if !require(repeated_fd >= 0 && C.read(repeated_fd, buffer, 5) == 5, 468, c'repeated_fd >= 0 && read(repeated_fd, buffer, 5) == 5') {
					return 1
				}
				C.close(repeated_fd)
				C.errno = 0
				if !require((C.pread(secret_fd, buffer, 1, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 470, c'(pread(secret_fd, buffer, 1, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
					return 1
				}
				if !require(C.pread(readonly_fd, buffer, 6, 0) == 6, 471, c'pread(readonly_fd, buffer, 6, 0) == 6') {
					return 1
				}
				C.errno = 0
				if !require((C.prlimit(parent, C.RLIMIT_NOFILE, nil, old_limit)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 472, c'(prlimit(parent, 7, ((void*)0), &old_limit)) == -1 && (errno == EACCES || errno == EPERM)') {
					return 1
				}
				if !require(C.prlimit(0, C.RLIMIT_NOFILE, nil, old_limit) == 0, 473, c'prlimit(0, RLIMIT_NOFILE, NULL, &old_limit) == 0') {
					return 1
				}
				C.errno = 0
				if !require((C.syscall(C.SYS_get_robust_list, parent, robust_head, robust_length)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 474, diagnostic_474()) {
					return 1
				}
				if !require(C.syscall(C.SYS_sched_getscheduler, 0) == C.SCHED_OTHER, 475, c'syscall(SYS_sched_getscheduler, 0) == SCHED_OTHER') {
					return 1
				}
			}
			mut after := slab_bytes()
			C.printf(c'SECURITY MAC OPS retained_bytes=%lld\n', native_signed(i64(after - before)))
			if !require(after <= before + 1024, 479, c'after <= before + 1024') { return 1 }
			// The original 512-byte-class check isolates the stored FIFO interface box.
			for i := i32(0); i < 20; i++ {
				if !require(C.mkfifo(c'/mac-private/temporary-fifo', 0o600) == 0, 484, c'mkfifo("/mac-private/temporary-fifo", 0600) == 0') {
					return 1
				}
				if !require(C.unlink(c'/mac-private/temporary-fifo') == 0, 485, c'unlink("/mac-private/temporary-fifo") == 0') {
					return 1
				}
			}
			before = slab_class_bytes(512)
			for i := i32(0); i < 200; i++ {
				if !require(C.mkfifo(c'/mac-private/temporary-fifo', 0o600) == 0, 489, c'mkfifo("/mac-private/temporary-fifo", 0600) == 0') {
					return 1
				}
				if !require(C.unlink(c'/mac-private/temporary-fifo') == 0, 490, c'unlink("/mac-private/temporary-fifo") == 0') {
					return 1
				}
			}
			after = slab_class_bytes(512)
			C.printf(c'SECURITY MAC FIFO interface_bytes=%lld\n', native_signed(i64(after - before)))
			if !require(after <= before + 512, 494, c'after <= before + 512') { return 1 }
			nested := C.fork()
			if !require(nested >= 0, 496, c'nested >= 0') { return 1 }
			if nested == 0 {
				if control(0, 0, 0, 0) != 1 || C.pread(secret_fd, buffer, 1, 0) != -1 || C.errno != C.EACCES {
					C._exit(1)
				}
				C._exit(0)
			}
			status := &i32(C.__builtin_alloca(sizeof(i32)))
			if !require(C.waitpid(nested, status, 0) == nested && C.WIFEXITED(*status) && C.WEXITSTATUS(*status) == 0, 502, c'waitpid(nested, &status, 0) == nested && WIFEXITED(status) && WEXITSTATUS(status) == 0') {
				return 1
			}
			a := &char(C.__builtin_alloca(32))
			b := &char(C.__builtin_alloca(32))
			c := &char(C.__builtin_alloca(32))
			d := &char(C.__builtin_alloca(32))
			e := &char(C.__builtin_alloca(32))
			C.snprintf(a, 32, c'%d', secret_fd)
			C.snprintf(b, 32, c'%d', readonly_fd)
			C.snprintf(c, 32, c'%d', channel)
			C.snprintf(d, 32, c'%d', parent)
			C.snprintf(e, 32, c'%llu', native_unsigned(u64(address)))
			mut args := [&char(c'/sbin/init'), &char(c'worker-again'), a, b, c, d, e, &char(nil)]!
			C.execv(c'/sbin/init', &args[0])
			if !require(false, 512, c'0') { return 1 }
		}
		C.close(secret_fd)
		C.close(readonly_fd)
		C.close(channel)
		return 0
	}
}

@[export: 'main']
pub fn entry(argc i32, argv &&char) i32 {
	unsafe {
		C.setbuf(C.stdout, nil)
		if argc == 4 && C.strcmp(argv[1], c'ipc-worker') == 0 {
			C._exit(ipc_worker(C.atoi(argv[2]), C.atoi(argv[3])))
		}
		if argc == 2 && C.strcmp(argv[1], c'exec-race') == 0 {
			C._exit(if control(0, 0, 0, 0) == 1 { i32(0) } else { i32(1) })
		}
		if argc == 7 && (C.strcmp(argv[1], c'worker') == 0 || C.strcmp(argv[1], c'worker-again') == 0) {
			result := worker(C.atoi(argv[2]), C.atoi(argv[3]), C.atoi(argv[4]), C.atoi(argv[5]), usize(C.strtoull(argv[6], nil, 10)), i32(C.strcmp(argv[1], c'worker-again') == 0))
			C._exit(result)
		}
		if !require(control(0, 0, 0, 0) == 0, 528, c'control(0, 0, 0, 0) == 0') { return 1 }
		if !require(control(4, 0, 0, 0) == 0, 529, c'control(4, 0, 0, 0) == 0') { return 1 }
		C.errno = 0
		if !require((control(3, 1, 0, 0)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 530, c'(control(3, 1, 0, 0)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		if !require(C.mkdir(c'/mac-private', 0o700) == 0, 531, c'mkdir("/mac-private", 0700) == 0') {
			return 1
		}
		if !require(C.mkdir(c'/mac-secret', 0o700) == 0, 532, c'mkdir("/mac-secret", 0700) == 0') {
			return 1
		}
		if !require(C.mkdir(c'/mac-readonly', 0o700) == 0, 533, c'mkdir("/mac-readonly", 0700) == 0') {
			return 1
		}
		if !require(C.mkdir(c'/mac-bind', 0o700) == 0, 534, c'mkdir("/mac-bind", 0700) == 0') {
			return 1
		}
		if !require(label(c'/mac-private', c'1') == 0, 535, c'label("/mac-private", "1") == 0') {
			return 1
		}
		if !require(label(c'/mac-secret', c'2') == 0, 536, c'label("/mac-secret", "2") == 0') {
			return 1
		}
		if !require(label(c'/mac-readonly', c'3') == 0, 537, c'label("/mac-readonly", "3") == 0') {
			return 1
		}
		C.errno = 0
		if !require(label(c'/mac-private', c'01') == -1 && C.errno == C.EINVAL, 538, c'label("/mac-private", "01") == -1 && errno == EINVAL') {
			return 1
		}
		C.errno = 0
		if !require(label(c'/mac-private', c'31') == -1 && C.errno == C.EINVAL, 539, c'label("/mac-private", "31") == -1 && errno == EINVAL') {
			return 1
		}
		C.errno = 0
		if !require(label(c'/mac-private', c'malformed') == -1 && C.errno == C.EINVAL, 540, c'label("/mac-private", "malformed") == -1 && errno == EINVAL') {
			return 1
		}
		if !require(contents(c'/mac-secret/secret', c'secret') == 0, 541, c'contents("/mac-secret/secret", "secret") == 0') {
			return 1
		}
		if !require(contents(c'/mac-readonly/public', c'public') == 0, 542, c'contents("/mac-readonly/public", "public") == 0') {
			return 1
		}
		if !require(contents(c'/mac-private/replace', c'replace') == 0, 543, c'contents("/mac-private/replace", "replace") == 0') {
			return 1
		}
		if !require(contents(c'/mac-private/exec-denied', c'not an executable') == 0, 544, c'contents("/mac-private/exec-denied", "not an executable") == 0') {
			return 1
		}
		if !require(label(c'/mac-private/exec-denied', c'4') == 0, 545, c'label("/mac-private/exec-denied", "4") == 0') {
			return 1
		}
		if !require(contents(c'/mac-private/shebang', c'#!/mac-private/exec-denied\n') == 0, 546, c'contents("/mac-private/shebang", "#!/mac-private/exec-denied\\n") == 0') {
			return 1
		}
		if !require(prepare_interpreter_test() == 0, 547, c'prepare_interpreter_test() == 0') {
			return 1
		}
		if !require(C.mknod(c'/mac-private/raw', C.S_IFBLK | 0o600, 0) == 0, 548, c'mknod("/mac-private/raw", S_IFBLK | 0600, 0) == 0') {
			return 1
		}
		if !require(C.link(c'/mac-secret/secret', c'/mac-private/secret-alias') == 0, 549, c'link("/mac-secret/secret", "/mac-private/secret-alias") == 0') {
			return 1
		}
		if !require(C.symlink(c'/mac-secret/secret', c'/mac-private/secret-symlink') == 0, 550, c'symlink("/mac-secret/secret", "/mac-private/secret-symlink") == 0') {
			return 1
		}
		if !require(C.symlink(c'/mac-readonly/public', c'/mac-private/denied-link') == 0, 551, c'symlink("/mac-readonly/public", "/mac-private/denied-link") == 0') {
			return 1
		}
		if !require(C.symlink(c'/mac-readonly', c'/mac-private/denied-directory') == 0, 552, c'symlink("/mac-readonly", "/mac-private/denied-directory") == 0') {
			return 1
		}
		if !require(C.symlink(c'/sbin/init', c'/mac-private/denied-executable') == 0, 553, c'symlink("/sbin/init", "/mac-private/denied-executable") == 0') {
			return 1
		}
		if !require(C.lsetxattr(c'/mac-private/denied-link', c'security.vinix', c'2', 1, 0) == 0, 554, c'lsetxattr("/mac-private/denied-link", "security.vinix", "2", 1, 0) == 0') {
			return 1
		}
		if !require(C.lsetxattr(c'/mac-private/denied-directory', c'security.vinix', c'2', 1, 0) == 0, 555, c'lsetxattr("/mac-private/denied-directory", "security.vinix", "2", 1, 0) == 0') {
			return 1
		}
		if !require(C.lsetxattr(c'/mac-private/denied-executable', c'security.vinix', c'2', 1, 0) == 0, 556, c'lsetxattr("/mac-private/denied-executable", "security.vinix", "2", 1, 0) == 0') {
			return 1
		}
		if !require(C.mount(c'/mac-secret', c'/mac-bind', nil, C.MS_BIND, nil) == 0, 557, c'mount("/mac-secret", "/mac-bind", NULL, MS_BIND, NULL) == 0') {
			return 1
		}
		if !require(C.mkdir(c'/mac-lower', 0o700) == 0, 558, c'mkdir("/mac-lower", 0700) == 0') {
			return 1
		}
		if !require(C.mkdir(c'/mac-upper', 0o700) == 0, 559, c'mkdir("/mac-upper", 0700) == 0') {
			return 1
		}
		if !require(C.mkdir(c'/mac-work', 0o700) == 0, 560, c'mkdir("/mac-work", 0700) == 0') {
			return 1
		}
		if !require(C.mkdir(c'/mac-overlay', 0o700) == 0, 561, c'mkdir("/mac-overlay", 0700) == 0') {
			return 1
		}
		if !require(label(c'/mac-lower', c'1') == 0, 562, c'label("/mac-lower", "1") == 0') {
			return 1
		}
		if !require(label(c'/mac-upper', c'1') == 0, 563, c'label("/mac-upper", "1") == 0') {
			return 1
		}
		if !require(label(c'/mac-work', c'1') == 0, 564, c'label("/mac-work", "1") == 0') {
			return 1
		}
		if !require(contents(c'/mac-lower/owned', c'lower') == 0, 565, c'contents("/mac-lower/owned", "lower") == 0') {
			return 1
		}
		if !require(contents(c'/mac-lower/secret', c'secret') == 0, 566, c'contents("/mac-lower/secret", "secret") == 0') {
			return 1
		}
		if !require(label(c'/mac-lower/secret', c'2') == 0, 567, c'label("/mac-lower/secret", "2") == 0') {
			return 1
		}
		if !require(C.mount(c'overlay', c'/mac-overlay', c'overlay', 0,
			c'lowerdir=/mac-lower,upperdir=/mac-upper,workdir=/mac-work') == 0, diagnostic_mount_line(), c'mount("overlay", "/mac-overlay", "overlay", 0, "lowerdir=/mac-lower,upperdir=/mac-upper,workdir=/mac-work") == 0') {
			return 1
		}

		userns := C.fork()
		if !require(userns >= 0, 572, c'userns >= 0') { return 1 }
		if userns == 0 {
			if C.unshare(C.CLONE_NEWUSER) != 0 { C._exit(2) }
			C.errno = 0
			if label(c'/mac-private', c'0') != -1 || C.errno != C.EPERM { C._exit(3) }
			C.errno = 0
			if control(1, 1, 2, all) != -1 || C.errno != C.EPERM { C._exit(4) }
			C._exit(0)
		}
		status := &i32(C.__builtin_alloca(sizeof(i32)))
		if !require(C.waitpid(userns, status, 0) == userns && C.WIFEXITED(*status) && C.WEXITSTATUS(*status) == 0, 582, c'waitpid(userns, &status, 0) == userns && WIFEXITED(status) && WEXITSTATUS(status) == 0') {
			return 1
		}
		if !require(control(1, 1, 0, inspect | read_mask | execute_mask | search) == 0, 583, c'control(1, 1, 0, INSPECT | READ | EXECUTE | SEARCH) == 0') {
			return 1
		}
		if !require(control(1, 1, 1, all) == 0, 584, c'control(1, 1, 1, ALL) == 0') { return 1 }
		if !require(control(1, 1, 3, inspect | read_mask | search) == 0, 585, c'control(1, 1, 3, INSPECT | READ | SEARCH) == 0') {
			return 1
		}
		if !require(control(1, 1, 29, all & ~inspect) == 0, 586, c'control(1, 1, 29, ALL & ~INSPECT) == 0') {
			return 1
		}
		if !require(control(1, 1, 30, inspect | read_mask | write_mask | ioctl_mask) == 0, 587, c'control(1, 1, 30, INSPECT | READ | WRITE | IOCTL) == 0') {
			return 1
		}
		if !require(control(1, 1, 31, inspect | read_mask | search) == 0, 588, c'control(1, 1, 31, INSPECT | READ | SEARCH) == 0') {
			return 1
		}
		if !require(control(1, 2, 0, inspect | read_mask | execute_mask | search) == 0, 589, c'control(1, 2, 0, INSPECT | READ | EXECUTE | SEARCH) == 0') {
			return 1
		}
		if !require(control(1, 2, 30, inspect | read_mask | write_mask | ioctl_mask) == 0, 590, c'control(1, 2, 30, INSPECT | READ | WRITE | IOCTL) == 0') {
			return 1
		}
		if !require(control(1, 2, 31, inspect | read_mask | search) == 0, 591, c'control(1, 2, 31, INSPECT | READ | SEARCH) == 0') {
			return 1
		}

		denied_memfd := i32(C.syscall(C.SYS_memfd_create, c'mac-denied', i32(0)))
		if !require(denied_memfd >= 0 && C.write(denied_memfd, c'not ELF', 7) == 7 && C.fchmod(denied_memfd, 0o755) == 0, 593, c'denied_memfd >= 0 && write(denied_memfd, "not ELF", 7) == 7 && fchmod(denied_memfd, 0755) == 0') {
			return 1
		}
		if !require(C.fsetxattr(denied_memfd, c'security.vinix', c'4', 1, 0) == 0, 594, c'fsetxattr(denied_memfd, "security.vinix", "4", 1, 0) == 0') {
			return 1
		}
		executable_memfd := copy_program_to_memfd()
		if !require(executable_memfd >= 0, 596, c'executable_memfd >= 0') { return 1 }
		audit_fd := C.open(c'/proc/security_audit', C.O_RDONLY)
		audit_header := &char(C.__builtin_alloca(16))
		if !require(audit_fd >= 0 && C.read(audit_fd, audit_header, 16) > 0, 599, c'audit_fd >= 0 && read(audit_fd, audit_header, sizeof(audit_header)) > 0') {
			return 1
		}
		if !require(control(2, 0, 0, 0) == 0, 600, c'control(2, 0, 0, 0) == 0') { return 1 }
		C.errno = 0
		if !require((control(1, 1, 2, all)) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 601, c'(control(1, 1, 2, 511U)) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((label(c'/mac-private', c'0')) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 602, c'(label("/mac-private", "0")) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		C.errno = 0
		if !require((C.removexattr(c'/mac-secret', c'security.vinix')) == -1 && (C.errno == C.EACCES || C.errno == C.EPERM), 603, c'(removexattr("/mac-secret", "security.vinix")) == -1 && (errno == EACCES || errno == EPERM)') {
			return 1
		}
		if !require(test_exec_descriptor_close() == 0, 604, c'test_exec_descriptor_close() == 0') {
			return 1
		}
		if !require(test_pipe_transfer_policy() == 0, 605, c'test_pipe_transfer_policy() == 0') {
			return 1
		}
		secret := C.open(c'/mac-secret/secret', C.O_RDWR)
		readonly := C.open(c'/mac-readonly/public', C.O_RDWR)
		if !require(secret >= 0 && readonly >= 0, 608, c'secret >= 0 && readonly >= 0') { return 1 }
		watch := C.inotify_init1(C.IN_NONBLOCK)
		if !require(watch >= 0 && C.inotify_add_watch(watch, c'/mac-secret', C.IN_CREATE) >= 0, 610, c'watch >= 0 && inotify_add_watch(watch, "/mac-secret", IN_CREATE) >= 0') {
			return 1
		}
		if !require(contents(c'/mac-secret/event', c'hidden') == 0, 611, c'contents("/mac-secret/event", "hidden") == 0') {
			return 1
		}
		if !require(C.mmap(voidptr(usize(0x680000000000)), 16384, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED | C.MAP_FIXED_NOREPLACE, secret, 0) == voidptr(usize(0x680000000000)), 612, c'mmap(OLD_MAP, 16384, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED_NOREPLACE, secret, 0) == OLD_MAP') {
			return 1
		}
		pipes_for_thread := &i32(C.__builtin_alloca(2 * sizeof(i32)))
		if !require(C.pipe(pipes_for_thread) == 0, 614, c'pipe(pipes_for_thread) == 0') { return 1 }
		extra := &C.pthread_t(C.__builtin_alloca(sizeof(C.pthread_t)))
		if !require(C.pthread_create(extra, nil, C.vinix_mac_policy_blocked_thread, &pipes_for_thread[0]) == 0, 616, c'pthread_create(&extra, NULL, blocked_thread, &pipes_for_thread[0]) == 0') {
			return 1
		}
		C.errno = 0
		if !require(control(3, 1, 0, 0) == -1 && C.errno == C.EBUSY, 617, c'control(3, 1, 0, 0) == -1 && errno == EBUSY') {
			return 1
		}
		if !require(C.write(pipes_for_thread[1], c'x', 1) == 1 && C.pthread_join(*extra, nil) == 0, 618, c'write(pipes_for_thread[1], "x", 1) == 1 && pthread_join(extra, NULL) == 0') {
			return 1
		}
		C.close(pipes_for_thread[0])
		C.close(pipes_for_thread[1])
		channels := &i32(C.__builtin_alloca(2 * sizeof(i32)))
		if !require(C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, channels) == 0, 621, c'socketpair(AF_UNIX, SOCK_STREAM, 0, channels) == 0') {
			return 1
		}
		mut parent_data := u8(`S`)
		child := C.fork()
		if !require(child >= 0, 624, c'child >= 0') { return 1 }
		if child == 0 {
			C.close(channels[0])
			if control(3, 1, 0, 0) != 0 { C._exit(5) }
			if control(0, 0, 0, 0) != 0 { C._exit(6) }
			mut denied_args := [&char(c'/mac-private/exec-denied'), &char(nil)]!
			C.errno = 0
			if C.execv(c'/mac-private/exec-denied', &denied_args[0]) != -1 || C.errno != C.EACCES || control(0, 0, 0, 0) != 0 {
				C._exit(8)
			}
			a := &char(C.__builtin_alloca(32))
			b := &char(C.__builtin_alloca(32))
			c := &char(C.__builtin_alloca(32))
			d := &char(C.__builtin_alloca(32))
			e := &char(C.__builtin_alloca(32))
			C.snprintf(a, 32, c'%d', secret)
			C.snprintf(b, 32, c'%d', readonly)
			C.snprintf(c, 32, c'%d', channels[1])
			C.snprintf(d, 32, c'%d', C.getppid())
			C.snprintf(e, 32, c'%llu', native_unsigned(u64(usize(&parent_data))))
			mut args := [&char(c'/sbin/init'), &char(c'worker'), a, b, c, d, e, &char(nil)]!
			C.syscall(C.SYS_execveat, executable_memfd, c'', &args[0], voidptr(nil), i32(C.AT_EMPTY_PATH))
			C.fprintf(C.stderr, c'SECURITY MAC FAIL exec: %s\n', C.strerror(C.errno))
			C._exit(7)
		}
		held_limit := &C.rlimit(C.__builtin_alloca(sizeof(C.rlimit)))
		if !require(C.prlimit(child, C.RLIMIT_NOFILE, nil, held_limit) == 0, 644, c'prlimit(child, RLIMIT_NOFILE, NULL, &held_limit) == 0') {
			return 1
		}
		if !require(C.prlimit(child, C.RLIMIT_NOFILE, held_limit, nil) == 0, 645, c'prlimit(child, RLIMIT_NOFILE, &held_limit, NULL) == 0') {
			return 1
		}
		C.errno = 0
		if !require(C.prlimit(child, C.RLIMIT_NOFILE, nil, &C.rlimit(usize(1))) == -1 && C.errno == C.EFAULT, 646, c'prlimit(child, RLIMIT_NOFILE, NULL, (struct rlimit *)(uintptr_t)1) == -1 && errno == EFAULT') {
			return 1
		}
		C.close(channels[1])
		C.close(executable_memfd)
		if !require(send_fd(channels[0], secret) == 0, 649, c'send_fd(channels[0], secret) == 0') {
			return 1
		}
		if !require(send_fd(channels[0], watch) == 0, 650, c'send_fd(channels[0], watch) == 0') {
			return 1
		}
		if !require(send_fd(channels[0], denied_memfd) == 0, 651, c'send_fd(channels[0], denied_memfd) == 0') {
			return 1
		}
		if !require(send_fd(channels[0], audit_fd) == 0, 652, c'send_fd(channels[0], audit_fd) == 0') {
			return 1
		}
		if !require(C.waitpid(child, status, 0) == child && C.WIFEXITED(*status) && C.WEXITSTATUS(*status) == 0, 653, c'waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0') {
			return 1
		}
		original := &char(C.__builtin_alloca(8))
		if !require(C.pread(secret, original, 6, 0) == 6 && C.memcmp(original, c'secret', 6) == 0, 655, c'pread(secret, original, 6, 0) == 6 && memcmp(original, "secret", 6) == 0') {
			return 1
		}
		if !require(C.pread(readonly, original, 6, 0) == 6 && C.memcmp(original, c'public', 6) == 0, 656, c'pread(readonly, original, 6, 0) == 6 && memcmp(original, "public", 6) == 0') {
			return 1
		}
		if !require(C.munmap(voidptr(usize(0x680000000000)), 16384) == 0, 657, c'munmap(OLD_MAP, 16384) == 0') {
			return 1
		}
		C.close(secret)
		C.close(readonly)
		C.close(channels[0])
		C.close(watch)
		C.close(denied_memfd)
		C.close(audit_fd)
		C.puts(c'SECURITY MAC PASS')
		return 0
	}
}

fn diagnostic_254() &char {
	$if arm64 {
		return c'(syscall(77, source, sink, 4, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(276, source, sink, 4, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_256() &char {
	$if arm64 {
		return c'(syscall(75, sink, &vector, 1, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(278, sink, &vector, 1, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_375() &char {
	$if arm64 {
		return c'(syscall(285, secret_fd, &from, output, &to, 3, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(326, secret_fd, &from, output, &to, 3, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_377() &char {
	$if arm64 {
		return c'(syscall(285, readonly_fd, &from, secret_fd, &to, 3, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(326, readonly_fd, &from, secret_fd, &to, 3, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_418() &char {
	$if arm64 {
		return c'(syscall(120, parent)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(145, parent)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_419() &char {
	$if arm64 {
		return c'(syscall(121, parent, &parameters)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(143, parent, &parameters)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_420() &char {
	$if arm64 {
		return c'(syscall(119, parent, 0, &parameters)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(144, parent, 0, &parameters)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_421() &char {
	$if arm64 {
		return c'(syscall(118, parent, &parameters)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(142, parent, &parameters)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_426() &char {
	$if arm64 {
		return c'(syscall(275, parent, &scheduling, sizeof(scheduling), 0)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(315, parent, &scheduling, sizeof(scheduling), 0)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_427() &char {
	$if arm64 {
		return c'(syscall(274, parent, &scheduling, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(314, parent, &scheduling, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_429() &char {
	$if arm64 {
		return c'(syscall(274, parent, &scheduling, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(314, parent, &scheduling, 0)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_438() &char {
	$if arm64 {
		return c'(syscall(100, parent, &robust_head, &robust_length)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(274, parent, &robust_head, &robust_length)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_458() &char {
	$if arm64 {
		return c'(syscall(281, passed, "", memfd_arguments, ((void*)0), 0x1000)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(322, passed, "", memfd_arguments, ((void*)0), 0x1000)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_474() &char {
	$if arm64 {
		return c'(syscall(100, parent, &robust_head, &robust_length)) == -1 && (errno == EACCES || errno == EPERM)'
	} $else {
		return c'(syscall(274, parent, &robust_head, &robust_length)) == -1 && (errno == EACCES || errno == EPERM)'
	}
}

fn diagnostic_mount_line() i32 {
	$if arm64 {
		return 569
	} $else {
		return 568
	}
}
