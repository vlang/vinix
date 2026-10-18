// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import time
import tools.packages.pkgprotocol

#include <poll.h>
#include <sys/wait.h>
#include <signal.h>
#define vinix_package_poll poll
#define vinix_package_waitpid waitpid
fn C.vinix_package_poll(voidptr, usize, int) int
fn C.pipe(&i32) int
fn C.pipe2(&i32, int) int
fn C.fcntl(int, int, ...int) int
fn C.fork() int
fn C.dup2(int, int) int
fn C._exit(int)
fn C.kill(int, int) int
fn C.vinix_package_waitpid(int, &i32, int) int

struct HttpsOutputOptions {
	program string = '/usr/bin/curl'
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	flush fn (int) int = atomic_flush
}

struct HttpsOutput { fd int bytes u64 device u64 inode u64 }
struct OutputPoll { mut: fd i32 events i16 revents i16 }

fn open_https_output(path string, maximum u64, resume bool) !HttpsOutput {
	if path == '' || path.contains('\x00') { return error('download destination requires a valid regular-file path') }
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK, 0o600)
	if fd < 0 { return error('cannot open ordinary download destination: ${path}') }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o100000 || info.st_size < 0 || info.st_nlink != 1 {
		C.close(fd)
		return error('download destination must be an ordinary regular file without hard links: ${path}')
	}
	if resume && u64(info.st_size) > maximum {
		C.close(fd)
		return error('download resume prefix exceeds its authenticated size limit: ${path}')
	}
	return HttpsOutput{ fd: fd, bytes: u64(info.st_size), device: u64(info.st_dev), inode: u64(info.st_ino) }
}

