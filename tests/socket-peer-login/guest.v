module main

// Target-only Linux ABI fixture. All implementation is V; C supplies libc ABI.
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <sys/socket.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}

fn C.socket(i32, i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.bind(i32, voidptr, u32) i32
fn C.listen(i32, i32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.accept(i32, voidptr, voidptr) i32
fn C.getsockopt(i32, i32, i32, voidptr, &u32) i32
fn C.close(i32) i32
fn C.getpid() i32
fn C.alarm(u32) u32
fn C.sched_yield() i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)
fn C.__atomic_add_fetch(&u32, u32, i32) u32

const peer_option = i32(0x564c)
const address_length = u32(16)

struct Address {
mut:
	family u16 = 1
	path [108]u8
}

struct PeerLogin {
	uid u32
	session u32
}

struct Connector {
mut:
	fd i32
	address Address
	ready &u32 = unsafe { nil }
	start &u32 = unsafe { nil }
	result i32 = -2
	error_code i32
}

fn demand(ok bool, message string) {
	if !ok { panic('PEER-LOGIN FAIL: ' + message) }
}

fn address(tag u8, round u16) Address {
	mut result := Address{}
	result.path[1] = `v`; result.path[2] = `p`; result.path[3] = `l`
	pid := u32(C.getpid())
	for i in 0 .. 4 { result.path[4 + i] = u8(pid >> (i * 8)) }
	result.path[8] = tag
	result.path[9] = u8(round); result.path[10] = u8(round >> 8)
	return result
}

fn stream() i32 {
	fd := C.socket(1, 1, 0)
	demand(fd >= 0, 'socket')
	return fd
}

fn listener(name &Address) i32 {
	// Nonblocking accept proves that the losing listener has no queued child.
	fd := C.socket(1, 1 | 0x800, 0)
	demand(fd >= 0, 'listener socket')
	demand(C.bind(fd, voidptr(name), address_length) == 0, 'bind')
	demand(C.listen(fd, 8) == 0, 'listen')
	return fd
}

fn identity(fd i32, expected PeerLogin) {
	mut value := PeerLogin{}
	mut length := u32(sizeof(PeerLogin))
	demand(C.getsockopt(fd, 1, peer_option, &value, &length) == 0, 'get peer identity')
	demand(length == 8 && value == expected, 'exact peer tuple and size')
}

fn unconnected(fd i32) {
	mut value := PeerLogin{}
	mut length := u32(8)
	demand(C.getsockopt(fd, 1, peer_option, &value, &length) == -1
		&& C.errno == C.ENOTCONN, 'unconnected identity refusal')
}

fn pair_checks() PeerLogin {
	mut pair := [2]i32{}
	demand(C.socketpair(1, 1, 0, &pair[0]) == 0, 'socketpair')
	defer { C.close(pair[0]); C.close(pair[1]) }
	mut expected := PeerLogin{}
	mut length := u32(8)
	demand(C.getsockopt(pair[0], 1, peer_option, &expected, &length) == 0 && length == 8,
		'socketpair initial identity')
	identity(pair[1], expected)
	length = 7
	demand(C.getsockopt(pair[0], 1, peer_option, &expected, &length) == -1
		&& C.errno == C.EINVAL, 'short capacity refusal')
	length = 8
	demand(C.getsockopt(pair[0], 1, peer_option, unsafe { nil }, &length) == -1
		&& C.errno == C.EFAULT, 'null value refusal')
	return expected
}

fn failed_retry(expected PeerLogin) {
	client := stream()
	defer { C.close(client) }
	unconnected(client)
	absent := address(1, 0)
	demand(C.connect(client, voidptr(&absent), address_length) == -1 && C.errno == C.ECONNREFUSED,
		'failed connect')
	unconnected(client)
	name := address(2, 0)
	server := listener(&name)
	defer { C.close(server) }
	demand(C.connect(client, voidptr(&name), address_length) == 0, 'retry after failed connect')
	accepted := C.accept(server, unsafe { nil }, unsafe { nil })
	demand(accepted >= 0, 'accept retry')
	identity(client, expected); identity(accepted, expected)
	demand(C.connect(client, voidptr(&name), address_length) == -1 && C.errno == C.EISCONN,
		'repeated connect refusal')
	C.close(accepted)
	identity(client, expected)
	println('PEER-LOGIN failed-retry repeated-connect peer-close PASS')
}

fn connect_worker(raw voidptr) voidptr {
	mut work := unsafe { &Connector(raw) }
	C.__atomic_add_fetch(work.ready, 1, C.__ATOMIC_RELEASE)
	for C.__atomic_load_n(work.start, C.__ATOMIC_ACQUIRE) == 0 { C.sched_yield() }
	work.result = C.connect(work.fd, voidptr(&work.address), address_length)
	work.error_code = C.errno
	return unsafe { nil }
}

fn concurrent_connect(round u16, expected PeerLogin) {
	left_name := address(3, round)
	right_name := address(4, round)
	left := listener(&left_name); right := listener(&right_name)
	client := stream()
	defer { C.close(client); C.close(left); C.close(right) }
	mut ready := u32(0)
	mut start := u32(0)
	mut a := Connector{fd: client, address: left_name, ready: unsafe { &ready }, start: unsafe { &start }}
	mut b := Connector{fd: client, address: right_name, ready: unsafe { &ready }, start: unsafe { &start }}
	mut thread_a := C.pthread_t{}
	mut thread_b := C.pthread_t{}
	demand(C.pthread_create(&thread_a, unsafe { nil }, connect_worker, unsafe { &a }) == 0,
		'create first connector')
	demand(C.pthread_create(&thread_b, unsafe { nil }, connect_worker, unsafe { &b }) == 0,
		'create second connector')
	for C.__atomic_load_n(&ready, C.__ATOMIC_ACQUIRE) != 2 { C.sched_yield() }
	C.__atomic_store_n(&start, 1, C.__ATOMIC_RELEASE)
	demand(C.pthread_join(thread_a, unsafe { nil }) == 0, 'join first connector')
	demand(C.pthread_join(thread_b, unsafe { nil }) == 0, 'join second connector')
	demand((a.result == 0) != (b.result == 0), 'exactly one connection wins')
	loser := if a.result == 0 { b } else { a }
	demand(loser.result == -1 && loser.error_code in [i32(C.EALREADY), i32(C.EISCONN)],
		'concurrent loser refusal')
	winner_fd := if a.result == 0 { left } else { right }
	loser_fd := if a.result == 0 { right } else { left }
	accepted := C.accept(winner_fd, unsafe { nil }, unsafe { nil })
	demand(accepted >= 0, 'winning listener accepts')
	defer { C.close(accepted) }
	demand(C.accept(loser_fd, unsafe { nil }, unsafe { nil }) == -1 && C.errno == C.EAGAIN,
		'losing listener queue remains empty')
	identity(client, expected); identity(accepted, expected)
	mut sent := u8(0x6b)
	mut received := u8(0)
	demand(C.write(client, &sent, 1) == 1 && C.read(accepted, &received, 1) == 1
		&& received == sent, 'winning peer matches transport')
	demand(C.connect(client, voidptr(&left_name), address_length) == -1 && C.errno == C.EISCONN,
		'connected socket cannot move to another listener')
}

fn main() {
	// Bounds failed thread startup and every blocking libc operation as well.
	C.alarm(30)
	demand(sizeof(Address) == 110 && sizeof(PeerLogin) == 8, 'Linux ABI sizes')
	expected := pair_checks()
	failed_retry(expected)
	for round in u16(0) .. u16(32) { concurrent_connect(round, expected) }
	C.alarm(0)
	println('PEER-LOGIN concurrent-connect rounds=32 PASS')
	println('PEER-LOGIN ALL PASS')
}
