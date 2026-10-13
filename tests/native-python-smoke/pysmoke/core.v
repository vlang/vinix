// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module pysmoke

import cpythonapi as py
import os

__global (
	callback_api &py.Api = unsafe { nil }
)

struct Smoke {
mut:
	failures []string
}

fn (mut smoke Smoke) check(condition bool, description string) {
	C.printf(c'%-40s %s\n', description.str, if condition { c'ok' } else { c'FAIL' })
	flush_stdout()
	if !condition { smoke.failures << description }
}

fn (mut smoke Smoke) filesystem(api &py.Api, work string) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	posix := a.load('os')!
	builtins := a.load('builtins')!
	paths := a.attr(posix, 'path')!
	a.method(posix, 'makedirs', [a.text(work)!], {
		'exist_ok': a.boolean(true)!
	})!
	path := work + '/file'
	output := a.method(builtins, 'open', [a.text(path)!, a.text('w')!], {})!
	a.method(output, 'write', [a.text('hello\n'.repeat(100))!], {})!
	a.method(output, 'close', [], {})!
	smoke.check(a.integer(a.method(paths, 'getsize', [a.text(path)!], {})!)! == 600, 'write and stat a file')
	input := a.method(builtins, 'open', [a.text(path)!], {})!
	smoke.check(a.length(a.method(input, 'readlines', [], {})!)! == 100, 'read it back')
	a.method(input, 'close', [], {})!
	a.method(posix, 'rename', [a.text(path)!, a.text(path + '2')!], {})!
	smoke.check(a.truth(a.method(paths, 'exists', [a.text(path + '2')!], {})!)! && !a.truth(a.method(paths, 'exists', [a.text(path)!], {})!)!, 'os.rename')
	a.method(posix, 'symlink', [a.text('file2')!, a.text(work + '/link')!], {})!
	smoke.check(a.string(a.method(posix, 'readlink', [a.text(work + '/link')!], {})!)! == 'file2', 'symlink and readlink')
	listing := a.method(builtins, 'sorted', [a.method(posix, 'listdir', [a.text(work)!], {})!], {})!
	smoke.check(a.equal(listing, a.list([a.text('file2')!, a.text('link')!])!)!, 'os.listdir')
	a.method(posix, 'truncate', [a.text(path + '2')!, a.int(10)!], {})!
	smoke.check(a.integer(a.method(paths, 'getsize', [a.text(path + '2')!], {})!)! == 10, 'os.truncate')
	state := a.method(posix, 'statvfs', [a.text('/tmp')!], {})!
	smoke.check(a.integer(a.attr(state, 'f_bsize')!)! > 0, 'os.statvfs')
}

fn (mut smoke Smoke) processes(api &py.Api) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	posix := a.load('os')!
	pair := a.method(posix, 'pipe', [], {})!
	read_fd, write_fd := a.item(pair, 0)!, a.item(pair, 1)!
	pid := a.method(posix, 'fork', [], {})!
	if a.integer(pid)! == 0 {
		a.method(posix, 'close', [read_fd], {})!
		a.method(posix, 'write', [write_fd, a.data('from the child'.bytes())!], {})!
		a.method(posix, '_exit', [a.int(3)!], {})!
		return error('CPython _exit returned')
	}
	a.method(posix, 'close', [write_fd], {})!
	data := a.method(posix, 'read', [read_fd, a.int(64)!], {})!
	waited := a.method(posix, 'waitpid', [pid, a.int(0)!], {})!
	status := a.item(waited, 1)!
	smoke.check(a.bytes(data)! == 'from the child'.bytes(), 'fork and pipe')
	smoke.check(a.truth(a.method(posix, 'WIFEXITED', [status], {})!)! && a.integer(a.method(posix, 'WEXITSTATUS', [status], {})!)! == 3, 'waitpid exit status')
	a.method(posix, 'close', [read_fd], {})!
	subprocess := a.load('subprocess')!
	result := a.method(subprocess, 'run', [a.list([a.text('/bin/busybox')!, a.text('echo')!,
		a.text('subprocess works')!])!], {
		'capture_output': a.boolean(true)!
		'text':           a.boolean(true)!
	})!
	smoke.check(a.integer(a.attr(result, 'returncode')!)! == 0 && a.string(a.attr(result, 'stdout')!)!.contains('subprocess works'), 'subprocess.run')
}

