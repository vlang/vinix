// SPDX-License-Identifier: GPL-2.0-or-later
module ppollargscheck

import strconv

fn require(good bool, reason string) ! { if !good { return error(reason) } }
fn number(text string) !u64 {
	require(text.len > 0 && text.bytes().all(it >= `0` && it <= `9`), 'Invalid unsigned number')!
	return strconv.parse_uint(text, 10, 64)!
}
fn flat(text string) ! {
	pair := text.split('/')
	require(pair.len == 2 && number(pair[0])! == number(pair[1])!, 'Storage changed')!
}
fn classes(arch string, compact bool) []u64 {
	mut result := [u64(16),32,48,64,96,128,192,256,384,512,768,1024,1536,2048]
	if arch == 'aarch64' { result << if compact { [u64(2688),4048,5392,8096] } else { [u64(2704),4064,5424,8144] } }
	return result
}
fn code(amount int, mask int, timeout int, descriptor int, old bool) int {
	if old {
		if amount >= 2 { return 22 }
		if amount == 1 && descriptor == 3 { return 14 }
		if timeout == 1 || mask in [5,6] { return 14 }
		if timeout >= 2 { return 22 }
		if amount == 1 && descriptor == 4 { return 14 }
		return 0
	}
	if timeout == 1 { return 14 }
	if timeout >= 2 || mask in [3,4,6,7] { return 22 }
	if mask == 5 { return 14 }
	if amount == 2 { return 22 }
	if amount in [1,4,5] && descriptor in [3,4] { return 14 }
	return 0
}
fn result(amount int, descriptor int, error_code int, old bool) int {
	if error_code != 0 { return -1 }
	one := if old { amount == 1 } else { amount in [1,4,5] }
	return if one && descriptor in [1,2] { 1 } else { 0 }
}
fn failures(amount int, mask int) int {
	mut total := 0
	for timeout in 0 .. 5 { for descriptor in 0 .. 5 {
		previous := code(amount,mask,timeout,descriptor,true)
		wanted := code(amount,mask,timeout,descriptor,false)
		if previous != wanted { total++ }
		if result(amount,descriptor,previous,true) != result(amount,descriptor,wanted,false) { total++ }
		old_output := previous == 0 && amount == 1 && descriptor < 3
		new_output := wanted == 0 && amount in [1,4,5] && descriptor < 3
		if old_output != new_output { total++ }
	} }
	return total
}
pub fn expected(_arch string, baseline bool) []string {
	mut result := []string{}
	mut total := 0
	for uid in [0,1000] { for amount in 0 .. 7 { for mask in 0 .. 8 {
		failed := if baseline { failures(amount,mask) } else { 0 }
		result << 'LINUX PPOLLARGS CASE: uid='+uid.str()+' gid='+if uid == 0 { '0' } else { '2000' }+' amount='+amount.str()+' mask='+mask.str()+' checks=175 failures='+failed.str()
		total += failed
	} } }
	result << 'LINUX PPOLLARGS SUMMARY: checks=19600 failures='+total.str()
	result << 'LINUX PPOLLARGS: '+if baseline { 'FAIL' } else { 'PASS' }
	return result
}

