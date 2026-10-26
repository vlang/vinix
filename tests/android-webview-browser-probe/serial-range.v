// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve a complete stopped UART capture while selecting explicit whole lines.
module main

import crypto.sha256
import json2
import os

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.fstat(int, &C.stat) int
fn C.pread(int, voidptr, u64, i64) i64
fn C.write(int, voidptr, u64) i64
fn C.ftruncate(int, u64) int
fn C.mkfifo(&char, u32) int

const max_uart = 256 * 1024 * 1024
const repository = '/Users/alex/code/vinix'
const receipt_kind = 'vinix-serial-byte-range-v1'
const receipt_scope = 'Exact byte range only; the unchanged strict protocol collector must validate this segment.'

struct RangeReceipt {
	kind            string
	source_path     string
	original_bytes  int
	original_sha256 string
	start_inclusive int
	end_exclusive   int
	range_bytes     int
	range_sha256    string
	scope           string
}

fn clean_path(path string) !string {
	if path == '' || path.contains_any('\x00\r\n') { return error('invalid path') }
	absolute := os.abs_path(path)
	if os.real_path(os.dir(absolute)) != os.dir(absolute) {
		return error('canonical existing parent without symlinks required: ' + absolute)
	}
	return absolute
}

fn file_stat(fd int) !os.Stat {
	mut value := C.stat{}
	if C.fstat(fd, &value) != 0 { return error('fstat failed') }
	return os.Stat{
		dev:   u64(value.st_dev)
		inode: value.st_ino
		mode:  value.st_mode
		nlink: value.st_nlink
		size:  u64(value.st_size)
		mtime: value.st_mtime
		ctime: value.st_ctime
	}
}

fn regular_bounded(info os.Stat, limit int) ! {
	if info.get_filetype() != .regular || info.nlink != 1 || info.size > u64(limit) {
		return error('single-link regular file within byte limit required')
	}
}

fn same_file(a os.Stat, b os.Stat) bool {
	return a.dev == b.dev && a.inode == b.inode && a.mode == b.mode
		&& a.nlink == b.nlink && a.size == b.size && a.mtime == b.mtime && a.ctime == b.ctime
}

fn open_source(path string, limit int) !(int, os.Stat) {
	canonical := clean_path(path)!
	named := os.lstat(canonical)!
	regular_bounded(named, limit)!
	fd := C.open(canonical.str, C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('cannot open regular input without following symlinks') }
	info := file_stat(fd) or {
		C.close(fd)
		return err
	}
	regular_bounded(info, limit) or {
		C.close(fd)
		return err
	}
	if !same_file(named, info) {
		C.close(fd)
		return error('source changed while opening')
	}
	return fd, info
}

fn read_at(fd int, mut bytes []u8, offset int) ! {
	mut position := 0
	for position < bytes.len {
		count := C.pread(fd, unsafe { &bytes[position] }, u64(bytes.len - position), i64(offset + position))
		if count <= 0 { return error('input truncated or unreadable') }
		position += int(count)
	}
}

// A second complete hash and descriptor/path metadata checks detect changes
// during capture, including same-size edits with coarse timestamp resolution.
fn verify_stable(fd int, path string, before os.Stat, expected_hash string) ! {
	if !same_file(before, file_stat(fd)!) || !same_file(before, os.lstat(path)!) {
		return error('source changed during capture')
	}
	mut digest := sha256.new()
	defer { unsafe { digest.free() } }
	mut buffer := []u8{len: 64 * 1024}
	mut offset := 0
	for offset < int(before.size) {
		count := if int(before.size) - offset < buffer.len {
			int(before.size) - offset
		} else {
			buffer.len
		}
		mut part := unsafe { buffer[..count] }
		read_at(fd, mut part, offset)!
		digest.write(part)!
		offset += count
	}
	mut extra := u8(0)
	if C.pread(fd, &extra, 1, i64(before.size)) != 0
		|| digest.sum([]).hex() != expected_hash
		|| !same_file(before, file_stat(fd)!) || !same_file(before, os.lstat(path)!) {
		return error('source changed during capture')
	}
	clean_path(path)!
}

fn snapshot(path string, limit int) ![]u8 {
	canonical := clean_path(path)!
	fd, before := open_source(canonical, limit)!
	defer { C.close(fd) }
	mut bytes := []u8{len: int(before.size)}
	read_at(fd, mut bytes, 0)!
	verify_stable(fd, canonical, before, sha256.sum(bytes).hex())!
	return bytes
}