struct CallbackState {
	seen         py.Ref
	synchronizer py.Ref
	method       py.Method
}

fn callback_destroy(capsule py.Ref) {
	api := callback_api
	if api == unsafe { nil } { return }
	state := unsafe { &CallbackState(api.capsule_pointer(capsule, nil)) }
	if state == unsafe { nil } { return }
	api.dec(state.seen)
	api.dec(state.synchronizer)
	unsafe { free(state) }
}

fn callback(mut a py.Arena, seen py.Ref, synchronizer py.Ref, name &char, function voidptr) !py.Ref {
	state := &CallbackState{ seen: seen, synchronizer: synchronizer, method: py.Method{ name: name, function: function } }
	a.api.inc(seen)
	a.api.inc(synchronizer)
	reference := a.api.capsule_new(state, nil, voidptr(callback_destroy))
	if reference == unsafe { nil } {
		a.api.dec(seen)
		a.api.dec(synchronizer)
		unsafe { free(state) }
		return a.api.exception()
	}
	capsule := a.take(reference)!
	return a.take(a.api.function_new(&state.method, capsule, nil))!
}

fn worker_callback(capsule py.Ref, args py.Ref) py.Ref {
	api := callback_api
	state := unsafe { &CallbackState(api.capsule_pointer(capsule, nil)) }
	mut a := py.Arena{ api: api }
	defer { a.close() }
	result := worker_run(mut a, state, args) or {
		api.error_string(api.runtime_error, err.msg().str)
		return py.Ref(unsafe { nil })
	}
	api.inc(result) // transfer a separate reference; the arena still owns its copy
	return result
}

fn worker_run(mut a py.Arena, state &CallbackState, args py.Ref) !py.Ref {
	a.method(state.synchronizer, 'acquire', [], {})!
	defer { a.method(state.synchronizer, 'release', [], {}) or {} }
	if a.api.append(state.seen, a.item(args, 0)!) != 0 { return a.api.exception() }
	return a.borrow(a.api.none)!
}

fn waiter_callback(capsule py.Ref, _ py.Ref) py.Ref {
	api := callback_api
	state := unsafe { &CallbackState(api.capsule_pointer(capsule, nil)) }
	mut a := py.Arena{ api: api }
	defer { a.close() }
	result := waiter_run(mut a, state) or {
		api.error_string(api.runtime_error, err.msg().str)
		return py.Ref(unsafe { nil })
	}
	api.inc(result)
	return result
}

fn waiter_run(mut a py.Arena, state &CallbackState) !py.Ref {
	a.method(state.synchronizer, 'wait', [a.int(5)!], {})!
	if a.api.append(state.seen, a.text('woken')!) != 0 { return a.api.exception() }
	return a.borrow(a.api.none)!
}

fn (mut smoke Smoke) threads(api &py.Api) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	threading := a.load('threading')!
	builtins := a.load('builtins')!
	clock := a.load('time')!
	seen := a.list([])!
	mutex := a.method(threading, 'Lock', [], {})!
	// Capsules retain state, definitions and strong SDK references through
	// callback retirement, including partial-start or failed-join paths.
	worker := callback(mut a, seen, mutex, c'worker', voidptr(worker_callback))!
	mut workers := []py.Ref{}
	for index in 0 .. 8 {
		workers << a.method(threading, 'Thread', [], {
			'target': worker
			'args':   a.tuple([a.int(index)!])!
		})!
	}
	defer { for item in workers { a.method(item, 'join', [], {}) or {} }
	 }
	for item in workers { a.method(item, 'start', [], {})! }
	for item in workers { a.method(item, 'join', [], {})! }
	mut golden := []py.Ref{}
	for index in 0 .. 8 { golden << a.int(index)! }
	smoke.check(a.equal(a.method(builtins, 'sorted', [seen], {})!, a.list(golden)!)!, 'eight threads with a lock')
	wake := a.method(threading, 'Event', [], {})!
	waiter := callback(mut a, seen, wake, c'waiter', voidptr(waiter_callback))!
	waiting := a.method(threading, 'Thread', [], {
		'target': waiter
	})!
	a.method(waiting, 'start', [], {})!
	defer { a.method(waiting, 'join', [], {}) or {} }
	a.method(clock, 'sleep', [a.float(0.2)!], {})!
	a.method(wake, 'set', [], {})!
	a.method(waiting, 'join', [], {})!
	smoke.check(a.truth(a.method(seen, '__contains__', [a.text('woken')!], {})!)!, 'threading.Event')
}

