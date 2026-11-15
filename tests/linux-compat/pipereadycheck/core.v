// SPDX-License-Identifier: GPL-2.0-or-later
module pipereadycheck

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
fn status(kind int, baseline bool) int {
 if baseline { return match kind { 0,1 { 4 } 2,3 { 5 } 4,5 { 1 } 6 { 20 } 7 { 21 } 8 { 8 } else { 9 } } }
 return match kind { 0,5 { 0 } 1,3 { 0x104 } 2,4 { 0x41 } 6 { 16 } 7 { 0x51 } 8 { 0x10c } else { 8 } }
}
fn events(profile int) int {
 return match profile { 0 { 0 } 1 { 1 } 2 { 2 } 3 { 4 } 4 { 5 } 5 { 0x40 } 6 { 0x80 } 7 { 0x100 } 8 { 0x200 } 9 { 0x41 } 10 { 0x104 } 11 { 0x145 } 12 { 0x7fff } 13 { 8 } 14 { 16 } else { 0x2000 } }
}
fn failures(family int, kind int) int {
 old, new := status(kind,true),status(kind,false)
 mut failed := 0
 for _ in 0 .. 3 {
  if family == 1 {
   for sets in 1 .. 8 {
    a := sets&1 != 0 && old&0xf9 != 0
    b := sets&2 != 0 && old&0x30c != 0
    x := sets&1 != 0 && new&0xf9 != 0
    y := sets&2 != 0 && new&0x30c != 0
    if int(a)+int(b) != int(x)+int(y) { failed++ }
    if a != x { failed++ }; if b != y { failed++ }
   }
  } else {
   for profile in 0 .. 16 {
    a := (old&events(profile)) | (old&24)
    b := (new&events(profile)) | (new&24)
    if a != b { failed++ }
    if (a == 0) != (b == 0) { failed++ }
   }
  }
 }
 return failed
}
pub fn expected(arch string, baseline bool) []string {
 mut rows := []string{}
 mut total := 0
 apis := if arch == 'aarch64' { 3 } else { 4 }
 for uid in [0,1000] { for family in 0 .. 3 { for api in 0 .. if family == 2 { 1 } else { apis } { for kind in 0 .. 10 {
 failed := if baseline { failures(family,kind) } else { 0 }
 checks := if family == 1 { 147 } else { 192 }
 rows << "LINUX PIPEREADY CASE: uid="+uid.str()+" gid="+if uid == 0 { "0" } else { "2000" }+" family="+family.str()+" api="+api.str()+" kind="+kind.str()+" checks="+checks.str()+" failures="+failed.str()
 total += failed
 } } } }
 rows << "LINUX PIPEREADY SUMMARY: checks="+(20*(apis*339+192)).str()+" failures="+total.str()
 rows << "LINUX PIPEREADY: "+if baseline { "FAIL" } else { "PASS" }
 return rows
}

pub fn verify(text string, arch string, baseline bool, reference bool) ! {
	require(arch in ['aarch64','x86_64'] && !(baseline && reference), 'Invalid execution profile')!
	if reference { require(text.contains('Linux version '), 'Missing Linux boot')! }
	for bad in ['KERNEL PANIC','FATAL EXCEPTION','Kernel panic','BUG:','LINUX PIPEREADY FAIL:','REFERENCE FAIL'] {
		require(!text.contains(bad), 'Failure marker: '+bad)!
	}
	mut wanted := map[string]int{}
	for line in expected(arch,baseline) { wanted[line]++ }
	mut actual := map[string]int{}
	mut sizes := map[string][]u64{}
	mut summaries := map[string]int{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('LINUX PIPEREADY SLAB:') || line.starts_with('LINUX PIPEREADY STORAGE:') {
			f := line.fields()
			require(f.len >= 4 && f[3] in ['uid=0','uid=1000'], 'Unexpected storage owner')!
			uid := f[3]
			if reference {
				require(line == 'LINUX PIPEREADY STORAGE: '+uid+' SKIP reference', 'Unexpected reference storage')!
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
		if line.starts_with('LINUX PIPEREADY') {
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
		if reference { output += 'LINUX PIPEREADY STORAGE: uid='+uid.str()+' SKIP reference\n' }
		else {
			for size in classes(arch,true) { output += 'LINUX PIPEREADY SLAB: uid='+uid.str()+' size='+size.str()+' live=10/10 cycles=200\n' }
			output += 'LINUX PIPEREADY STORAGE: uid='+uid.str()+' cycles=200 big_pages=20/20 tainted=0/0 PASS\n'
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
		mut variants := [good+'KERNEL PANIC injected\n',good+'LINUX PIPEREADY UNKNOWN\n',
			good.replace('checks=192','checks=191'),good.replace('gid=2000','gid=1001')]
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
			return error('Altered pipe readiness evidence accepted')
		}
	} }
	println('Pipe readiness parser: PASS ('+positives.str()+' positive, '+negatives.str()+' negative controls)')
}
