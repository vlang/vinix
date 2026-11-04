// SPDX-License-Identifier: GPL-2.0-or-later
module selectcheck

pub fn summary(arch string, baseline bool) string {
	checks := if arch == 'aarch64' { '2176' } else { '2752' }
	failures := if baseline { if arch == 'aarch64' { '576' } else { '704' } } else { '0' }
	return 'LINUX SELECTEMPTY SUMMARY: checks=' + checks + ' failures=' + failures
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
pub fn expected(arch string, baseline bool) []string {
	mut result := []string{}
	apis := if arch == 'aarch64' { 3 } else { 4 }
	for ordinary in 0 .. 2 { for api in 0 .. apis { for nfds in [0, 1, 65, 1024] { for buffer in 0 .. 2 { for mode in 0 .. 4 { for restart in 0 .. 2 {
		if api >= 2 && mode == 0 { continue }
		checks := if mode <= 1 { 7 } else if mode == 2 { 5 } else { 6 }
		failures := if baseline && mode <= 1 { if mode == 0 { 3 } else { 4 } } else { 0 }
		fields := 'api=' + api.str() + ' nfds=' + nfds.str() + ' buffer=' + buffer.str() + ' mode=' + mode.str() + ' restart=' + restart.str()
		result << 'LINUX SELECTEMPTY CASE: uid=' + if ordinary == 0 { '0 gid=0' } else { '1000 gid=2000' }
			+ ' ' + fields + ' checks=' + checks.str() + ' failures=' + failures.str()
		if failures > 0 {
			for stage in if mode == 0 { [11, 12, 13] } else { [11, 12, 13, 17] } {
				result << 'LINUX SELECTEMPTY MISMATCH: ' + fields + ' stage=' + stage.str()
			}
		}
	} } } } } }
	result << summary(arch, baseline)
	result << 'LINUX SELECTEMPTY: ' + if baseline { 'FAIL' } else { 'PASS' }
	return result
}
pub fn verify(text string, arch string, baseline bool, linux bool) ! {
	if arch !in ['aarch64', 'x86_64'] { return error('Unsupported architecture') }
	if linux && !text.contains('Linux version ') { return error('Linux boot missing') }
	for bad in ['LINUX SELECTEMPTY FAIL:', 'REFERENCE FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION', 'Kernel panic', 'BUG:'] {
		if text.contains(bad) { return error('Failure marker: ' + bad) }
	}
	mut wanted := map[string]int{}
	for line in expected(arch, baseline) { wanted[line]++ }
	mut actual := map[string]int{}
	mut slabs := map[string][]u64{}
	mut summaries := map[string]int{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('LINUX SELECTEMPTY SLAB:') || line.starts_with('LINUX SELECTEMPTY STORAGE:') {
			fields := line.fields()
			if fields.len < 4 || fields[3] !in ['uid=0', 'uid=1000'] { return error('Unexpected storage owner') }
			uid := fields[3]
			if linux {
				if line != 'LINUX SELECTEMPTY STORAGE: ' + uid + ' SKIP reference' { return error('Unexpected reference storage result') }
				summaries[uid]++
			} else if fields[2] == 'SLAB:' {
				if fields.len != 7 || fields[6] != 'cycles=200' || !fields[4].starts_with('size=') || !fields[5].starts_with('live=') { return error('Invalid slab record') }
				size := number(fields[4].all_after('='))!
				if size == 0 || size in slabs[uid] { return error('Invalid/duplicate slab class') }
				flat_pair(fields[5].all_after('='))!
				slabs[uid] << size
			} else {
				expected_interrupts := if baseline { 'interrupted=0' } else { 'interrupted=200' }
				if fields.len != 9 || fields[4] != 'cycles=200' || fields[5] != expected_interrupts || !fields[6].starts_with('big_pages=') || fields[7] != 'tainted=0/0' || fields[8] != 'PASS' { return error('Invalid storage summary') }
				flat_pair(fields[6].all_after('='))!
				summaries[uid]++
			}
			continue
		}
		if line.starts_with('LINUX SELECTEMPTY') {
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
fn storage_controls(arch string, baseline bool) string {
	mut result := ''
	mut sizes := [16, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]
	if arch == 'aarch64' { sizes << [2704, 4064, 5424, 8144] }
	for uid in [0, 1000] {
		for size in sizes { result += 'LINUX SELECTEMPTY SLAB: uid=' + uid.str() + ' size=' + size.str() + ' live=10/10 cycles=200\n' }
		result += 'LINUX SELECTEMPTY STORAGE: uid=' + uid.str() + ' cycles=200 interrupted=' + if baseline { '0' } else { '200' } + ' big_pages=20/20 tainted=0/0 PASS\n'
	}
	return result
}
pub fn self_test() ! {
	mut negatives := 0
	for arch in ['aarch64', 'x86_64'] { for baseline in [false, true] {
		good := 'Linux version control\n' + expected(arch, baseline).join('\n') + '\n' + storage_controls(arch, baseline)
		verify(good, arch, baseline, false)!
		for line in good.split_into_lines().filter(it != '' && !it.starts_with('Linux version ')) {
			for bad in [good.replace(line + '\n', ''), good + line + '\n'] {
				verify(bad, arch, baseline, false) or { negatives++; continue }
				return error('Missing/duplicate negative accepted')
			}
		}
		for bad in [good.replace('checks=7', 'checks=6'), good + 'Kernel panic injected\n', good + 'LINUX SELECTEMPTY UNKNOWN\n', good.replace('live=10/10', 'live=10/11'), good.replace('big_pages=20/20', 'big_pages=20/21'), good.replace('tainted=0/0', 'tainted=0/1')] {
			verify(bad, arch, baseline, false) or { negatives++; continue }
			return error('Alteration negative accepted')
		}
	} }
	println('Empty-select parser: PASS (4 positive, ' + negatives.str() + ' negative)')
}
