// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <sys/epoll.h>

struct C.epoll_event {
mut:
	events u32
}

fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32, i32, i32, &C.epoll_event) i32
fn C.epoll_wait(i32, &C.epoll_event, i32, i32) i32
fn C.alarm(u32) u32

// Run under an alarm: a temporary epoll snapshot reference used to wake the
// slave again on release, keeping even a finite timeout inside the kernel.
fn epoll_slave_cases() i32 {
	unsafe {
		C.alarm(5)
		mut unlock := i32(0)
		mut id := u32(0)
		master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
		if master < 0 || C.ioctl(master, C.TIOCSPTLCK, &unlock) != 0
			|| C.ioctl(master, C.TIOCGPTN, &id) != 0 { return 1 }
		mut path := [64]char{}
		C.snprintf(&path[0], 64, c'/dev/pts/%u', id)
		slave := C.open(&path[0], C.O_RDWR | C.O_NOCTTY | C.O_NONBLOCK)
		poller := C.epoll_create1(C.EPOLL_CLOEXEC)
		mut interest := C.epoll_event{events: u32(C.EPOLLIN)}
		if slave < 0 || poller < 0
			|| C.epoll_ctl(poller, C.EPOLL_CTL_ADD, slave, &interest) != 0 { return 1 }
		mut ready := C.epoll_event{}
		mut start := C.timespec{}
		mut finish := C.timespec{}
		C.clock_gettime(C.CLOCK_MONOTONIC, &start)
		count := C.epoll_wait(poller, &ready, 1, 25)
		C.clock_gettime(C.CLOCK_MONOTONIC, &finish)
		elapsed := (finish.tv_sec - start.tv_sec) * 1000000000 + finish.tv_nsec - start.tv_nsec
		check(count == 0 && elapsed >= 10000000 && elapsed < 2000000000,
			c'epoll idle slave respects timeout without self-wake')
		check(C.write(master, c'x\n', 2) == 2 && C.epoll_wait(poller, &ready, 1, 1000) == 1
			&& ready.events & u32(C.EPOLLIN) != 0, c'epoll slave reports actual input')
		mut bytes := [2]u8{}
		check(C.read(slave, &bytes[0], 2) == 2 && bytes == [u8(`x`), `\n`]!,
			c'epoll slave input drains exactly')
		check(C.epoll_wait(poller, &ready, 1, 25) == 0,
			c'epoll drained slave respects timeout')
		C.close(master)
		check(C.epoll_wait(poller, &ready, 1, 1000) == 1
			&& ready.events & u32(C.EPOLLHUP) != 0, c'epoll slave reports real master hangup')
		C.close(poller)
		C.close(slave)

		// A real description close must still wake the peer's blocked epoll.
		// Only the child retains the last slave description during this wait.
		peer := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
		if peer < 0 || C.ioctl(peer, C.TIOCSPTLCK, &unlock) != 0
			|| C.ioctl(peer, C.TIOCGPTN, &id) != 0 { return 1 }
		C.snprintf(&path[0], 64, c'/dev/pts/%u', id)
		endpoint := C.open(&path[0], C.O_RDWR | C.O_NOCTTY)
		watch := C.epoll_create1(C.EPOLL_CLOEXEC)
		if endpoint < 0 || watch < 0
			|| C.epoll_ctl(watch, C.EPOLL_CTL_ADD, peer, &interest) != 0 { return 1 }
		child := C.fork()
		if child == 0 {
			C.close(watch)
			C.close(peer)
			C.usleep(100000)
			C._exit(if C.close(endpoint) == 0 { 0 } else { 1 })
		}
		if child < 0 { return 1 }
		C.close(endpoint)
		check(C.epoll_wait(watch, &ready, 1, 1000) == 1
			&& ready.events & u32(C.EPOLLHUP) != 0,
			c'epoll master wakes on actual last slave close')
		check(exited_ok(child), c'epoll delayed slave closer reaped')
		C.close(watch)
		C.close(peer)
		C.alarm(0)
		return if failures == 0 { 0 } else { 1 }
	}
}
