// SPDX-License-Identifier: GPL-2.0-or-later
module selecttimeoutcheck

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

pub fn expected(arch string, baseline bool) []string {
 mut result := []string{}
 apis := if arch == "aarch64" { 2 } else { 3 }
 for uid in [0,1000] { for api in 0 .. apis { for mode in 0 .. 14 { for readonly in 0 .. 2 { for restart in 0 .. if mode in [7,11] { 2 } else { 1 } {
 if api == 2 && mode in [6,10] { continue }
 failed := baseline && api != 1 && readonly == 0 && mode !in [5,6,8,13]
 if failed { result << "LINUX SELECTTIMEOUT MISMATCH: stage=7" }
 result << "LINUX SELECTTIMEOUT CASE: uid="+uid.str()+" gid="+if uid == 0 { "0" } else { "2000" }+" api="+api.str()+" mode="+mode.str()+" readonly="+readonly.str()+" restart="+restart.str()+" checks=12 failures="+if failed { "1" } else { "0" }
 } } } } }
 result << "LINUX SELECTTIMEOUT SUMMARY: checks="+if arch == "aarch64" { "1536" } else { "2208" }+" failures="+if !baseline { "0" } else if arch == "aarch64" { "24" } else { "46" }
 result << "LINUX SELECTTIMEOUT: "+if baseline { "FAIL" } else { "PASS" }
 return result
}
pub fn verify(text string, arch string, baseline bool, reference bool) ! {
	require(arch in ['aarch64','x86_64'] && !(baseline && reference), 'Invalid execution profile')!
	if reference { require(text.contains('Linux version '), 'Missing Linux boot')! }
	for bad in ['KERNEL PANIC','FATAL EXCEPTION','Kernel panic','BUG:','LINUX SELECTTIMEOUT FAIL:','REFERENCE FAIL'] {
		require(!text.contains(bad), 'Failure marker: '+bad)!
	}
	mut wanted := map[string]int{}
	for line in expected(arch,baseline) { wanted[line]++ }
	mut actual := map[string]int{}
	mut sizes := map[string][]u64{}
	mut summaries := map[string]int{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('LINUX SELECTTIMEOUT SLAB:') || line.starts_with('LINUX SELECTTIMEOUT STORAGE:') {
			f := line.fields()
			require(f.len >= 4 && f[3] in ['uid=0','uid=1000'], 'Unexpected storage owner')!
			uid := f[3]
			if reference {
				require(line == 'LINUX SELECTTIMEOUT STORAGE: '+uid+' SKIP reference', 'Unexpected reference storage')!
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
		if line.starts_with('LINUX SELECTTIMEOUT') {
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
		if reference { output += 'LINUX SELECTTIMEOUT STORAGE: uid='+uid.str()+' SKIP reference\n' }
		else {
			for size in classes(arch,true) { output += 'LINUX SELECTTIMEOUT SLAB: uid='+uid.str()+' size='+size.str()+' live=10/10 cycles=200\n' }
			output += 'LINUX SELECTTIMEOUT STORAGE: uid='+uid.str()+' cycles=200 big_pages=20/20 tainted=0/0 PASS\n'
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
		mut variants := [good+'KERNEL PANIC injected\n',good+'LINUX SELECTTIMEOUT UNKNOWN\n',
			good.replace('checks=12','checks=11'),good.replace('gid=2000','gid=1001')]
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
			return error('Altered select timeout evidence accepted')
		}
	} }
	println('Select timeout parser: PASS ('+positives.str()+' positive, '+negatives.str()+' negative controls)')
}
