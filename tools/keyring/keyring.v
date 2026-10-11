// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// vinix-keyring: an account's credential store (keyringcore/core.v), as a
// service that holds the store open for a session and the commands that
// ask it.
//
//	vinix-keyring daemon [--unlock-stdin]
//	    serve this account's store on a socket only this account can
//	    reach, until the session ends. With --unlock-stdin a password is
//	    read from standard input first and the store opened with it: how a
//	    login opens the store with what was typed at the login screen.
//
//	vinix-keyring status            absent, locked or unlocked, and how many
//	vinix-keyring init              make the store; prints the recovery key
//	vinix-keyring unlock | lock
//	vinix-keyring set SERVICE ACCOUNT        the secret on standard input
//	vinix-keyring get SERVICE ACCOUNT
//	vinix-keyring delete SERVICE ACCOUNT
//	vinix-keyring list
//	vinix-keyring change-password   the old password, then the new
//	vinix-keyring recover           the recovery key, then a new password;
//	                                prints a new recovery key
//
// Passwords and secrets are read from the terminal without echo, or one per
// line from standard input when that is not a terminal.
//
// The service keeps the store key in memory while the store is open and
// nowhere else. It marks itself undumpable, so no other process of the
// account can read its memory through /proc, and it answers only this
// account. Any program of the account can still ask it for any secret:
// keeping applications apart is confinement's job.
module main

import authproto
import keyringcore
import os

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <termios.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
$if linux {
	#include <sys/prctl.h>
}

fn C.socket(domain int, kind int, protocol int) int
fn C.bind(fd int, address voidptr, length u32) int
fn C.listen(fd int, backlog int) int
fn C.accept(fd int, address voidptr, length voidptr) int
fn C.connect(fd int, address voidptr, length u32) int
fn C.getsockopt(fd int, level int, name int, value voidptr, length &u32) int
fn C.geteuid() u32
fn C.unlink(path &char) int
fn C.umask(mask u32) u32
fn C.fsync(fd int) int
fn C.mlockall(flags int) int
fn C.isatty(fd int) int
fn C.tcgetattr(fd int, termios voidptr) int
fn C.tcsetattr(fd int, action int, termios voidptr) int
fn C.signal(signal int, handler voidptr) voidptr
fn C.alarm(seconds u32) u32
fn C.sleep(seconds u32) u32
$if linux {
	fn C.prctl(option int, a u64, b u64, c u64, d u64) int
} $else {
	fn C.getpeereid(fd int, uid &u32, gid &u32) int
}

struct C.sockaddr_un {
mut:
	sun_family u16
	sun_path   [108]char
}

struct C.termios {
mut:
	c_lflag u32
}

struct Ucred {
mut:
	pid i32
	uid u32
	gid u32
}

const op_status = u16(1)
const op_init = u16(2)
const op_unlock = u16(3)
const op_lock = u16(4)
const op_set = u16(5)
const op_get = u16(6)
const op_delete = u16(7)
const op_list = u16(8)
const op_change = u16(9)
const op_recover = u16(10)

const ok = authproto.status_ok
const refused = authproto.status_denied
const invalid = authproto.status_invalid
const failed = authproto.status_failed

struct Service {
	store_path string
	cost       keyringcore.Cost
mut:
	key      []u8 // empty while the store is locked
	failures int
}

fn fail(message string) {
	eprintln('vinix-keyring: ${message}')
	exit(1)
}

fn home() string {
	value := os.getenv('HOME')
	if value == '' || value[0] != `/` {
		fail('HOME is not set')
	}
	return value
}

fn default_store() string {
	return os.join_path(home(), '.local', 'share', 'vinix', 'keyring')
}

fn default_socket() string {
	runtime := os.getenv('XDG_RUNTIME_DIR')
	if runtime == '' || runtime[0] != `/` {
		fail('XDG_RUNTIME_DIR is not set: there is no session to keep a store open for')
	}
	return os.join_path(runtime, 'vinix-keyring.sock')
}

fn reply(status u16, fields ...string) authproto.Frame {
	return authproto.text_frame(status, ...fields)
}

fn (s &Service) load() !keyringcore.Store {
	info := os.lstat(s.store_path) or { return error('absent') }
	if info.get_filetype() != .regular || info.mode & 0o077 != 0 || info.uid != C.geteuid() {
		return error('${s.store_path} is not a store this account alone can read')
	}
	return keyringcore.parse(os.read_file(s.store_path) or { return error('unreadable') })
}

