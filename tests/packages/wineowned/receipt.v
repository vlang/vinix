// SPDX-License-Identifier: GPL-2.0-or-later
// Shared captured-file admission for native production and retention.
module wineowned

import os
import json2
import crypto.sha256
import tests.packages.winesource

#include <fcntl.h>
#include <sys/stat.h>
#define wine_receipt_open open
#define wine_receipt_openat openat
#define wine_receipt_fstat fstat
#define wine_receipt_read read
fn C.wine_receipt_open(&char, i32) i32
fn C.wine_receipt_openat(i32, &char, i32) i32
fn C.wine_receipt_fstat(i32, &C.stat) i32
fn C.wine_receipt_read(i32, voidptr, u64) i64

// Fixed relative paths beneath one captured prepared directory. Neither a
// symlink nor a FIFO/device may stand in for a receipt or the compiled runner.
fn owned_bytes(rootfd i32, relative string, limit int) !string {
	parts := relative.split('/')
	defer { unsafe { for part in parts { part.free() }; (&array(&parts)).free() } }
	mut parent := rootfd
	mut own_parent := false
	defer { if own_parent { C.close(parent) } }
	for index in 0 .. parts.len - 1 {
		part := parts[index]
		next := C.wine_receipt_openat(parent, part.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if next < 0 { return error('owned Wine receipt requires captured ordinary files: ' + relative) }
		if own_parent { C.close(parent) }
		parent = next
		own_parent = true
	}
	fd := C.wine_receipt_openat(parent, parts.last().str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('owned Wine receipt requires captured ordinary files: ' + relative) }
	defer { C.close(fd) }
	mut st := C.stat{}
	if C.wine_receipt_fstat(fd, &st) != 0 || st.st_mode & C.S_IFMT != C.S_IFREG || st.st_size < 1 || st.st_size > limit {
		return error('owned Wine receipt file is not bounded and regular: ' + relative)
	}
	mut bytes := []u8{len: int(st.st_size) + 1}
	defer { unsafe { bytes.free() } }
	mut got := 0
	for got < bytes.len {
		count := C.wine_receipt_read(fd, unsafe { &bytes[got] }, u64(bytes.len - got))
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return error('cannot read owned Wine receipt file: ' + relative)
		}
		if count == 0 { break }
		got += int(count)
	}
	mut after := C.stat{}
	if got != st.st_size || C.wine_receipt_fstat(fd, &after) != 0 || after.st_size != st.st_size || after.st_mode != st.st_mode {
		return error('owned Wine receipt file changed while reading: ' + relative)
	}
	return unsafe { tos(bytes.data, got) }.clone()
}

pub fn admit(prepared string, arch string, root string) ! {
	if arch != 'x86_64' { return error('owned native Wine qualification requires x86_64') }
	fd := C.wine_receipt_open(prepared.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return error('owned Wine prepared directory is unavailable') }
	defer { C.close(fd) }
	mode_text := owned_bytes(fd, 'owned-manager.json', 8192)!
	output_text := owned_bytes(fd, 'outputs.json', 1024 * 1024)!
	argv_text := owned_bytes(fd, 'logs/v.log.argv.json', 65536)!
	runner := owned_bytes(fd, 'prepared/' + arch + '/runtime/bin/wine-runner', 32 * 1024 * 1024)!
	defer { unsafe { mode_text.free(); output_text.free(); argv_text.free(); runner.free() } }
	mode := json2.decode[map[string]string](mode_text) or { return error('owned Wine mode JSON invalid') }
	outputs := json2.decode[map[string]string](output_text) or { return error('owned Wine outputs JSON invalid') }
	argv := json2.decode[[]string](argv_text) or { return error('owned Wine compiler arguments JSON invalid') }
	if argv.len < 2 || argv.len > 512 { return error('owned Wine compiler arguments outside bound') }
	mut flag := false
	for index in 0 .. argv.len - 1 { if argv[index] == '-d' && argv[index + 1] == 'wine_owned_manager' { flag = true } }
	if mode.len != 3 || mode['architecture'] != arch || mode['mode'] != 'wine_owned_manager' || !flag
		|| mode['runner_source_sha256'] != winesource.file_digest(root + '/tools/packages/wine-runner.v')!
		|| outputs['owned-manager.json'] != sha256.hexhash(mode_text)
		|| outputs['prepared/' + arch + '/runtime/bin/wine-runner'] != sha256.hexhash(runner) {
		return error('owned Wine runtime build receipt differs')
	}
}