fn byte_offset(text string) !int {
	if text == '' || text.len > 9 || (text.len > 1 && text[0] == `0`) {
		return error('canonical decimal byte offset required')
	}
	mut value := 0
	for digit in text.bytes() {
		if digit < `0` || digit > `9` { return error('decimal byte offset required') }
		value = value * 10 + int(digit - `0`)
		if value > max_uart { return error('byte offset exceeds 256 MiB') }
	}
	return value
}

fn validate_range(bytes []u8, start int, end int) ! {
	if start < 0 || start >= end || end > bytes.len || bytes.len > max_uart {
		return error('nonempty bounded byte range required')
	}
	if (start != 0 && bytes[start - 1] != `\n`) || bytes[end - 1] != `\n` {
		return error('START and END must select complete LF-terminated lines')
	}
}

fn fresh_output(path string) !string {
	root := clean_path(path)!
	if root == repository || root.starts_with(repository + '/') {
		return error('output must be outside the repository')
	}
	if _ := os.lstat(root) { return error('output must be fresh') }
	return root
}

fn write_new(path string, bytes []u8) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('exclusive output creation failed: ' + path) }
	defer { C.close(fd) }
	mut position := 0
	for position < bytes.len {
		count := C.write(fd, unsafe { &bytes[position] }, u64(bytes.len - position))
		if count <= 0 { return error('output write failed') }
		position += int(count)
	}
}

fn extract(source string, start int, end int, output string) ! {
	root := fresh_output(output)!
	source_path := clean_path(source)!
	bytes := snapshot(source_path, max_uart)!
	validate_range(bytes, start, end)!
	selected := bytes[start..end]
	receipt := RangeReceipt{
		kind:            receipt_kind
		source_path:     source_path
		original_bytes:  bytes.len
		original_sha256: sha256.sum(bytes).hex()
		start_inclusive: start
		end_exclusive:   end
		range_bytes:     selected.len
		range_sha256:    sha256.sum(selected).hex()
		scope:           receipt_scope
	}
	os.mkdir(root, mode: 0o700)!
	write_new(root + '/serial-original.log', bytes)!
	write_new(root + '/serial-range.log', selected)!
	write_new(root + '/range.json', (json2.encode(receipt, prettify: true) + '\n').bytes())!
	check_bundle(root)!
}

fn check_bundle(path string) ! {
	root := clean_path(path)!
	if os.real_path(root) != root || os.lstat(root)!.get_filetype() != .directory {
		return error('canonical nonsymlink bundle directory required')
	}
	mut names := os.ls(root)!
	names.sort()
	if names != ['range.json', 'serial-original.log', 'serial-range.log'] {
		return error('exact three-file range bundle required')
	}
	encoded := snapshot(root + '/range.json', 16 * 1024)!.bytestr()
	receipt := json2.decode[RangeReceipt](encoded)!
	// The retained bundle remains checkable if the original source is moved.
	if receipt.kind != receipt_kind || receipt.scope != receipt_scope
		|| receipt.source_path == '' || receipt.source_path.contains_any('\x00\r\n')
		|| receipt.source_path != os.abs_path(receipt.source_path)
		|| receipt.original_bytes <= 0 || receipt.original_bytes > max_uart {
		return error('invalid range receipt')
	}
	bytes := snapshot(root + '/serial-original.log', max_uart)!
	selected := snapshot(root + '/serial-range.log', max_uart)!
	validate_range(bytes, receipt.start_inclusive, receipt.end_exclusive)!
	if receipt.original_bytes != bytes.len || receipt.original_sha256 != sha256.sum(bytes).hex()
		|| receipt.range_bytes != selected.len || receipt.range_sha256 != sha256.sum(selected).hex()
		|| selected != bytes[receipt.start_inclusive..receipt.end_exclusive] {
		return error('range receipt or retained bytes changed')
	}
}

