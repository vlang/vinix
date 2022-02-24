// syscall_table.v: Table of syscalls and their inners.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

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
import time.sys
import time.timerfd
import net
import time.itimer
import sched

__global (
	syscall_table [66]voidptr
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
	syscall_table[40] = voidptr(socket.syscall_bind)
	syscall_table[41] = voidptr(socket.syscall_listen)
	syscall_table[42] = voidptr(fs.syscall_inotify_init)
	syscall_table[43] = voidptr(fs.syscall_mount)
	syscall_table[44] = voidptr(fs.syscall_umount)
	syscall_table[45] = voidptr(userland.syscall_signalfd)
	syscall_table[46] = voidptr(socket.syscall_socketpair)
	syscall_table[47] = voidptr(file.syscall_epoll_ctl)
	syscall_table[48] = voidptr(mmap.syscall_mprotect)
	syscall_table[49] = voidptr(file.syscall_epoll_pwait)
	syscall_table[50] = voidptr(sys.syscall_clock_get)
	syscall_table[51] = voidptr(net.syscall_gethostname)
	syscall_table[52] = voidptr(net.syscall_sethostname)
	syscall_table[53] = voidptr(sys.syscall_nanosleep)
	syscall_table[54] = voidptr(timerfd.syscall_timerfd_create)
	syscall_table[55] = voidptr(timerfd.syscall_timerfd_settime)
	syscall_table[56] = voidptr(timerfd.syscall_timerfd_gettime)
	syscall_table[57] = voidptr(fs.syscall_fchmod)
	syscall_table[58] = voidptr(fs.syscall_linkat)
	syscall_table[59] = voidptr(socket.syscall_connect)
	syscall_table[60] = voidptr(socket.syscall_getpeername)
	syscall_table[61] = voidptr(socket.syscall_accept)
	syscall_table[62] = voidptr(socket.syscall_recvmsg)
	syscall_table[63] = voidptr(itimer.syscall_getitimer)
	syscall_table[64] = voidptr(itimer.syscall_setitimer)
	syscall_table[65] = voidptr(sched.syscall_new_thread)
}