fn (mut smoke Smoke) readiness(api &py.Api) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	posix := a.load('os')!
	selector := a.load('select')!
	pair := a.method(posix, 'pipe', [], {})!
	read_fd, write_fd := a.item(pair, 0)!, a.item(pair, 1)!
	readers, empty := a.list([read_fd])!, a.list([])!
	smoke.check(a.equal(a.method(selector, 'select', [readers, empty, empty, a.int(0)!], {})!, a.tuple([
		empty,
		empty,
		empty,
	])!)!, 'select sees nothing ready')
	a.method(posix, 'write', [write_fd, a.data('x'.bytes())!], {})!
	selected := a.method(selector, 'select', [readers, empty, empty, a.int(1)!], {})!
	smoke.check(a.equal(a.item(selected, 0)!, readers)!, 'select sees a readable pipe')
	poller := a.method(selector, 'poll', [], {})!
	a.method(poller, 'register', [read_fd, a.attr(selector, 'POLLIN')!], {})!
	polled := a.method(poller, 'poll', [a.int(1000)!], {})!
	smoke.check(a.equal(a.item(a.item(polled, 0)!, 0)!, read_fd)!, 'select.poll')
	if api.has_attribute(selector, c'epoll') == 1 {
		epoll := a.method(selector, 'epoll', [], {})!
		a.method(epoll, 'register', [read_fd, a.attr(selector, 'EPOLLIN')!], {})!
		smoke.check(a.length(a.method(epoll, 'poll', [a.int(1)!], {})!)! == 1, 'select.epoll')
		a.method(epoll, 'close', [], {})!
	}
	a.method(posix, 'close', [read_fd], {})!
	a.method(posix, 'close', [write_fd], {})!
}

fn (mut smoke Smoke) sockets(api &py.Api, work string) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	posix := a.load('os')!
	socket := a.load('socket')!
	arrays := a.load('array')!
	pair := a.method(socket, 'socketpair', [], {})!
	left, right := a.item(pair, 0)!, a.item(pair, 1)!
	a.method(left, 'send', [a.data('ping'.bytes())!], {})!
	smoke.check(a.bytes(a.method(right, 'recv', [a.int(16)!], {})!)! == 'ping'.bytes(), 'socketpair round trip')
	for item in [left, right] { a.method(item, 'close', [], {})! }
	connected := a.method(socket, 'socketpair', [], {})!
	sender, receiver := a.item(connected, 0)!, a.item(connected, 1)!
	passed := a.method(posix, 'open', [a.text('/dev/null')!, a.attr(posix, 'O_RDONLY')!], {})!
	a.method(sender, 'sendall', [a.data('before'.bytes())!], {})!
	encoded := a.method(arrays, 'array', [a.text('i')!, a.list([passed])!], {})!
	level, kind := a.attr(socket, 'SOL_SOCKET')!, a.attr(socket, 'SCM_RIGHTS')!
	a.method(sender, 'sendmsg', [a.list([a.data('rights'.bytes())!])!,
		a.list([a.tuple([level, kind, encoded])!])!], {})!
	a.method(sender, 'sendall', [a.data('after'.bytes())!], {})!
	itemsize := a.attr(encoded, 'itemsize')!
	message := a.method(receiver, 'recvmsg', [a.int(64)!,
		a.method(socket, 'CMSG_SPACE', [itemsize], {})!], {})!
	received := a.method(arrays, 'array', [a.text('i')!], {})!
	ancillary := a.item(message, 1)!
	for index in 0 .. a.length(ancillary)! {
		entry := a.item(ancillary, index)!
		if a.equal(a.item(entry, 0)!, level)! && a.equal(a.item(entry, 1)!, kind)! {
			data := a.bytes(a.item(entry, 2)!)!
			width := int(a.integer(itemsize)!)
			if width <= 0 { return error('invalid ancillary integer size') }
			a.method(received, 'frombytes', [a.data(data[..data.len - data.len % width])!], {})!
		}
	}
	smoke.check(a.bytes(a.item(message, 0)!)! == 'beforerights'.bytes(), 'SCM_RIGHTS stream boundary')
	smoke.check(a.integer(a.item(message, 2)!)! == 0 && a.length(received)! == 1, 'SCM_RIGHTS descriptor delivery')
	smoke.check(a.bytes(a.method(receiver, 'recv', [a.int(64)!], {})!)! == 'after'.bytes(), 'SCM_RIGHTS leaves following bytes')
	for index in 0 .. a.length(received)! {
		a.method(posix, 'close', [a.item(received, index)!], {})!
	}
	a.method(posix, 'close', [passed], {})!
	for item in [sender, receiver] { a.method(item, 'close', [], {})! }
	path := work + '/server.sock'
	server := a.method(socket, 'socket', [a.attr(socket, 'AF_UNIX')!, a.attr(socket, 'SOCK_STREAM')!], {})!
	a.method(server, 'bind', [a.text(path)!], {})!
	a.method(server, 'listen', [a.int(1)!], {})!
	client := a.method(socket, 'socket', [a.attr(socket, 'AF_UNIX')!, a.attr(socket, 'SOCK_STREAM')!], {})!
	a.method(client, 'connect', [a.text(path)!], {})!
	connection := a.item(a.method(server, 'accept', [], {})!, 0)!
	a.method(client, 'sendall', [a.data('over a unix socket'.bytes())!], {})!
	smoke.check(a.bytes(a.method(connection, 'recv', [a.int(64)!], {})!)! == 'over a unix socket'.bytes(), 'unix socket connect/accept')
	for item in [client, connection, server] { a.method(item, 'close', [], {})! }
	a.method(posix, 'unlink', [a.text(path)!], {})!
	smoke.check(!a.truth(a.method(a.attr(posix, 'path')!, 'exists', [a.text(path)!], {})!)!, 'unlink unix socket path')
}

