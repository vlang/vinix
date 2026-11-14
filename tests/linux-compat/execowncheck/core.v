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

fn storage_pair(value string, growth u64) ! {
	pair := value.split('/')
	require(pair.len == 2, 'Invalid storage pair')!
	before, after := number(pair[0])!, number(pair[1])!
	require(after >= before && after - before == growth, 'Unexpected storage change')!
}

fn slab_sizes(arch string, compact bool) []u64 {
	mut result := [u64(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]
	if arch == 'aarch64' {
		// Complete allocator layouts emitted by the two retained V builds.
		// Require one whole layout below; mixed or missing classes still fail.
		result << if compact { [u64(2688), 4048, 5392, 8096] } else { [u64(2704), 4064, 5424, 8144] }
	}
	return result
}

pub fn verify(text string, arch string, reference bool) ! {
	verify_profile(text, arch, reference, false)!
}

// The original bug retains two size-16 objects in each of 200 cycles. Keep
// that exact failing result separate from candidate and Linux success.
pub fn verify_retained(text string, arch string) ! {
	verify_profile(text, arch, false, true)!
}

fn verify_profile(text string, arch string, reference bool, retained bool) ! {
	require(arch in ['aarch64', 'x86_64'], 'Unsupported architecture')!
	if reference { require(text.contains('Linux version '), 'Linux boot missing')! }
	for bad in ['KERNEL PANIC', 'FATAL EXCEPTION', 'Kernel panic', 'BUG:', 'REFERENCE FAIL',
		'LINUX EXECOWN FAIL', 'LINUX EXECOWN MISMATCH', 'LINUX EXECOWN CHILD:'] {
		if retained && bad in ['LINUX EXECOWN FAIL', 'LINUX EXECOWN MISMATCH'] { continue }
		require(!text.contains(bad), 'Failure marker: ' + bad)!
	}
	checks := if reference { '6' } else { '7' }
	mut wanted := {
		'LINUX EXECOWN COHORT: uid=0 checks=' + checks + ' failures=' + if retained { '1' } else { '0' }: 1
		'LINUX EXECOWN COHORT: uid=1000 checks=' + checks + ' failures=' + if retained { '1' } else { '0' }: 1
		'LINUX EXECOWN SUMMARY: checks=' + if reference { '12' } else { '14' } + ' failures=' + if retained { '4' } else { '0' }: 1
		'LINUX EXECOWN' + if reference { ' REFERENCE: PASS' } else if retained { ' FAIL: arguments, environment, errors or cleanup' } else { ': PASS' }: 1
	}
	if retained {
		for uid in ['0', '1000'] { wanted['LINUX EXECOWN MISMATCH: uid=' + uid + ' stage=30 errno=2'] = 1 }
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
				require(size !in slabs[uid] && (size in slab_sizes(arch, false)
					|| size in slab_sizes(arch, true)), 'Duplicate/unexpected slab class')!
				storage_pair(fields[5].all_after('='), if retained && size == 16 { u64(400) } else { u64(0) })!
				slabs[uid] << size
			} else {
				require(fields.len == 8 && fields[4] == 'cycles=200'
					&& fields[5].starts_with('big_pages=') && fields[6] == 'tainted=0/0'
					&& fields[7] == if retained { 'FAIL' } else { 'PASS' }, 'Invalid cleanup summary')!
				storage_pair(fields[5].all_after('='), 0)!
				summaries[uid]++
			}
			continue
		}
		require(line in wanted, 'Unexpected exec record: ' + line)!
		actual[line]++
	}
	require(actual == wanted, 'Missing, repeated or changed exec records')!
	mut layout := []u64{}
	for uid in ['uid=0', 'uid=1000'] {
		require(summaries[uid] == 1, 'Missing/repeated cleanup summary')!
		if !reference {
			mut sizes := slabs[uid].clone()
			sizes.sort()
			require(sizes == slab_sizes(arch, false) || sizes == slab_sizes(arch, true), 'Incomplete/mixed cleanup classes')!
			if layout.len == 0 { layout = sizes.clone() }
			else { require(sizes == layout, 'Cohorts use different allocator layouts')! }
		}
	}
}

fn control_log(arch string, reference bool) string {
	mut output := if reference { 'Linux version control\n' } else { '' }
	for uid in ['0', '1000'] {
		if reference { output += 'LINUX EXECOWN STORAGE: uid=' + uid + ' SKIP Linux reference\n' }
		else {
			for size in slab_sizes(arch, false) {
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
		retained := control_log(arch, false).replace('size=16 live=10/10', 'size=16 live=10/410')
			.replace('failures=0', 'failures=1').replace('checks=14 failures=1', 'checks=14 failures=4')
			.replace('tainted=0/0 PASS', 'tainted=0/0 FAIL')
			.replace('LINUX EXECOWN: PASS', 'LINUX EXECOWN MISMATCH: uid=0 stage=30 errno=2\nLINUX EXECOWN MISMATCH: uid=1000 stage=30 errno=2\nLINUX EXECOWN FAIL: arguments, environment, errors or cleanup')
		verify_retained(retained, arch)!
		for bad in [retained.replace('live=10/410', 'live=10/411'),
			retained.replace('size=32 live=10/10', 'size=32 live=10/11'),
			retained.replace('LINUX EXECOWN MISMATCH: uid=0 stage=30 errno=2\n', ''),
			retained.replace('stage=30', 'stage=20'), retained + 'KERNEL PANIC injected\n'] {
			verify_retained(bad, arch) or { negatives++; continue }
			return error('Invalid original retention accepted')
		}
		for reference in [false, true] {
			good := control_log(arch, reference)
			verify(good, arch, reference)!
			if arch == 'aarch64' && !reference {
				compact := good.replace('size=2704 ', 'size=2688 ').replace('size=4064 ', 'size=4048 ')
					.replace('size=5424 ', 'size=5392 ').replace('size=8144 ', 'size=8096 ')
				verify(compact, arch, reference)!
			}
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
				if arch == 'aarch64' {
					variants << good.replace('size=2704 ', 'size=2688 ')
					variants << good.replace('uid=0 size=2704 ', 'uid=0 size=2688 ')
						.replace('uid=0 size=4064 ', 'uid=0 size=4048 ')
						.replace('uid=0 size=5424 ', 'uid=0 size=5392 ')
						.replace('uid=0 size=8144 ', 'uid=0 size=8096 ')
				}
			}
			for bad in variants {
				verify(bad, arch, reference) or { negatives++; continue }
				return error('Invalid exec log accepted')
			}
		}
	}
	println('Exec ownership parser: PASS (7 positive, ' + negatives.str() + ' negative controls)')
}
