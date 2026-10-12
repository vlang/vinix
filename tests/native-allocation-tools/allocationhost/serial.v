// SPDX-License-Identifier: GPL-2.0-or-later
module allocationhost

import cachecli
import comparecore
import guesthost
import hosttest
import net.unix
import os
import qmpclient
import strconv
import time

#include <poll.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/socket.h>
struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

fn C.poll(&C.pollfd, usize, i32) i32

fn socket_ready(fd int, writing bool, deadline u64) !bool {
	mut descriptor := C.pollfd{ fd: fd, events: i16(if writing { C.POLLOUT } else { C.POLLIN }) }
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint()!
		count := C.poll(&descriptor, 1, 20)
		if count > 0 { return true }
		if count < 0 && C.errno != C.EINTR { return os.error_posix() }
	}
	return false
}

fn socket_send(fd int, data []u8) ! {
	deadline := time.sys_mono_now() + u64(200 * time.millisecond)
	mut position := 0
	for position < data.len {
		if !socket_ready(fd, true, deadline)! { return error('serial send timed out') }
		count := unsafe { C.send(fd, &data[position], usize(data.len - position), 0) }
		if count < 0 {
			if C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
			return os.error_posix()
		}
		if count == 0 { return error('serial socket closed') }
		position += int(count)
	}
}

fn read_tail(path string, offset i64) ![]u8 {
	mut file := os.open(path)!
	defer { file.close() }
	file.seek(offset, .start)!
	mut data := []u8{}
	mut chunk := []u8{len: 65536}
	for {
		cachecli.checkpoint()!
		count := file.read(mut chunk) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		if data.len > 2147483647 - count { return error('serial data exceeds native array size') }
		data << chunk[..count]
	}
	return data
}

pub fn console_broker(runtime string) ! {
	os.write_file(runtime + '/control.pid', os.getpid().str() + '\n')!
	mut connection := &unix.StreamConn(unsafe { nil })
	defer { if connection != unsafe { nil } { connection.close() or {} } }
	for _ in 0 .. 100 {
		cachecli.checkpoint()!
		connection = unix.connect_stream(runtime + '/serial.sock') or {
			if err.code() != C.ECONNREFUSED { return err }
			checkpoint_sleep(100 * time.millisecond)!
			continue
		}
		break
	}
	mut cursor := if os.exists(runtime + '/control.cursor') {
		strconv.parse_int(os.read_file(runtime + '/control.cursor')!.trim_space(), 10, 64)!
	} else {
		i64(0)
	}
	log_path := runtime + '/console.log'
	log_fd := unsafe { C.open(log_path.str, C.O_WRONLY | C.O_CREAT | C.O_APPEND | C.O_CLOEXEC, 0o666) }
	if log_fd < 0 { return os.error_posix() }
	defer { C.close(log_fd) }
	if connection == unsafe { nil } { return error('serial connection refused') }
	fd := connection.sock.handle
	if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 || C.fcntl(fd, C.F_SETFL, C.O_NONBLOCK) != 0 {
		return os.error_posix()
	}
	mut buffer := [65536]u8{}
	for {
		cachecli.checkpoint()!
		queue := runtime + '/commands.txt'
		if os.exists(queue) {
			pending := read_tail(queue, cursor)!
			if pending.len > 0 {
				socket_send(fd, pending)!
				cursor += pending.len
				os.write_file(runtime + '/control.cursor', cursor.str() + '\n')!
			}
		}
		if !socket_ready(fd, false, time.sys_mono_now() + u64(200 * time.millisecond))! { continue }
		count := C.recv(fd, &buffer[0], buffer.len, 0)
		if count < 0 {
			if C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
			return os.error_posix()
		}
		if count == 0 { break }
		mut position := 0
		// The recorded observer tails this file while the broker stays alive.
		// SDK writes preserve the original unbuffered append, including errors.
		for position < count {
			written := C.write(log_fd, &buffer[position], usize(count - position))
			if written < 0 {
				if C.errno == C.EINTR { continue }
				return os.error_posix()
			}
			if written == 0 { return error('serial log write made no progress') }
			position += int(written)
		}
	}
}

pub fn measure_recorded(runtime string, state string, base_config string) ! {
	work := hosttest.work_dir(if state == '' { '.' } else { state }, 'vinix-alloc-measure-')!
	console := runtime + '/console.log'
	offset := i64(os.file_size(console))
	// stat failure must precede reading the configuration, as in the original.
	os.stat(console)!
	mut config := hosttest.decode_json(os.read_file(base_config)!)!.as_map().clone()
	config['argv'] = hosttest.decode_json(os.read_file(runtime + '/argv.json')!)!
	config['iterations'] = 200000
	config['samples'] = 7
	config['guest_compile_command'] = config['guest_compile_command']!.str().replace('/tmp/bench-native.s', '/tmp/bench-native-fresh.s')
	config['freshly_verified_assembly_sha256'] = 'ff4f96b50b88ea1482866c7fed1bbc0750d46e47c0f984466332615439136bdd'
	config['binary_reused_after_matching_fresh_guest_codegen'] = true
	config['started_utc'] = checked(['date', '-u', '+%Y-%m-%dT%H:%M:%SZ'])!.stdout.trim_space()
	config['transport'] = 'private serial console in single-user mode'
	write_json(work + '/config.json', config)!
	mut monitor := qmpclient.connect_checked(runtime + '/qmp.sock', time.sys_mono_now() + u64(5 * time.second), cachecli.cancelled)!
	defer { monitor.close() }
	monitor.set_deadline(time.sys_mono_now() + u64(5 * time.second))
	monitor.command('cont', {})!
	measure_loop(runtime, work, console, offset) or {
		failure := err
		stop_measure(mut monitor)!
		return failure
	}
	stop_measure(mut monitor)!
}

fn stop_measure(mut monitor qmpclient.Monitor) ! {
	monitor.set_cancel(unsafe { nil })
	monitor.set_deadline(time.sys_mono_now() + u64(5 * time.second))
	monitor.command('stop', {})!
}

// Queue publication and the complete observer share one retirement scope.
fn measure_loop(runtime string, work string, console string, offset i64) ! {
	mut commands := os.open_append(runtime + '/commands.txt')!
	commands.write_string('/tmp/alloc-bench-native --label macos --iterations 200000 --samples 7\n')!
	commands.close()
	deadline := time.sys_mono_now() + u64(3600 * time.second)
	mut last := ''
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint()!
		data := read_tail(console, offset)!
		os.write_file(work + '/serial.log', data.bytestr())!
		text := guesthost.replacement_text(data)
		results := comparecore.lines(text).map(it.trim_space()).filter(it.starts_with('ALLOC-RESULT'))
		if results.len > 0 && results.last() != last {
			last = results.last()
			println(last)
			flush_stdout()
		}
		if text.contains('ALLOC-ERROR') || text.contains('ALLOC-FAIL') {
			return error('macOS benchmark failed')
		}
		if text.contains('ALLOC-DONE') {
			println('macOS benchmark complete')
			flush_stdout()
			return
		}
		checkpoint_sleep(250 * time.millisecond)!
	}
	return error('macOS benchmark timeout; guest may still be running')
}
