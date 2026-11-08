// SPDX-License-Identifier: GPL-2.0-or-later
module opathepollcheck

fn number(value string) !u64 {
	if value.len == 0 || !value.bytes().all(it >= `0` && it <= `9`) { return error('Invalid number') }
	return value.u64()
}
fn flat_pair(value string) ! {
	parts := value.split('/')
	if parts.len != 2 || number(parts[0])! != number(parts[1])! { return error('Retention changed') }
}
fn records(arch string) map[string]int {
	mut wanted := map[string]int{}
	for uid in [0, 1000] { for kind in 0 .. 10 { for api in 0 .. 3 {
		wanted['LINUX OPATHEPOLL CASE: uid=' + uid.str() + ' kind=' + kind.str() + ' api=' + api.str() + ' checks=' + (if api == 2 { if arch == 'aarch64' { '4' } else { '5' } } else { '54' }) + ' failures=0'] = 4
	} } }
	wanted['LINUX OPATHEPOLL SUMMARY: checks=' + if arch == 'aarch64' { '8960' } else { '9040' } + ' failures=0'] = 1
	wanted['LINUX OPATHEPOLL: PASS'] = 1
	return wanted
}
pub fn verify(text string, arch string, baseline bool, linux bool) ! {
	if arch !in ['aarch64', 'x86_64'] || baseline { return error('Expected a native candidate or Linux reference') }
	if linux && !text.contains('Linux version ') { return error('Linux boot missing') }
	for bad in ['FAIL', 'MISMATCH', 'KERNEL PANIC', 'FATAL EXCEPTION', 'Kernel panic', 'BUG:'] {
		if text.contains(bad) { return error('Failure marker: ' + bad) }
	}
	wanted := records(arch)
	mut actual := map[string]int{}
	mut slabs := map[string][]u64{}
	mut storage := map[string]int{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if !line.starts_with('LINUX OPATHEPOLL') { continue }
		if line.starts_with('LINUX OPATHEPOLL SLAB:') || line.starts_with('LINUX OPATHEPOLL STORAGE:') {
			fields := line.fields()
			if fields.len < 4 || fields[3] !in ['uid=0', 'uid=1000'] { return error('Invalid storage owner') }
			uid := fields[3]
			if linux {
				if line != 'LINUX OPATHEPOLL STORAGE: ' + uid + ' SKIP reference' { return error('Unexpected Linux storage') }
				storage[uid]++
			} else if fields[2] == 'SLAB:' {
				if fields.len != 6 || !fields[4].starts_with('size=') || !fields[5].starts_with('live=') { return error('Invalid slab record') }
				size := number(fields[4].all_after('='))!
				if size == 0 || size in slabs[uid] { return error('Invalid or duplicate slab class') }
				flat_pair(fields[5].all_after('='))!
				slabs[uid] << size
			} else {
				if fields.len != 8 || fields[4] != 'cycles=200' || !fields[5].starts_with('big_pages=') || fields[6] != 'tainted=0/0' || fields[7] != 'PASS' { return error('Invalid storage result') }
				flat_pair(fields[5].all_after('='))!
				storage[uid]++
			}
		} else {
			if line !in wanted { return error('Unexpected result: ' + line) }
			actual[line]++
		}
	}
	if actual != wanted { return error('Missing, repeated or altered result') }
	for uid in ['uid=0', 'uid=1000'] {
		if storage[uid] != 1 { return error('Missing or repeated storage result') }
		if linux { continue }
		if slabs[uid].len != if arch == 'aarch64' { 18 } else { 14 } { return error('Missing slab classes') }
		for size in [u64(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048] {
			if size !in slabs[uid] { return error('Missing fixed slab class') }
		}
	}
}
pub fn self_test() ! {
	mut rejected := 0
	for arch in ['aarch64', 'x86_64'] { for linux in [false, true] {
		mut good := 'Linux version control\n'
		for line, count in records(arch) { for _ in 0 .. count { good += line + '\n' } }
		for uid in [0, 1000] {
			prefix := 'LINUX OPATHEPOLL STORAGE: uid=' + uid.str()
			if linux { good += prefix + ' SKIP reference\n'; continue }
			mut sizes := [16, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]
			if arch == 'aarch64' { sizes << [2704, 4064, 5424, 8144] }
			for size in sizes { good += 'LINUX OPATHEPOLL SLAB: uid=' + uid.str() + ' size=' + size.str() + ' live=10/10\n' }
			good += prefix + ' cycles=200 big_pages=20/20 tainted=0/0 PASS\n'
		}
		verify(good, arch, false, linux)!
		for line in good.split_into_lines().filter(it.starts_with('LINUX OPATHEPOLL')) {
			for bad in [good.replace_once(line + '\n', ''), good + line + '\n'] {
				verify(bad, arch, false, linux) or { rejected++; continue }
				return error('Accepted missing or duplicate record')
			}
		}
		for bad in [good.replace('failures=0', 'failures=1'), good + 'Kernel panic injected\n'] {
			verify(bad, arch, false, linux) or { rejected++; continue }
			return error('Accepted failure')
		}
		if !linux { for bad in [good.replace('live=10/10', 'live=10/11'), good.replace('big_pages=20/20', 'big_pages=20/21'), good.replace('tainted=0/0', 'tainted=0/1')] {
			verify(bad, arch, false, linux) or { rejected++; continue }
			return error('Accepted retention')
		} }
	} }
	println('O_PATH epoll parser: PASS (4 positive, ' + rejected.str() + ' negative)')
}
