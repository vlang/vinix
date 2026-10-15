// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

#include <sys/socket.h>
#include <sys/uio.h>

struct C.iovec { mut: iov_base voidptr iov_len usize }
struct C.cmsghdr { mut: cmsg_len usize cmsg_level i32 cmsg_type i32 }
struct C.msghdr {
mut:
	msg_name voidptr
	msg_namelen u32
	msg_iov &C.iovec
	msg_iovlen usize
	msg_control voidptr
	msg_controllen usize
	msg_flags i32
}
fn C.socketpair(int, int, int, &i32) int
fn C.sendmsg(int, &C.msghdr, int) isize
fn C.recvmsg(int, &C.msghdr, int) isize

fn unmount_handle_busy(path &char, mark &char) {
	unsafe {
		mut before := C.stat{}
		check(C.stat(path, &before) == 0, 3500)
		for _ in 0 .. 200 {
			refused_unmount(path, 0, C.EBUSY, 3500)
			check(same(path, &before) && contents(mark), 3500)
		}
	}
}

fn unmount_handle_send(socket int, fd int) {
	unsafe {
		mut byte := u8(`X`)
		mut control := [3]u64{}
		header := &C.cmsghdr(&control[0])
		*header = C.cmsghdr{cmsg_len: 20, cmsg_level: C.SOL_SOCKET, cmsg_type: C.SCM_RIGHTS}
		*(&i32(&control[2])) = i32(fd)
		mut vector := C.iovec{iov_base: &byte, iov_len: 1}
		mut message := C.msghdr{msg_iov: &vector, msg_iovlen: 1, msg_control: &control[0], msg_controllen: 24}
		check(C.sendmsg(socket, &message, 0) == 1, 3501)
	}
}

fn unmount_handle_receive(socket int, flags int, control_present bool) int {
	unsafe {
		mut byte := u8(0)
		mut control := [3]u64{}
		mut vector := C.iovec{iov_base: &byte, iov_len: 1}
		mut message := C.msghdr{msg_iov: &vector, msg_iovlen: 1,
			msg_control: if control_present { voidptr(&control[0]) } else { nil },
			msg_controllen: if control_present { usize(24) } else { usize(0) }}
		check(C.recvmsg(socket, &message, flags) == 1 && byte == `X`, 3502)
		if !control_present {
			check(message.msg_flags & C.MSG_CTRUNC != 0, 3502)
			return -1
		}
		header := &C.cmsghdr(&control[0])
		fd := int(*(&i32(&control[2])))
		check(message.msg_flags & C.MSG_CTRUNC == 0 && message.msg_controllen >= 20
			&& header.cmsg_len == 20 && header.cmsg_level == C.SOL_SOCKET
			&& header.cmsg_type == C.SCM_RIGHTS && fd >= 0, 3502)
		return fd
	}
}

struct UnmountHandleWorker { mut: fd int kind int ready i32 }

fn unmount_handle_worker(argument voidptr) voidptr {
	unsafe {
		state := &UnmountHandleWorker(argument)
		tid := i32(C.syscall(int(C.SYS_gettid)))
		check(tid > 0 && C.write(int(state.ready), &tid, sizeof(i32)) == sizeof(i32), 3503)
		mut byte := u8(`X`)
		result := if state.kind == 0 { C.read(state.fd, &byte, 1) } else { C.write(state.fd, &byte, 1) }
		check(result == 1 && byte == `X`, 3503)
		return nil
	}
}

fn unmount_handle_wait(tid i32) {
	unsafe {
		mut path := [128]char{}
		check(C.snprintf(&path[0], 128, c'/proc/self/task/%d/stat', tid) > 0, 3504)
		for _ in 0 .. 10000 {
			fd := C.open(&path[0], C.O_RDONLY)
			mut bytes := [1024]u8{}
			check(fd >= 0, 3504)
			count := C.read(fd, &bytes[0], 1023)
			check(count > 0 && C.close(fd) == 0, 3504)
			for i := int(count) - 4; i >= 0; i-- {
				if bytes[i] == `)` && bytes[i + 1] == ` ` && bytes[i + 2] == `S`
					&& bytes[i + 3] == ` ` { return }
			}
			C.sched_yield()
		}
		check(false, 3504)
	}
}

fn unmount_handle_io(kind int) {
	unsafe {
		check(C.syscall(int(C.SYS_mknodat), i32(C.AT_FDCWD), c'/tmp/mount-lifecycle/uh/a/fifo',
			u32(C.S_IFIFO | 0o600), u64(0)) == 0, 3505)
		first := C.open(if kind == 0 { c'/tmp/mount-lifecycle/uh/a/fifo' } else { c'/tmp/mount-lifecycle/uh/b/fifo' }, C.O_RDONLY | C.O_NONBLOCK)
		second := C.open(if kind == 0 { c'/tmp/mount-lifecycle/uh/b/fifo' } else { c'/tmp/mount-lifecycle/uh/a/fifo' }, C.O_WRONLY | C.O_NONBLOCK)
		check(first >= 0 && second >= 0, 3505)
		fd := if kind == 0 { first } else { second }
		peer := if kind == 0 { second } else { first }
		if kind == 1 {
			mut bytes := [4096]u8{}
			mut filled := false
			for _ in 0 .. 4096 {
				result := C.write(fd, &bytes[0], bytes.len)
				if result == -1 {
					check(*C.__errno_location() == C.EAGAIN, 3505)
					filled = true
					break
				}
				check(result > 0, 3505)
			}
			check(filled, 3505)
		}
		check(C.syscall(int(C.SYS_fcntl), i32(fd), i32(C.F_SETFL), i32(0)) == 0, 3505)
		mut ready := [2]i32{}
		check(C.pipe(&ready[0]) == 0, 3505)
		state := &UnmountHandleWorker(C.alloca(sizeof(UnmountHandleWorker)))
		*state = UnmountHandleWorker{fd: fd, kind: kind, ready: ready[1]}
		mut worker_handle := C.pthread_t{}
		check(C.pthread_create(&worker_handle, nil, unmount_handle_worker, state) == 0, 3505)
		mut tid := i32(0)
		check(C.read(int(ready[0]), &tid, sizeof(i32)) == sizeof(i32), 3505)
		unmount_handle_wait(tid)
		check(C.close(fd) == 0, 3505)
		unmount_handle_busy(c'/tmp/mount-lifecycle/uh/a', c'/tmp/mount-lifecycle/uh/a/marker')
		if kind == 0 { check(C.write(peer, c'X', 1) == 1, 3506) }
		else {
			mut bytes := [4096]u8{}
			check(C.read(peer, &bytes[0], bytes.len) > 0, 3506)
		}
		check(C.pthread_join(worker_handle, nil) == 0 && C.close(peer) == 0
			&& C.close(int(ready[0])) == 0 && C.close(int(ready[1])) == 0, 3506)
		check(C.umount2(c'/tmp/mount-lifecycle/uh/a', 0) == 0, 3506)
	}
}

