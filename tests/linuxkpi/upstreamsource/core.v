// SPDX-License-Identifier: GPL-2.0-or-later
// Stream trusted archives into a private tree; publish only checked inputs.
module upstreamsource

import os
import time
import json2
import hosttest

#flag -lcurl
#flag -larchive
#flag -I @DIR
#include <curl/curl.h>
#include "archive_extra_abi.h"
#include <unistd.h>

fn C.curl_global_init(i64) i32
fn C.curl_global_cleanup()
fn C.curl_easy_init() voidptr
fn C.curl_easy_setopt(voidptr, i32, ...voidptr) i32
fn C.curl_easy_perform(voidptr) i32
fn C.curl_easy_strerror(i32) &char
fn C.curl_easy_cleanup(voidptr)
fn C.mkstemp(&u8) i32
fn C.fdopen(i32, &char) &C.FILE
fn C.close(i32) i32

struct C.archive {}

struct C.archive_entry {}

fn C.archive_read_new() &C.archive
fn C.archive_read_support_filter_xz(&C.archive) i32
fn C.archive_read_support_format_tar(&C.archive) i32
fn C.archive_read_open_filename(&C.archive, &char, usize) i32
fn C.archive_read_next_header(&C.archive, &&C.archive_entry) i32
fn C.archive_entry_pathname(&C.archive_entry) &char
fn C.archive_entry_filetype(&C.archive_entry) u32
fn C.archive_entry_hardlink(&C.archive_entry) &char
fn C.archive_read_data(&C.archive, voidptr, usize) isize
fn C.archive_error_string(&C.archive) &char
fn C.archive_read_free(&C.archive) i32

struct Transfer {
mut:
	file         &C.FILE = unsafe { nil }
	last_data    u64
	write_failed bool
}

fn receive(data &char, size usize, count usize, opaque voidptr) usize {
	if size != 0 && count > usize(0xffffffffffffffff) / size { return 0 }
	length := size * count
	mut transfer := unsafe { &Transfer(opaque) }
	written := C.fwrite(data, 1, length, transfer.file)
	if written != length { transfer.write_failed = true }
	if written != 0 { transfer.last_data = time.sys_mono_now() }
	return written
}

fn progress(opaque voidptr, _ i64, _ i64, _ i64, _ i64) i32 {
	transfer := unsafe { &Transfer(opaque) }
	// The original urlopen timeout is an inactivity limit rather than a
	// deadline for the whole archive. Successful chunks restart this clock.
	return if time.sys_mono_now() - transfer.last_data >= u64(60 * time.second) { 1 } else { 0 }
}

fn setting(handle voidptr, option i32, value i64) ! {
	if C.curl_easy_setopt(handle, option, value) != 0 {
		return error('Cannot configure download transport')
	}
}

fn download(url string, descriptor i32) ! {
	stream := C.fdopen(descriptor, c'wb')
	if stream == unsafe { nil } {
		C.close(descriptor)
		return os.error_posix()
	}
	mut closed := false
	defer { if !closed { C.fclose(stream) } }
	if C.curl_global_init(i64(C.CURL_GLOBAL_DEFAULT)) != 0 {
		return error('Cannot initialize download transport')
	}
	defer { C.curl_global_cleanup() }
	handle := C.curl_easy_init()
	if handle == unsafe { nil } { return error('Cannot allocate download transport') }
	defer { C.curl_easy_cleanup(handle) }
	mut transfer := Transfer{ file: stream, last_data: time.sys_mono_now() }
	if C.curl_easy_setopt(handle, C.CURLOPT_URL, url.str) != 0
		|| C.curl_easy_setopt(handle, C.CURLOPT_WRITEFUNCTION, receive) != 0
		|| C.curl_easy_setopt(handle, C.CURLOPT_WRITEDATA, unsafe { &transfer }) != 0
		|| C.curl_easy_setopt(handle, C.CURLOPT_XFERINFOFUNCTION, progress) != 0
		|| C.curl_easy_setopt(handle, C.CURLOPT_XFERINFODATA, unsafe { &transfer }) != 0 {
		return error('Cannot configure download transport')
	}
	setting(handle, C.CURLOPT_FOLLOWLOCATION, 1)!
	setting(handle, C.CURLOPT_MAXREDIRS, 10)!
	setting(handle, C.CURLOPT_FAILONERROR, 1)!
	setting(handle, C.CURLOPT_CONNECTTIMEOUT, 60)!
	setting(handle, C.CURLOPT_NOPROGRESS, 0)!
	setting(handle, C.CURLOPT_SSL_VERIFYPEER, 1)!
	setting(handle, C.CURLOPT_SSL_VERIFYHOST, 2)!
	status := C.curl_easy_perform(handle)
	if transfer.write_failed { return error('Cannot write downloaded archive') }
	if status != 0 {
		message := unsafe { cstring_to_vstring(C.curl_easy_strerror(status)) }
		return error('Download failed: ' + message)
	}
	flushed := C.fclose(stream)
	closed = true
	if flushed != 0 { return os.error_posix() }
}

