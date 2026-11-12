// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <sys/syscall.h>
#include <signal.h>
#include <poll.h>
#define vinix_wine_peer_fcntl fcntl
#define vinix_wine_peer_getsockopt getsockopt
#define vinix_wine_peer_getpeername(fd, address, length) getpeername((fd), (struct sockaddr *)(address), (length))
#define vinix_wine_peer_waitid waitid
#define vinix_wine_peer_syscall syscall
#define vinix_wine_peer_poll(fds, count, timeout) poll((struct pollfd *)(fds), (count), (timeout))
#define vinix_wine_owner_lock flock
#define vinix_wine_child_info siginfo_t
#define vinix_wine_peer_address sockaddr_un

struct C.vinix_wine_owner_lock {
mut:
	l_type i16
	l_whence i16
	l_start i64
	l_len i64
	l_pid i32
}
@[typedef]
struct C.vinix_wine_child_info { mut: si_pid i32 }
struct C.vinix_wine_peer_address { mut: sun_family u16 sun_path [108]char }
struct ServerCredentials { mut: pid i32 uid u32 gid u32 }
struct ServerSignalAction { handler u64 flags u64 restorer u64 mask u64 }
struct ServerPoll { mut: fd i32 events i16 revents i16 }
fn C.vinix_wine_peer_fcntl(i32, i32, ...voidptr) i32
fn C.vinix_wine_peer_getsockopt(i32, i32, i32, voidptr, &u32) i32
fn C.vinix_wine_peer_getpeername(i32, voidptr, &u32) i32
fn C.vinix_wine_peer_waitid(i32, u32, voidptr, i32) i32
fn C.vinix_wine_peer_syscall(i64, ...) i64
fn C.vinix_wine_peer_poll(voidptr, u64, i32) i32

fn live_server_child(child i32) ! {
	mut info := C.vinix_wine_child_info{}
	if C.vinix_wine_peer_waitid(C.P_PID, u32(child), unsafe { &info }, C.WEXITED | C.WNOHANG | C.WNOWAIT) != 0 {
		return error('Wine server must remain an exclusively owned waitable child')
	}
	if info.si_pid != 0 { return error('Wine server child has already exited') }
}

fn verify_server_linux(socket_fd i32, lock_fd i32, child i32) ! {
	if socket_fd < 3 || lock_fd < 3 || socket_fd == lock_fd || child <= 0
		|| child == os.getpid() || C.geteuid() == 0 || os.getegid() == 0 {
		return error('Wine server identity requires private descriptors and an ordinary-account child')
	}
	mut action := ServerSignalAction{}
	if C.vinix_wine_peer_syscall(C.SYS_rt_sigaction, C.SIGCHLD, voidptr(0), unsafe { &action }, u64(8)) != 0
		|| action.handler != 0 || action.flags & u64(C.SA_NOCLDWAIT) != 0 {
		return error('Wine server identity requires default waitable SIGCHLD')
	}
	live_server_child(child)!
	// The Wine 9.17 server holds a POSIX write lock on exactly byte zero.
	// F_GETLK is observational; flock/OFD locks and current-process POSIX
	// locks cannot satisfy this check. Closing this borrowed FD is forbidden.
	guard_file(lock_fd)!
	mut owner := C.vinix_wine_owner_lock{l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_SET), l_start: 0, l_len: 1}
	if C.vinix_wine_peer_fcntl(lock_fd, C.F_GETLK, unsafe { &owner }) != 0 || owner.l_type != C.F_WRLCK
		|| owner.l_whence != C.SEEK_SET || owner.l_start != 0 || owner.l_len != 1 || owner.l_pid != child {
		return error('Wine server lock does not identify the owned child')
	}
	flags := C.vinix_wine_peer_fcntl(socket_fd, C.F_GETFD)
	if flags < 0 || flags & C.FD_CLOEXEC == 0 { return error('Wine server socket must be close-on-exec') }
	mut kind := i32(0)
	mut size := u32(sizeof(i32))
	if C.vinix_wine_peer_getsockopt(socket_fd, C.SOL_SOCKET, C.SO_TYPE, unsafe { &kind }, &size) != 0
		|| size != sizeof(i32) || kind != C.SOCK_STREAM { return error('Wine server needs a connected Unix stream') }
	mut address := C.vinix_wine_peer_address{}
	size = u32(sizeof(C.vinix_wine_peer_address))
	if C.vinix_wine_peer_getpeername(socket_fd, unsafe { &address }, &size) != 0 || size < 2
		|| size > sizeof(C.vinix_wine_peer_address) || address.sun_family != C.AF_UNIX {
		return error('Wine server needs a connected Unix stream')
	}
	mut credentials := ServerCredentials{}
	size = u32(sizeof(ServerCredentials))
	if C.vinix_wine_peer_getsockopt(socket_fd, C.SOL_SOCKET, C.SO_PEERCRED, unsafe { &credentials }, &size) != 0
		|| size != sizeof(ServerCredentials) || credentials.pid != child
		|| credentials.uid != u32(C.geteuid()) || credentials.gid != u32(os.getegid()) {
		return error('Wine server socket peer does not identify the owned account and child')
	}
	mut ready := ServerPoll{fd: socket_fd, events: i16(C.POLLIN | C.POLLRDHUP)}
	if C.vinix_wine_peer_poll(unsafe { &ready }, 1, 0) < 0
		|| ready.revents & i16(C.POLLHUP | C.POLLERR | C.POLLNVAL | C.POLLRDHUP) != 0 {
		return error('Wine server socket peer has disconnected')
	}
	// An exit while inspecting the lock/credentials must still refuse, without
	// consuming the saved exit status or freeing the child's PID for reuse.
	live_server_child(child)!
}
