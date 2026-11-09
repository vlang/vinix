// SPDX-License-Identifier: GPL-2.0-or-later
module selectreadycheck

pub fn summary(arch string, baseline bool, linux bool) string {
	checks := if arch == 'aarch64' { '6720' } else { '8960' }
	failures := if linux { '0' } else if baseline { if arch == 'aarch64' { '960' } else { '1280' } } else { if arch == 'aarch64' { '672' } else { '896' } }
	return 'LINUX SELECTREADY SUMMARY: checks=' + checks + ' failures=' + failures
}
fn number(value string) !u64 {
	if value.len == 0 || !value.bytes().all(it >= `0` && it <= `9`) { return error('Invalid number') }
	return value.u64()
}
fn flat_pair(value string) ! {
	pair := value.split('/')
	if pair.len != 2 { return error('Invalid retention pair') }
	if number(pair[0])! != number(pair[1])! { return error('Retained storage changed') }
}
pub fn expected(arch string, baseline bool, linux bool) []string {
	mut result := []string{}
	apis := if arch == 'aarch64' { 3 } else { 4 }
	for ordinary in 0 .. 2 { for api in 0 .. apis { for kind in 0 .. 4 {
		uid := if ordinary == 0 { '0' } else { '1000' }
		result << 'LINUX SELECTREADY CASE: uid=' + uid + ' gid=' + if ordinary == 0 { '0' } else { '2000' }
			+ ' api=' + api.str() + ' kind=' + kind.str() + ' layouts=4 sets=7 timeouts=2 checks=280 failures=' + if !linux && kind == 0 { '112' } else if baseline { '16' } else { '0' }
		if !linux && kind == 0 { for layout in 0 .. 4 { for sets in 1 .. 8 { for timed in 0 .. 2 {
			if sets == 4 { continue }
			count := if layout == 3 { 3 } else if layout == 2 { 2 } else { 1 }
			prefix := 'LINUX SELECTREADY MISMATCH: uid=' + uid + ' api=' + api.str() + ' kind=0 layout=' + layout.str() + ' sets=' + sets.str() + ' timed=' + timed.str() + ' stage='
			result << prefix + '1'
			if sets & 1 != 0 { result << prefix + '3' }
			if sets & 2 != 0 { result << prefix + '4' }
			wanted := count * (if sets & 1 != 0 { 1 } else { 0 }) + count * (if sets & 2 != 0 { 1 } else { 0 })
			result << 'LINUX SELECTREADY DETAIL: actual=0/0 expected=' + wanted.str() + '/0'
		} } } }
		else if baseline { for layout in 0 .. 4 { for sets in [3, 7] { for timed in 0 .. 2 {
			count := if layout == 3 { 3 } else if layout == 2 { 2 } else { 1 }
			result << 'LINUX SELECTREADY MISMATCH: uid=' + uid + ' api=' + api.str() + ' kind=' + kind.str() + ' layout=' + layout.str() + ' sets=' + sets.str() + ' timed=' + timed.str() + ' stage=1'
			result << 'LINUX SELECTREADY DETAIL: actual=' + count.str() + '/0 expected=' + (count * 2).str() + '/0'
		} } } }
	} } }
	result << summary(arch, baseline, linux)
	result << 'LINUX SELECTREADY: ' + if linux { 'PASS' } else { 'FAIL' }
	return result
}
pub fn verify(text string, arch string, baseline bool, linux bool) ! {
	if arch !in ['aarch64', 'x86_64'] { return error('Unsupported architecture') }
	if linux && baseline { return error('A Linux reference cannot be a Vinix baseline') }
	if linux && !text.contains('Linux version ') { return error('Linux boot missing') }
	for bad in ['LINUX SELECTREADY FAIL:', 'REFERENCE FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION', 'Kernel panic', 'BUG:'] {
		if text.contains(bad) { return error('Failure marker: ' + bad) }
	}
	mut wanted := map[string]int{}
	for line in expected(arch, baseline, linux) { wanted[line]++ }
	mut actual := map[string]int{}
	mut slabs := map[string][]u64{}
	mut summaries := map[string]int{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('LINUX SELECTREADY SLAB:') || line.starts_with('LINUX SELECTREADY STORAGE:') {
			fields := line.fields()
			if fields.len < 4 || fields[3] !in ['uid=0', 'uid=1000'] { return error('Unexpected storage owner') }
			uid := fields[3]
			if linux {
				if line != 'LINUX SELECTREADY STORAGE: ' + uid + ' SKIP reference' { return error('Unexpected reference storage result') }
				summaries[uid]++
			} else if fields[2] == 'SLAB:' {
				if fields.len != 7 || fields[6] != 'cycles=200' || !fields[4].starts_with('size=') || !fields[5].starts_with('live=') { return error('Invalid slab record') }
				size := number(fields[4].all_after('='))!
				if size == 0 || size in slabs[uid] { return error('Invalid/duplicate slab class') }
				flat_pair(fields[5].all_after('='))!
				slabs[uid] << size
			} else {
				wrong := if baseline { if arch == 'aarch64' { '600' } else { '800' } } else { '0' }
				if fields.len != 9 || fields[4] != 'cycles=200' || fields[5] != 'wrong_counts=' + wrong || !fields[6].starts_with('big_pages=') || fields[7] != 'tainted=0/0' || fields[8] != 'PASS' { return error('Invalid storage summary') }
				flat_pair(fields[6].all_after('='))!
				summaries[uid]++
			}
			continue
		}
		if line.starts_with('LINUX SELECTREADY') {
			if line !in wanted { return error('Unexpected record: ' + line) }
			actual[line]++
		}
	}
	if actual != wanted { return error('Missing, repeated or altered records') }
	for uid in ['uid=0', 'uid=1000'] {
		if summaries[uid] != 1 { return error('Missing or repeated storage summary') }
		if linux { continue }
		if slabs[uid].len != if arch == 'aarch64' { 18 } else { 14 } { return error('Missing slab classes') }
		for size in [u64(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048] {
			if size !in slabs[uid] { return error('Missing fixed slab class') }
		}
		for size in slabs[uid] { if size > 2048 && (arch != 'aarch64' || size > 8192) { return error('Unexpected medium slab class') } }
	}
}
fn storage_controls(arch string, baseline bool, linux bool) string {
	mut result := ''
	mut sizes := [16, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]
	if arch == 'aarch64' { sizes << [2704, 4064, 5424, 8144] }
	for uid in [0, 1000] {
		if linux { result += 'LINUX SELECTREADY STORAGE: uid=' + uid.str() + ' SKIP reference\n'; continue }
		for size in sizes { result += 'LINUX SELECTREADY SLAB: uid=' + uid.str() + ' size=' + size.str() + ' live=10/10 cycles=200\n' }
		wrong := if baseline { if arch == 'aarch64' { '600' } else { '800' } } else { '0' }
		result += 'LINUX SELECTREADY STORAGE: uid=' + uid.str() + ' cycles=200 wrong_counts=' + wrong + ' big_pages=20/20 tainted=0/0 PASS\n'
	}
	return result
}
pub fn self_test() ! {
	mut negatives := 0
	for arch in ['aarch64', 'x86_64'] { for baseline in [false, true] { for linux in [false, true] {
		if linux && baseline { continue }
		good := 'Linux version control\n' + expected(arch, baseline, linux).join('\n') + '\n' + storage_controls(arch, baseline, linux)
		verify(good, arch, baseline, linux)!
		for line in good.split_into_lines().filter(it != '' && !it.starts_with('Linux version ')) {
			for bad in [good.replace(line + '\n', ''), good + line + '\n'] {
				verify(bad, arch, baseline, linux) or { negatives++; continue }
				return error('Missing/duplicate negative accepted')
			}
		}
		for bad in [good.replace('checks=280', 'checks=279'), good + 'Kernel panic injected\n', good + 'LINUX SELECTREADY UNKNOWN\n'] {
			verify(bad, arch, baseline, linux) or { negatives++; continue }
			return error('Alteration negative accepted')
		}
		if !linux { for bad in [good.replace('live=10/10', 'live=10/11'), good.replace('big_pages=20/20', 'big_pages=20/21'), good.replace('tainted=0/0', 'tainted=0/1')] {
			verify(bad, arch, baseline, linux) or { negatives++; continue }
			return error('Retention negative accepted')
		} }
	} } }
	println('Select readiness parser: PASS (6 positive, ' + negatives.str() + ' negative)')
}
