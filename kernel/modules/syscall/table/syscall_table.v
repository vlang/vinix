module table

import userland
import errno
import proc

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

	syscall_table[0x0c] = voidptr(userland.syscall_brk)
}