fn check_https_output(output HttpsOutput, path string, bytes u64) ! {
	mut opened := C.stat{}
	mut named := C.stat{}
	// These synchronous calls retain neither pointer. Repeated stream checks
	// must keep their stat scratch on the stack under -gc none -manualfree.
	if C.fstat(output.fd, unsafe { &opened }) != 0 || opened.st_mode & 0o170000 != 0o100000
		|| opened.st_size < 0 || u64(opened.st_size) != bytes
		|| opened.st_nlink != 1 || C.fstatat(C.AT_FDCWD, path.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| named.st_mode & 0o170000 != 0o100000 || u64(named.st_dev) != output.device || u64(named.st_ino) != output.inode {
		return error('download destination changed while transferring; inspect retained data before retrying: ${path}')
	}
}

fn output_pipe() ![2]i32 {
	mut fds := [i32(-1), -1]!
	mut code := -1
	$if linux { code = C.pipe2(&fds[0], C.O_CLOEXEC) }
	$else { code = C.pipe(&fds[0]) }
	if code != 0 { return error('cannot create download output pipe') }
	if C.fcntl(fds[0], C.F_SETFD, C.FD_CLOEXEC) != 0 || C.fcntl(fds[1], C.F_SETFD, C.FD_CLOEXEC) != 0
		|| C.fcntl(fds[0], C.F_SETFL, C.O_NONBLOCK) != 0 {
		C.close(fds[0]); C.close(fds[1])
		return error('cannot configure download output pipe')
	}
	return fds
}

fn reap_output(pid int) !int {
	mut status := i32(0)
	for {
		waited := C.vinix_package_waitpid(pid, &status, 0)
		if waited < 0 && C.errno == C.EINTR { continue }
		if waited != pid { return error('cannot collect download process status') }
		return if status & 0x7f == 0 { (status >> 8) & 0xff } else { 128 + (status & 0x7f) }
	}
}

fn pump_https_output(output HttpsOutput, path string, maximum u64, offset u64, args []string, event pkgprotocol.Progress, report fn (pkgprotocol.Progress), options HttpsOutputOptions) !int {
	check_https_output(output, path, output.bytes)!
	if C.lseek(output.fd, i64(offset), C.SEEK_SET) != i64(offset) { return error('cannot seek download destination: ${path}') }
	fds := output_pipe()!
	defer { C.close(fds[0]) }
	mut argv := []&char{cap: args.len + 2}
	argv << &char(options.program.str)
	for argument in args { argv << &char(argument.str) }
	argv << &char(unsafe { nil })
	defer { unsafe { (&array(&argv)).free() } }
	pid := C.fork()
	if pid < 0 { C.close(fds[1]); return error('cannot start download process') }
	if pid == 0 {
		// Only async-signal-safe calls between fork and exec. Destination and
		// package-lock descriptors remain close-on-exec; curl receives a pipe.
		if C.dup2(fds[1], 1) < 0 || C.fcntl(1, C.F_SETFD, 0) != 0 { C._exit(126) }
		if fds[0] != 1 { C.close(fds[0]) }
		if fds[1] != 1 { C.close(fds[1]) }
		C.execv(options.program.str, unsafe { &argv[0] })
		C._exit(127)
	}
	C.close(fds[1])
	mut reaped := false
	defer {
		if !reaped { C.kill(pid, 9); reap_output(pid) or {} }
	}
	mut buffer := []u8{len: 64 * 1024}
	defer { unsafe { buffer.free() } }
	mut done := offset
	mut started := false
	mut last := time.sys_mono_now()
	if event.phase != '' { report(pkgprotocol.Progress{ ...event, current: done }) }
	check_https_output(output, path, output.bytes)!
	for {
		mut polling := OutputPoll{ fd: fds[0], events: i16(C.POLLIN) }
		ready := C.vinix_package_poll(unsafe { voidptr(&polling) }, 1, 200)
		if ready < 0 && C.errno == C.EINTR { continue }
		if ready < 0 { return error('cannot monitor download output') }
		if ready > 0 {
			count := C.read(fds[0], buffer.data, usize(buffer.len))
			if count < 0 && (C.errno == C.EINTR || C.errno == C.EAGAIN || C.errno == C.EWOULDBLOCK) { continue }
			if count < 0 { return error('cannot read download output') }
			if count == 0 { break }
			if u64(count) > maximum - done { return error('download exceeded its authenticated size limit; retained bounded partial data for retry') }
			check_https_output(output, path, if started { done } else { output.bytes })!
			if !started && offset == 0 && C.ftruncate(output.fd, 0) != 0 { return error('cannot restart download destination: ${path}') }
			started = true
			mut sent := 0
			for sent < int(count) {
				written := C.write(output.fd, unsafe { &u8(buffer.data) + sent }, usize(int(count) - sent))
				if written < 0 && C.errno == C.EINTR { continue }
				if written <= 0 { return error('cannot write download destination; check disk space: ${path}') }
				sent += int(written)
			}
			done += u64(count)
			options.checkpoint('written', path)!
			check_https_output(output, path, done)!
		}
		if event.phase != '' && time.sys_mono_now() - last >= 200_000_000 {
			report(pkgprotocol.Progress{ ...event, current: done })
			check_https_output(output, path, if started { done } else { output.bytes })!
			last = time.sys_mono_now()
		}
	}
	reaped = true
	code := reap_output(pid)!
	check_https_output(output, path, if started { done } else { output.bytes })!
	// Delay fresh truncation until bytes arrive (or successful empty EOF), so
	// certificate/HTTP failures and range refusal preserve the retained prefix.
	if code == 0 && !started && offset == 0 && C.ftruncate(output.fd, 0) != 0 { return error('cannot clear empty download destination: ${path}') }
	expected := if !started && code != 0 { output.bytes } else { done }
	check_https_output(output, path, expected)!
	if code == 0 {
		for {
			if options.flush(output.fd) == 0 { break }
			if C.errno == C.EINTR { continue }
			return error('cannot flush captured download destination; retained partial data may need retry after checking storage: ${path}')
		}
	}
	options.checkpoint('finished', path)!
	check_https_output(output, path, expected)!
	if event.phase != '' { report(pkgprotocol.Progress{ ...event, current: done }) }
	check_https_output(output, path, expected)!
	return code
}

fn fetch_https_with(url string, destination string, maximum u64, resume bool, offline bool, event pkgprotocol.Progress, report fn (pkgprotocol.Progress), options HttpsOutputOptions) !bool {
	if offline { return error('offline mode: verified payload is missing from cache: ${url}') }
	if !url.starts_with('https://') || url.contains('\x00') { return error('repository transport requires HTTPS or a local file repository') }
	output := open_https_output(destination, maximum, resume)!
	defer { C.close(output.fd) }
	options.checkpoint('opened', destination)!
	check_https_output(output, destination, output.bytes)!
	mut resumed := resume && output.bytes > 0
	limit := maximum.str()
	defer { unsafe { limit.free() } }
	mut code := 0
	for attempt in 0 .. 2 {
		offset := if resumed { output.bytes } else { u64(0) }
		position := offset.str()
		// Arguments borrow literals and this call's URL/numeric strings. Fixed
		// stack lists avoid allocating abandoned temporary arrays on each append.
		base := ['--disable', '--fail', '--show-error', '--silent', '--location', '--proto', '=https',
			'--proto-redir', '=https', '--tlsv1.2', '--connect-timeout', '20', '--max-time', '1800',
			'--retry', '0', '--max-filesize', limit, '--output', '-']!
		mut args := []string{cap: base.len + 4}
		unsafe { args.flags |= .noslices }
		unsafe { args.push_many(&base[0], base.len) }
		if resumed {
			range := ['--continue-at', position]!
			unsafe { args.push_many(&range[0], range.len) }
		}
		target := ['--', url]!
		unsafe { args.push_many(&target[0], target.len) }
		code = pump_https_output(output, destination, maximum, offset, args, event, report, options) or {
			unsafe { position.free(); (&array(&args)).free() }
			return err
		}
		unsafe { position.free(); (&array(&args)).free() }
		if code != 33 || !resumed || attempt != 0 { break }
		label := if event.package == '' { 'download' } else { event.package + '/' + event.path }
		message := 'Restarting ${label}: repository does not support byte ranges'
		println(message)
		unsafe { label.free(); message.free() }
		resumed = false
	}
	if code != 0 { return https_transport_failure(code, url, options.program) }
	return resumed
}
