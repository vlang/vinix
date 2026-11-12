// SPDX-License-Identifier: GPL-2.0-or-later
// Summarize retained, non-atomic processsnapshot smaps without opening a VM disk.
module main

import os
import strconv

struct Region {
mut:
	header string
	size u64
	rss u64
	has_size bool
	has_rss bool
}

fn amount(line string) !u64 {
	words := line.fields()
	if words.len != 3 || words[2] != 'kB' { return error('invalid smaps amount') }
	return strconv.parse_uint(words[1], 10, 64)!
}

fn regions(text string) ![]Region {
	mut result := []Region{}
	lines := text.split_into_lines()
	for line in lines {
		words := line.fields()
		if words.len >= 5 && words[0].contains('-') && words[1].len == 4 && words[1][0] in [`r`, `-`] {
			result << Region{header: line}
			continue
		}
		if !line.starts_with('Size:') && !line.starts_with('Rss:') { continue }
		if result.len == 0 { return error('smaps amount before mapping') }
		index := result.len - 1
		value := amount(line)!
		if line.starts_with('Size:') {
			if result[index].has_size { return error('duplicate mapping size') }
			result[index].size = value
			result[index].has_size = true
		} else {
			if result[index].has_rss { return error('duplicate mapping RSS') }
			result[index].rss = value
			result[index].has_rss = true
		}
	}
	if result.len == 0 { return error('empty smaps') }
	for region in result {
		if !region.has_size || !region.has_rss || region.rss > region.size { return error('incomplete or inconsistent smaps') }
	}
	return result
}

fn report(root string) ! {
	mut names := os.ls(root)!
	names.sort()
	for name in names {
		if !name.ends_with('-stat') { continue }
		pid := name.all_before('-')
		strconv.parse_uint(pid, 10, 32)!
		identity := os.read_file(root + '/' + pid + '-identity') or {
			println('MEMORY-REPORT pid=${pid} incomplete=true')
			continue
		}
		if !identity.ends_with(' stable=true\n') {
			println('MEMORY-REPORT pid=${pid} identity_unstable=true')
			continue
		}
		path := root + '/' + pid + '-smaps'
		if !os.is_file(path) {
			println('MEMORY-REPORT pid=${pid} smaps_unavailable=true')
			continue
		}
		if os.file_size(path) > 2 * 1024 * 1024 { return error('smaps exceeds capture bound') }
		mut maps := regions(os.read_file(path)!)!
		mut size, mut rss, mut unnamed := u64(0), u64(0), u64(0)
		for region in maps {
			if size > ~u64(0) - region.size || rss > ~u64(0) - region.rss { return error('smaps sum overflow') }
			size += region.size
			rss += region.rss
			if region.header.fields().len == 5 { unnamed += region.rss }
		}
		println('MEMORY-REPORT pid=${pid} mappings=${maps.len} size_kib=${size} rss_kib=${rss} unnamed_rss_kib=${unnamed} non_atomic=true')
		if rss < 65536 { continue }
		maps.sort(a.rss > b.rss)
		limit := if maps.len < 12 { maps.len } else { 12 }
		for i in 0 .. limit {
			region := maps[i]
			println('MEMORY-REGION pid=${pid} size_kib=${region.size} rss_kib=${region.rss} map=${region.header}')
		}
	}
}

fn self_test() ! {
	text := '1000-2000 rw-p 00000000 00:00 0\nSize: 4 kB\nRss: 2 kB\n'
	maps := regions(text)!
	assert maps.len == 1 && maps[0].size == 4 && maps[0].rss == 2
	for bad in ['', 'Rss: 1 kB', text + 'Rss: 2 kB\n', text.replace('Size: 4', 'Size: 1'), text.replace(' kB', ' MB'), text.replace('Rss: 2 kB\n', '')] {
		if _ := regions(bad) { return error('invalid smaps accepted') }
	}
	println('MAPS-MEMORY-REPORT-SELFTEST-PASS')
}

fn main() {
	if os.args.len != 2 { eprintln('usage: maps-memory-report SNAPSHOT_DIRECTORY | --selftest'); exit(2) }
	if os.args[1] == '--selftest' { self_test()!; return }
	report(os.args[1]) or { eprintln(err); exit(1) }
}
