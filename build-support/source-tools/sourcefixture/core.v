// SPDX-License-Identifier: GPL-2.0-or-later
module sourcefixture

import encoding.binary
import encoding.hex
import encoding.utf8
import os

#include <sys/stat.h>

pub fn read(path string) !string {
	text := os.read_file(path)!
	if !utf8.validate_str(text) { return error('invalid UTF-8 source: ' + path) }
	return text.replace('\r\n', '\n').replace('\r', '\n')
}

fn index(text string, marker string, start int) !int {
	if start < 0 || start > text.len { return error('invalid source offset') }
	position := text[start..].index(marker) or { return error('source marker missing: ' + marker) }
	return start + position
}

fn between(text string, begin string, end string) !string {
	start := index(text, begin, 0)!
	finish := index(text, end, start)!
	return text[start..finish]
}

pub fn clock(text string) !string {
	return 'module time\n' + between(text, 'pub struct TimeSpec', '__global (')!
}

pub fn ext2_mmap(text string) !string {
	return 'module ext2\nimport errno\nimport memory\nimport memory.mmap as mmap_mod\nimport stat\n' +
		between(text, 'fn (mut this EXT2Resource) mmap(', 'fn (mut this EXT2Resource) read(')!
}

pub fn private_fixture(text string) !(string, string) {
	begin := index(text, 'fn test_', 0)!
	header := index(text, 'const page_size', 0)!
	return text[..begin], text[..header] + text[begin..]
}

fn function(text string, name string, one_line bool) !string {
	mut begin := index(text, 'fn ' + name + '(', 0)!
	if begin >= 4 && text[begin - 4..begin] == 'pub ' { begin -= 4 }
	end := if one_line { index(text, '\n', begin)! + 1 } else { index(text, '\n}\n', begin)! + 3 }
	return text[begin..end] + '\n'
}

pub fn private_install(text string, paging_text string, file_pages bool, paging bool) !string {
	mut names := ['page_table_flags', 'range_page_has_file_data', 'install_range_page',
		'resolve_cow_fault', 'unshare_private_page_unlocked']
	mut result := 'module mmap\nimport memory\nimport numa\nimport lib\nimport proc\nimport pager\nimport errno\nimport resource\n'
	if !file_pages {
		result += 'fn resolve_shared_file_write(_pm &memory.Pagemap, _address u64) bool { return false }\nfn pageout_file_span(_pm &memory.Pagemap, _begin u64, _end u64) u64 { return 0 }\n'
	}
	result += between(paging_text, 'struct PagedPage', 'fn reclaim_uncovered_paged_locked')!
	if paging {
		result = result[..index(result, 'struct PagedPage', 0)!] + between(paging_text, 'struct PagedPage', '__global (')!
		result = result.replace('import errno\n', 'import errno\nimport sched\nimport kbudget\n')
		result += '__global (pageout_process_cursor = int(1))\n'
		result += function(paging_text, 'reclaim_anonymous', false)!
		result += function(paging_text, 'max_u64', true)!
		names << 'range_priority'
	}
	for name in names { result += function(text, name, false)! }
	return result
}

pub fn m1_kernel() []u8 {
	mut bytes := []u8{len: 64}
	prefix := [u8(127), `E`, `L`, `F`, 2, 1, 1]
	for position, value in prefix { bytes[position] = value }
	binary.little_endian_put_u16(mut bytes[16..18], 2)
	binary.little_endian_put_u16(mut bytes[18..20], 183)
	binary.little_endian_put_u32(mut bytes[20..24], 1)
	bytes << hex.decode('888b4cdf30ddb1c77bf094a183e8820a7e851b9a817ba695e0736a3b721bb6a0') or { panic(err) }
	return bytes
}
