// SPDX-License-Identifier: GPL-2.0-or-later
// Exact byte snapshots of a growing UART; no frame parsing or repair.
module main

import crypto.sha256
import json2
import os

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

fn C.open(&char, int, ...int) int
fn C.read(int, voidptr, u64) i64
fn C.write(int, voidptr, u64) i64
fn C.close(int) int
fn C.fstat(int, &C.stat) int
fn C.lseek(int, i64, int) i64
fn C.fchmod(int, int) int
fn C.fsync(int) int
fn C.mkdir(&char, int) int

const limit = 8 * 1024 * 1024

struct Receipt {
	version int
	kind string
	source string
	source_device u64
	source_inode u64
	source_size_after i64
	full_bytes int
	full_sha256 string
	interval_start int
	interval_bytes int
	interval_sha256 string
	prior_directory string
	prior_receipt_sha256 string
	prior_full_sha256 string
}

fn digest(data []u8) string { return sha256.sum(data).hex() }

fn valid_digest(s string) bool {
	return s.len == 64 && s.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn canonical(path string) ! {
	if !os.is_abs_path(path) || os.real_path(path) != path {
		return error('canonical absolute path required')
	}
}

fn fresh(path string) ! {
	canonical(os.dir(path))!
	if !os.is_abs_path(path) || os.file_name(path) in ['', '.', '..'] || path.ends_with('/')
		|| C.mkdir(path.str, 0o700) != 0 {
		return error('fresh private output directory required')
	}
}

fn opened(path string, readonly bool) !(int, C.stat) {
	canonical(path)!
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('input open failed') }
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 || st.st_mode & C.S_IFMT != C.S_IFREG || st.st_nlink != 1
		|| st.st_size < 0 || st.st_size > limit || (readonly && st.st_mode & 0o777 != 0o400) {
		C.close(fd)
		return error('input type, mode or size rejected')
	}
	return fd, st
}

fn read_exact(fd int, count int) ![]u8 {
	if count < 0 || count > limit || C.lseek(fd, 0, C.SEEK_SET) != 0 {
		return error('read bounds or seek rejected')
	}
	mut data := []u8{len: count}
	mut at := 0
	for at < count {
		n := unsafe { C.read(fd, &u8(data.data) + at, u64(count - at)) }
		if n <= 0 { return error('input truncated or read failed') }
		at += int(n)
	}
	return data
}

// Appends are allowed; an inode replacement, truncation or changed byte is not.
fn snapshot(path string, readonly bool) !([]u8, C.stat) {
	fd, before := opened(path, readonly)!
	defer { C.close(fd) }
	data := read_exact(fd, int(before.st_size))!
	if read_exact(fd, data.len)! != data { return error('input prefix changed during snapshot') }
	mut after := C.stat{}
	if C.fstat(fd, &after) != 0 || after.st_dev != before.st_dev || after.st_ino != before.st_ino
		|| after.st_nlink != 1 || after.st_size < before.st_size || after.st_size > limit
		|| (readonly && (after.st_size != before.st_size || after.st_mode & 0o777 != 0o400)) {
		return error('input identity or size changed')
	}
	other, current := opened(path, readonly)!
	C.close(other)
	if current.st_dev != before.st_dev || current.st_ino != before.st_ino || current.st_size < before.st_size {
		return error('input pathname changed')
	}
	return data, after
}

fn save(path string, data []u8) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o400)
	if fd < 0 { return error('exclusive output open failed') }
	defer { C.close(fd) }
	mut at := 0
	for at < data.len {
		n := unsafe { C.write(fd, &u8(data.data) + at, u64(data.len - at)) }
		if n <= 0 { return error('output write failed') }
		at += int(n)
	}
	if C.fchmod(fd, 0o400) != 0 || C.fsync(fd) != 0 { return error('output seal failed') }
	readback, _ := snapshot(path, true)!
	if readback != data { return error('output readback mismatch') }
}

fn previous(path string, pin string, source string) !([]u8, string) {
	canonical(path)!
	mut names := os.ls(path)!
	names.sort()
	if names != ['full.log', 'interval.log', 'receipt.json'] || !valid_digest(pin) {
		return error('prior snapshot members or receipt pin rejected')
	}
	encoded, _ := snapshot(path + '/receipt.json', true)!
	if digest(encoded) != pin { return error('prior receipt SHA256 mismatch') }
	r := json2.decode[Receipt](encoded.bytestr())!
	data, _ := snapshot(path + '/full.log', true)!
	interval, _ := snapshot(path + '/interval.log', true)!
	if r.version != 1 || r.kind != 'vinix-uart-snapshot-v1' || r.source != source
		|| r.full_bytes != data.len || r.full_sha256 != digest(data)
		|| r.interval_start < 0 || r.interval_start > data.len
		|| r.interval_bytes != data.len - r.interval_start || r.interval_sha256 != digest(interval)
		|| interval != data[r.interval_start..] {
		return error('prior snapshot receipt or exact interval mismatch')
	}
	return data, r.full_sha256
}

