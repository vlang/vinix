// SPDX-License-Identifier: GPL-2.0-or-later
module processsnapshot

import os

const total_limit = 64 * 1024 * 1024

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
}
