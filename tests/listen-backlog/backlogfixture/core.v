// Independent listen backlog probe; all original deadlines and checks retained.
@[translated; has_globals]
module backlogfixture

#include <backlog-native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.vlb_native_ull {}
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct C.pollfd { mut: fd i32 events i16 revents i16 }
struct C.sockaddr_un { mut: sun_family u16 sun_path [108]char }
struct C.sockaddr {}
@[c_extern] __global C.errno i32
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.stderr &C.FILE
@[cinit] __global listener = i32(-1)
@[cinit] __global client = i32(-1)
@[cinit] __global peer = i32(-1)
__global socket_path [108]char
const backlogs = [i32(-1), i32(-2147483647 - 1), i32(2147483647), i32(0), i32(1), i32(128), i32(4096)]!

fn C.close(i32) i32
fn C.unlink(&char) i32
fn C.fprintf(&C.FILE, &char, ...) i32
fn C.exit(i32)
fn C.clock_gettime(i32, &C.timespec) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.listen(i32, i32) i32
fn C.syscall(isize, ...) isize
fn C.send(i32, voidptr, usize, i32) isize
fn C.recv(i32, voidptr, usize, i32) isize
fn C.snprintf(&char, usize, &char, ...) i32
fn C.getpid() i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.socket(i32, i32, i32) i32
fn C.bind(i32, &C.sockaddr, u32) i32
fn C.connect(i32, &C.sockaddr, u32) i32
fn C.getsockopt(i32, i32, i32, voidptr, &u32) i32
fn C.accept4(i32, voidptr, voidptr, i32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32

fn cleanup() {
	unsafe {
		if peer >= 0 { C.close(peer) }
		if client >= 0 { C.close(client) }
		if listener >= 0 { C.close(listener) }
		peer = -1
		client = -1
		listener = -1
		if socket_path[0] != 0 { C.unlink(&socket_path[0]) }
		socket_path[0] = 0
	}
}

fn require(condition bool, operation &char) {
	unsafe {
		if !condition {
			saved_errno := C.errno
			C.fprintf(C.stderr, c'LISTEN-BACKLOG-FAIL %s errno=%d\n', operation, saved_errno)
			cleanup()
			C.exit(1)
		}
	}
}

fn monotonic_ms() i64 {
	unsafe {
		mut now := C.timespec{}
		require(C.clock_gettime(C.CLOCK_MONOTONIC, &now) == 0, c'read monotonic clock')
		return now.tv_sec * 1000 + now.tv_nsec / 1000000
	}
}

fn ready(fd i32, events i16, operation &char) {
	unsafe {
		mut watched := C.pollfd{fd: fd, events: events}
		deadline := monotonic_ms() + 5000
		for {
			remaining := deadline - monotonic_ms()
			require(remaining > 0, operation)
			result := C.poll(&watched, 1, i32(remaining))
			if result < 0 && C.errno == C.EINTR { continue }
			require(result == 1 && (watched.revents & events) != 0, operation)
			return
		}
	}
}

fn listen_promptly(backlog i32) {
	unsafe {
		start := monotonic_ms()
		require(C.listen(listener, backlog) == 0, c'listen succeeds')
		require(monotonic_ms() - start < 5000, c'listen returns within five seconds')
	}
}

fn raw_listen_promptly(backlog i32) {
	unsafe {
		argument_bits := (u64(1) << 32) | u64(u32(backlog))
		mut argument := C.vlb_native_ull{}
		C.memcpy(&argument, &argument_bits, sizeof(C.vlb_native_ull))
		start := monotonic_ms()
		require(C.syscall(C.SYS_listen, listener, argument) == 0, c'raw listen truncates upper word')
		require(monotonic_ms() - start < 5000, c'raw listen returns within five seconds')
	}
}

fn send_byte(fd i32, value u8) {
	unsafe {
		ready(fd, C.POLLOUT, c'socket becomes writable')
		require(C.send(fd, &value, 1, C.MSG_NOSIGNAL) == 1, c'send one byte')
	}
}

fn receive_byte(fd i32, expected u8) {
	unsafe {
		mut value := u8(0)
		ready(fd, C.POLLIN, c'socket becomes readable')
		require(C.recv(fd, &value, 1, 0) == 1, c'receive one byte')
		require(value == expected, c'received byte matches peer')
	}
}

fn exercise(backlog i32, index u32) {
	unsafe {
		mut address := C.sockaddr_un{sun_family: C.AF_UNIX}
		written := C.snprintf(&socket_path[0], sizeof(socket_path), c'/tmp/vinix-listen-%ld-%u.sock', i64(C.getpid()), index)
		require(written > 0 && usize(written) < sizeof(socket_path), c'socket pathname fits')
		C.memcpy(&address.sun_path[0], &socket_path[0], usize(written) + 1)
		address_length := u32(C.VLB_PATH_OFFSET + written + 1)
		require(C.unlink(&socket_path[0]) == 0 || C.errno == C.ENOENT, c'remove stale endpoint')
		listener = C.socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_NONBLOCK | C.SOCK_CLOEXEC, 0)
		require(listener >= 0, c'create nonblocking listener')
		require(C.bind(listener, &C.sockaddr(&address), address_length) == 0, c'bind listener')
		C.printf(c'LISTEN-BACKLOG-BEGIN backlog=%d\n', backlog)
		raw_listen_promptly(backlog)
		listen_promptly(backlog)
		client = C.socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_NONBLOCK | C.SOCK_CLOEXEC, 0)
		require(client >= 0, c'create nonblocking client')
		connected := C.connect(client, &C.sockaddr(&address), address_length)
		require(connected == 0 || (connected < 0 && C.errno == C.EINPROGRESS), c'connect client')
		if connected < 0 {
			ready(client, C.POLLOUT, c'connection completes')
			mut error := i32(-1)
			mut length := u32(sizeof(error))
			require(C.getsockopt(client, C.SOL_SOCKET, C.SO_ERROR, &error, &length) == 0 && error == 0, c'connection has no socket error')
		}
		request := u8(u32(0x40) + index)
		send_byte(client, request)
		listen_promptly(-1)
		listen_promptly(0)
		ready(listener, C.POLLIN, c'queued connection survives repeated listen')
		peer = C.accept4(listener, nil, nil, C.SOCK_NONBLOCK | C.SOCK_CLOEXEC)
		require(peer >= 0, c'accept queued connection')
		receive_byte(peer, request)
		send_byte(peer, u8(request + 1))
		receive_byte(client, u8(request + 1))
		require(C.close(peer) == 0, c'close accepted endpoint')
		peer = -1
		require(C.close(client) == 0, c'close client endpoint')
		client = -1
		require(C.close(listener) == 0, c'close listener endpoint')
		listener = -1
		require(C.unlink(&socket_path[0]) == 0, c'unlink listener endpoint')
		socket_path[0] = 0
		C.printf(c'LISTEN-BACKLOG-CASE-PASS backlog=%d queued_connection=preserved\n', backlog)
	}
}

@[export: 'vinix_independent_fixture']
pub fn run() i32 {
	unsafe {
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		for i := u32(0); i < 7; i++ { exercise(backlogs[i], i) }
		C.puts(c'LISTEN-BACKLOG-PASS cases=7')
		return 0
	}
}
