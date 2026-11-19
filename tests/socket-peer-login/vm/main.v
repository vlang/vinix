// SPDX-License-Identifier: GPL-2.0-or-later
// PID 1 of the peer-login machine. It runs the transport fixture
// (/usr/bin/peer-login) as an ordinary child, then checks what that fixture
// cannot: that the record names the login of the other end, across logins.
//
// PID 1 itself belongs to the system (uid 4294967295, session 0) and stays
// so; every login here is started by a child for itself.
module main

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/reboot.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.fork() i32
fn C.execve(&char, &&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pipe(&i32) i32
fn C.socket(i32, i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.bind(i32, voidptr, u32) i32
fn C.listen(i32, i32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.accept(i32, voidptr, voidptr) i32
fn C.getsockopt(i32, i32, i32, voidptr, &u32) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.alarm(u32) u32
fn C.chmod(&char, u32) i32
fn C.signal(i32, fn (i32)) voidptr
fn C.sync()
fn C.reboot(i32) i32
fn C._exit(i32)

const peer_option = i32(0x564c)
const peer_credentials = i32(17)
const system = PeerLogin{0xffffffff, 0}

struct Address {
mut:
	family u16 = 1
	path   [108]u8
}

struct PeerLogin {
	uid     u32
	session u32
}

struct Credentials {
	pid i32
	uid u32
	gid u32
}

// Everything a child is told and tells goes through pipes: one byte to go
// on, one login record to report.
struct Pipe {
mut:
	ends [2]i32
}

fn say(line string) {
	text := line + '\n'
	mut offset := 0
	for offset < text.len {
		written := unsafe { C.write(1, text.str + offset, usize(text.len - offset)) }
		if written == -1 && C.errno == C.EINTR { continue }
		if written <= 0 { return }
		offset += int(written)
	}
}

fn power_off() {
	C.sync()
	C.reboot(C.RB_POWER_OFF)
	for {}
}

// A process inside a login that does not hold the seat cannot write to the
// console it inherited, so a child leaves what went wrong in a file and PID 1
// prints it: when the child is reaped, or when the alarm ends a wait for a
// child that will never come.
const failures = '/tmp/peer-login-failures'

fn print_failures() {
	fd := C.open(failures.str, C.O_RDONLY)
	if fd < 0 { return }
	mut buffer := [512]u8{}
	for {
		got := C.read(fd, &buffer[0], 512)
		if got <= 0 { break }
		C.write(1, &buffer[0], usize(got))
	}
	C.close(fd)
}

fn give_up(_ i32) {
	print_failures()
	say('PEER-LOGIN VM FAIL timed out')
	say('HWTEST FAIL peer-login')
	power_off()
}

fn demand(ok bool, message string) {
	if ok { return }
	code := C.errno
	line := 'PEER-LOGIN VM FAIL ' + message + ' errno=' + code.str()
	if C.getpid() == 1 {
		print_failures()
		say(line)
		say('HWTEST FAIL peer-login')
		power_off()
	}
	fd := C.open(failures.str, C.O_WRONLY | C.O_APPEND)
	if fd >= 0 {
		text := line + '\n'
		C.write(fd, text.str, usize(text.len))
		C.close(fd)
	}
	C._exit(1)
}

fn C.getpid() i32

fn address(name string) Address {
	mut result := Address{}
	for i in 0 .. name.len { result.path[i] = name[i] }
	return result
}

fn stream() i32 {
	fd := C.socket(1, 1, 0)
	demand(fd >= 0, 'socket')
	return fd
}

fn listener(name string) i32 {
	fd := stream()
	where := address(name)
	demand(C.bind(fd, voidptr(&where), u32(sizeof(Address))) == 0, 'bind ' + name)
	demand(C.listen(fd, 8) == 0, 'listen ' + name)
	return fd
}

fn connected(name string) i32 {
	fd := stream()
	where := address(name)
	demand(C.connect(fd, voidptr(&where), u32(sizeof(Address))) == 0, 'connect ' + name)
	return fd
}

fn accepted(server i32, what string) i32 {
	fd := C.accept(server, unsafe { nil }, unsafe { nil })
	demand(fd >= 0, 'accept ' + what)
	return fd
}

fn login_of(fd i32, what string) PeerLogin {
	mut value := PeerLogin{}
	mut length := u32(sizeof(PeerLogin))
	demand(C.getsockopt(fd, 1, peer_option, &value, &length) == 0 && length == 8, 'peer login of ' + what)
	return value
}

fn expect(fd i32, wanted PeerLogin, what string) {
	got := login_of(fd, what)
	demand(got == wanted, '${what}: peer login ${got.uid}/${got.session}, wanted ${wanted.uid}/${wanted.session}')
}

fn refused(fd i32, wanted i32, what string) {
	mut value := PeerLogin{}
	mut length := u32(sizeof(PeerLogin))
	demand(C.getsockopt(fd, 1, peer_option, &value, &length) == -1 && C.errno == wanted, what)
}

fn number(path string) u32 {
	fd := C.open(path.str, C.O_RDONLY)
	demand(fd >= 0, 'open ' + path)
	mut buffer := [32]u8{}
	got := C.read(fd, &buffer[0], 31)
	C.close(fd)
	demand(got > 0, 'read ' + path)
	return unsafe { tos(&buffer[0], int(got)) }.trim_space().u32()
}

// Start a login session for the calling process, as the session manager
// does for the program it is about to hand to a user.
fn log_in(uid u32) PeerLogin {
	fd := C.open(c'/proc/self/loginuid', C.O_WRONLY)
	demand(fd >= 0, 'open loginuid')
	text := uid.str()
	demand(C.write(fd, text.str, usize(text.len)) == text.len, 'start login session')
	C.close(fd)
	identity := PeerLogin{number('/proc/self/loginuid'), number('/proc/self/sessionid')}
	demand(identity.uid == uid && identity.session != 0, 'login session was not started')
	return identity
}

fn pipe() Pipe {
	mut result := Pipe{}
	demand(C.pipe(&result.ends[0]) == 0, 'pipe')
	return result
}

fn (p &Pipe) go_on() {
	mut byte := u8(1)
	demand(C.write(p.ends[1], &byte, 1) == 1, 'release')
}

fn (p &Pipe) wait() {
	mut byte := u8(0)
	demand(C.read(p.ends[0], &byte, 1) == 1, 'wait for release')
}

fn (p &Pipe) report(identity PeerLogin) {
	demand(C.write(p.ends[1], &identity, 8) == 8, 'report login')
}

fn (p &Pipe) reported() PeerLogin {
	mut identity := PeerLogin{}
	demand(C.read(p.ends[0], &identity, 8) == 8, 'read reported login')
	return identity
}

fn reap(pid i32, what string) {
	mut status := i32(0)
	for {
		got := C.waitpid(pid, &status, 0)
		if got == -1 && C.errno == C.EINTR { continue }
		demand(got == pid, 'waitpid ' + what)
		break
	}
	demand(status == 0, '${what} ended with raw status ${status}')
}

fn run_fixture() {
	mut argv := [&char(c'/usr/bin/peer-login'), &char(unsafe { nil })]!
	mut envp := [&char(unsafe { nil })]!
	child := C.fork()
	demand(child >= 0, 'fork fixture')
	if child == 0 {
		unsafe { C.execve(c'/usr/bin/peer-login', &argv[0], &envp[0]) }
		C._exit(127)
	}
	reap(child, 'transport fixture')
}

// What a logged-in child does. `early` was made by the system before the
// child existed; `before` is made by the child before it logs in and
// `after` once it has.
fn logged_in_child(round int, uid u32, up &Pipe, down &Pipe) {
	before := listener('/tmp/peer-before-${round}')
	identity := log_in(uid)
	after := listener('/tmp/peer-after-${round}')
	// The system made the listener: that is who is at the other end, and
	// this end's own login changes nothing about it.
	first := connected('/tmp/peer-early')
	expect(first, system, 'login connecting to a system listener')
	// A pair made inside the login is the login at both ends.
	mut pair := [2]i32{}
	demand(C.socketpair(1, 1, 0, &pair[0]) == 0, 'socketpair')
	expect(pair[0], identity, 'pair inside a login')
	expect(pair[1], identity, 'pair inside a login, other end')
	// What the login starts is the login, whatever uid it goes on to run
	// as: the label is not the credentials.
	other := C.fork()
	demand(other >= 0, 'fork inside login')
	if other == 0 {
		demand(C.setgid(2000 + uid) == 0 && C.setuid(2000 + uid) == 0, 'change identity inside login')
		second := connected('/tmp/peer-early')
		expect(second, system, 'descendant connecting to a system listener')
		down.wait()
		C._exit(0)
	}
	up.report(identity)
	from_before := accepted(before, 'listener made before login')
	expect(from_before, system, 'system connecting to a listener made before login')
	from_after := accepted(after, 'listener made after login')
	expect(from_after, system, 'system connecting to a listener made after login')
	up.go_on()
	down.wait()
	reap(other, 'descendant inside login')
	C._exit(0)
}

fn credentials_of(fd i32) Credentials {
	mut value := Credentials{}
	mut length := u32(sizeof(Credentials))
	demand(C.getsockopt(fd, 1, peer_credentials, &value, &length) == 0 && length == 12, 'peer credentials')
	return value
}

// One login from start to finish, seen from the system's side. Returns the
// session it was.
fn one_login(round int, uid u32, early i32) PeerLogin {
	up := pipe()
	down := pipe()
	child := C.fork()
	demand(child >= 0, 'fork login')
	if child == 0 {
		logged_in_child(round, uid, &up, &down)
		C._exit(0)
	}
	identity := up.reported()
	demand(identity.uid == uid && identity.session != 0, 'child reported no login')
	// The two connections to the system's listener, in the order they were
	// made: the login itself, then what it started under another uid.
	own := accepted(early, 'login')
	expect(own, identity, 'login accepted by the system')
	demand(credentials_of(own).uid == 0, 'login still runs as root')
	descendant := accepted(early, 'descendant')
	expect(descendant, identity, 'descendant accepted by the system')
	demand(credentials_of(descendant).uid == 2000 + uid, 'descendant runs as another uid')
	// A listener is whoever its maker was when it was made.
	to_before := connected('/tmp/peer-before-${round}')
	expect(to_before, system, 'listener made before login')
	to_after := connected('/tmp/peer-after-${round}')
	expect(to_after, identity, 'listener made after login')
	up.wait()
	down.go_on()
	down.go_on()
	reap(child, 'login')
	// The record outlives the process it describes, which a lookup of the
	// peer's pid cannot: the pid may by now be someone else's.
	expect(own, identity, 'login after its process is gone')
	expect(descendant, identity, 'descendant after its process is gone')
	expect(to_after, identity, 'listener of a login that is gone')
	for fd in [own, descendant, to_before, to_after, up.ends[0], up.ends[1], down.ends[0], down.ends[1]] {
		C.close(fd)
	}
	return identity
}

fn across_logins() {
	early := listener('/tmp/peer-early')
	// What a login runs under another uid must be able to reach it.
	demand(C.chmod(c'/tmp/peer-early', 0o666) == 0, 'open the system listener to everyone')
	first := one_login(1, 1000, early)
	second := one_login(2, 1001, early)
	demand(first.session != second.session, 'two logins share a session')
	// The same person logging in again is another login.
	third := one_login(3, 1000, early)
	demand(third.session != first.session && third.session != second.session, 'a later login reuses a session')
	say('PEER-LOGIN across-logins sessions=${first.session},${second.session},${third.session} PASS')
	// Sockets that are no connection, and sockets that are no UNIX socket.
	datagram := C.socket(1, 2, 0)
	demand(datagram >= 0, 'datagram socket')
	refused(datagram, C.ENOTCONN, 'datagram socket has no peer login')
	refused(early, C.ENOTCONN, 'listener has no peer login')
	internet := C.socket(2, 1, 0)
	demand(internet >= 0, 'internet socket')
	refused(internet, C.ENOPROTOOPT, 'internet socket has no peer login')
	say('PEER-LOGIN unconnected-and-foreign refusals PASS')
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 {
		C.dup2(fd, 1)
		C.dup2(fd, 2)
		if fd > 2 { C.close(fd) }
	}
	say('HWTEST START peer-login')
	created := C.open(failures.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, 0o666)
	demand(created >= 0 && C.chmod(failures.str, 0o666) == 0, 'create the failure record')
	C.close(created)
	C.signal(C.SIGALRM, give_up)
	C.alarm(60)
	run_fixture()
	across_logins()
	C.alarm(0)
	say('HWTEST PASS peer-login')
	power_off()
}
