// SPDX-License-Identifier: GPL-2.0-or-later
module execowncheck

import strconv

fn require(good bool, reason string) ! {
	if !good { return error(reason) }
}

fn number(value string) !u64 {
	require(value.len > 0 && value.bytes().all(it >= `0` && it <= `9`), 'Invalid unsigned number')!
	return strconv.parse_uint(value, 10, 64)!
}

fn flat_pair(value string) ! {
	pair := value.split('/')
	require(pair.len == 2, 'Invalid storage pair')!
	require(number(pair[0])! == number(pair[1])!, 'Storage changed')!
}

fn slab_sizes(arch string) []u64 {
	mut result := [u64(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]
	if arch == 'aarch64' { result << [u64(2704), 4064, 5424, 8144] }
	return result
}

pub fn verify(text string, arch string, reference bool) ! {
	require(arch in ['aarch64', 'x86_64'], 'Unsupported architecture')!
	if reference { require(text.contains('Linux version '), 'Linux boot missing')! }
	for bad in ['KERNEL PANIC', 'FATAL EXCEPTION', 'Kernel panic', 'BUG:', 'REFERENCE FAIL',
		'LINUX EXECOWN FAIL', 'LINUX EXECOWN MISMATCH', 'LINUX EXECOWN CHILD:'] {
		require(!text.contains(bad), 'Failure marker: ' + bad)!
	}
	checks := if reference { '6' } else { '7' }
	wanted := {
		'LINUX EXECOWN COHORT: uid=0 checks=' + checks + ' failures=0': 1
		'LINUX EXECOWN COHORT: uid=1000 checks=' + checks + ' failures=0': 1
		'LINUX EXECOWN SUMMARY: checks=' + if reference { '12' } else { '14' } + ' failures=0': 1
		'LINUX EXECOWN' + if reference { ' REFERENCE: PASS' } else { ': PASS' }: 1
	}
	mut actual := map[string]int{}
	mut summaries := map[string]int{}
	mut slabs := map[string][]u64{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if !line.starts_with('LINUX EXECOWN') { continue }
		if line.starts_with('LINUX EXECOWN SLAB:') || line.starts_with('LINUX EXECOWN STORAGE:') {
			fields := line.fields()
			require(fields.len >= 4 && fields[3] in ['uid=0', 'uid=1000'], 'Unexpected storage owner')!
			uid := fields[3]
			if reference {
				require(line == 'LINUX EXECOWN STORAGE: ' + uid + ' SKIP Linux reference', 'Unexpected reference storage')!
				summaries[uid]++
			} else if fields[2] == 'SLAB:' {
				require(fields.len == 7 && fields[4].starts_with('size=')
					&& fields[5].starts_with('live=') && fields[6] == 'cycles=200', 'Invalid slab row')!
				size := number(fields[4].all_after('='))!
				require(size !in slabs[uid] && size in slab_sizes(arch), 'Duplicate/unexpected slab class')!
				flat_pair(fields[5].all_after('='))!
				slabs[uid] << size
			} else {
				require(fields.len == 8 && fields[4] == 'cycles=200'
					&& fields[5].starts_with('big_pages=') && fields[6] == 'tainted=0/0'
					&& fields[7] == 'PASS', 'Invalid cleanup summary')!
				flat_pair(fields[5].all_after('='))!
				summaries[uid]++
			}
			continue
		}
		require(line in wanted, 'Unexpected exec record: ' + line)!
		actual[line]++
	}
	require(actual == wanted, 'Missing, repeated or changed exec records')!
	for uid in ['uid=0', 'uid=1000'] {
		require(summaries[uid] == 1, 'Missing/repeated cleanup summary')!
		if !reference {
			mut sizes := slabs[uid].clone()
			sizes.sort()
			require(sizes == slab_sizes(arch), 'Incomplete cleanup classes')!
		}
	}
}

fn control_log(arch string, reference bool) string {
	mut output := if reference { 'Linux version control\n' } else { '' }
	for uid in ['0', '1000'] {
		if reference { output += 'LINUX EXECOWN STORAGE: uid=' + uid + ' SKIP Linux reference\n' }
		else {
			for size in slab_sizes(arch) {
				output += 'LINUX EXECOWN SLAB: uid=' + uid + ' size=' + size.str() + ' live=10/10 cycles=200\n'
			}
			output += 'LINUX EXECOWN STORAGE: uid=' + uid + ' cycles=200 big_pages=20/20 tainted=0/0 PASS\n'
		}
		output += 'LINUX EXECOWN COHORT: uid=' + uid + ' checks=' + if reference { '6' } else { '7' } + ' failures=0\n'
	}
	output += 'LINUX EXECOWN SUMMARY: checks=' + if reference { '12' } else { '14' } + ' failures=0\n'
	output += 'LINUX EXECOWN' + if reference { ' REFERENCE: PASS\n' } else { ': PASS\n' }
	return output
}

pub fn self_test() ! {
	mut negatives := 0
	for arch in ['aarch64', 'x86_64'] {
		for reference in [false, true] {
			good := control_log(arch, reference)
			verify(good, arch, reference)!
			mut variants := []string{}
			for line in good.split_into_lines().filter(it != '') {
				if !reference && line.starts_with('Linux version') { continue }
				variants << good.replace(line + '\n', '')
				if !line.starts_with('Linux version') { variants << good + line + '\n' }
			}
			variants << [good + 'KERNEL PANIC injected\n', good + 'LINUX EXECOWN UNKNOWN\n',
				good.replace('failures=0', 'failures=1'), good.replace('uid=1000', 'uid=1001')]
			if !reference {
				variants << [good.replace('live=10/10', 'live=10/11'),
					good.replace('big_pages=20/20', 'big_pages=20/21'), good.replace('tainted=0/0', 'tainted=0/1'),
					good.replace('cycles=200', 'cycles=199'), good.replace('size=16 ', 'size=17 '),
					good.replace('live=10/10', 'live=18446744073709551616/0')]
			}
			for bad in variants {
				verify(bad, arch, reference) or { negatives++; continue }
				return error('Invalid exec log accepted')
			}
		}
	}
	println('Exec ownership parser: PASS (4 positive, ' + negatives.str() + ' negative controls)')
}
