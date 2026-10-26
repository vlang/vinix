// SPDX-License-Identifier: GPL-2.0-or-later
// One credential-free browser archive, over a private TCP connection.
module browsertransfer

import crypto.sha256
import io
import json2
import net
import os
import time

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

pub const limit = 32 * 1024 * 1024
const prefix = 'VINIX-BROWSER-RESULTS-1 BEGIN '
const scope = 'Exact credential-free browser archive retransmission over TCP; source UART export remains independently failed or unqualified. No Google authentication proof.'

pub struct Expected {
pub:
	sha256 string
	bytes  int
}

pub struct Receipt {
pub:
	format               int    = 1
	transport            string = 'browser-tcp-v1'
	scope                string = scope
	started_utc          string
	finished_utc         string
	source_serial_path   string
	source_serial_sha256 string
	source_serial_bytes  u64
	archive_sha256       string
	archive_bytes        int
	listen_address       string
	receiver_sha256      string
	eof                  bool
}

pub fn expected(sha string, bytes string) !Expected {
	if sha.len != 64 || !sha.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| bytes == '' || bytes.len > 8 || bytes.starts_with('0')
		|| !bytes.bytes().all(it >= `0` && it <= `9`) || bytes.u64() > limit {
		return error('canonical browser archive SHA/length required')
	}
	return Expected{sha, bytes.int()}
}

pub fn file_hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

// Only the intact BEGIN supplies the expected bytes. This deliberately does
// not repair, accept, or reinterpret any damaged UART CHUNK/END frames.
pub fn source_pin(path string, pin Expected) !(string, u64) {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size > 256 * 1024 * 1024 {
		return error('bounded regular source UART log required')
	}
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut line := []u8{cap: 1025}
	mut oversized := false
	mut found := 0
	mut count := u64(0)
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		count += u64(n)
		if count > st.size { return error('source UART grew during read') }
		hash.write(buffer[..n])!
		for byte in buffer[..n] {
			if byte == `\n` {
				if !oversized && line.bytestr().starts_with(prefix) {
					fields := line.bytestr().trim_right('\r')[prefix.len..].split(' ')
					if fields.len != 3 || fields[0] != pin.sha256 || fields[1] != pin.bytes.str()
						|| fields[2] != ((pin.bytes + 511) / 512).str() {
						return error('source BEGIN differs from expected archive')
					}
					found++
				}
				line.clear()
				oversized = false
			} else if line.len < 1024 {
				line << byte
			} else {
				oversized = true
			}
		}
	}
	if count != st.size || found != 1 {
		return error('exactly one intact matching source BEGIN required')
	}
	return hash.sum([]u8{}).hex(), count
}

fn exclusive(path string) !int {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot exclusively create ' + path) }
	return fd
}

fn write_all(fd int, bytes []u8) ! {
	mut offset := 0
	for offset < bytes.len {
		n := unsafe { C.write(fd, &u8(bytes.data) + offset, uint(bytes.len - offset)) }
		if n <= 0 { return error('archive file write failed') }
		offset += int(n)
	}
}

// The socket has one absolute deadline, including the mandatory EOF read.
pub fn receive_stream(mut connection net.TcpConn, target string, pin Expected, deadline time.Time) ! {
	connection.set_read_deadline(deadline)
	fd := exclusive(target)!
	defer { C.close(fd) }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut count := 0
	for {
		if time.now() > deadline { return error('archive transfer deadline') }
		n := connection.read(mut buffer) or {
			if err is io.Eof { break }
			return err
		}
		if n == 0 { break }
		if count + n > pin.bytes { return error('extra archive bytes') }
		write_all(fd, buffer[..n])!
		hash.write(buffer[..n])!
		count += n
	}
	if count != pin.bytes { return error('truncated archive') }
	if hash.sum([]u8{}).hex() != pin.sha256 { return error('archive hash mismatch') }
}

pub fn external_path(root string) ! {
	parent := os.dir(root)
	name := os.file_name(root)
	if !root.starts_with('/') || root.contains_any('\x00\n\r') || name in ['', '.', '..']
		|| os.real_path(parent) != parent || parent + '/' + name != root {
		return error('canonical absolute transfer path required')
	}
	mut ancestor := parent
	for {
		if os.exists(ancestor + '/.git') {
			return error('transfer artifacts must be outside Git checkouts')
		}
		if ancestor == '/' { break }
		ancestor = os.dir(ancestor)
	}
}

