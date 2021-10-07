module table

import userland
import errno
import proc
import fs
import file

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
	syscall_table[17] = voidptr(fs.syscall_pread)
	syscall_table[12] = voidptr(userland.syscall_brk)
	syscall_table[20] = voidptr(fs.syscall_writev)
	syscall_table[21] = voidptr(fs.syscall_access)
	syscall_table[63] = voidptr(userland.syscall_uname)
	syscall_table[257] = voidptr(fs.syscall_openat)
	syscall_table[262] = voidptr(fs.syscall_fstatat)
}