fn (mut smoke Smoke) clocks(api &py.Api) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	clock := a.load('time')!
	posix := a.load('os')!
	builtins := a.load('builtins')!
	started := a.floating(a.method(clock, 'monotonic', [], {})!)!
	a.method(clock, 'sleep', [a.float(0.3)!], {})!
	smoke.check(a.floating(a.method(clock, 'monotonic', [], {})!)! - started >= 0.25, 'time.sleep and monotonic')
	smoke.check(a.floating(a.method(clock, 'time', [], {})!)! > 1_000_000, 'time.time')
	smoke.check(a.integer(a.method(posix, 'getuid', [], {})!)! == 0 && a.integer(a.method(posix, 'geteuid', [], {})!)! == 0, 'process credentials')
	smoke.check(a.integer(a.method(posix, 'getpid', [], {})!)! > 0, 'process ID')
	smoke.check(a.length(a.method(builtins, 'bytearray', [a.int(1 << 20)!], {})!)! == 1 << 20, 'allocate a megabyte')
	one := a.method(posix, 'urandom', [a.int(32)!], {})!
	two := a.method(posix, 'urandom', [a.int(32)!], {})!
	three := a.method(posix, 'urandom', [a.int(32)!], {})!
	smoke.check(a.length(one)! == 32 && !a.equal(two, three)!, 'os.urandom')
}

const extension_modules = ['bz2', 'ctypes', 'datetime', 'decimal', 'hashlib', 'lzma', 'math', 'sqlite3',
	'ssl', 'struct', 'zlib']

fn (mut smoke Smoke) extensions(api &py.Api) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	for name in extension_modules {
		a.load(name) or {
			smoke.check(false, 'import ' + name + ' (' + err.msg() + ')')
			continue
		}
		smoke.check(true, 'import ' + name)
	}
	zlib := a.load('zlib')!
	data := a.data('vinix'.repeat(1000).bytes())!
	smoke.check(a.equal(a.method(zlib, 'decompress', [a.method(zlib, 'compress', [data], {})!], {})!, data)!, 'zlib round trip')
	hash := a.method(a.load('hashlib')!, 'sha256', [data], {})!
	smoke.check(a.length(a.method(hash, 'hexdigest', [], {})!)! == 64, 'sha256')
}