fn append_interval(data []u8, prior []u8) ![]u8 {
	if data.len <= prior.len || data[..prior.len] != prior {
		return error('UART did not append to the complete prior snapshot')
	}
	return data[prior.len..].clone()
}

fn capture(source string, out string, prior_dir string, prior_pin string) !Receipt {
	mut prior := []u8{}
	mut prior_sha := ''
	if prior_dir != '' {
		prior, prior_sha = previous(prior_dir, prior_pin, source)!
	} else if prior_pin != '' { return error('unexpected prior receipt pin') }
	data, after := snapshot(source, false)!
	interval := if prior_dir == '' { data.clone() } else { append_interval(data, prior)! }
	r := Receipt{version: 1, kind: 'vinix-uart-snapshot-v1', source: source,
		source_device: u64(after.st_dev), source_inode: u64(after.st_ino), source_size_after: after.st_size,
		full_bytes: data.len, full_sha256: digest(data), interval_start: prior.len,
		interval_bytes: interval.len, interval_sha256: digest(interval), prior_directory: prior_dir,
		prior_receipt_sha256: prior_pin, prior_full_sha256: prior_sha}
	fresh(out)!
	save(out + '/full.log', data)!
	save(out + '/interval.log', interval)!
	save(out + '/receipt.json', json2.encode(r).bytes())!
	os.chmod(out, 0o500)!
	return r
}

fn rejected(source string, out string, prior string, pin string) ! {
	if _ := capture(source, out, prior, pin) { return error('negative capture unexpectedly accepted') }
}

fn self_test(out string) ! {
	fresh(out)!
	source := out + '/serial.log'
	first := 'boot\r\nfirst\x00\xff\n'.bytes()
	second := 'VINIX-SERVICE-QUERY-RESULTS-1 BEGIN untouched\r\n'.bytes()
	os.write_file(source, first.bytestr())!
	r1 := capture(source, out + '/first', '', '')!
	pin := digest(os.read_bytes(out + '/first/receipt.json')!)
	mut combined := first.clone()
	combined << second
	os.write_file(source, combined.bytestr())!
	r2 := capture(source, out + '/second', out + '/first', pin)!
	if r1.full_bytes != first.len || r2.interval_start != first.len
		|| os.read_bytes(out + '/second/full.log')! != combined
		|| os.read_bytes(out + '/second/interval.log')! != second {
		return error('exact binary snapshot/interval proof failed')
	}
	rejected(source, out + '/bad-pin', out + '/first', '0'.repeat(64))!
	os.write_file(source, 'changed\n' + second.bytestr())!
	rejected(source, out + '/bad-prefix', out + '/first', pin)!
	os.write_file(source, first[..first.len - 1].bytestr())!
	rejected(source, out + '/truncated', out + '/first', pin)!
	os.write_file(source, first.bytestr())!
	rejected(source, out + '/no-append', out + '/first', pin)!
	rejected(source, out + '/first', '', '')!
	os.symlink(source, out + '/symlink.log')!
	rejected(out + '/symlink.log', out + '/bad-link', '', '')!
	if _ := append_interval([u8(1)], [u8(1), 2]) { return error('short prefix accepted') }
	if _ := read_exact(-1, limit + 1) { return error('read limit accepted') }
	println('UART-SNAPSHOT-SELFTEST PASS exact-binary prefix-continuity pin truncation no-append fresh-output symlink bounds')
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		self_test(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 3 && !(os.args.len == 6 && os.args[3] == '--after') {
		eprintln('usage: uart-snapshot SERIAL FRESH_OUTPUT [--after PRIOR_OUTPUT PRIOR_RECEIPT_SHA256] | --self-test FRESH_OUTPUT')
		exit(1)
	}
	prior := if os.args.len == 6 { os.args[4] } else { '' }
	pin := if os.args.len == 6 { os.args[5] } else { '' }
	r := capture(os.args[1], os.args[2], prior, pin) or { eprintln(err); exit(1) }
	println('UART-SNAPSHOT PASS full_bytes=${r.full_bytes} interval_start=${r.interval_start} interval_bytes=${r.interval_bytes} full_sha256=${r.full_sha256} interval_sha256=${r.interval_sha256}')
	println('receipt_sha256=' + digest(os.read_bytes(os.args[2] + '/receipt.json') or { eprintln(err); exit(1) }))
}