fn self_test() ! {
	root := os.real_path(os.temp_dir()) + '/vinix-serial-range-selftest-' + os.getpid().str()
	os.mkdir(root, mode: 0o700)!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/input', mode: 0o700)!
	source := root + '/input/uart.log'
	raw := 'boot\r\nPHASE-A BEGIN\nPHASE-A END\nPHASE-B BEGIN\nPHASE-B END\ntail'
	os.write_file(source, raw)!
	start := raw.index('PHASE-B') or { return error('self-test phase missing') }
	end := raw.len - 4
	extract(source, start, end, root + '/valid')!
	assert os.read_file(root + '/valid/serial-original.log')! == raw
	assert os.read_file(root + '/valid/serial-range.log')! == raw[start..end]
	check_bundle(root + '/valid')!
	extract(source, 0, 6, root + '/first')!
	os.write_file(source, 'complete\n')!
	extract(source, 0, 9, root + '/whole')!
	os.write_file(source, raw)!
	for bounds in [[start + 1, end], [start, end - 1], [start, raw.len], [0, raw.len + 1],
		[start, start], [end, start], [-1, end]] {
		if _ := extract(source, bounds[0], bounds[1], root + '/invalid') {
			return error('invalid range accepted')
		}
		assert !os.exists(root + '/invalid')
	}
	for text in ['', '-1', '+1', '01', '1 ', '268435457', '999999999', '1000000000'] {
		if _ := byte_offset(text) { return error('invalid offset accepted') }
	}
	assert byte_offset('0')! == 0 && byte_offset('268435456')! == max_uart
	if _ := extract(source, start, end, root + '/valid') {
		return error('existing output accepted')
	}
	assert os.read_file(root + '/valid/serial-original.log')! == raw
	os.symlink(source, root + '/source-link')!
	if _ := snapshot(root + '/source-link', max_uart) { return error('source symlink accepted') }
	assert C.mkfifo((root + '/fifo').str, 0o600) == 0
	if _ := snapshot(root + '/fifo', max_uart) { return error('nonregular source accepted') }
	os.symlink(root + '/absent', root + '/dangling-output')!
	if _ := extract(source, start, end, root + '/dangling-output') {
		return error('dangling output accepted')
	}
	os.symlink(root, root + '/parent-link')!
	if _ := extract(source, start, end, root + '/parent-link/output') {
		return error('linked output parent accepted')
	}
	if _ := snapshot(root + '/parent-link/input/uart.log', max_uart) {
		return error('linked input parent accepted')
	}
	if _ := fresh_output(repository + '/serial-range-selftest') {
		return error('repository output accepted')
	}
	// A sparse file exercises the real metadata bound without allocating 256 MiB.
	oversized := root + '/oversized'
	big_fd := C.open(oversized.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
	assert big_fd >= 0
	assert C.ftruncate(big_fd, u64(max_uart) + 1) == 0
	C.close(big_fd)
	if _ := snapshot(oversized, max_uart) { return error('oversized UART accepted') }
	// Inject deterministic edits between capture and its second-pass check.
	fd, before := open_source(source, max_uart)!
	original_hash := sha256.sum(raw.bytes()).hex()
	os.write_file(source, raw.replace('PHASE-A', 'PHASE-X'))!
	if _ := verify_stable(fd, source, before, original_hash) {
		return error('same-size source edit accepted')
	}
	C.close(fd)
	os.write_file(source, raw)!
	fd2, before2 := open_source(source, max_uart)!
	os.write_file(source, 'truncated\n')!
	if _ := verify_stable(fd2, source, before2, original_hash) {
		return error('source truncation accepted')
	}
	C.close(fd2)
	os.write_file(source, raw)!
	fd3, before3 := open_source(source, max_uart)!
	os.mv(source, root + '/old-source')!
	os.write_file(source, raw)!
	if _ := verify_stable(fd3, source, before3, original_hash) {
		return error('source replacement accepted')
	}
	C.close(fd3)
	os.write_file(root + '/valid/serial-range.log', raw[start..end].replace('PHASE-B', 'PHASE-X'))!
	if _ := check_bundle(root + '/valid') { return error('range tampering accepted') }
	os.write_file(root + '/valid/serial-range.log', raw[start..end])!
	os.write_file(root + '/valid/serial-original.log', raw.replace('boot', 'BOOT'))!
	if _ := check_bundle(root + '/valid') { return error('original tampering accepted') }
	os.write_file(root + '/valid/serial-original.log', raw)!
	receipt_path := root + '/valid/range.json'
	receipt := os.read_file(receipt_path)!
	os.write_file(receipt_path, receipt.replace('"start_inclusive": ${start}', '"start_inclusive": 0'))!
	assert os.read_file(receipt_path)! != receipt
	if _ := check_bundle(root + '/valid') { return error('offset tampering accepted') }
	os.write_file(receipt_path, receipt)!
	check_bundle(root + '/valid')!
	os.rmdir_all(root + '/input')!
	check_bundle(root + '/valid')!
	println('SERIAL-RANGE-PASS whole-lines bounds truncation stable-source replacement fresh-output symlinks tamper')
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test()!
		return
	}
	if os.args.len == 3 && os.args[1] == '--check' {
		check_bundle(os.args[2])!
		println('SERIAL-RANGE-CHECK-PASS ' + os.abs_path(os.args[2]))
		return
	}
	if os.args.len != 5 {
		return error('usage: serial-range SERIAL_LOG START END FRESH_EXTERNAL_RESULTS | --check BUNDLE | --self-test')
	}
	extract(os.args[1], byte_offset(os.args[2])!, byte_offset(os.args[3])!, os.args[4])!
	println('SERIAL-RANGE-PASS ' + os.abs_path(os.args[4]))
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
