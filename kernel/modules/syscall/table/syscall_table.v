module table

import userland
import errno
import proc
import fs
import file
import x86.cpu
import memory.mmap
import dev.random
import time

const table_size = 333

__global (
	systab_size = u64(table_size)
	syscall_table [table_size]voidptr
)

pub fn syscall_enosys() i64 {
	mut thread := proc.current_thread()

	C.printf(c'\n\e[31mstrace\e[m: Unsupported system call: %d\n', thread.syscall_num)

	panic('Unsupported system call: $thread.syscall_num')

	return -errno.enosys
}

pub fn init_syscall_table() {
	for i := u64(0); i < table_size; i++ {
		syscall_table[i] = voidptr(syscall_enosys)
	}

	syscall_table[0] = voidptr(fs.syscall_read)
	syscall_table[3] = voidptr(fs.syscall_close)
	syscall_table[9] = voidptr(file.syscall_mmap)
	syscall_table[10] = voidptr(mmap.syscall_mprotect)
	syscall_table[13] = voidptr(userland.syscall_sigaction)
	syscall_table[17] = voidptr(fs.syscall_pread)
	syscall_table[12] = voidptr(userland.syscall_brk)
	syscall_table[20] = voidptr(fs.syscall_writev)
	syscall_table[21] = voidptr(fs.syscall_access)
	syscall_table[63] = voidptr(userland.syscall_uname)
	syscall_table[158] = voidptr(cpu.syscall_arch_prctl)
	syscall_table[218] = voidptr(userland.syscall_set_tid_address)
	syscall_table[228] = voidptr(time.syscall_clock_gettime)
	syscall_table[257] = voidptr(fs.syscall_openat)
	syscall_table[262] = voidptr(fs.syscall_fstatat)
	syscall_table[273] = voidptr(userland.syscall_set_robust_list)
	syscall_table[302] = voidptr(userland.syscall_prlimit)
	syscall_table[318] = voidptr(random.syscall_get_random)
}
