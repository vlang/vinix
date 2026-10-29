// SPDX-License-Identifier: GPL-2.0-or-later
// Extract only child.log from an explicitly pinned two-file diagnostic archive.
module main

import crypto.sha256
import encoding.base64
import json2
import os

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.fstat(int, &C.stat) int

const archive_limit = 8 * 1024 * 1024
const child_limit = 4 * 1024 * 1024

struct Entry {
	path string
	kind string
	mode u32
	size u64
	sha256 string
	data string
	link string
}

struct Archive {
	version int
	root_mode u32
	entries []Entry
}

fn hash(text string) string { return sha256.sum(text.bytes()).hex() }

fn valid_pin(pin string) bool {
	return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn read_bounded(path string, limit int) !string {
	if !os.is_abs_path(path) || os.real_path(path) != path { return error('canonical regular input required') }
	fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('input open failed') }
	defer { C.close(fd) }
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 || st.st_mode & C.S_IFMT != C.S_IFREG || st.st_nlink != 1
		|| st.st_size <= 0 || st.st_size > limit { return error('regular input bounds rejected') }
	mut bytes := []u8{len: int(st.st_size)}
	mut at := 0
	for at < bytes.len {
		n := unsafe { C.read(fd, &u8(bytes.data) + at, usize(bytes.len - at)) }
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

fn child_payload(text string) !string {
	archive := json2.decode[Archive](text)!
	if archive.version != 1 || archive.root_mode != 0o755 || archive.entries.len != 2 {
		return error('two-file fixture archive required')
	}
	mut seen := map[string]bool{}
	mut child := ''
	for entry in archive.entries {
		if entry.path !in ['child.log', 'receipt.json'] || entry.path in seen
			|| entry.kind != 'regular' || entry.mode != 0o600 || entry.link != ''
			|| entry.size == 0 || entry.size > child_limit || !valid_pin(entry.sha256)
			|| entry.data.len > 4 * ((child_limit + 2) / 3) {
			return error('fixture entry identity or bounds rejected')
		}
		seen[entry.path] = true
		bytes := base64.decode(entry.data)
		if base64.encode(bytes) != entry.data || u64(bytes.len) != entry.size
			|| sha256.sum(bytes).hex() != entry.sha256 { return error('fixture entry bytes rejected') }
		if entry.path == 'child.log' { child = bytes.bytestr() }
	}
	if seen.len != 2 || !seen['child.log'] || !seen['receipt.json'] { return error('one child log required') }
	return child
}

fn write_fresh(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o400)
	if fd < 0 { return error('fresh output required') }
	mut at := 0
	for at < text.len {
		n := unsafe { C.write(fd, text.str + at, usize(text.len - at)) }
		if n <= 0 { C.close(fd); return error('output write failed') }
		at += int(n)
	}
	if C.close(fd) != 0 { return error('output close failed') }
	if read_bounded(path, archive_limit)! != text { return error('output readback differs') }
}

fn extract(input string, pin string, output string) ! {
	external(output)!
	if !valid_pin(pin) { return error('explicit archive SHA256 required') }
	text := read_bounded(input, archive_limit)!
	if hash(text) != pin { return error('archive SHA256 differs') }
	child := child_payload(text)!
	if read_bounded(input, archive_limit)! != text { return error('archive changed') }
	if C.mkdir(output.str, 0o700) != 0 { return error('fresh output directory required') }
	write_fresh(output + '/child.log', child)!
	write_fresh(output + '/receipt.json', json2.encode({
		'kind': json2.Any('vinix-diagnostic-uart-child-v1')
		'archive_path': json2.Any(input)
		'archive_sha256': json2.Any(pin)
		'child_sha256': json2.Any(hash(child))
		'child_bytes': json2.Any(child.len)
		'scope': json2.Any('Diagnostic derivation only; no strict UART import, fixture contract or authentication claim.')
	}, prettify: true) + '\n')!
	os.chmod(output, 0o500)!
	println('DIAGNOSTIC CHILD PASS sha256=' + hash(child) + ' bytes=' + child.len.str())
}

fn entry(path string, content string) Entry {
	return Entry{path: path, kind: 'regular', mode: 0o600, size: u64(content.len), sha256: hash(content), data: base64.encode(content.bytes())}
}

fn selftest(root string) ! {
	$if prod { return error('assertions required for selftest') }
	external(root)!
	if C.mkdir(root.str, 0o700) != 0 { return error('fresh selftest directory required') }
	child := entry('child.log', 'synthetic\x00\xff\n')
	receipt := entry('receipt.json', '{}\n')
	good := json2.encode(Archive{version: 1, root_mode: 0o755, entries: [child, receipt]})
	input := root + '/archive.json'
	write_fresh(input, good)!
	extract(input, hash(good), root + '/derived')!
	assert read_bounded(root + '/derived/child.log', child_limit)! == 'synthetic\x00\xff\n'
	for entries in [[receipt], [child, child], [child, receipt, child],
		[Entry{...child, sha256: '0'.repeat(64)}, receipt],
		[Entry{...child, data: '%%%='}, receipt], [Entry{...child, data: 'YQ'}, receipt],
		[Entry{...child, size: 1}, receipt], [Entry{...child, kind: 'symlink'}, receipt],
		[Entry{...child, path: '../child.log'}, receipt], [Entry{...child, path: '/child.log'}, receipt]] {
		if _ := child_payload(json2.encode(Archive{version: 1, root_mode: 0o755, entries: entries})) {
			return error('invalid fixture entry accepted')
		}
	}
	if _ := child_payload('{') { return error('malformed JSON accepted') }
	if _ := extract(input, '0'.repeat(64), root + '/bad-pin') { return error('wrong archive pin accepted') }
	if _ := extract(input, hash(good), root + '/derived') { return error('existing directory accepted') }
	os.symlink(root + '/derived', root + '/linked-output')!
	if _ := extract(input, hash(good), root + '/linked-output') { return error('symlink output accepted') }
	os.symlink(input, root + '/linked-input')!
	if _ := extract(root + '/linked-input', hash(good), root + '/bad-input') { return error('symlink input accepted') }
	if _ := read_bounded(input, 1) { return error('oversized input accepted') }
	os.mkdir(root + '/writer')!
	write_fresh(root + '/writer/child.log', 'first')!
	if _ := write_fresh(root + '/writer/child.log', 'second') { return error('existing file replaced') }
	os.symlink(input, root + '/writer/link')!
	if _ := write_fresh(root + '/writer/link', 'second') { return error('output symlink followed') }
	assert read_bounded(input, archive_limit)! == good
	println('DIAGNOSTIC CHILD SELFTEST PASS exact-two-files bounded-input pinned-archive canonical-base64 content-hash duplicate-missing-child malformed-data fresh-output symlinks')
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		selftest(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 4 { eprintln('usage: diagnostic-uart-child ARCHIVE_JSON SHA256 FRESH_OUTPUT | --self-test FRESH_DIR'); exit(2) }
	extract(os.args[1], os.args[2], os.args[3]) or { eprintln(err); exit(1) }
}
