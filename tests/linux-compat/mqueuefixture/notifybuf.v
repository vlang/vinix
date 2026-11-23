// SPDX-License-Identifier: GPL-2.0-or-later
module mqueuefixture

fn notification_buffer(mut s State) {
	unsafe {
		s.label = c'notification socket capacity'
		sock := C.socket(af_netlink, sock_raw, 0)
		mut limit := i32(65536)
		configured := sock >= 0 && C.fcntl(sock, C.F_SETFL, o_nonblock) == 0
			&& C.syscall(isize(C.SYS_setsockopt), sock, C.SOL_SOCKET, C.SO_RCVBUF, &limit, 4) == 0
		check(mut s, c'configure notification socket', configured, sock)
		if !configured { return }
		mut queues := [64]i32{}
		mut cookie := [32]u8{}
		cookie[1] = 0x68
		name := &char(s.text)
		mut created := 0
		mut registered := 0
		for i in 0 .. queues.len {
			C.snprintf(name, 64, c'notify-buffer-%d', i)
			q := mq_open(name, o_creat | o_excl | o_rdwr | o_nonblock, 0o600,
				set_attr(s.attr, 0, 1, 16, 0))
			if q < 0 { break }
			queues[i] = i32(q)
			created++
			cookie[0] = u8(i)
			if mq_notify(q, set_signal_event(mut s, 2, sock, u64(&cookie[0]))) != 0 { break }
			registered++
		}
		check(mut s, c'register all cookies', registered == queues.len, registered)
		check(mut s, c'registration reserves space without readable data',
			C.recv(sock, s.buf, 64, 0) == -1 && *C.__errno_location() == C.EAGAIN, 0)
		limit = 2048
		check(mut s, c'shrink receive buffer below reserved capacity',
			C.syscall(isize(C.SYS_setsockopt), sock, C.SOL_SOCKET, C.SO_RCVBUF, &limit, 4) == 0, 0)
		mut sent := 0
		for i in 0 .. registered {
			if mq_send(queues[i], c't', 1, 0, nil) == 0 { sent++ }
		}
		check(mut s, c'trigger all notifications', sent == queues.len, sent)
		mut ready := [2]i32{}
		mut done := [2]i32{}
		pipes := C.pipe(&ready[0]) == 0 && C.pipe(&done[0]) == 0
		child := if pipes { C.fork() } else { -1 }
		if child == 0 {
			C.close(ready[0])
			C.close(done[0])
			if C.write(ready[1], c'r', 1) != 1 { C._exit(1) }
			result := mq_notify(999, set_signal_event(mut s, 2, sock, u64(&cookie[0])))
			C._exit(if result == -C.EBADF && C.write(done[1], c'd', 1) == 1 { 0 } else { 2 })
		}
		blocked := if child > 0 {
			C.close(ready[1])
			C.close(done[1])
			mut pfd := &C.pollfd(s.words + 2)
			pfd.fd = done[0]
			pfd.events = i16(C.POLLIN)
			pfd.revents = 0
			C.read(ready[0], s.buf, 1) == 1 && C.poll(pfd, 1, 100) == 0
		} else { false }
		mut received := 0
		for i in 0 .. registered {
			n := C.recv(sock, s.buf, 64, 0)
			if n != 32 || s.buf[0] != u8(i) || s.buf[1] != 0x68 || s.buf[31] != 1 { break }
			received++
		}
		check(mut s, c'all reserved cookies survive the new limit', received == queues.len, received)
		check(mut s, c'full socket waits before validating queue descriptor', blocked, 0)
		mut status := i32(-1)
		drained := child > 0 && C.read(done[0], s.buf, 1) == 1
			&& C.waitpid(child, &status, 0) == child && status == 0
		check(mut s, c'draining wakes registration to validate its descriptor', drained, status)
		if child > 0 {
			C.close(ready[0])
			C.close(done[0])
		}
		mut failures := 0
		for _ in 0 .. queues.len {
			if mq_notify(999, set_signal_event(mut s, 2, sock, u64(&cookie[0]))) != -C.EBADF { failures++ }
		}
		check(mut s, c'failed registrations return reserved receive space', failures == 0, failures)
		for i in 0 .. created {
			C.close(queues[i])
			C.snprintf(name, 64, c'notify-buffer-%d', i)
			mq_unlink(name)
		}
		C.close(sock)
	}
}
