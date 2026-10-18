// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <poll.h>
#include <string.h>
#include <fcntl.h>

__global service_private_fd i32
__global service_private_owner i32
__global service_private_attached bool

struct C.sockaddr_un {
	sun_family u16
	sun_path [108]char
}

struct C.pollfd {
	fd i32
	events i16
	revents i16
}

fn C.socket(i32, i32, i32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.mkdir(&char, u32) i32
fn C.strlen(&char) usize
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.fcntl(i32, i32, ...voidptr) i32

fn service_socket_path() [108]char {
	unsafe {
		mut path := [108]char{}
		runtime := C.getenv(c'VINIX_SESSION_RUNTIME')
		check(runtime != nil, 485)
		n := C.snprintf(&path[0], path.len, c'%s/vinix-session.%u/broker', runtime, C.getuid())
		check(n > 0 && n < path.len, 486)
		return path
	}
}

fn service_hex(source &char, length int, mut target [8192]char) int {
	unsafe {
		check(length >= 0 && length * 2 < target.len, 450)
		alphabet := &char(c'0123456789abcdef')
		for i in 0 .. length {
			byte := u8(source[i])
			target[i * 2] = alphabet[byte >> 4]
			target[i * 2 + 1] = alphabet[byte & 15]
		}
		target[length * 2] = 0
		return length * 2
	}
}

fn service_transfer(fd i32, buffer &char, length int, writing bool) {
	unsafe {
		deadline := job_clock() + 3000000000
		mut offset := 0
		for offset < length {
			check(job_clock() < deadline, 451)
			mut ready := C.pollfd{fd: fd, events: i16(if writing { C.POLLOUT } else { C.POLLIN })}
			check(C.poll(&ready, 1, 100) >= 0, 452)
			if ready.revents & ready.events == 0 { continue }
			n := if writing { C.write(fd, buffer + offset, usize(length - offset)) }
				else { C.read(fd, buffer + offset, usize(length - offset)) }
			if n < 0 && *C.__errno_location() == C.EAGAIN { continue }
			check(n > 0, 453)
			offset += int(n)
		}
	}
}

fn service_request(fields [4]&char, count int, denied bool) [4096]char {
	unsafe {
		mut reply := [4096]char{}
		check(count > 0 && count <= fields.len, 454)
		mut request := [8192]char{}
		mut used := int(C.strlen(fields[0]))
		check(used > 0 && used < 128, 455)
		for i in 0 .. used { request[i] = fields[0][i] }
		for i in 1 .. count {
			request[used] = char(9)
			used++
			mut encoded := [8192]char{}
			n := service_hex(fields[i], int(C.strlen(fields[i])), mut encoded)
			check(used + n < request.len, 456)
			for j in 0 .. n { request[used + j] = encoded[j] }
			used += n
		}
		private := service_private_fd >= 3 && service_private_attached && service_private_owner == C.getpid()
		fd := if private { service_private_fd }
			else { C.socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC | C.SOCK_NONBLOCK, 0) }
		check(fd >= 0, 457)
		if !private {
			mut address := C.sockaddr_un{sun_family: u16(C.AF_UNIX)}
			address.sun_path = service_socket_path()
			check(C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) == 0, 458)
		}
		mut header := [char(used), char(used >> 8), char(used >> 16), char(used >> 24)]!
		service_transfer(fd, &header[0], 4, true)
		service_transfer(fd, &request[0], used, true)
		service_transfer(fd, &header[0], 4, false)
		size := int(u32(u8(header[0])) | (u32(u8(header[1])) << 8)
			| (u32(u8(header[2])) << 16) | (u32(u8(header[3])) << 24))
		check(size > 0 && size < reply.len, 459)
		service_transfer(fd, &reply[0], size, false)
		reply[size] = 0
		if !private { check(C.close(fd) == 0, 460) }
		check((size >= 6 && C.memcmp(&reply[0], c'error\t', 6) == 0) == denied, 461)
		return reply
	}
}

fn service_call(command &char, argument &char, extra &char) {
	if C.strcmp(command, c'attach') == 0 { service_private_attached = true }
	reply := service_request([command, argument, extra, unsafe { &char(nil) }]!,
		if argument == unsafe { nil } { 1 } else if extra == unsafe { nil } { 2 } else { 3 }, false)
	check(C.strcmp(unsafe { &reply[0] }, c'ok') == 0, 484)
	if C.strcmp(command, c'shutdown') == 0 {
		check(C.close(service_private_fd) == 0, 460)
		service_private_fd = 0
		service_private_attached = false
	}
}

