// SPDX-License-Identifier: GPL-2.0-or-later
// Pin one complete immutable export without decoding or repairing its payload.
module main

import crypto.sha256
import os

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

fn C.open(&char, int, ...int) int
fn C.read(int, voidptr, u64) i64
fn C.write(int, voidptr, u64) i64
fn C.close(int) int
fn C.fstat(int, &C.stat) int
fn C.mkdir(&char, int) int
fn C.mkfifo(&char, u32) i32

const raw_limit = 8 * 1024 * 1024
const archive_limit = 4 * 1024 * 1024
const prefixes = ['VINIX-BROWSER-RESULTS-1 ', 'VINIX-HEADLESS-RESULTS-1 ',
	'VINIX-ACCOUNT-UI-RESULTS-1 ', 'VINIX-MAPS-ACCOUNT-RESULTS-1 ',
	'VINIX-ACCOUNT-TOKEN-CACHE-RESULTS-1 ', 'VINIX-SERVICE-QUERY-RESULTS-1 ']

struct Metadata {
	archive_sha256 string
	archive_bytes int
	archive_chunks int
}

fn hash(raw string) string { return sha256.sum(raw.bytes()).hex() }

fn valid_digest(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn decimal(value string, limit int) !int {
	if value == '' || value.len > 10 || (value.len > 1 && value[0] == `0`)
		|| !value.bytes().all(it >= `0` && it <= `9`) || value.u64() > u64(limit) {
		return error('noncanonical or out-of-bounds decimal')
	}
	return value.int()
}

fn selected_prefix(selector string) !string {
	return match selector {
		'--maps-account' { 'VINIX-MAPS-ACCOUNT-RESULTS-1 ' }
		'--service-query' { 'VINIX-SERVICE-QUERY-RESULTS-1 ' }
		else { return error('explicit maps-account or service-query selector required') }
	}
}

fn metadata(raw string, selected string) !Metadata {
	if raw.len == 0 || raw.len > raw_limit { return error('UART size rejected') }
	mut begun := false
	mut ended := false
	mut index := 0
	mut result := Metadata{}
	lines := raw.split('\n')
	for ordinal, raw_line in lines {
		line := if raw_line.ends_with('\r') { raw_line[..raw_line.len - 1] } else { raw_line }
		for known in prefixes {
			if pos := line.index(known) {
				if pos != 0 || known != selected { return error('embedded or foreign export frame') }
			}
		}
		if !line.starts_with(selected) { continue }
		if ordinal + 1 == lines.len || line.contains('\r') { return error('export LF/CRLF boundary rejected') }
		if ended || line.len > 1024 { return error('repeated or oversized export frame') }
		fields := line[selected.len..].split(' ')
		if fields.len != 4 || fields.any(it == '') { return error('noncanonical frame fields') }
		match fields[0] {
			'BEGIN' {
				if begun || !valid_digest(fields[1]) { return error('BEGIN rejected') }
				bytes := decimal(fields[2], archive_limit)!
				chunks := decimal(fields[3], (archive_limit + 511) / 512)!
				if bytes <= 0 || chunks != (bytes + 511) / 512 { return error('archive bounds rejected') }
				result = Metadata{fields[1], bytes, chunks}
				begun = true
			}
			'CHUNK' {
				if !begun || fields[1] != result.archive_sha256 || index >= result.archive_chunks
					|| decimal(fields[2], result.archive_chunks)! != index || fields[3].len > 684 {
					return error('CHUNK metadata rejected')
				}
				// Payload encoding, size, digest and archive validation remain the
				// unchanged diagnostic reconstructor's responsibility.
				index++
			}
			'END' {
				if !begun || fields[1] != result.archive_sha256 || index != result.archive_chunks
					|| decimal(fields[2], archive_limit)! != result.archive_bytes
					|| decimal(fields[3], result.archive_chunks)! != result.archive_chunks {
					return error('END rejected')
				}
				ended = true
			}
			else { return error('unknown export frame') }
		}
	}
	if !ended { return error('complete export required') }
	return result
}

fn read_immutable(path string) !string {
	if !os.is_abs_path(path) || os.real_path(path) != path { return error('canonical input required') }
	fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('input open failed') }
	defer { C.close(fd) }
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 || st.st_mode & C.S_IFMT != C.S_IFREG || st.st_nlink != 1
		|| st.st_mode & 0o777 != 0o400 || st.st_size <= 0 || st.st_size > raw_limit {
		return error('immutable regular input bounds rejected')
	}
	mut bytes := []u8{len: int(st.st_size)}
	mut at := 0
	for at < bytes.len {
		n := unsafe { C.read(fd, &u8(bytes.data) + at, u64(bytes.len - at)) }
		if n <= 0 { return error('input truncated or read failed') }
		at += int(n)
	}
	mut extra := u8(0)
	if C.read(fd, &extra, 1) != 0 { return error('input changed size') }
	return bytes.bytestr()
}