// The whole store, written beside itself, synced and renamed over the old.
fn (s &Service) save(store keyringcore.Store) ! {
	os.mkdir_all(os.dir(s.store_path), mode: 0o700) or {}
	temporary := s.store_path + '.new'
	os.rm(temporary) or {}
	fd := C.open(&char(temporary.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC,
		0o600)
	if fd < 0 {
		return error('cannot create ${temporary}')
	}
	text := store.format()
	mut done := 0
	for done < text.len {
		put := C.write(fd, unsafe { text.str + done }, usize(text.len - done))
		if put <= 0 {
			C.close(fd)
			os.rm(temporary) or {}
			return error('cannot write ${temporary}')
		}
		done += int(put)
	}
	if C.fsync(fd) != 0 {
		C.close(fd)
		os.rm(temporary) or {}
		return error('cannot sync ${temporary}')
	}
	C.close(fd)
	os.rename(temporary, s.store_path) or {
		os.rm(temporary) or {}
		return error('cannot replace ${s.store_path}')
	}
}

fn (mut s Service) lock() {
	keyringcore.wipe(mut s.key)
	s.key = []u8{}
}

// Wrong passwords make the next try wait, here as at a login.
fn (mut s Service) wrong() {
	s.failures++
	if s.failures >= 3 {
		mut seconds := u32(1) << u32(if s.failures - 3 > 5 { 5 } else { s.failures - 3 })
		C.sleep(seconds)
	}
}

fn (mut s Service) handle(mut request authproto.Frame) authproto.Frame {
	defer { request.wipe() }
	fields := request.fields
	match request.code {
		op_status {
			store := s.load() or {
				return reply(ok, if err.msg() == 'absent' { 'absent' } else { 'unusable' }, '0')
			}
			return reply(ok, if s.key.len > 0 { 'unlocked' } else { 'locked' }, store.count().str())
		}
		op_init {
			if fields.len != 1 || fields[0].len == 0 {
				return reply(invalid, 'init takes a password')
			}
			if os.exists(s.store_path) || os.is_link(s.store_path) {
				return reply(refused, 'there is a store already')
			}
			store, key, recovery := keyringcore.create(fields[0], s.cost) or {
				return reply(failed, err.msg())
			}
			s.save(store) or { return reply(failed, err.msg()) }
			s.key = key
			return reply(ok, recovery)
		}
		op_unlock {
			if fields.len != 1 {
				return reply(invalid, 'unlock takes a password')
			}
			store := s.load() or { return reply(failed, err.msg()) }
			key := store.unlock(fields[0]) or {
				s.wrong()
				return reply(refused, err.msg())
			}
			s.failures = 0
			s.key = key
			return reply(ok)
		}
		op_lock {
			s.lock()
			return reply(ok)
		}
		op_change {
			if fields.len != 2 || fields[1].len == 0 {
				return reply(invalid, 'expected the old and the new password')
			}
			mut store := s.load() or { return reply(failed, err.msg()) }
			// Being unlocked is not enough: whoever asks must know the
			// password that is being replaced.
			key := store.unlock(fields[0]) or {
				s.wrong()
				return reply(refused, err.msg())
			}
			store.set_password(key, fields[1], s.cost) or { return reply(failed, err.msg()) }
			s.save(store) or { return reply(failed, err.msg()) }
			s.failures = 0
			s.key = key
			return reply(ok)
		}
		op_recover {
			if fields.len != 2 || fields[1].len == 0 {
				return reply(invalid, 'expected the recovery key and a new password')
			}
			mut store := s.load() or { return reply(failed, err.msg()) }
			key := store.unlock_with_recovery(fields[0].bytestr()) or {
				s.wrong()
				return reply(refused, err.msg())
			}
			store.set_password(key, fields[1], s.cost) or { return reply(failed, err.msg()) }
			// A recovery key that has been typed somewhere is used up.
			fresh := store.new_recovery(key) or { return reply(failed, err.msg()) }
			s.save(store) or { return reply(failed, err.msg()) }
			s.failures = 0
			s.key = key
			return reply(ok, fresh)
		}
		op_set, op_get, op_delete, op_list {
			if s.key.len == 0 {
				return reply(refused, 'the store is locked')
			}
			mut store := s.load() or { return reply(failed, err.msg()) }
			match request.code {
				op_set {
					if fields.len != 3 {
						return reply(invalid, 'set takes a service, an account and a secret')
					}
					store.put(s.key, service: request.text(0), account: request.text(1), secret: fields[2]) or {
						return reply(invalid, err.msg())
					}
					s.save(store) or { return reply(failed, err.msg()) }
					return reply(ok)
				}
				op_get {
					if fields.len != 2 {
						return reply(invalid, 'get takes a service and an account')
					}
					secret := store.get(s.key, request.text(0), request.text(1)) or {
						return reply(refused, err.msg())
					}
					return authproto.Frame{
						code:   ok
						fields: [secret]
					}
				}
				op_delete {
					if fields.len != 2 {
						return reply(invalid, 'delete takes a service and an account')
					}
					store.delete(s.key, request.text(0), request.text(1)) or {
						return reply(refused, err.msg())
					}
					s.save(store) or { return reply(failed, err.msg()) }
					return reply(ok)
				}
				else {
					items := store.list(s.key) or { return reply(failed, err.msg()) }
					mut lines := []string{cap: items.len}
					for item in items {
						lines << '${item.service}\t${item.account}'
					}
					// A reply has room for a few thousand bytes of names;
					// a store with more is listed as far as that goes.
					mut text := lines.join('\n')
					if text.len > authproto.max_field {
						text = text[..authproto.max_field].all_before_last('\n')
					}
					return reply(ok, text)
				}
			}
		}
		else {
			return reply(invalid, 'unknown request')
		}
	}
}

fn peer_uid(fd int) ?u32 {
	$if linux {
		mut cred := Ucred{}
		mut length := u32(sizeof(Ucred))
		if C.getsockopt(fd, 1, 17, &cred, &length) != 0 {
			return none
		}
		return cred.uid
	} $else {
		mut uid := u32(0)
		mut gid := u32(0)
		if C.getpeereid(fd, &uid, &gid) != 0 {
			return none
		}
		return uid
	}
}

fn socket_address(path string) C.sockaddr_un {
	if path.len >= 100 {
		fail('socket path too long')
	}
	mut address := C.sockaddr_un{}
	address.sun_family = u16(C.AF_UNIX)
	unsafe { vmemcpy(&address.sun_path[0], path.str, path.len) }
	return address
}

fn read_secret(prompt string) []u8 {
	typed := C.isatty(0) == 1
	mut saved := C.termios{}
	if typed {
		eprint(prompt)
		C.tcgetattr(0, &saved)
		mut quiet := saved
		quiet.c_lflag &= ~u32(C.ECHO)
		C.tcsetattr(0, C.TCSAFLUSH, &quiet)
	}
	mut line := []u8{cap: 64}
	mut one := [1]u8{}
	for line.len < authproto.max_field {
		if C.read(0, &one[0], 1) != 1 || one[0] == `\n` {
			break
		}
		line << one[0]
	}
	if typed {
		C.tcsetattr(0, C.TCSAFLUSH, &saved)
		eprintln('')
	}
	return line
}

fn serve(store_path string, socket_path string, unlock bool, cost keyringcore.Cost) {
	$if linux {
		// PR_SET_DUMPABLE 4: nothing else of this account reads this memory.
		C.prctl(4, 0, 0, 0, 0)
	}
	// Keep the key out of swap where that is allowed.
	C.mlockall(3)
	C.umask(0o077)
	mut service := Service{
		store_path: store_path
		cost:       cost
	}
	// Listening before anything slow: whoever asks while the store is
	// being opened waits for the answer instead of finding nobody there.
	C.unlink(&char(socket_path.str))
	listener := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	mut address := socket_address(socket_path)
	if listener < 0 || C.bind(listener, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0
		|| C.listen(listener, 8) != 0 {
		fail('cannot listen on ${socket_path}')
	}
	os.chmod(socket_path, 0o600) or {}
	if unlock {
		// Started by a login, which waits on descriptor 3 until this
		// service can be asked (sessioncore/launch.v).
		C.close(3)
		mut password := read_secret('')
		if password.len > 0 {
			if store := service.load() {
				if key := store.unlock(password) {
					service.key = key
				} else {
					eprintln('vinix-keyring: the login password does not open the store; it stays locked')
				}
			}
		}
		keyringcore.wipe(mut password)
		// Whatever standard input was, the service does not read it again.
		null := C.open(c'/dev/null', C.O_RDONLY)
		if null >= 0 {
			C.dup2(null, 0)
			C.close(null)
		}
	}
	C.signal(C.SIGPIPE, voidptr(1))
	for {
		connection := C.accept(listener, unsafe { nil }, unsafe { nil })
		if connection < 0 {
			continue
		}
		uid := peer_uid(connection) or {
			C.close(connection)
			continue
		}
		if uid != C.geteuid() {
			C.close(connection)
			continue
		}
		// A caller that connects and says nothing does not hold the
		// service up for long.
		C.alarm(10)
		mut request := authproto.read_frame(connection) or {
			C.alarm(0)
			C.close(connection)
			continue
		}
		C.alarm(0)
		mut response := service.handle(mut request)
		authproto.write_frame(connection, response) or {}
		response.wipe()
		C.close(connection)
	}
}

fn C.dup2(old int, new int) int

fn ask(socket_path string, code u16, fields ...[]u8) authproto.Frame {
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	mut address := socket_address(socket_path)
	if fd < 0 || C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
		fail('the keyring service is not running in this session')
	}
	mut request := authproto.Frame{
		code:   code
		fields: fields
	}
	authproto.write_frame(fd, request) or { fail('cannot reach the keyring service') }
	request.wipe()
	answer := authproto.read_frame(fd) or {
		fail('the keyring service did not answer')
		return authproto.Frame{}
	}
	C.close(fd)
	return answer
}

fn finish(answer authproto.Frame) {
	if answer.code == ok {
		exit(0)
	}
	eprintln('vinix-keyring: ${if answer.text(0) == '' { 'refused' } else { answer.text(0) }}')
	exit(if answer.code == invalid { 2 } else { 1 })
}

fn usage() {
	eprintln('usage: vinix-keyring daemon [--unlock-stdin] | status | init | unlock | lock | set SERVICE ACCOUNT | get SERVICE ACCOUNT | delete SERVICE ACCOUNT | list | change-password | recover')
	exit(2)
}

fn main() {
	mut args := os.args[1..].clone()
	mut store_path := ''
	mut socket_path := ''
	// Where the store and the socket are, for tests.
	for args.len >= 2 && (args[0] == '--store' || args[0] == '--socket') {
		if args[0] == '--store' {
			store_path = args[1]
		} else {
			socket_path = args[1]
		}
		args = args[2..].clone()
	}
	if args.len == 0 {
		usage()
	}
	if C.geteuid() == 0 {
		fail('root has no credential store: this is for an account in a session')
	}
	if store_path == '' {
		store_path = default_store()
	}
	if socket_path == '' {
		socket_path = default_socket()
	}
	match args[0] {
		'daemon' {
			// A cheaper cost only where a test asks for it by naming its
			// own store.
			cost := if os.getenv('VINIX_KEYRING_TEST_COST') == '1' {
				keyringcore.Cost{
					ln: 10
				}
			} else {
				keyringcore.Cost{}
			}
			serve(store_path, socket_path, args.len > 1 && args[1] == '--unlock-stdin',
				cost)
		}
		'status' {
			answer := ask(socket_path, op_status)
			println('${answer.text(0)} ${answer.text(1)}')
			finish(answer)
		}
		'init' {
			answer := ask(socket_path, op_init, read_secret('Password: '))
			if answer.code == ok {
				println(answer.text(0))
				eprintln('This is the recovery key. It opens the store if the password is lost,')
				eprintln('and it is shown this once: write it down and keep it away from this machine.')
			}
			finish(answer)
		}
		'unlock' {
			finish(ask(socket_path, op_unlock, read_secret('Password: ')))
		}
		'lock' {
			finish(ask(socket_path, op_lock))
		}
		'set' {
			if args.len != 3 {
				usage()
			}
			finish(ask(socket_path, op_set, args[1].bytes(), args[2].bytes(), read_secret('Secret: ')))
		}
		'get' {
			if args.len != 3 {
				usage()
			}
			answer := ask(socket_path, op_get, args[1].bytes(), args[2].bytes())
			if answer.code == ok && answer.fields.len == 1 {
				println(answer.text(0))
			}
			finish(answer)
		}
		'delete' {
			if args.len != 3 {
				usage()
			}
			finish(ask(socket_path, op_delete, args[1].bytes(), args[2].bytes()))
		}
		'list' {
			answer := ask(socket_path, op_list)
			if answer.code == ok && answer.text(0) != '' {
				println(answer.text(0))
			}
			finish(answer)
		}
		'change-password' {
			old := read_secret('Current password: ')
			finish(ask(socket_path, op_change, old, read_secret('New password: ')))
		}
		'recover' {
			recovery := read_secret('Recovery key: ')
			answer := ask(socket_path, op_recover, recovery, read_secret('New password: '))
			if answer.code == ok {
				println(answer.text(0))
				eprintln('The store is open and has a new recovery key, above: the old one no longer works.')
			}
			finish(answer)
		}
		else {
			usage()
		}
	}
}