fn service_config(mut encoded [8192]char) {
	unsafe {
		mut text := [4096]char{}
		fd := C.open(c'/home/developer/.vinix-services', C.O_RDONLY)
		check(fd >= 0, 462)
		mut st := C.stat{}
		n := C.read(fd, &text[0], text.len - 1)
		check(n > 0 && n < text.len - 1 && C.fstat(fd, &st) == 0 && st.st_uid == 1000
			&& st.st_mode & 0o077 == 0 && C.close(fd) == 0, 463)
		service_hex(&text[0], int(n), mut encoded)
	}
}

fn service_wait(stopped bool) i32 {
	unsafe {
		deadline := job_clock() + 10000000000
		for {
			reply := service_request([&char(c'services'), &char(nil), &char(nil), &char(nil)]!, 1, false)
			line := C.strstr(&reply[0], c'\nservice\t0\t76696e69782d6a6f62732e73657276696365\t')
			mut state := i32(-1)
			mut pid := i32(-1)
			check(line != nil && C.sscanf(line,
				c'\nservice\t0\t76696e69782d6a6f62732e73657276696365\t%d\t%d', &state, &pid) == 2, 464)
			if (stopped && pid == 0) || (!stopped && pid > 1) { return pid }
			check(job_clock() < deadline, 465)
			C.usleep(10000)
		}
		return -1
	}
}

fn service_broker() i32 {
	unsafe {
		if service_private_fd >= 3 { check(C.close(service_private_fd) == 0, 460) }
		service_private_attached = false
		mut pair := [i32(-1), i32(-1)]!
		check(C.socketpair(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC | C.SOCK_NONBLOCK, 0, &pair[0]) == 0, 466)
		pid := C.fork()
		check(pid >= 0, 466)
		if pid == 0 {
			check(C.close(pair[0]) == 0 && C.dup2(pair[1], 3) == 3, 460)
			if pair[1] != 3 { C.close(pair[1]) }
			check(C.fcntl(3, C.F_SETFD, 0) == 0, 460)
			log := C.open(c'/home/developer/service-broker.log', C.O_WRONLY | C.O_CREAT | C.O_APPEND, u32(0o600))
			if log < 0 || C.dup2(log, 1) != 1 || C.dup2(log, 2) != 2 { C._exit(125) }
			if log > 2 { C.close(log) }
			argv := [&char(c'/usr/bin/vinix-session'),
				&char(c'--session-home=/home/developer'), &char(c'--session-control-fd=3'), &char(nil)]!
			C.execv(argv[0], &argv[0])
			C._exit(127)
		}
		check(C.close(pair[1]) == 0, 460)
		service_private_fd = pair[0]
		service_private_owner = C.getpid()
		deadline := job_clock() + 10000000000
		mut address := C.sockaddr_un{sun_family: u16(C.AF_UNIX)}
		address.sun_path = service_socket_path()
		for {
			// bind publishes the pathname before listen admits connections.
			// Probe the listener, then send the authenticated ping below.
			fd := C.socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC | C.SOCK_NONBLOCK, 0)
			check(fd >= 0, 457)
			connected := C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) == 0
			failure := *C.__errno_location()
			check(C.close(fd) == 0, 460)
			if connected { break }
			retry := failure == C.ENOENT || failure == C.ECONNREFUSED
			if !retry || job_clock() >= deadline { emit_command_log(c'/home/developer/service-broker.log') }
			check(retry && C.kill(pid, 0) == 0 && job_clock() < deadline, 467)
			C.usleep(10000)
		}
		mut ready_header := [4]char{}
		mut ready := [5]char{}
		service_transfer(service_private_fd, &ready_header[0], 4, false)
		check(ready_header[0] == char(5) && ready_header[1] == 0 && ready_header[2] == 0 && ready_header[3] == 0, 459)
		service_transfer(service_private_fd, &ready[0], 5, false)
		check(C.memcmp(&ready[0], c'ready', 5) == 0, 459)
		service_call(c'ping', nil, nil)
		return pid
	}
}

