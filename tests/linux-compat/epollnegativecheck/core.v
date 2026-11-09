// SPDX-License-Identifier: GPL-2.0-or-later
module epollnegativecheck

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

fn records(arch string, baseline bool) map[string]int {
	mut wanted := map[string]int{}
	for uid in [0, 1000] {
		for api in 0 .. if arch == 'aarch64' { 3 } else { 4 } {
			for value in 0 .. 10 {
				for restart in 0 .. 2 {
					for mode in if value < 8 { [0, 1, 2, 4] } else { [3] } {
						key := 'uid=' + uid.str() + ' api=' + api.str() + ' value=' + value.str() + ' mode=' + mode.str() + ' restart=' + restart.str()
						stages := if baseline && value > 0 && value < 8 {
							match mode {
								0 { [1, 2] }
								1 { [1, 2, 6, 8] }
								2 { [1, 3, 5] }
								else { [1] }
							}
						} else {
							[]int{}
						}
						wanted['LINUX EPOLLNEGATIVE CASE: ' + key + ' checks=8 failures=' + stages.len.str()] = 1
						for stage in stages {
							wanted['LINUX EPOLLNEGATIVE MISMATCH: ' + key + ' stage=' + stage.str()] = 1
						}
					}
				}
			}
		}
	}
	failures := if baseline {
		if arch == 'aarch64' { 840 } else { 1120 }
	} else {
		0
	}
	wanted['LINUX EPOLLNEGATIVE SUMMARY: checks=' + if arch == 'aarch64' { '3264' } else { '4352' } + ' failures=' + failures.str()] = 1
	wanted['LINUX EPOLLNEGATIVE: ' + if baseline { 'FAIL' } else { 'PASS' }] = 1
	return wanted
}

pub fn verify(text string, arch string, baseline bool, linux bool) ! {
	if arch !in ['aarch64', 'x86_64'] || (baseline && linux) {
		return error('Expected a native baseline/candidate or Linux reference')
	}
	if linux && !text.contains('Linux version ') { return error('Linux boot missing') }
	for bad in ['LINUX EPOLLNEGATIVE FAIL:', 'KERNEL PANIC', 'FATAL EXCEPTION', 'Kernel panic',
		'BUG:'] {
		if text.contains(bad) { return error('Failure marker: ' + bad) }
	}
	wanted := records(arch, baseline)
	mut actual := map[string]int{}
	mut slabs := map[string][]u64{}
	mut storage := map[string]int{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if !line.starts_with('LINUX EPOLLNEGATIVE') { continue }
		if line.starts_with('LINUX EPOLLNEGATIVE SLAB:') || line.starts_with('LINUX EPOLLNEGATIVE STORAGE:') {
			if baseline { return error('Unexpected baseline storage') }
			fields := line.fields()
			if fields.len < 4 || fields[3] !in ['uid=0', 'uid=1000'] {
				return error('Invalid storage owner')
			}
			uid := fields[3]
			if linux {
				if line != 'LINUX EPOLLNEGATIVE STORAGE: ' + uid + ' SKIP reference' {
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
				prefix := 'LINUX EPOLLNEGATIVE STORAGE: uid=' + uid.str()
				if linux {
					good += prefix + ' SKIP reference\n'
					continue
				}
				mut sizes := [16, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]
				if arch == 'aarch64' { sizes << [2704, 4064, 5424, 8144] }
				for size in sizes {
					good += 'LINUX EPOLLNEGATIVE SLAB: uid=' + uid.str() + ' size=' + size.str() + ' live=10/10\n'
				}
				good += prefix + ' cycles=200 big_pages=20/20 tainted=0/0 PASS\n'
			}
			verify(good, arch, false, linux)!
			for line in good.split_into_lines().filter(it.starts_with('LINUX EPOLLNEGATIVE')) {
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
		for line in good.split_into_lines().filter(it.starts_with('LINUX EPOLLNEGATIVE')) {
			for bad in [good.replace_once(line + '\n', ''), good + line + '\n'] {
				verify(bad, arch, true, false) or {
					rejected++
					continue
				}
				return error('Accepted incomplete baseline')
			}
		}
	}
	println('Negative epoll timeout parser: PASS (6 positive, ' + rejected.str() + ' negative)')
}