pub fn receive(root string, port string, pin Expected, source string) ! {
	external_path(root)!
	if port == '' || !port.bytes().all(it >= `0` && it <= `9`) || port.len > 5 || port.u64() > 65535 {
		return error('TCP port must be 0..65535')
	}
	serial := os.real_path(source)
	before, size := source_pin(serial, pin)!
	if unsafe { C.mkdir(root.str, 0o700) } != 0 {
		return error('fresh private transfer directory required')
	}
	started := time.utc().str()
	mut listener := net.listen_tcp(.ip, '127.0.0.1:' + port)!
	defer { listener.close() or {} }
	deadline := time.now().add(600 * time.second)
	listener.set_accept_deadline(deadline)
	address := listener.addr()!.str()
	println('BROWSER-TCP READY ' + address)
	flush_stdout()
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	receive_stream(mut connection, root + '/archive.partial', pin, deadline)!
	if file_hash(root + '/archive.partial')! != pin.sha256 {
		return error('archive readback mismatch')
	}
	after, after_size := source_pin(serial, pin)!
	if before != after || size != after_size { return error('source UART changed during transfer') }
	os.rename(root + '/archive.partial', root + '/archive.json')!
	receipt := Receipt{
		started_utc:          started
		finished_utc:         time.utc().str()
		source_serial_path:   serial
		source_serial_sha256: before
		source_serial_bytes:  size
		archive_sha256:       pin.sha256
		archive_bytes:        pin.bytes
		listen_address:       address
		receiver_sha256:      file_hash(os.executable())!
		eof:                  true
	}
	fd := exclusive(root + '/transfer.json')!
	defer { C.close(fd) }
	write_all(fd, (json2.encode(receipt, prettify: true) + '\n').bytes())!
	println('BROWSER-TCP PASS sha256=' + pin.sha256 + ' bytes=' + pin.bytes.str())
}

pub fn checked(root string) !Receipt {
	external_path(root)!
	if os.lstat(root)!.get_filetype() != .directory || os.lstat(root)!.mode & 0o777 != 0o700 {
		return error('private transfer directory required')
	}
	st := os.lstat(root + '/transfer.json')!
	if st.get_filetype() != .regular || st.size > 16384 {
		return error('bounded transfer receipt required')
	}
	r := json2.decode[Receipt](os.read_file(root + '/transfer.json')!)!
	pin := expected(r.archive_sha256, r.archive_bytes.str())!
	expected(r.receiver_sha256, '1')!
	if r.format != 1 || r.transport != 'browser-tcp-v1' || r.scope != scope || !r.eof
		|| !r.listen_address.starts_with('127.0.0.1:') || r.started_utc == '' || r.finished_utc == '' {
		return error('invalid TCP transfer receipt')
	}
	archive := os.lstat(root + '/archive.json')!
	if archive.get_filetype() != .regular || archive.size != u64(pin.bytes)
		|| file_hash(root + '/archive.json')! != pin.sha256 {
		return error('TCP archive size/hash mismatch')
	}
	sha, size := source_pin(r.source_serial_path, pin)!
	if sha != r.source_serial_sha256 || size != r.source_serial_bytes {
		return error('TCP source UART pin mismatch')
	}
	return r
}

pub fn send(path string, address string, pin Expected, timeout time.Duration) ! {
	$if !net_nonblocking_sockets ? {
		return error('sender requires compilation with -d net_nonblocking_sockets')
	}
	if timeout <= 0 || timeout > 120 * time.second { return error('invalid sender timeout') }
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size != u64(pin.bytes) || file_hash(path)! != pin.sha256 {
		return error('retained archive differs from expected source BEGIN')
	}
	mut file := os.open(path)!
	defer { file.close() }
	mut connection := net.dial_tcp(address)!
	defer { connection.close() or {} }
	deadline := time.now().add(timeout)
	connection.set_write_deadline(deadline)
	mut buffer := []u8{len: 65536}
	mut count := 0
	mut hash := sha256.new()
	for {
		if time.now() > deadline { return error('sender deadline') }
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		count += n
		if count > pin.bytes { return error('retained archive grew') }
		if connection.write(buffer[..n])! != n { return error('short TCP write') }
		hash.write(buffer[..n])!
	}
	if count != pin.bytes || hash.sum([]u8{}).hex() != pin.sha256 {
		return error('retained archive changed during send')
	}
	// Closing supplies EOF. Success here is sender completion, not host import.
	println('BROWSER-TCP SENT sha256=' + pin.sha256 + ' bytes=' + count.str())
}