pub fn selected(name string, pin map[string]json2.Any) !bool {
	excluded := (pin['excluded_directories'] or { return error('excluded_directories') }).as_array()
	if excluded.any(name.starts_with(it.str())) { return false }
	files := (pin['files'] or { return error('files') }).as_array()
	directories := (pin['directories'] or { return error('directories') }).as_array()
	return files.any(name == it.str()) || directories.any(name.starts_with(it.str()))
}

fn archive_error(reader &C.archive) IError {
	pointer := C.archive_error_string(reader)
	return error(if pointer == unsafe { nil } {
		'invalid archive'
	} else {
		unsafe { cstring_to_vstring(pointer) }
	})
}

fn copy_member(reader &C.archive, output string, mut buffer []u8) ! {
	stream := C.fopen(output.str, c'wb')
	if stream == unsafe { nil } { return os.error_posix() }
	mut closed := false
	defer { if !closed { C.fclose(stream) } }
	for {
		read := C.archive_read_data(reader, buffer.data, usize(buffer.len))
		if read < 0 { return archive_error(reader) }
		if read == 0 { break }
		if C.fwrite(buffer.data, 1, usize(read), stream) != usize(read) { return os.error_posix() }
	}
	status := C.fclose(stream)
	closed = true
	if status != 0 { return os.error_posix() }
}

fn extract(archive string, temporary string, prefix string, pin map[string]json2.Any) !map[string]string {
	reader := C.archive_read_new()
	if reader == unsafe { nil } { return error('Cannot allocate archive reader') }
	defer { C.archive_read_free(reader) }
	if C.archive_read_support_filter_xz(reader) != 0 || C.archive_read_support_format_tar(reader) != 0
		|| C.archive_read_open_filename(reader, archive.str, 10240) != 0 {
		return archive_error(reader)
	}
	mut files := map[string]string{}
	mut entry := &C.archive_entry(unsafe { nil })
	mut buffer := []u8{len: 1024 * 1024}
	for {
		status := C.archive_read_next_header(reader, &entry)
		if status == 1 { break }
		if status != 0 { return archive_error(reader) }
		pathname := C.archive_entry_pathname(entry)
		if pathname == unsafe { nil } { return error('Archive entry has no pathname') }
		member := unsafe { cstring_to_vstring(pathname) }
		if !member.starts_with(prefix) { continue }
		name := member[prefix.len..]
		if !selected(name, pin)! || C.archive_entry_filetype(entry) != 0o100000
			|| C.archive_entry_hardlink(entry) != unsafe { nil } {
			continue
		}
		if name.starts_with('/') || '..' in name.split('/') {
			return error('unsafe archive member: ' + member)
		}
		output := os.join_path(temporary, name)
		os.mkdir_all(os.dir(output))!
		copy_member(reader, output, mut buffer)!
		files[name] = hosttest.file_digest(output)!
	}
	return files
}

pub fn fetch(base string, pin map[string]json2.Any) !string {
	os.mkdir_all(base)!
	version := (pin['version'] or { return error('version') }).str()
	checksum := (pin['sha256'] or { return error('sha256') }).str()
	archive := os.join_path(base, 'linux-' + version + '.tar.xz')
	if !os.exists(archive) || hosttest.file_digest(archive)! != checksum {
		mut pattern := (os.join_path(base, '.download-XXXXXX') + '\x00').bytes()
		descriptor := unsafe { C.mkstemp(pattern.data) }
		if descriptor < 0 { return os.error_posix() }
		download_path := unsafe { cstring_to_vstring(&char(pattern.data)) }
		defer { os.rm(download_path) or {} }
		url := (pin['url'] or {
			C.close(descriptor)
			return error('url')
		}).str()
		println('Downloading ' + url)
		C.fflush(unsafe { nil })
		download(url, descriptor)!
		if hosttest.file_digest(download_path)! != checksum {
			return error('download SHA256 differs from upstream.json')
		}
		if C.rename(download_path.str, archive.str) != 0 { return os.error_posix() }
	}
	root := os.join_path(base, 'linux-' + version)
	if os.exists(root) {
		hosttest.verify_upstream(root, pin)!
		return root
	}
	mut pattern := (os.join_path(base, '.extract-XXXXXX') + '\x00').bytes()
	pointer := unsafe { C.mkdtemp(&char(pattern.data)) }
	if pointer == unsafe { nil } { return os.error_posix() }
	temporary := unsafe { cstring_to_vstring(pointer) }
	defer { if os.exists(temporary) { os.rmdir_all(temporary) or {} } }
	files := extract(archive, temporary, os.file_name(root) + '/', pin)!
	os.write_file(os.join_path(temporary, '.vinix-upstream.json'), hosttest.bounds_json(map[string]json2.Any{
		'archive_sha256': json2.Any(checksum)
		'files':          hosttest.string_map(files)
	}))!
	if C.rename(temporary.str, root.str) != 0 { return os.error_posix() }
	hosttest.verify_upstream(root, pin)!
	return root
}