fn (mut smoke Smoke) positioned(api &py.Api, work string) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	posix := a.load('os')!
	builtins := a.load('builtins')!
	open_flags := a.integer(a.attr(posix, 'O_CREAT')!)! | a.integer(a.attr(posix, 'O_RDWR')!)!
	fd := a.method(posix, 'open', [a.text(work + '/positioned-io')!, a.int(open_flags)!, a.int(0o600)!], {})!
	a.method(posix, 'pwrite', [fd, a.data('SQLite format 3\x00'.bytes())!, a.int(0)!], {})!
	smoke.check(a.bytes(a.method(posix, 'pread', [fd, a.int(16)!, a.int(0)!], {})!)! == 'SQLite format 3\x00'.bytes(), 'positioned file I/O')
	position := a.method(posix, 'lseek', [fd, a.int(7)!, a.attr(posix, 'SEEK_SET')!], {})!
	vectors := a.list([a.data('vector'.bytes())!, a.data(' write'.bytes())!])!
	smoke.check(a.integer(a.method(posix, 'pwritev', [fd, vectors, a.int(32)!], {})!)! == 12, 'positioned vector write')
	first := a.method(builtins, 'bytearray', [a.int(6)!], {})!
	second := a.method(builtins, 'bytearray', [a.int(6)!], {})!
	count := a.method(posix, 'preadv', [fd, a.list([first, second])!, a.int(32)!], {})!
	joined := a.method(builtins, 'bytes', [a.method(first, '__add__', [second], {})!], {})!
	smoke.check(a.integer(count)! == 12 && a.bytes(joined)! == 'vector write'.bytes() && a.equal(a.method(posix, 'lseek', [
		fd,
		a.int(0)!,
		a.attr(posix, 'SEEK_CUR')!,
	], {})!, position)!, 'positioned vector read preserves offset')
	a.method(posix, 'posix_fallocate', [fd, a.int(0)!, a.int(128)!], {})!
	smoke.check(a.integer(a.attr(a.method(posix, 'fstat', [fd], {})!, 'st_size')!)! >= 128, 'posix_fallocate')
	a.method(posix, 'posix_fadvise', [fd, a.int(0)!, a.int(0)!, a.attr(posix, 'POSIX_FADV_NORMAL')!], {})!
	smoke.check(true, 'posix_fadvise')
	a.method(posix, 'ftruncate', [fd, a.int(0)!], {})!
	a.method(posix, 'lseek', [fd, a.int(24)!, a.attr(posix, 'SEEK_SET')!], {})!
	smoke.check(a.integer(a.attr(a.method(posix, 'fstat', [fd], {})!, 'st_size')!)! == 0 && a.bytes(a.method(posix, 'read', [
		fd,
		a.int(1)!,
	], {})!)!.len == 0, 'seek/read beyond EOF')
	a.method(posix, 'write', [fd, a.data('x'.bytes())!], {})!
	smoke.check(a.bytes(a.method(posix, 'pread', [fd, a.int(25)!, a.int(0)!], {})!)! == ('\x00'.repeat(24) + 'x').bytes(), 'zero-filled sparse write')
	a.method(posix, 'close', [fd], {})!
}