fn external(path string) ! {
	parent := os.dir(path)
	if !os.is_abs_path(path) || os.real_path(parent) != parent || path.ends_with('/')
		|| parent + '/' + os.file_name(path) != path || os.file_name(path) in ['', '.', '..']
		|| path.contains_any('\x00\r\n\\') { return error('canonical external output required') }
	mut ancestor := parent
	for {
		if os.exists(ancestor + '/.git') { return error('output inside checkout rejected') }
		if ancestor == '/' { break }
		ancestor = os.dir(ancestor)
	}
}

fn write_fresh(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o400)
	if fd < 0 { return error('fresh output required') }
	mut at := 0
	for at < text.len {
		n := unsafe { C.write(fd, text.str + at, u64(text.len - at)) }
		if n <= 0 { C.close(fd); return error('output write failed') }
		at += int(n)
	}
	if C.close(fd) != 0 { return error('output close failed') }
	if read_immutable(path)! != text { return error('output readback mismatch') }
}

fn generate(selector string, input string, pin string, output string) !string {
	external(output)!
	if !valid_digest(pin) { return error('explicit input digest required') }
	raw := read_immutable(input)!
	if hash(raw) != pin { return error('input pin mismatch') }
	selected := selected_prefix(selector)!
	meta := metadata(raw, selected)!
	// All interpolated strings have fixed alphabets: two fixed prefixes and
	// lowercase hexadecimal digests. No payload or unchecked string enters JSON.
	text := '{"version":2,"frame_prefix":"${selected}","serial_sha256":"${pin}","archive_sha256":"${meta.archive_sha256}","archive_bytes":${meta.archive_bytes},"archive_chunks":${meta.archive_chunks},"removals":[]}\n'
	if read_immutable(input)! != raw { return error('input changed') }
	write_fresh(output, text)!
	return hash(text)
}

fn selftest(output string) ! {
	$if prod { return error('assertions required for selftest') }
	external(output)!
	if C.mkdir(output.str, 0o700) != 0 { return error('fresh selftest directory required') }
	prefix := selected_prefix('--service-query')!
	pin := hash('{}')
	frame := prefix + 'BEGIN ${pin} 2 1\r\n' + prefix + 'CHUNK ${pin} 0 e30=\r\n' + prefix + 'END ${pin} 2 1\r\n'
	assert metadata('boot\r\n' + frame + 'done\r\n', prefix)! == Metadata{pin, 2, 1}
	for bad in [frame + frame, frame[..frame.len - 1], frame.replace('\r\n', '\r\r\n'),
		frame.replace('\r\n', '\r'), frame.replace(prefix + 'END ${pin} 2 1\r\n', ''),
		frame.replace('END', 'STOP'), frame.replace('CHUNK ${pin} 0', 'CHUNK ${pin} 1'),
		frame.replace(' 2 1', ' 02 1'), frame.replace('e30=', 'e30= extra'), frame.replace('END ${pin} 2 1', 'END ${pin} 3 1'),
		'x' + frame, frame + prefixes[0] + 'BEGIN ${pin} 2 1\n', frame.replace('BEGIN ${pin}', 'BEGIN BAD')] {
		if _ := metadata(bad, prefix) { return error('malformed metadata accepted') }
	}
	input := output + '/input.log'
	write_fresh(input, frame)!
	plan := output + '/plan.json'
	plan_pin := generate('--service-query', input, hash(frame), plan)!
	assert hash(read_immutable(plan)!) == plan_pin
	assert read_immutable(plan)!.contains('"removals":[]')
	if _ := generate('--service-query', input, '0'.repeat(64), output + '/bad-pin.json') { return error('bad pin accepted') }
	if _ := generate('--service-query', input, hash(frame), plan) { return error('existing output accepted') }
	os.symlink(input, output + '/link.log')!
	if _ := read_immutable(output + '/link.log') { return error('symlink accepted') }
	if C.mkfifo((output + '/fifo').str, 0o400) != 0 { return error('FIFO fixture failed') }
	if _ := read_immutable(output + '/fifo') { return error('FIFO accepted') }
	os.rm(output + '/fifo')!
	if _ := metadata(frame, selected_prefix('--maps-account')!) { return error('foreign prefix accepted') }
	println('UART-NO-REMOVAL-PLAN SELFTEST PASS')
}

fn run() ! {
	if os.args.len == 3 && os.args[1] == '--self-test' { selftest(os.args[2])!; return }
	if os.args.len != 5 { return error('usage: uart-no-removal-plan --maps-account|--service-query IMMUTABLE_UART SHA256 FRESH_PLAN | --self-test FRESH_DIR') }
	pin := generate(os.args[1], os.args[2], os.args[3], os.args[4])!
	println('UART-NO-REMOVAL-PLAN PASS plan=' + pin)
}

fn main() { run() or { eprintln(err); exit(1) } }
