module table

import kprint
import file
import fs
import x86.cpu
import userland
import futex
import pipe
import socket
import memory.mmap

__global (
	syscall_table [40]voidptr
)

pub fn init_syscall_table() {
	syscall_table[0] = voidptr(kprint.syscall_kprint)
	syscall_table[1] = voidptr(file.syscall_mmap)
	syscall_table[2] = voidptr(fs.syscall_openat)
	syscall_table[3] = voidptr(fs.syscall_read)
	syscall_table[4] = voidptr(fs.syscall_write)
	syscall_table[5] = voidptr(fs.syscall_seek)
	syscall_table[6] = voidptr(fs.syscall_close)
	syscall_table[7] = voidptr(cpu.syscall_set_fs_base)
	syscall_table[8] = voidptr(cpu.syscall_set_gs_base)
	syscall_table[9] = voidptr(fs.syscall_ioctl)
	syscall_table[10] = voidptr(fs.syscall_fstat)
	syscall_table[11] = voidptr(fs.syscall_fstatat)
	syscall_table[12] = voidptr(file.syscall_fcntl)
	syscall_table[13] = voidptr(file.syscall_dup3)
	syscall_table[14] = voidptr(userland.syscall_fork)
	syscall_table[15] = voidptr(userland.syscall_exit)
	syscall_table[16] = voidptr(userland.syscall_waitpid)
	syscall_table[17] = voidptr(userland.syscall_execve)
	syscall_table[18] = voidptr(fs.syscall_chdir)
	syscall_table[19] = voidptr(fs.syscall_readdir)
	syscall_table[20] = voidptr(fs.syscall_faccessat)
	syscall_table[21] = voidptr(pipe.syscall_pipe)
	syscall_table[22] = voidptr(fs.syscall_mkdirat)
	syscall_table[23] = voidptr(futex.syscall_futex_wait)
	syscall_table[24] = voidptr(futex.syscall_futex_wake)
	syscall_table[25] = voidptr(fs.syscall_getcwd)
	syscall_table[26] = voidptr(userland.syscall_kill)
	syscall_table[27] = voidptr(userland.syscall_sigentry)
	syscall_table[28] = voidptr(userland.syscall_sigprocmask)
	syscall_table[29] = voidptr(userland.syscall_sigaction)
	syscall_table[30] = voidptr(userland.syscall_sigreturn)
	syscall_table[31] = voidptr(userland.syscall_getpid)
	syscall_table[32] = voidptr(userland.syscall_getppid)
	syscall_table[33] = voidptr(fs.syscall_readlinkat)
	syscall_table[34] = voidptr(mmap.syscall_munmap)
	syscall_table[35] = voidptr(fs.syscall_unlinkat)
	syscall_table[36] = voidptr(file.syscall_ppoll)
	syscall_table[37] = voidptr(file.syscall_epoll_create)
	syscall_table[38] = voidptr(userland.syscall_getgroups)
	syscall_table[39] = voidptr(socket.syscall_socket)
}