fn unmount_handle_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 3507)
		busy_mount(c'/tmp/mount-lifecycle/uh')
		directory(c'/tmp/mount-lifecycle/uh/a')
		directory(c'/tmp/mount-lifecycle/uh/b')
		busy_mount(c'/tmp/mount-lifecycle/uh/a')
		marker(c'/tmp/mount-lifecycle/uh/a/marker')
		check(C.mount(c'/tmp/mount-lifecycle/uh/a', c'/tmp/mount-lifecycle/uh/b', nil,
			usize(C.MS_BIND), nil) == 0, 3507)
		if kind < 2 { unmount_handle_io(kind) }
		else {
			mut pair := [2]i32{}
			check(C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0, 3508)
			for direction in 0 .. if kind == 6 { 2 } else { 1 } {
				path := if direction == 0 { &char(c'/tmp/mount-lifecycle/uh/a/marker') } else { &char(c'/tmp/mount-lifecycle/uh/b/marker') }
				active := if direction == 0 { &char(c'/tmp/mount-lifecycle/uh/a') } else { &char(c'/tmp/mount-lifecycle/uh/b') }
				other := if direction == 0 { &char(c'/tmp/mount-lifecycle/uh/b') } else { &char(c'/tmp/mount-lifecycle/uh/a') }
				fd := C.open(if kind == 4 { c'/tmp/mount-lifecycle/uh/a' } else { path }, if kind in [3, 4] { C.O_PATH } else { C.O_RDONLY })
				check(fd >= 0, 3508)
				unmount_handle_send(int(pair[0]), fd)
				check(C.close(fd) == 0, 3508)
				if kind == 6 { check(C.umount2(other, 0) == 0, 3508) }
				if kind == 7 {
					child := C.fork()
					check(child >= 0, 3509)
					if child == 0 {
						check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.umount2(active, 0) == 0, 3509)
						check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 3509)
						refused_unmount(active, 0, C.EPERM, 3509)
						C._exit(0)
					}
					wait_child(child)
				}
				if kind == 8 {
					check(C.umount2(active, int(C.MNT_DETACH)) == 0, 3510)
					busy_mount(active)
					check(C.umount2(active, 0) == 0, 3510)
				} else { unmount_handle_busy(active, path) }
				if kind == 9 {
					check(C.close(int(pair[1])) == 0, 3511)
				} else if kind == 5 {
					check(unmount_handle_receive(int(pair[1]), 0, false) == -1, 3511)
				} else {
					received := unmount_handle_receive(int(pair[1]), C.MSG_CMSG_CLOEXEC, true)
					if kind !in [3, 4] { unmount_descriptor_data(received) }
					if kind != 8 { unmount_handle_busy(active, path) }
					check(C.close(received) == 0, 3511)
				}
				if kind != 8 { check(C.umount2(active, 0) == 0, 3511) }
				if kind == 6 && direction == 0 {
					busy_mount(c'/tmp/mount-lifecycle/uh/a')
					marker(c'/tmp/mount-lifecycle/uh/a/marker')
					check(C.mount(c'/tmp/mount-lifecycle/uh/a', c'/tmp/mount-lifecycle/uh/b', nil, usize(C.MS_BIND), nil) == 0, 3511)
				}
			}
			check(C.close(int(pair[0])) == 0, 3512)
			if kind != 9 { check(C.close(int(pair[1])) == 0, 3512) }
		}
		if kind != 6 { check(C.umount2(c'/tmp/mount-lifecycle/uh/b', 0) == 0, 3512) }
		check(C.umount2(c'/tmp/mount-lifecycle/uh', 0) == 0, 3512)
	}
}

fn unmount_handle_cases(selected int) {
	unsafe { directory(c'/tmp/mount-lifecycle/uh') }
	for kind in 0 .. 10 {
		if selected >= 0 && kind != selected { continue }
		child := C.fork()
		check(child >= 0, 3513)
		if child == 0 { unmount_handle_case(kind); C._exit(0) }
		wait_child(child)
		unsafe { C.printf(c'MOUNT UNMOUNT HANDLE CASE: %d PASS\n', i32(kind)) }
		C.fflush(unsafe { nil })
	}
	C.puts(c'MOUNT UNMOUNT HANDLES: PASS')
	C.fflush(unsafe { nil })
}
