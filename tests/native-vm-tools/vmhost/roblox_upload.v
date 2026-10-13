// SPDX-License-Identifier: MIT
module vmhost

import cachecli
import gamehost
import io
import net
import os
import perfreport
import sourcecommand
import strconv
import time

pub fn roblox_upload_name(path string) string {
	parts := path.split('/').filter(it != '' && it != '.')
	return if parts.len == 0 { 'upload' } else { parts.last() }
}

fn upload_connection(mut connection net.TcpConn, directory string) {
	defer { connection.close() or {} }
	upload_request(mut connection, directory) or {}
}

fn upload_line(mut connection net.TcpConn) !string {
	mut bytes := []u8{}
	mut one := []u8{len: 1}
	for bytes.len <= 65536 {
		if connection.read(mut one)! == 0 { return error('upload request EOF') }
		bytes << one[0]
		if one[0] == `\n` { return bytes.bytestr().trim_right('\r\n') }
	}
	return error('upload header line too long')
}

fn upload_request(mut connection net.TcpConn, directory string) ! {
	first := upload_line(mut connection)!.fields()
	if first.len != 3 { return error('malformed upload request') }
	mut length := '0'
	mut found_length := false
	mut ended := false
	for _ in 0 .. 100 {
		line := upload_line(mut connection)!
		if line == '' {
			ended = true
			break
		}
		at := line.index(':') or { continue }
		if line[..at].to_lower() == 'content-length' && !found_length {
			length = line[at + 1..].trim_space()
			found_length = true
		}
	}
	if !ended { return error('too many upload headers') }
	if first[0] != 'POST' {
		connection.write_string('HTTP/1.0 501 Unsupported method\r\nContent-Length: 0\r\n\r\n')!
		return
	}
	normalized := perfreport.integer_text(length)!
	count := strconv.parse_int(normalized, 10, 64)!
	mut body := []u8{}
	mut buffer := []u8{len: 65536}
	for count < 0 || i64(body.len) < count {
		size := if count < 0 || count - body.len > buffer.len {
			buffer.len
		} else {
			int(count - body.len)
		}
		n := connection.read(mut buffer[..size]) or {
			if err is io.Eof { break }
			return err
		}
		if n == 0 { break }
		body << buffer[..n]
	}
	os.write_file_array(directory + '/' + roblox_upload_name(first[1]), body)!
	connection.write_string('HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n')!
}

pub fn roblox_serve(directory string, port string) !int {
	gamehost.mkdir(directory)!
	number := strconv.parse_int(port, 10, 64)!
	if number < 0 || number > 65535 { return error('port must be 0..65535') }
	mut listener := net.listen_tcp(.ip, '127.0.0.1:' + port)!
	defer { listener.close() or {} }
	println('ROBLOX-UPLOAD-READY ' + listener.addr()!.port()!.str())
	flush_stdout()
	for {
		mut connection := listener.accept()!
		// The server's private process owns all concurrent request threads. Its
		// parent retires that process and every outstanding request together.
		spawn upload_connection(mut connection, directory)
	}
	return 0
}

pub struct RobloxUploads {
pub:
	port string
	pid  int
mut:
	child sourcecommand.ReaderChild
}

pub fn roblox_uploads(executable string, directory string, port string) !RobloxUploads {
	mut child := sourcecommand.spawn_reader([executable, 'roblox-upload', directory, port], os.environ())!
	mut ready := false
	defer { if !ready { child.close() or {} } }
	mut response := ''
	mut buffer := []u8{len: 1024}
	until := now() + 10
	for now() < until {
		cachecli.checkpoint()!
		mut descriptor := C.pollfd{ fd: child.descriptor, events: i16(C.POLLIN) }
		rc := C.poll(&descriptor, 1, 50)
		if rc < 0 {
			if C.errno == C.EINTR { continue }
			return os.error_posix()
		}
		if rc > 0 {
			count := unsafe { C.read(child.descriptor, buffer.data, usize(buffer.len)) }
			if count > 0 { response += buffer[..int(count)].bytestr() }
			if count == 0 { return error('upload server exited before readiness') }
			if response.contains('\n') {
				if !response.starts_with('ROBLOX-UPLOAD-READY ') {
					return error('unexpected upload server greeting')
				}
				ready = true
				return RobloxUploads{response.all_before('\n').all_after('ROBLOX-UPLOAD-READY '), child.pid, child}
			}
		}
		if child.poll()!.exited { return error('upload server could not start') }
		time.sleep(time.millisecond)
	}
	return error('upload server readiness timed out')
}

pub fn (mut server RobloxUploads) close() ! { server.child.close()! }
