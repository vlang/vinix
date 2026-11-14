// SPDX-License-Identifier: GPL-2.0-or-later
module processsnapshot

import os
import json2

#include <unistd.h>
fn C.readlink(&char, &char, uint) i32

const total_limit = 64 * 1024 * 1024

struct Descriptor {
	fd u64
	available bool
	target string
}

// Private, one-shot descriptor inventory. The kernel may close/reuse an fd
// while it is read; retain failures and bracket the inventory with process
// start times instead of presenting it as an atomic snapshot.
pub fn capture_descriptors(pid string, root string) ! {
	descriptors_from('/proc', pid, root)!
}

fn descriptors_from(proc_root string, pid string, root string) ! {
	value := decimal(pid, 0, pid.len)!
	if value == 0 || value > 2147483647 || value.str() != pid {
		return error('canonical positive PID required')
	}
	if os.exists(root) || os.is_link(root) { return error('fresh descriptor directory required') }
	os.mkdir_all(root, mode: 0o700)!
	proc := proc_root + '/' + pid
	before := read_bounded(proc + '/stat', 65536)!
	started := start_time(before)!
	os.write_file(root + '/stat-before', before)!
	for name in ['status', 'limits'] {
		content := read_bounded(proc + '/' + name, 65536)!
		os.write_file(root + '/' + name, content)!
	}
	mut names := os.ls(proc + '/fd')!
	if names.len > 4096 { return error('descriptor count exceeds bound') }
	names.sort()
	mut entries := []Descriptor{cap: names.len}
	mut bytes := 0
	mut unavailable := 0
	for name in names {
		fd := decimal(name, 0, name.len)!
		if fd > 1048575 || fd.str() != name { return error('invalid descriptor name') }
		path := proc + '/fd/' + name
		mut buffer := [4096]u8{}
		length := C.readlink(&char(path.str), &char(&buffer[0]), 4096)
		if length < 0 {
			unavailable++
			entries << Descriptor{fd: fd}
			continue
		}
		if length == 0 || length >= 4096 { return error('descriptor target exceeds bound') }
		target := buffer[..int(length)].bytestr()
		bytes += target.len
		if bytes > 4 * 1024 * 1024 { return error('descriptor target inventory exceeds bound') }
		entries << Descriptor{fd, true, target}
	}
	os.write_file(root + '/descriptors.json', json2.encode(entries, prettify: true))!
	after := read_bounded(proc + '/stat', 65536)!
	os.write_file(root + '/stat-after', after)!
	after_started := start_time(after)!
	os.write_file(root + '/identity', 'pid=${pid} start=${started} after_start=${after_started} stable=${started == after_started}\n')!
	if started != after_started { return error('process identity changed during descriptor capture') }
	println('MAPS-DESCRIPTOR-SNAPSHOT-END pid=${pid} count=${entries.len} unavailable=${unavailable} non_atomic=true')
}

struct Budget {
mut:
	remaining int = total_limit
}

fn decimal(text string, start int, end int) !u64 {
	if start >= end { return error('empty number') }
	mut result := u64(0)
	for i in start .. end {
		c := text[i]
		if c < `0` || c > `9` || result > (~u64(0) - u64(c - `0`)) / 10 {
			return error('invalid number')
		}
		result = result * 10 + u64(c - `0`)
	}
	return result
}

fn start_time(text string) !u64 {
	// comm may contain spaces and parentheses; fields start after its final ).
	mut end := -1
	for i, c in text { if c == `)` { end = i } }
	if end < 0 || end + 2 >= text.len || text[end + 1] != ` ` { return error('invalid stat') }
	mut cursor := end + 2
	for field in 0 .. 20 {
		for cursor < text.len && text[cursor] == ` ` { cursor++ }
		begin := cursor
		for cursor < text.len && text[cursor] != ` ` && text[cursor] != `\n` { cursor++ }
		if begin == cursor { return error('short stat') }
		if field == 19 { return decimal(text, begin, cursor) }
	}
	return error('missing start time')
}