pub fn verify(text string, arch string, baseline bool, reference bool) ! {
	require(arch in ['aarch64','x86_64'] && !(baseline && reference), 'Invalid execution profile')!
	if reference { require(text.contains('Linux version '), 'Missing Linux boot')! }
	for bad in ['KERNEL PANIC','FATAL EXCEPTION','Kernel panic','BUG:','LINUX PPOLLARGS FAIL:','REFERENCE FAIL'] {
		require(!text.contains(bad), 'Failure marker: '+bad)!
	}
	mut wanted := map[string]int{}
	for line in expected(arch,baseline) { wanted[line]++ }
	mut actual := map[string]int{}
	mut sizes := map[string][]u64{}
	mut summaries := map[string]int{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('LINUX PPOLLARGS SLAB:') || line.starts_with('LINUX PPOLLARGS STORAGE:') {
			f := line.fields()
			require(f.len >= 4 && f[3] in ['uid=0','uid=1000'], 'Unexpected storage owner')!
			uid := f[3]
			if reference {
				require(line == 'LINUX PPOLLARGS STORAGE: '+uid+' SKIP reference', 'Unexpected reference storage')!
				summaries[uid]++
			} else if f[2] == 'SLAB:' {
				require(f.len == 7 && f[4].starts_with('size=') && f[5].starts_with('live=') && f[6] == 'cycles=200', 'Malformed slab row')!
				size := number(f[4].all_after('='))!
				require(size !in sizes[uid], 'Repeated slab class')!
				flat(f[5].all_after('='))!
				sizes[uid] << size
			} else {
				require(f.len == 8 && f[4] == 'cycles=200' && f[5].starts_with('big_pages=')
					&& f[6] == 'tainted=0/0' && f[7] == 'PASS', 'Invalid storage summary')!
				flat(f[5].all_after('='))!
				summaries[uid]++
			}
			continue
		}
		if line.starts_with('LINUX PPOLLARGS') {
			require(line in wanted, 'Unexpected semantic record: '+line)!
			actual[line]++
		}
	}
	require(actual == wanted, 'Missing, repeated or changed semantic records')!
	mut layout := []u64{}
	for uid in ['uid=0','uid=1000'] {
		require(summaries[uid] == 1, 'Missing/repeated storage summary')!
		if reference { continue }
		mut found := sizes[uid].clone(); found.sort()
		require(found == classes(arch,false) || found == classes(arch,true), 'Incomplete/mixed slab classes')!
		if layout.len == 0 { layout = found.clone() } else { require(found == layout, 'Different cohort layouts')! }
	}
}
fn control(arch string, reference bool) string {
	mut output := ''
	for uid in [0,1000] {
		if reference { output += 'LINUX PPOLLARGS STORAGE: uid='+uid.str()+' SKIP reference\n' }
		else {
			for size in classes(arch,true) { output += 'LINUX PPOLLARGS SLAB: uid='+uid.str()+' size='+size.str()+' live=10/10 cycles=200\n' }
			output += 'LINUX PPOLLARGS STORAGE: uid='+uid.str()+' cycles=200 big_pages=20/20 tainted=0/0 PASS\n'
		}
	}
	return output
}
pub fn self_test() ! {
	mut positives := 0
	mut negatives := 0
	for arch in ['aarch64','x86_64'] { for mode in 0 .. 3 {
		baseline, reference := mode == 1, mode == 2
		good := 'Linux version control\n'+expected(arch,baseline).join('\n')+'\n'+control(arch,reference)
		verify(good,arch,baseline,reference)!; positives++
		mut variants := [good+'KERNEL PANIC injected\n',good+'LINUX PPOLLARGS UNKNOWN\n',
			good.replace('checks=175','checks=174'),good.replace('gid=2000','gid=1001')]
		for line in good.split_into_lines().filter(it != '' && !it.starts_with('Linux version ')) {
			variants << good.replace(line+'\n','')
			variants << good+line+'\n'
		}
		if !reference {
			variants << [good.replace('live=10/10','live=10/11'),good.replace('big_pages=20/20','big_pages=20/21'),
				good.replace('tainted=0/0','tainted=0/1'),good.replace('cycles=200','cycles=199'),
				good.replace('size=16 ','size=17 '),good.replace('live=10/10','live=18446744073709551616/0')]
		}
		for bad in variants {
			verify(bad,arch,baseline,reference) or { negatives++; continue }
			return error('Altered ppoll argument evidence accepted')
		}
	} }
	println('Ppoll arguments parser: PASS ('+positives.str()+' positive, '+negatives.str()+' negative controls)')
}