fn service_lifecycle_checks() {
	unsafe {
		// This optional input is selected and pinned by the host controller.
		broker_file := C.open(c'/usr/bin/vinix-session', C.O_RDONLY)
		if broker_file < 0 { return }
		check(C.close(broker_file) == 0 && C.mkdir(c'/home/developer/service-runtime', 0o700) == 0
			&& C.setenv(c'VINIX_SESSION_RUNTIME', c'/home/developer/service-runtime', 1) == 0, 468)
		check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/service-jobs.json', c'/home/developer/service-state') == 0, 469)
		check(command_output(c'/usr/bin/vinix-jobs', c'service-unit', c'/home/developer/service-state', nil,
			c'/home/developer/service.service') == 0, 470)
		mut broker := service_broker()
		fields := [&char(c'service.import'), &char(c'vinix-jobs.service'),
			&char(c'/home/developer/service.service'), &char(c'0')]!
		_ = service_request(fields, 4, true)
		check(C.open(c'/home/developer/.vinix-services', C.O_RDONLY) == -1, 471)
		service_call(c'attach', nil, nil)
		_ = service_request(fields, 4, false)
		service_wait(true)
		check(C.open(c'/home/developer/service.parent.pid', C.O_RDONLY) == -1, 472)
		mut disabled := [8192]char{}
		mut enabled := [8192]char{}
		mut actual := [8192]char{}
		service_config(mut disabled)
		// A child of the attached compositor remains an ordinary application.
		child := C.fork()
		check(child >= 0, 473)
		if child == 0 {
			_ = service_request([&char(c'service.enable'), &char(c'0'), &char(c'1'), &char(nil)]!, 3, true)
			C._exit(0)
		}
		wait_jobs(child, 0)
		service_config(mut actual)
		check(C.strcmp(&actual[0], &disabled[0]) == 0, 474)
		mut guardians := [3]i32{}
		mut watchers := [3]i32{}
		mut stopped := [3]u64{}
		for cycle in 0 .. 3 {
			if cycle < 2 { service_call(c'service.enable', c'0', c'1') }
			guardians[cycle] = service_wait(false)
			parent := job_pid(c'/home/developer/service', c'parent')
			payload_child := job_pid(c'/home/developer/service', c'child')
			watchers[cycle] = job_pid(c'/home/developer/service', c'owner')
			check(C.getpgid(parent) == parent && C.getpgid(payload_child) == parent
				&& C.getpgid(watchers[cycle]) == guardians[cycle], 475)
			service_config(mut actual)
			if cycle == 0 { enabled = actual }
			else { check(C.strcmp(&actual[0], &enabled[0]) == 0, 476) }
			before := job_clock()
			if cycle == 1 {
				service_call(c'shutdown', nil, nil)
				wait_jobs(broker, 0)
			} else {
				service_call(c'service.enable', c'0', c'0')
				service_wait(true)
			}
			retired_job(guardians[cycle])
			retired_job(watchers[cycle])
			retired_job(parent)
			retired_job(payload_child)
			stopped[cycle] = (job_clock() - before) / 1000000
			check(stopped[cycle] < 10000, 477)
			mut snapshot := [256]char{}
			C.snprintf(&snapshot[0], snapshot.len, c'/home/developer/service-stop-%d.json', i32(cycle + 1))
			snapshot_job(c'/home/developer/service-state/state.json', &snapshot[0])
			private_receipt(&snapshot[0], c'job interrupted')
			check(C.unlink(c'/home/developer/service.parent.pid') == 0
				&& C.unlink(c'/home/developer/service.child.pid') == 0
				&& C.unlink(c'/home/developer/service.owner.pid') == 0, 478)
			if cycle == 1 {
				service_config(mut actual)
				check(C.strcmp(&actual[0], &enabled[0]) == 0, 479)
				broker = service_broker()
				service_call(c'attach', nil, nil)
			}
		}
		service_config(mut actual)
		check(C.strcmp(&actual[0], &disabled[0]) == 0, 480)
		service_call(c'service.remove', c'vinix-jobs.service', nil)
		mut removed := [8192]char{}
		service_config(mut removed)
		service_call(c'shutdown', nil, nil)
		wait_jobs(broker, 0)
		broker = service_broker()
		reply := service_request([&char(c'services'), &char(nil), &char(nil), &char(nil)]!, 1, false)
		check(C.strcmp(&reply[0], c'vinix-service-status\t1\n') == 0, 481)
		service_call(c'attach', nil, nil)
		service_call(c'shutdown', nil, nil)
		wait_jobs(broker, 0)
		mut proof := [24576]char{}
		length := C.snprintf(&proof[0], proof.len,
			c'{"schema":1,"uid":1000,"guardians":[%d,%d,%d],"watchers":[%d,%d,%d],"stop_millis":[%lu,%lu,%lu],"enabled":"%s","disabled":"%s","removed":"%s"}',
			guardians[0], guardians[1], guardians[2], watchers[0], watchers[1], watchers[2],
			stopped[0], stopped[1], stopped[2], &enabled[0], &disabled[0], &removed[0])
		check(length > 0 && length < proof.len, 482)
		write_text(c'/home/developer/service-proof.json', &proof[0], usize(length))
		private_receipt(c'/home/developer/service-proof.json', c'"schema":1')
		emit_command_log(c'/home/developer/service-broker.log')
		C.puts(c'DEVELOPMENT SERVICE LIFECYCLE PASS: UID 1000, disabled import, ordinary-child refusal, active-job stop, broker shutdown and enabled restoration, removal survives broker restart')
	}
}
