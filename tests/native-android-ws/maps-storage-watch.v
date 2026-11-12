// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only, bounded observation of RAM-backed guest storage during startup.
module main

import os
import strconv
import time
import processsnapshot

fn memory_kib(text string, key string) !u64 {
	mut found := false
	mut value := u64(0)
	for line in text.split_into_lines() {
		if !line.starts_with(key + ':') { continue }
		fields := line.fields()
		if found || fields.len != 3 || fields[2] != 'kB' { return error('invalid memory field: ' + key) }
		value = strconv.parse_uint(fields[1], 10, 64)!
		found = true
	}
	if !found { return error('missing memory field: ' + key) }
	return value
}

fn observe() ! {
	start := time.sys_mono_now()
	mut next := u64(0)
	mut minimum := ~u64(0)
	mut free_minimum := ~u64(0)
	mut reported := ~u64(0)
	for {
		elapsed := (time.sys_mono_now() - start) / 1_000_000
		text := os.read_file('/proc/meminfo')!
		free := memory_kib(text, 'MemFree')!
		total := memory_kib(text, 'MemTotal')!
		disk := os.disk_usage('/var/lib/vinix/apps')!
		if free < free_minimum { free_minimum = free }
		if disk.available < minimum { minimum = disk.available }
		if elapsed >= next || reported - minimum >= 64 * 1024 * 1024 {
			println('MAPS-STORAGE-WATCH ms=${elapsed} available_bytes=${disk.available} minimum_bytes=${minimum} mem_free_kib=${free} mem_minimum_kib=${free_minimum} mem_total_kib=${total}')
			next = elapsed + 5000
			reported = minimum
		}
		if elapsed >= 600_000 {
			println('MAPS-STORAGE-WATCH-END ms=${elapsed} minimum_bytes=${minimum} mem_minimum_kib=${free_minimum}')
			return
		}
		time.sleep(250 * time.millisecond)
	}
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--memory-snapshot' {
		processsnapshot.capture(os.args[2]) or { eprintln('MAPS-MEMORY-SNAPSHOT-FAILED ' + err.msg()); exit(1) }
		return
	}
	if os.args.len == 2 && os.args[1] == '--selftest' {
		processsnapshot.self_test()!
		assert memory_kib('MemTotal: 123 kB\nMemFree: 7 kB\n', 'MemFree')! == 7
		for text in ['MemFree: 7 MB', 'MemFree: 7 kB\nMemFree: 8 kB', 'MemTotal: 7 kB', 'MemFree: -1 kB'] {
			if _ := memory_kib(text, 'MemFree') { panic('invalid observation accepted') }
		}
		println('MAPS-STORAGE-WATCH-SELFTEST-PASS')
		return
	}
	if os.args.len != 1 { eprintln('usage: maps-storage-watch [--selftest | --memory-snapshot FRESH_OUTPUT]'); exit(2) }
	observe() or { eprintln('MAPS-STORAGE-WATCH-FAILED ' + err.msg()); exit(1) }
}