fn (mut smoke Smoke) event_and_sendfile(api &py.Api, work string) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	posix := a.load('os')!
	selector := a.load('select')!
	builtins := a.load('builtins')!
	flags := a.integer(a.attr(posix, 'EFD_NONBLOCK')!)! | a.integer(a.attr(posix, 'EFD_CLOEXEC')!)!
	fd := a.method(posix, 'eventfd', [a.int(0)!, a.int(flags)!], {})!
	poller := a.method(selector, 'epoll', [], {})!
	a.method(poller, 'register', [fd, a.attr(selector, 'EPOLLIN')!], {})!
	smoke.check(a.length(a.method(poller, 'poll', [a.int(0)!], {})!)! == 0, 'eventfd starts unreadable')
	a.method(posix, 'eventfd_write', [fd, a.int(7)!], {})!
	smoke.check(a.length(a.method(poller, 'poll', [a.int(1)!], {})!)! == 1 && a.integer(a.method(posix, 'eventfd_read', [fd], {})!)! == 7, 'eventfd and epoll')
	a.method(poller, 'close', [], {})!
	a.method(posix, 'close', [fd], {})!
	source_path, target_path := work + '/sendfile-source', work + '/sendfile-target'
	written := a.method(builtins, 'open', [a.text(source_path)!, a.text('wb')!], {})!
	a.method(written, 'write', [a.data('0123456789'.bytes())!], {})!
	a.method(written, 'close', [], {})!
	source := a.method(builtins, 'open', [a.text(source_path)!, a.text('rb')!], {})!
	target := a.method(builtins, 'open', [a.text(target_path)!, a.text('wb')!], {})!
	a.method(source, 'seek', [a.int(8)!], {})!
	smoke.check(a.integer(a.method(posix, 'sendfile', [
		a.method(target, 'fileno', [], {})!,
		a.method(source, 'fileno', [], {})!,
		a.int(2)!,
		a.int(5)!,
	], {})!)! == 5, 'sendfile')
	smoke.check(a.integer(a.method(source, 'tell', [], {})!)! == 8, 'sendfile explicit offset is positioned')
	for item in [source, target] { a.method(item, 'close', [], {})! }
	copied := a.method(builtins, 'open', [a.text(target_path)!, a.text('rb')!], {})!
	smoke.check(a.bytes(a.method(copied, 'read', [], {})!)! == '23456'.bytes(), 'sendfile contents')
	a.method(copied, 'close', [], {})!
}

fn (mut smoke Smoke) resources(api &py.Api) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	posix := a.load('os')!
	resource := a.load('resource')!
	limits := a.method(resource, 'getrlimit', [a.attr(resource, 'RLIMIT_NOFILE')!], {})!
	soft, hard := a.integer(a.item(limits, 0)!)!, a.integer(a.item(limits, 1)!)!
	smoke.check(soft > 0 && hard >= soft, 'getrlimit')
	if api.has_attribute(posix, c'sched_getcpu') == 1 {
		smoke.check(a.integer(a.method(posix, 'sched_getcpu', [], {})!)! >= 0, 'getcpu')
	}
	if api.has_attribute(posix, c'sched_rr_get_interval') == 1 {
		smoke.check(a.floating(a.method(posix, 'sched_rr_get_interval', [a.int(0)!], {})!)! > 0, 'sched_rr_get_interval')
	}
	smoke.check(a.string(a.attr(a.method(posix, 'uname', [], {})!, 'machine')!)! == 'aarch64', 'uname Linux layout')
}

fn (mut smoke Smoke) sqlite(api &py.Api, work string) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	database := a.method(a.load('sqlite3')!, 'connect', [a.text(work + '/database.sqlite')!], {})!
	a.method(database, 'execute', [a.text('create table rows (number int, text text)')!], {})!
	mut values := []py.Ref{}
	for number in 0 .. 100 { values << a.tuple([a.int(number)!, a.text('row' + number.str())!])! }
	a.method(database, 'executemany', [a.text('insert into rows values (?, ?)')!, a.list(values)!], {})!
	a.method(database, 'commit', [], {})!
	cursor := a.method(database, 'execute', [a.text('select count(*) from rows')!], {})!
	smoke.check(a.integer(a.item(a.method(cursor, 'fetchone', [], {})!, 0)!)! == 100, 'sqlite3 insert and select')
	a.method(database, 'close', [], {})!
}

fn (mut smoke Smoke) run(api &py.Api) ! {
	mut a := py.Arena{ api: api }
	defer { a.close() }
	sys := a.load('sys')!
	smoke.check(a.integer(a.attr(a.attr(sys, 'version_info')!, 'major')!)! == 3, 'interpreter is Python 3')
	println('  [info] ' + a.string(a.attr(sys, 'version')!)!.replace('\n', ' '))
	flush_stdout()
	work := '/tmp/python3-smoke-' + os.getpid().str()
	smoke.filesystem(api, work)!
	smoke.processes(api)!
	smoke.threads(api)!
	smoke.readiness(api)!
	smoke.sockets(api, work)!
	smoke.clocks(api)!
	smoke.extensions(api)!
	smoke.positioned(api, work)!
	smoke.event_and_sendfile(api, work)!
	smoke.resources(api)!
	smoke.sqlite(api, work)!
}
