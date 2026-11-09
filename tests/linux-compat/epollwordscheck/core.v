// SPDX-License-Identifier: GPL-2.0-or-later
module epollwordscheck

fn number(value string) !u64 {
	if value.len == 0 || !value.bytes().all(it >= `0` && it <= `9`) {
		return error('Invalid number')
	}
	return value.u64()
}

fn flat_pair(value string) ! {
	parts := value.split('/')
	if parts.len != 2 || number(parts[0])! != number(parts[1])! {
		return error('Retention changed')
	}
}

fn add_case(mut wanted map[string]int, uid int, api int, value int, fd int, kind int, pattern int, baseline bool) int {
	key := 'uid=' + uid.str() + ' api=' + api.str() + ' value=' + value.str() + ' fd=' + fd.str() + ' kind=' + kind.str() + ' pattern=' + pattern.str()
	stages := if baseline && pattern >= 2 {
		if kind == 0 && fd in [0, 1, 2, 4] {
			if fd in [1, 2] { [1, 2, 5] } else { [1] }
		} else if kind == 1 && value in [3, 4, 5] && fd != 4 {
			if fd in [1, 2] { [1, 2, 5] } else { [1] }
		} else if kind == 2 {
			if api == 0 { [1, 3, 6] } else { [1, 3] }
		} else {
			[]int{}
		}
	} else {
		[]int{}
	}
	wanted['LINUX EPOLLWORDS CASE: ' + key + ' checks=6 failures=' + stages.len.str()] = 1
	for stage in stages {
		wanted['LINUX EPOLLWORDS MISMATCH: ' + key + ' stage=' + stage.str()] = 1
	}
	return stages.len
}

fn records(arch string, baseline bool) map[string]int {
	mut wanted := map[string]int{}
	mut checks := 0
	mut failures := 0
	for uid in [0, 1000] {
		for api in 0 .. if arch == 'aarch64' { 2 } else { 3 } {
			for kind in [0, 1, 3] {
				if kind == 3 && api == 2 { continue }
				for value in 0 .. if kind == 1 { 8 } else { 1 } {
					for fd in 0 .. 6 {
						for pattern in 0 .. 6 {
							checks += 6
							failures += add_case(mut wanted, uid, api, value, fd, kind, pattern, baseline)
						}
					}
				}
			}
			if api == 1 { continue }
			for pattern in 0 .. 6 {
				checks += 6
				failures += add_case(mut wanted, uid, api, 0, 0, 2, pattern, baseline)
			}
		}
	}
	wanted['LINUX EPOLLWORDS SUMMARY: checks=' + checks.str() + ' failures=' + failures.str()] = 1
	wanted['LINUX EPOLLWORDS: ' + if baseline { 'FAIL' } else { 'PASS' }] = 1
	return wanted
}