fn rss_kib(text string) !u64 {
	mut cursor := 0
	mut found := false
	mut result := u64(0)
	for cursor < text.len {
		begin := cursor
		for cursor < text.len && text[cursor] != `\n` { cursor++ }
		end := cursor
		cursor++
		key := 'VmRSS:'
		if end - begin < key.len { continue }
		mut matches := true
		for j in 0 .. key.len { if text[begin + j] != key[j] { matches = false } }
		if !matches { continue }
		if found { return error('duplicate RSS') }
		mut i := begin + key.len
		for i < end && text[i] in [` `, `\t`] { i++ }
		number := i
		for i < end && text[i] >= `0` && text[i] <= `9` { i++ }
		result = decimal(text, number, i)!
		for i < end && text[i] in [` `, `\t`] { i++ }
		if i + 2 != end || text[i] != `k` || text[i + 1] != `B` { return error('invalid RSS units') }
		found = true
	}
	if !found { return error('missing RSS') }
	return result
}

fn read_bounded(path string, limit int) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut bytes := []u8{len: limit + 1}
	defer { unsafe { bytes.free() } }
	mut used := 0
	for used <= limit {
		n := file.read(mut bytes[used..]) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		used += n
	}
	if used > limit { return error('proc file exceeds snapshot bound') }
	return bytes[..used].bytestr()
}

fn retain(proc_root string, root string, pid string, mut budget Budget) ! {
	proc := proc_root + '/' + pid
	defer { unsafe { proc.free() } }
	before_path := proc + '/stat'
	defer { unsafe { before_path.free() } }
	before := read_bounded(before_path, 65536)!
	defer { unsafe { before.free() } }
	started := start_time(before)!
	mut captured := 0
	for name in ['stat', 'status', 'maps', 'smaps'] {
		path := proc + '/' + name
		content := read_bounded(path, if name == 'smaps' { 2 * 1024 * 1024 } else { 512 * 1024 }) or {
			unsafe { path.free() }
			println('MAPS-MEMORY-FILE pid=${pid} file=${name} available=false')
			continue
		}
		unsafe { path.free() }
		if content.len > budget.remaining {
			unsafe { content.free() }
			budget.remaining = 0
			return error('total snapshot bound reached')
		}
		destination := root + '/' + pid + '-' + name
		os.write_file(destination, content) or {
			unsafe { destination.free(); content.free() }
			return err
		}
		budget.remaining -= content.len
		captured++
		if name == 'status' {
			if rss := rss_kib(content) { println('MAPS-MEMORY-RSS pid=${pid} start=${started} rss_kib=${rss}') }
		}
		unsafe { destination.free(); content.free() }
	}
	after := read_bounded(before_path, 65536)!
	defer { unsafe { after.free() } }
	after_start := start_time(after)!
	marker := root + '/' + pid + '-identity'
	defer { unsafe { marker.free() } }
	identity := 'start=${started} after_start=${after_start} stable=${started == after_start}\n'
	defer { unsafe { identity.free() } }
	if identity.len > budget.remaining { budget.remaining = 0; return error('identity exceeds total bound') }
	os.write_file(marker, identity)!
	budget.remaining -= identity.len
	println('MAPS-MEMORY-PROCESS pid=${pid} start=${started} stable=${started == after_start} files=${captured}')
}

// Administrator-only, one-shot observation. Files are not an atomic process
// snapshot: stat start times bracket each process, and disappearing processes
// or unavailable proc features are reported rather than treated as passes.
pub fn capture(root string) ! {
	capture_from('/proc', root)!
}

fn capture_from(proc_root string, root string) ! {
	if os.exists(root) { return error('fresh snapshot directory required') }
	os.mkdir_all(root, mode: 0o700)!
	mut names := os.ls(proc_root)!
	defer { unsafe { names.free() } }
	if names.len > 4096 { return error('proc directory exceeds bound') }
	names.sort()
	mut budget := Budget{}
	mut count := 0
	for name in names {
		pid := decimal(name, 0, name.len) or { continue }
		if pid == 0 || pid > 2147483647 { continue }
		if count == 128 { return error('process count exceeds bound') }
		count++
		retain(proc_root, root, name, mut budget) or { println('MAPS-MEMORY-PROCESS pid=${pid} complete=false') }
		if budget.remaining <= 0 { return error('total snapshot bound reached') }
	}
	println('MAPS-MEMORY-SNAPSHOT-END processes=${count} bytes=${total_limit - budget.remaining} non_atomic=true')
}

