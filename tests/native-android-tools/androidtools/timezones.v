// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import encoding.binary
import json2
import os

// Libcore reads Android's indexed tzdata container, rather than a directory of
// TZif files. Keep the original IANA records, including aliases and transitions.
pub fn build_android_tzdata(source string, version string, output string) !int {
	if version.len != 5 || !version[..4].bytes().all(it >= `0` && it <= `9`)
		|| version[4] < `a` || version[4] > `z` { return error('invalid IANA timezone version') }
	mut pending := ['']
	mut records := map[string][]u8{}
	for pending.len > 0 {
		directory := pending.pop()
		for name in os.ls(os.join_path(source, directory))! {
			id := if directory == '' { name } else { directory + '/' + name }
			path := os.join_path(source, id)
			if os.is_dir(path) {
				if !os.is_link(path) { pending << id }
				continue
			}
			data := os.read_bytes(path)!
			if data.len < 44 || data[..4].bytestr() != 'TZif' { continue }
			if id.len >= 40 { return error('timezone ID exceeds Android index capacity: ' + id) }
			records[id] = data
		}
	}
	if 'UTC' !in records || 'Europe/Paris' !in records || 'America/New_York' !in records {
		return error('incomplete IANA timezone directory: ' + source)
	}
	mut ids := records.keys()
	ids.sort()
	data_offset := 24 + ids.len * 52
	mut index := []u8{len: data_offset}
	magic := ('tzdata' + version).bytes()
	copy(mut index[..11], magic)
	binary.big_endian_put_u32(mut index[12..16], 24)
	binary.big_endian_put_u32(mut index[16..20], u32(data_offset))
	mut data := []u8{}
	for position, id in ids {
		at := 24 + position * 52
		copy(mut index[at..at + id.len], id.bytes())
		binary.big_endian_put_u32(mut index[at + 40..at + 44], u32(data.len))
		binary.big_endian_put_u32(mut index[at + 44..at + 48], u32(records[id].len))
		// The final legacy raw-offset field is unused by this libcore reader.
		data << records[id]
	}
	binary.big_endian_put_u32(mut index[20..24], u32(data_offset + data.len))
	data << os.read_bytes(source + '/zone.tab')!
	index << data
	os.mkdir_all(os.dir(output))!
	os.write_file_array(output, index)!
	return ids.len
}

fn build_native_timezones(runtime string, output string) ! {
	metadata := json2.decode[map[string]json2.Any](os.read_file(root() + '/build-support/android/packages.lock.json')!)!
	mut version := ''
	for record in metadata['packages']!.as_array() {
		entry := record.as_map()
		if entry['name']!.str() == 'tzdata' { version = entry['version']!.str().all_before('-r') }
	}
	count := build_android_tzdata(runtime + '/usr/share/zoneinfo', version, output + '/tzdata')!
	println('ANDROID-TZDATA-BUILD version=${version} zones=${count}')
}