pub fn verify(text string, arch string, baseline bool, linux bool) ! {
	if arch !in ['aarch64', 'x86_64'] || (baseline && linux) {
		return error('Expected a native baseline/candidate or Linux reference')
	}
	if linux && !text.contains('Linux version ') { return error('Linux boot missing') }
	for bad in ['LINUX EPOLLWORDS FAIL:', 'KERNEL PANIC', 'FATAL EXCEPTION', 'Kernel panic', 'BUG:'] {
		if text.contains(bad) { return error('Failure marker: ' + bad) }
	}
	wanted := records(arch, baseline)
	mut actual := map[string]int{}
	mut slabs := map[string][]u64{}
	mut storage := map[string]int{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if !line.starts_with('LINUX EPOLLWORDS') { continue }
		if line.starts_with('LINUX EPOLLWORDS SLAB:') || line.starts_with('LINUX EPOLLWORDS STORAGE:') {
			if baseline { return error('Unexpected baseline storage') }
			fields := line.fields()
			if fields.len < 4 || fields[3] !in ['uid=0', 'uid=1000'] {
				return error('Invalid storage owner')
			}
			uid := fields[3]
			if linux {
				if line != 'LINUX EPOLLWORDS STORAGE: ' + uid + ' SKIP reference' {
					return error('Unexpected Linux storage')
				}
				storage[uid]++
			} else if fields[2] == 'SLAB:' {
				if fields.len != 6 || !fields[4].starts_with('size=') || !fields[5].starts_with('live=') {
					return error('Invalid slab record')
				}
				size := number(fields[4].all_after('='))!
				if size == 0 || size in slabs[uid] {
					return error('Invalid or duplicate slab class')
				}
				flat_pair(fields[5].all_after('='))!
				slabs[uid] << size
			} else {
				if fields.len != 8 || fields[4] != 'cycles=200' || !fields[5].starts_with('big_pages=') || fields[6] != 'tainted=0/0' || fields[7] != 'PASS' {
					return error('Invalid storage result')
				}
				flat_pair(fields[5].all_after('='))!
				storage[uid]++
			}
		} else {
			if line !in wanted { return error('Unexpected result: ' + line) }
			actual[line]++
		}
	}
	if actual != wanted { return error('Missing, repeated or altered result') }
	if baseline { return }
	for uid in ['uid=0', 'uid=1000'] {
		if storage[uid] != 1 { return error('Missing or repeated storage result') }
		if linux { continue }
		if slabs[uid].len != if arch == 'aarch64' { 18 } else { 14 } {
			return error('Missing slab classes')
		}
		for size in [u64(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048] {
			if size !in slabs[uid] { return error('Missing fixed slab class') }
		}
	}
}

pub fn self_test() ! {
	mut rejected := 0
	for arch in ['aarch64', 'x86_64'] {
		for linux in [false, true] {
			mut good := 'Linux version control\n'
			for line, count in records(arch, false) {
				for _ in 0 .. count { good += line + '\n' }
			}
			for uid in [0, 1000] {
				prefix := 'LINUX EPOLLWORDS STORAGE: uid=' + uid.str()
				if linux {
					good += prefix + ' SKIP reference\n'
					continue
				}
				mut sizes := [16, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]
				if arch == 'aarch64' { sizes << [2704, 4064, 5424, 8144] }
				for size in sizes {
					good += 'LINUX EPOLLWORDS SLAB: uid=' + uid.str() + ' size=' + size.str() + ' live=10/10\n'
				}
				good += prefix + ' cycles=200 big_pages=20/20 tainted=0/0 PASS\n'
			}
			verify(good, arch, false, linux)!
			for index, line in good.split_into_lines().filter(it.starts_with('LINUX EPOLLWORDS')) {
				if index % 37 != 0 && !line.contains('SUMMARY') && !line.contains('STORAGE:') && !line.contains('SLAB:') {
					continue
				}
				for bad in [good.replace_once(line + '\n', ''), good + line + '\n'] {
					verify(bad, arch, false, linux) or {
						rejected++
						continue
					}
					return error('Accepted missing or duplicate record')
				}
			}
			for bad in [good.replace('failures=0', 'failures=1'), good + 'Kernel panic injected\n'] {
				verify(bad, arch, false, linux) or {
					rejected++
					continue
				}
				return error('Accepted failure')
			}
			if !linux {
				for bad in [good.replace('live=10/10', 'live=10/11'),
					good.replace('big_pages=20/20', 'big_pages=20/21'),
					good.replace('tainted=0/0', 'tainted=0/1')] {
					verify(bad, arch, false, linux) or {
						rejected++
						continue
					}
					return error('Accepted retention')
				}
			}
		}
	}
	for arch in ['aarch64', 'x86_64'] {
		mut good := ''
		for line, count in records(arch, true) {
			for _ in 0 .. count { good += line + '\n' }
		}
		verify(good, arch, true, false)!
		for index, line in good.split_into_lines().filter(it.starts_with('LINUX EPOLLWORDS')) {
			if index % 37 != 0 && !line.contains('SUMMARY') && !line.contains('STORAGE:') && !line.contains('SLAB:') {
				continue
			}
			for bad in [good.replace_once(line + '\n', ''), good + line + '\n'] {
				verify(bad, arch, true, false) or {
					rejected++
					continue
				}
				return error('Accepted incomplete baseline')
			}
		}
	}
	println('Epoll wait-word parser: PASS (6 positive, ' + rejected.str() + ' negative)')
}