pub fn self_test() ! {
	assert rss_kib('Name: main\nVmRSS:\t3456 kB\n')! == 3456
	for text in ['VmRSS: -1 kB', 'VmRSS: 1 MB', 'VmRSS: 1 kB\nVmRSS: 2 kB', 'Name: main', 'VmRSS: 18446744073709551616 kB'] {
		if _ := rss_kib(text) { return error('invalid RSS accepted') }
	}
	assert start_time('1 (a ) b) S' + ' 0'.repeat(18) + ' 123 0')! == 123
	if _ := start_time('1 (short) S 0') { return error('short stat accepted') }
	for text in ['', '-1', '1/2', '18446744073709551616'] {
		if _ := decimal(text, 0, text.len) { return error('invalid PID accepted') }
	}
	root := os.temp_dir() + '/vinix-memory-snapshot-selftest-' + os.getpid().str()
	if os.exists(root) { return error('fresh selftest directory required') }
	os.mkdir(root, mode: 0o700)!
	defer { os.rmdir_all(root) or {} }
	path := root + '/fixture'
	os.write_file(path, 'abcd')!
	assert read_bounded(path, 4)! == 'abcd'
	if _ := read_bounded(path, 3) { return error('oversized proc input accepted') }
	os.write_file(path, '')!
	assert read_bounded(path, 4)! == ''
	os.mkdir_all(root + '/proc/7')!
	os.mkdir_all(root + '/proc/not-a-pid')!
	os.write_file(root + '/proc/7/stat', '7 (fixture) S' + ' 0'.repeat(18) + ' 123 0')!
	os.write_file(root + '/proc/7/status', 'VmRSS: 64 kB\n')!
	os.write_file(root + '/proc/7/maps', 'mapping fixture\n')!
	os.write_file(root + '/proc/7/smaps', 'Rss: 64 kB\n')!
	capture_from(root + '/proc', root + '/capture')!
	assert os.read_file(root + '/capture/7-identity')! == 'start=123 after_start=123 stable=true\n'
	assert os.read_file(root + '/capture/7-smaps')! == 'Rss: 64 kB\n'
	if _ := capture_from(root + '/proc', root + '/capture') { return error('existing snapshot overwritten') }
	// Real readlink behavior, duplicate open targets, a disappearing/non-link
	// entry, JSON escaping and private output permissions on the host filesystem.
	os.mkdir(root + '/proc/7/fd')!
	os.symlink('/apk/framework-res.apk', root + '/proc/7/fd/3')!
	os.symlink('/apk/framework-res.apk', root + '/proc/7/fd/4')!
	os.symlink('/private/a"b.apk', root + '/proc/7/fd/5')!
	os.write_file(root + '/proc/7/fd/6', '')!
	os.write_file(root + '/proc/7/limits', 'Max open files 1024 1048576 files\n')!
	descriptors_from(root + '/proc', '7', root + '/descriptors')!
	entries := json2.decode[[]Descriptor](os.read_file(root + '/descriptors/descriptors.json')!)!
	assert entries.len == 4 && entries[0].target == entries[1].target
	assert entries[2].target == '/private/a"b.apk' && !entries[3].available
	assert os.stat(root + '/descriptors')!.mode & 0o777 == 0o700
	if _ := descriptors_from(root + '/proc', '7', root + '/descriptors') {
		return error('existing descriptor inventory overwritten')
	}
	for pid in ['0', '07', '-1', '7/../7', '2147483648'] {
		if _ := descriptors_from(root + '/proc', pid, root + '/invalid-descriptors') {
			return error('invalid descriptor PID accepted')
		}
	}
}
